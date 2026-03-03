local Vasc = script:FindFirstAncestor("Vasc")
local App = Vasc.App
local Components = App.Components

local Fusion = require(Vasc.Packages.Fusion)
local Signal = require(Vasc.Packages.Signal)

local Types = require(Vasc.Types)
local Theme = require(App.Theme)

local ScrollingContainer = require(Components.ScrollingContainer)
local TextButton = require(Components.TextButton)
local Container = require(Components.Container)
local Padding = require(Components.Padding)
local Text = require(Components.Text)
local List = require(Components.List)
local Box = require(Components.Box)

local Computed = Fusion.Computed
local ForValues = Fusion.ForValues
local Children = Fusion.Children
local cleanup = Fusion.cleanup

type Props = {
	App: { [string]: any },
	Changes: Types.Changes,
	SkippedIgnored: number?,
	Signal: Signal.Signal,
}

local function hex(kind: string): string
	return "#" .. Theme.Colors.Diff[kind]:ToHex()
end

local function s(n: number): string
	return n ~= 1 and "s" or ""
end

-- Build a one-line label for an addition snapshot
local function additionLabel(snapshot: Types.AddedSnapshot): string
	return `+ {snapshot.name} ({snapshot.class})`
end

local function countKeys(t: { [string]: any }?): number
	if not t then
		return 0
	end
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- Build a one-line label for an update snapshot
local function updateLabel(snapshot: Types.UpdatedSnapshot): string
	local name = snapshot.name or "(ref)"
	local propCount = countKeys(snapshot.properties)

	local parts = {}
	if snapshot.class then
		table.insert(parts, `class→{snapshot.class}`)
	end
	if snapshot.name then
		table.insert(parts, `name→{snapshot.name}`)
	end
	if propCount > 0 then
		table.insert(parts, `{propCount} prop{s(propCount)}`)
	end
	local detail = #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""

	return `~ {name}{detail}`
end

-- Build a one-line label for a removal entry (Ref or Instance)
local function removalLabel(object: Types.Ref | Instance): string
	if typeof(object) == "Instance" then
		return `- {(object :: Instance).Name}`
	end
	return "- (removed)"
end

-- Render a section with a coloured header and item list.
-- Returns nil if items is empty (caller should check before inserting).
local function Section(title: string, color: Color3, items: { string }): Frame?
	if #items == 0 then
		return nil
	end

	return Container {
		Size = UDim2.fromScale(1, 0),
		[Children] = {
			List {},
			Text {
				Text = title,
				Font = Theme.Fonts.Bold,
				TextSize = Theme.TextSize.Medium,
				Color = color,
			},
			ForValues(items, function(_, label)
				return Text {
					Text = label,
					Font = Theme.Fonts.Mono,
					TextSize = Theme.TextSize.Small,
					Color = Theme.Colors.TextDimmed,
				}
			end, cleanup),
		},
	}
end

return function(props: Props): { Instance }
	local changes = props.Changes
	local skipped = props.SkippedIgnored or 0

	local adds = #changes.additions
	local upds = #changes.updates
	local rems = #changes.removals

	-- Build summary line
	local summaryParts = {}
	if adds > 0 then
		table.insert(
			summaryParts,
			`<font color="{hex("Add")}">{adds} addition{s(adds)}</font>`
		)
	end
	if upds > 0 then
		table.insert(
			summaryParts,
			`<font color="{hex("Update")}">{upds} update{s(upds)}</font>`
		)
	end
	if rems > 0 then
		table.insert(
			summaryParts,
			`<font color="{hex("Remove")}">{rems} removal{s(rems)}</font>`
		)
	end
	if skipped > 0 then
		table.insert(summaryParts, `{skipped} skipped (ignored)`)
	end
	local summary = #summaryParts > 0 and table.concat(summaryParts, "  ") or "No changes"

	-- Build item label lists
	local addLabels: { string } = {}
	for _, snapshot in changes.additions do
		table.insert(addLabels, additionLabel(snapshot))
	end

	local updLabels: { string } = {}
	for _, snapshot in changes.updates do
		table.insert(updLabels, updateLabel(snapshot))
	end

	local remLabels: { string } = {}
	for _, object in changes.removals do
		table.insert(remLabels, removalLabel(object))
	end

	-- Build the scrollable content children, excluding empty sections
	local scrollChildren: { any } = {
		List {},
		Padding {},
		Text {
			Text = summary,
			RichText = true,
			TextWrapped = true,
			Font = Theme.Fonts.Bold,
			TextSize = Theme.TextSize.Medium,
		},
	}
	local addSection = Section(`Additions ({adds})`, Theme.Colors.Diff.Add, addLabels)
	if addSection then table.insert(scrollChildren, addSection) end
	local updSection = Section(`Updates ({upds})`, Theme.Colors.Diff.Update, updLabels)
	if updSection then table.insert(scrollChildren, updSection) end
	local remSection = Section(`Removals ({rems})`, Theme.Colors.Diff.Remove, remLabels)
	if remSection then table.insert(scrollChildren, remSection) end

	return {
		List {
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
		},
		Box {
			AutomaticSize = Enum.AutomaticSize.None,
			Size = Computed(function(use)
				local rootSize = use(props.App.rootSize)
				return UDim2.new(1, 0, 0, math.max(rootSize.Y - 120, 60))
			end),
			[Children] = {
				ScrollingContainer {
					Size = UDim2.new(1, -2, 1, 0),
					ScrollBar = true,
					[Children] = scrollChildren,
				},
			},
		},
		Container {
			Size = UDim2.fromScale(1, 0),
			[Children] = {
				List {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Right,
				},
				TextButton {
					Text = "Back",
					Solid = true,
					Activated = function()
						props.Signal:Fire("Back")
					end,
				},
			},
		},
	}
end
