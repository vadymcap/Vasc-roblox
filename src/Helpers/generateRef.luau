--!strict
local Vasc = script:FindFirstAncestor("Vasc")

local Types = require(Vasc.Types)

return function(): Types.Ref
	local buf = buffer.create(16)

	for i = 0, 15 do
		buffer.writeu8(buf, i, math.random(0, 255))
	end

	return buf
end
