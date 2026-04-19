--!strict
type SemVer = typeof(setmetatable(
	{} :: {
		major: number,
		minor: number,
		patch: number,
		valid: boolean,
	},
	{} :: SemVerImpl
))

type SemVerImpl = {
	__index: SemVerImpl,
	new: (major: number, minor: number, patch: number, valid: boolean?) -> SemVer,
	parse: (version: string) -> SemVer,
	toString: (self: SemVer) -> string,
	isCompatible: (self: SemVer, other: SemVer) -> boolean,
	isMajorCompatible: (self: SemVer, other: SemVer) -> boolean,
	__eq: (self: SemVer, other: SemVer) -> boolean,
	__lt: (self: SemVer, other: SemVer) -> boolean,
	__le: (self: SemVer, other: SemVer) -> boolean,
}

local SemVer: SemVerImpl = {} :: SemVerImpl
SemVer.__index = SemVer

function SemVer.new(major, minor, patch, valid)
	return setmetatable({
		major = major,
		minor = minor,
		patch = patch,
		valid = if valid == nil then true else valid,
	}, SemVer)
end

function SemVer.parse(version)
	local major, minor, patch = version:match("(%d+)%.(%d+)%.(%d+)")

	if not major or not minor or not patch then
		return SemVer.new(0, 0, 0, false)
	end

	return SemVer.new(tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0, true)
end

function SemVer:toString()
	return ("%d.%d.%d"):format(self.major, self.minor, self.patch)
end

function SemVer:isCompatible(other)
	return self.major == other.major and self.minor == other.minor
end

function SemVer:isMajorCompatible(other)
	return self.major == other.major
end

function SemVer:__eq(other)
	return self.major == other.major and self.minor == other.minor and self.patch == other.patch
end

function SemVer:__lt(other)
	if self.major < other.major then
		return true
	elseif self.major > other.major then
		return false
	end

	if self.minor < other.minor then
		return true
	elseif self.minor > other.minor then
		return false
	end

	return self.patch < other.patch
end

function SemVer:__le(other)
	return self == other or self < other
end

return SemVer
