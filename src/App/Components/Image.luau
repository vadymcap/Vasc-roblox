local Vasc = script:FindFirstAncestor("Vasc")

local Fusion = require(Vasc.Packages.Fusion)

local New = Fusion.New
local Hydrate = Fusion.Hydrate

type Props = {
	[any]: any,
}

return function(props: Props): ImageLabel
	return Hydrate(New("ImageLabel") {
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
	})(props)
end
