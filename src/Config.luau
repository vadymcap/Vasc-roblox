local plugin = script:FindFirstAncestorWhichIsA("Plugin")

local Vasc = script:FindFirstAncestor("Vasc")

local Util = require(Vasc.Util)
local Log = require(Vasc.Log)

export type Level = "Place" | "Game" | "Global"
export type Setting =
	"InitialSyncPriority"
	| "Host"
	| "Port"
	| "AutoConnect"
	| "AutoReconnect"
	| "LiveHydrate"
	| "KeepUnknowns"
	| "TwoWaySync"
	| "SyncbackProperties"
	| "OnlyCodeMode"
	| "OpenInEditor"
	| "DisplayPrompts"
	| "ChangesThreshold"
	| "LogLevel"
	| "VersionMismatchMode"
	| "OverridePackages"
	| "EnableIgnoreRules"
	| "ShowIgnoredSkips"
	| "PreviewBeforeApply"
	| "ShowSyncNotifications"

type Config = {
	__configs: { [Level]: { [Setting]: any } },
	__callbacks: { [Setting]: { (value: any) -> () } },
	load: () -> (),
	get: (self: Config, setting: Setting, level: Level?) -> any,
	getDefault: (self: Config, setting: Setting) -> any,
	set: (self: Config, setting: Setting, value: any, level: Level) -> (),
	restoreDefaults: (self: Config, level: Level) -> (),
	onChanged: (self: Config, setting: Setting, callback: (value: any) -> ()) -> () -> (),
}

local DEFAULTS = {
	InitialSyncPriority = "Server",
	Host = "localhost",
	Port = 8000,
	AutoConnect = true,
	AutoReconnect = false,
	LiveHydrate = true,
	KeepUnknowns = false,
	TwoWaySync = false,
	SyncbackProperties = false,
	OnlyCodeMode = true,
	OpenInEditor = false,
	DisplayPrompts = "Always",
	ChangesThreshold = 5,
	LogLevel = "Warn",
	VersionMismatchMode = "Strict",
	OverridePackages = true,
	EnableIgnoreRules = true,
	ShowIgnoredSkips = false,
	PreviewBeforeApply = "Threshold",
	ShowSyncNotifications = true,
}

local CONFIGS = {
	Place = "VascConfigPlace_" .. game.PlaceId,
	Game = "VascConfigGame_" .. game.GameId,
	Global = "VascConfigGlobal",
}

local Config: Config = {
	__configs = {},
	__callbacks = {},
} :: Config

function Config.load()
	for level, config in CONFIGS do
		config = plugin:GetSetting(config)

		if config and type(config) == "table" then
			Config.__configs[level] = config
		else
			Config.__configs[level] = {}
		end
	end
end

function Config:get(setting, level)
	local default = DEFAULTS[setting]

	if default == nil then
		Log.error(`Setting '{setting}' does not exist!`)
	end

	local value = nil

	if level then
		value = self.__configs[level][setting]
	else
		for _, config in self.__configs do
			if config[setting] ~= nil then
				value = config[setting]
				break
			end
		end
	end

	if value == nil then
		return default
	end

	if type(value) ~= type(default) then
		local casted = Util.cast(value, type(default))

		if casted == nil then
			Log.warn(
				`Invalid value type for setting '{setting}', expected '{type(default)}' but got '{type(value)}'. Falling back to default.`
			)
			return default
		end

		value = casted
	end

	return value
end

function Config:getDefault(setting)
	local default = DEFAULTS[setting]

	if default == nil then
		Log.error(`Setting '{setting}' does not exist!`)
	end

	return default
end

function Config:set(setting, value, level)
	local default = DEFAULTS[setting]

	if default == nil then
		Log.error(`Setting '{setting}' does not exist!`)
	end

	value = Util.cast(value, type(default))

	if value ~= self.__configs[level][setting] and self.__callbacks[setting] then
		for _, callback in self.__callbacks[setting] do
			callback(value)
		end
	end

	self.__configs[level][setting] = if value == default then nil else value

	local config = self.__configs[level]

	if not next(config) then
		plugin:SetSetting(CONFIGS[level], nil)
	else
		plugin:SetSetting(CONFIGS[level], config)
	end
end

function Config:restoreDefaults(level)
	for setting, _ in self.__configs[level] do
		if self.__callbacks[setting] then
			for _, callback in self.__callbacks[setting] do
				callback(self:getDefault(setting))
			end
		end
	end

	self.__configs[level] = {}

	plugin:SetSetting(CONFIGS[level], nil)
end

function Config:onChanged(setting, callback)
	if not self.__callbacks[setting] then
		self.__callbacks[setting] = {}
	end

	local id = Util.generateGUID()
	self.__callbacks[setting][id] = callback

	return function()
		self.__callbacks[setting][id] = nil
	end
end

return Config
