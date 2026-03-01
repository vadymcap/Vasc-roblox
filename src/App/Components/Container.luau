local Vasc = script:FindFirstAncestor("Vasc")

local Fusion = require(Vasc.Packages.Fusion)

local New = Fusion.New
local Hydrate = Fusion.Hydrate

type Props = {
	[any]: any,
}

return function(props: Props): Frame
	return Hydrate(New "Frame" {
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
	})(props)
end
