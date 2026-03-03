--!strict

-- Gitignore-style ignore rule matcher for instance paths.
-- Paths use "/" as separator and start from the DataModel root child,
-- e.g. "Workspace/Foo/Bar".

local Ignore = {}

-- Convert a gitignore-style glob to a Lua pattern (full-string match).
local function globToLua(glob: string): string
	-- Escape the % character first (Lua escape char in patterns)
	local result = glob:gsub("%%", "%%%%")
	-- Escape other Lua magic characters (not * or ?)
	result = result:gsub("([%(%)%.%+%-%[%]%^%$])", "%%%1")
	-- Replace ** before single * to avoid conflict; use a placeholder
	result = result:gsub("%*%*", "\1")
	-- Single * matches any non-slash characters
	result = result:gsub("%*", "[^/]*")
	-- ? matches any single non-slash character
	result = result:gsub("%?", "[^/]")
	-- Restore ** as .* (matches anything including slashes)
	result = result:gsub("\1", ".*")
	return result
end

-- Returns true if `str` fully matches the glob pattern.
local function matchGlob(str: string, glob: string): boolean
	return str:match("^" .. globToLua(glob) .. "$") ~= nil
end

-- Build the canonical instance path from the DataModel root.
-- Returns a string like "Workspace/Foo/Bar".
function Ignore.instancePath(instance: Instance): string
	local parts: { string } = {}
	local current: Instance? = instance
	while current and current ~= game do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return table.concat(parts, "/")
end

-- Determine whether an instance path should be ignored given a list of
-- gitignore-style patterns.  The function respects negation ("!pattern"),
-- comments ("#..."), trailing-slash directory markers, and root-anchored
-- patterns (leading "/").  Unanchored patterns can match at any level.
function Ignore.isIgnored(path: string, patterns: { string }): boolean
	if not patterns or #patterns == 0 then
		return false
	end

	local result = false

	for _, rawPattern in patterns do
		-- Skip empty lines and comments
		if rawPattern == "" or rawPattern:sub(1, 1) == "#" then
			continue
		end

		local negate = rawPattern:sub(1, 1) == "!"
		local pattern: string = negate and rawPattern:sub(2) or rawPattern

		-- A trailing "/" signals a directory match; strip it (we apply
		-- directory semantics via prefix checking below anyway).
		if pattern:sub(-1) == "/" then
			pattern = pattern:sub(1, -2)
		end

		-- A leading "/" anchors the pattern to the path root.
		local anchored = pattern:sub(1, 1) == "/"
		if anchored then
			pattern = pattern:sub(2)
		end

		-- Build the effective glob(s) to test.
		-- For anchored patterns we test exactly from the root.
		-- For unanchored patterns we also allow matching anywhere in the
		-- path hierarchy by prepending "**/" so that e.g. "Foo" matches
		-- "Workspace/Foo".
		local glob1 = anchored and pattern or ("**/" .. pattern)
		local glob2 = (not anchored) and pattern or nil

		-- Walk every prefix of `path` (split on "/").  We append a
		-- trailing "/" so that the last segment is captured by the
		-- ([^/]+)/ pattern.  If any prefix matches, `path` is ignored
		-- (directory semantics: ignoring a directory ignores its contents).
		local matched = false
		local currentPath = ""
		for segment in (path .. "/"):gmatch("([^/]+)/") do
			currentPath = if currentPath == "" then segment else (currentPath .. "/" .. segment)

			if matchGlob(currentPath, glob1) or (glob2 ~= nil and matchGlob(currentPath, glob2)) then
				matched = true
				break
			end
		end

		if matched then
			result = not negate
		end
	end

	return result
end

return Ignore
