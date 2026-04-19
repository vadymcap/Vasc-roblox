local ScriptEditorService = game:GetService("ScriptEditorService")

local Vasc = script:FindFirstAncestor("Vasc")

local Promise = require(Vasc.Packages.Promise)

local Client = require(Vasc.Client)
local Config = require(Vasc.Config)
local Log = require(Vasc.Log)
local Util = require(Vasc.Util)
local Types = require(Vasc.Types)
local Watcher = require(Vasc.Watcher)
local Executor = require(Vasc.Executor)
local SemVer = require(Vasc.SemVer)
local manifest = require(Vasc.manifest)
local equals = require(Vasc.Helpers.equals)

local Processor = require(script.Processor)
local Changes = require(script.Changes)
local Tree = require(script.Tree)
local Error = require(script.Error)

local Ignore = require(Vasc.Helpers.Ignore)

local SYNCBACK_RATE = 0.5
local SYNCBACK_DEBOUNCE = 0.01

local Core = {
	Status = {
		Disconnected = 0,
		Connecting = 1,
		Connected = 2,
		Disconnecting = 3,
	},
}
Core.__index = Core

function Core.new(host: string?, port: string?)
	local self = setmetatable({}, Core)

	self.project = nil
	self.rootInstances = {}
	self.connections = {}
	self.status = 0
	self.lastSync = os.clock()

	self.tree = Tree.new()
	self.client = Client.new(host or Config:get("Host"), port or Config:get("Port"))
	self.processor = Processor.new(self.tree, self.client)
	self.watcher = Watcher.new()
	self.executor = Executor.new()

	self.__prompt = function(_message: string, _changes: Types.Changes?): boolean
		return true
	end
	self.__ready = function(_project: Types.Project) end
	self.__sync = function(_kind: Types.MessageKind, _data: any) end

	self:__handleOpenInEditor(Config:get("OpenInEditor"))

	-- watch for `OpenInEditor setting
	table.insert(
		self.connections,
		Config:onChanged("OpenInEditor", function(enabled)
			self:__handleOpenInEditor(enabled)
		end)
	)

	-- watch for `TwoWaySync` setting
	table.insert(
		self.connections,
		Config:onChanged("TwoWaySync", function(enabled)
			if enabled then
				self.watcher:start(self.rootInstances)
			else
				self.watcher:stop()
			end
		end)
	)

	return self
end

function Core:run(): Promise.Promise
	return Promise.new(function(_, reject)
		self.status = Core.Status.Connecting

		local initialSyncPriority = Config:get("InitialSyncPriority")

		Log.trace("Fetching server details..")

		local project = self.client:fetchDetails():expect()
		self.project = project

		self:__verifyProject(project, true):expect()

		-- Apply ignore rules from project details
		self.processor.write:setIgnoreRules(project.ignore and project.ignore.patterns)

		Log.trace("Subscribing to the server queue..")

		self.client:subscribe():expect()

		Log.trace("Getting initial snapshot..")

		local snapshot = self.client:getSnapshot():expect()

		Log.trace("Initializing processor..")

		local changes = self.processor:init(snapshot, initialSyncPriority)

		if self.status ~= Core.Status.Connecting then
			return reject(Error.new(Error.Terminated))
		end

		for i, id in project.rootRefs do
			self.rootInstances[i] = self.tree:getInstance(id)
		end

		if initialSyncPriority ~= "None" then
			Log.trace("Processing initial snapshot..")

			if initialSyncPriority == "Server" then
				self:__verifyChanges(changes, true):expect()
				self.processor.write:applyChanges(changes, true)
			elseif changes:total() > 0 then
				local reversed = self.processor:reverseChanges(changes)
				self.client:write(reversed):expect()
			end
		end

		if Config:get("TwoWaySync") then
			self.watcher:start(self.rootInstances)
		end

		self.status = Core.Status.Connected
		self.__ready(project)

		if Config:get("ShowSyncNotifications") then
			print(`Vasc: Connected to '{project.name}'`)
		end

		Log.trace("Starting sync loops..")

		self:__startSyncbackLoop():catch(function(err)
			return reject(err)
		end)

		return self:__startSyncLoop():expect()
	end)
end

function Core:stop()
	Log.trace("Stopping Vasc core..")

	self.status = Core.Status.Disconnecting

	self.watcher:stop()

	if self.client.isSubscribed then
		task.spawn(function()
			self.client:unsubscribe():catch(function(err)
				Log.debug("Failed to unsubscribe from the server", err)
			end)
		end)
	end

	Util.clean(self.connections)
end

function Core:onPrompt(callback: (message: string, changes: Types.Changes?) -> boolean)
	self.__prompt = function(message, changes)
		if self.status == Core.Status.Disconnecting then
			return false
		end

		return callback(message, changes)
	end
end

function Core:onReady(callback: (project: Types.Project) -> ())
	self.__ready = function(project)
		if self.status == Core.Status.Disconnecting then
			return
		end

		return callback(project)
	end
end

function Core:onSync(callback: (kind: Types.MessageKind, data: any) -> ())
	self.__sync = function(kind, data)
		if self.status == Core.Status.Disconnecting then
			return
		end

		return callback(kind, data)
	end
end

function Core.wasExitGraceful(err: Error.Error)
	return err == Error.GameId or err == Error.PlaceIds or err == Error.TooManyChanges or err == Error.Terminated
end

-- Internal functions

function Core:__verifyProject(project: Types.Project, initial: boolean?): Promise.Promise
	if not self:__shouldPrompt(initial) then
		return Promise.resolve()
	end

	if project.gameId and project.gameId ~= game.GameId then
		local err = Error.new(Error.GameId, game.GameId, project.gameId)

		if not self.__prompt(err.message) then
			return Promise.reject(err)
		end
	end

	if #project.placeIds > 0 and not table.find(project.placeIds, game.PlaceId) then
		local err = Error.new(Error.PlaceIds, game.PlaceId, project.placeIds)

		if not self.__prompt(err.message) then
			return Promise.reject(err)
		end
	end

	local mode = Config:get("VersionMismatchMode")
	local serverVersion = SemVer.parse(project.version)
	local clientVersion = SemVer.parse(manifest.package.version)

	if not serverVersion.valid or not clientVersion.valid then
		local err = Error.new(Error.Version, manifest.package.version, project.version)

		if mode == "Strict" then
			return Promise.reject(err)
		end

		Log.warn(`Version parsing failed ({err.message}); continuing in mode '{mode}'`)
		return Promise.resolve()
	end

	local compatible = if mode == "AllowMinor"
		then clientVersion:isMajorCompatible(serverVersion)
		else clientVersion:isCompatible(serverVersion)

	if not compatible then
		local err = Error.new(Error.Version, manifest.package.version, project.version)

		if mode == "Warn" then
			Log.warn(`Version mismatch warning: {err.message}`)
		else
			return Promise.reject(err)
		end
	end

	return Promise.resolve()
end

function Core:__verifyChanges(changes: Types.Changes, initial: boolean?): Promise.Promise
	if not self:__shouldPrompt(initial) then
		return Promise.resolve()
	end

	local previewMode = Config:get("PreviewBeforeApply")

	-- "Never" means no prompt regardless of threshold
	if previewMode == "Never" then
		return Promise.resolve()
	end

	local total = Changes.Total(changes)
	local shouldPrompt = total > Config:get("ChangesThreshold") or previewMode == "Always"

	if shouldPrompt then
		local err = Error.new(Error.TooManyChanges, #changes.additions, #changes.updates, #changes.removals)

		if not self.__prompt(err.message, changes) then
			return Promise.reject(err)
		end
	end

	return Promise.resolve()
end

function Core:__startSyncLoop()
	return Promise.new(function(resolve, reject)
		while self.status == Core.Status.Connected do
			local message = self.client:read():expect() :: Types.Message?

			if not message then
				continue
			end

			local kind = next(message) :: Types.MessageKind
			local data = message[kind] :: any

			Log.trace("Received message:", kind)

			if kind == "SyncChanges" then
				self:__verifyChanges(data):expect()

				self.processor.write:applyChanges(data)
				self.lastSync = os.clock()

				local skipped = self.processor.write.skippedIgnored
				if skipped > 0 and Config:get("ShowIgnoredSkips") then
					Log.info(`Vasc: {skipped} change(s) skipped due to ignore rules`)
				end

				data.skippedIgnored = skipped
				self.__sync(kind, data)

				if Config:get("ShowSyncNotifications") then
					local adds = #data.additions
					local upds = #data.updates
					local rems = #data.removals
					print(`Vasc: Synced {adds} addition(s), {upds} update(s), {rems} removal(s)`)
				end
			elseif kind == "SyncDetails" then
				self:__verifyProject(data):expect()

				-- Update ignore rules whenever project details change
				self.processor.write:setIgnoreRules(data.ignore and data.ignore.patterns)

				if not equals(self.project.rootRefs, data.rootRefs) then
					self.rootInstances = {}

					for i, id in data.rootRefs do
						self.rootInstances[i] = self.tree:getInstance(id)
					end

					self.watcher:restart(self.rootInstances)
				end

				self.project = data

				self.__sync(kind, data)

				if Config:get("ShowSyncNotifications") then
					print(`Vasc: Project details updated for '{data.name}'`)
				end
			elseif kind == "ExecuteCode" then
				self.executor:execute(data.code)
			elseif kind == "Disconnect" then
				reject(Error.new(Error.Disconnected, data.message))
			else
				local err = Error.new(Error.UnknownEvent, kind, data)
				Log.warn(err)
			end
		end

		resolve()
	end)
end

function Core:__startSyncbackLoop()
	local aggregateChanges = Changes.new()

	return Promise.new(function(resolve)
		task.spawn(function()
			while self.status == Core.Status.Connected do
				task.wait(SYNCBACK_RATE)

				if aggregateChanges:isEmpty() then
					continue
				end

				local changes = aggregateChanges
				aggregateChanges = Changes.new()

				self.client:write(changes):catch(function(err)
					Log.warn("Failed to write changes to the server:", err)
				end)

				self.__sync("SyncbackChanges", changes)
			end
		end)

		while self.status == Core.Status.Connected do
			local event = self.watcher:listen() :: Types.WatcherEvent

			if os.clock() - self.lastSync <= SYNCBACK_DEBOUNCE then
				continue
			end

			-- Skip events for ignored instances
			if Config:get("EnableIgnoreRules") and self.project then
				local ignoreRules = self.project.ignore
				if ignoreRules and #ignoreRules.patterns > 0 then
					local path = Ignore.instancePath(event.instance)
					if Ignore.isIgnored(path, ignoreRules.patterns) then
						Log.trace("Syncback: ignoring event for", path)
						continue
					end
				end
			end

			local kind = event.kind
			local changes = Changes.new()

			Log.trace("Received event:", kind)

			if kind == "Add" then
				local snapshot = self.processor.read:onAdd(event.instance)

				if snapshot then
					changes:add(snapshot)
				end
			elseif kind == "Change" then
				local snapshot = self.processor.read:onChange(event.instance, event.property)

				if snapshot then
					changes:update(snapshot)
				end
			elseif kind == "Remove" then
				local id = self.processor.read:onRemove(event.instance)

				if id then
					changes:remove(id)
				end
			end

			aggregateChanges:join(changes, true)
		end

		resolve()
	end)
end

function Core:__handleOpenInEditor(enabled: boolean)
	if not enabled then
		local connection = self.connections["openInEditor"]

		if connection then
			connection:Disconnect()
			self.connections["openInEditor"] = nil
		end

		return
	end

	self.connections["openInEditor"] = ScriptEditorService.TextDocumentDidOpen:Connect(function(document)
		if self.status ~= Core.Status.Connected then
			return
		end

		if document:IsCommandBar() then
			Log.trace("Document is a command bar, ignoring")
			return
		end

		local id = self.tree:getId(document:GetScript())

		if not id then
			Log.trace("Document is not synced by Vasc, ignoring")
			return
		end

		local line = document:GetSelectionStart()

		self.client
			:open(id, line)
			:andThen(function()
				document:CloseAsync()
			end)
			:catch(function(err)
				Log.debug("Failed to open document in editor:", err)
			end)
	end)
end

function Core:__cleanConnection(id: string)
	local connection = self.connections[id]

	if connection then
		connection:Disconnect()
		self.connections[id] = nil
	end
end

function Core:__shouldPrompt(initial: boolean?): boolean
	local mode = Config:get("DisplayPrompts")

	if mode == "Always" then
		return true
	elseif mode == "Initial" and initial then
		return true
	else
		return false
	end
end

return Core
