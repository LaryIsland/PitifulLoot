local addonName, ns = ...

-- The options, described once and shown twice: on a page in the game's own options (Options > AddOns), built with
-- the Settings API as Blizzard's are, and on the window's Options tab (UI.lua). Officer options only matter to the
-- writer; the Options tab hides them unless an officer asks to see them.

local PREFIX = "PITIFULLOOT_"

local function Seconds(value)
	return ("%d sec"):format(value)
end

ns.OPTIONS = {
	{ section = "Announcements", officer = true },
	{ key = "announce", officer = true, kind = "checkbox", name = "Announce in Raid Chat",
		tooltip = "As the writer, post each roll, tie and result to raid chat, so players without the addon can follow along." },
	{ key = "raidWarning", officer = true, kind = "checkbox", name = "Use Raid Warnings",
		tooltip = "As the writer, post the start of each roll, ties and results as raid warnings, if you're the raid leader or an assistant. Breakdowns still go to raid chat." },
	{ section = "Rolls", officer = true },
	{ key = "rollTime", officer = true, kind = "slider", name = "Roll Time", min = 10, max = 120, step = 5, format = Seconds,
		tooltip = "How long players have to /roll when a roll starts." },
	{ key = "rerollTime", officer = true, kind = "slider", name = "Reroll Time", min = 10, max = 60, step = 5, format = Seconds,
		tooltip = "How long tied players have to /roll again." },
	{ key = "minQuality", officer = true, kind = "dropdown", name = "Loot Quality",
		choices = { { 2, "Uncommon" }, { 3, "Rare" }, { 4, "Epic" }, { 5, "Legendary" } },
		tooltip = "The lowest item quality listed from the loot window for rolling." },
	{ section = "Window" },
	{ key = "autoShow", kind = "checkbox", name = "Show When I Can Roll",
		tooltip = "Open the window on the Roll tab whenever a roll starts that you can take part in." },
	{ key = "pityByBoss", kind = "checkbox", name = "Group My Pity by Boss",
		tooltip = "On the My pity tab, group items by the boss that drops them, inside each raid." },
}

-- Changing an option, from either place.
function ns.SetOption(key, value)
	ns.settings[key] = value
	ns.Fire("SETTINGS_CHANGED", key)
	if ns.RefreshWindow then ns.RefreshWindow() end
end

local function RegisterOptions()
	local category = Settings.RegisterVerticalLayoutCategory("Pitiful Loot")
	local types = { checkbox = Settings.VarType.Boolean, slider = Settings.VarType.Number, dropdown = Settings.VarType.Number }
	for _, option in ipairs(ns.OPTIONS) do
		if option.key then
			local key = option.key
			-- Proxied rather than bound to a table, as the table changes with the profile.
			local setting = Settings.RegisterProxySetting(category, PREFIX .. key:upper(), types[option.kind], option.name,
				ns.DEFAULTS[key], function() return ns.settings[key] end, function(value) ns.SetOption(key, value) end)
			if option.kind == "checkbox" then
				Settings.CreateCheckbox(category, setting, option.tooltip)
			elseif option.kind == "slider" then
				local sliderOptions = Settings.CreateSliderOptions(option.min, option.max, option.step)
				sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, option.format)
				Settings.CreateSlider(category, setting, sliderOptions, option.tooltip)
			else
				Settings.CreateDropdown(category, setting, function()
					local container = Settings.CreateControlTextContainer()
					for _, choice in ipairs(option.choices) do container:Add(choice[1], choice[2]) end
					return container:GetData()
				end, option.tooltip)
			end
		end
	end
	Settings.RegisterAddOnCategory(category)
	ns.optionsCategory = category
end

function ns.OpenOptions()
	Settings.OpenToCategory(ns.optionsCategory:GetID())
end

ns.On("ADDON_LOADED", function(name)
	if name == addonName then RegisterOptions() end
end)
