local Vasc = script:FindFirstAncestor("Vasc")

local Promise = require(Vasc.Packages.Promise)

local Types = require(Vasc.Types)
local Place = require(Vasc.Place)
local Log = require(Vasc.Log)

local Http = require(script.Http)
local Error = require(script.Error)

local function generateId(): number
	return math.floor(math.random() * 10 ^ 9)
end

local READ_TIMEOUT_RETRIES = 5
local READ_RETRY_BASE_DELAY = 0.25
local READ_RETRY_MAX_DELAY = 2

local Client = {}
Client.__index = Client

function Client.new(host: string, port: number)
	local self = setmetatable({}, Client)

	self.isSubscribed = false
	self.clientId = generateId()
	self.placeName = Place.Name
	self.host = host
	self.port = port

	return self
end

function Client:getUrl(endpoint: string?): string
	return `http://{self.host}:{self.port}/{endpoint or ""}`
end

function Client:fetchDetails(): Promise.TypedPromise<Types.Project>
	Log.trace("Client request: details")

	local url = self:getUrl("details")

	return Http.get(url):andThen(function(response)
		return response:decode()
	end)
end

function Client:subscribe(): Promise.Promise
	Log.trace("Client request: subscribe")

	local url = self:getUrl("subscribe")

	return Http.post(url, {
		clientId = self.clientId,
		name = self.placeName,
	})
		:andThen(function()
			self.isSubscribed = true
		end)
		:catch(function(err)
			if err == Error.Unknown then
				return Promise.reject(Error.new(Error.AlreadySubscribed, self.clientId))
			else
				return Promise.reject(err)
			end
		end)
end

function Client:unsubscribe(): Promise.Promise
	Log.trace("Client request: unsubscribe")

	local url = self:getUrl("unsubscribe")

	return Http.post(url, {
		clientId = self.clientId,
	})
		:andThen(function()
			self.isSubscribed = false
		end)
		:catch(function(err)
			if err == Error.Unknown then
				return Promise.reject(Error.new(Error.NotSubscribed, self.clientId))
			else
				return Promise.reject(err)
			end
		end)
end

function Client:getSnapshot(instance: Types.Ref?): Promise.TypedPromise<Types.AddedSnapshot>
	Log.trace("Client request: snapshot")

	local url = self:getUrl("snapshot")

	return Http.post(url, {
		instance = instance or buffer.create(16),
	}):andThen(function(response)
		return response:decode()
	end)
end

function Client:read(): Promise.TypedPromise<Types.Message>
	Log.trace("Client request: read")

	local url = self:getUrl("read")

	local function readAttempt(attempt: number): Promise.TypedPromise<Types.Message>
		return Http.post(url, {
			clientId = self.clientId,
		})
			:andThen(function(response)
				return response:decode()
			end)
			:catch(function(err)
				if err == Error.Timedout and attempt < READ_TIMEOUT_RETRIES then
					local delay = math.min(READ_RETRY_BASE_DELAY * (2 ^ attempt), READ_RETRY_MAX_DELAY)

					Log.trace(`Read timed out, retrying in {delay}s (attempt {attempt + 1}/{READ_TIMEOUT_RETRIES})`)
					task.wait(delay)

					return readAttempt(attempt + 1)
				end

				return Promise.reject(err)
			end)
	end

	return readAttempt(0)
end

function Client:write(changes: Types.Changes): Promise.Promise
	Log.trace("Client request: write")

	local url = self:getUrl("write")

	return Http.post(url, {
		clientId = self.clientId,
		changes = changes,
	})
end

function Client:open(instance: Types.Ref, line: number): Promise.Promise
	Log.trace("Client request: open")

	local url = self:getUrl("open")

	return Http.post(url, {
		instance = instance,
		line = line,
	})
end

return Client
