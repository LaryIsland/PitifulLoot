local _, ns = ...

-- The font the addon's text is in (an option, 5.2): Cabin, which comes with the addon (Media, under the SIL Open Font
-- License), the game's own font (Friz Quadrata), or Arial Narrow. Every font object the addon's text uses has a copy
-- of its own in that font, at the same size and with the same outline, so changing the option changes all of the
-- text at once. The
-- game's tooltips, right-click menus and dialogs are shared with the rest of the game, so they keep its font.
-- Cabin has only western European letters, so a game in Russian, Korean or Chinese keeps its own font.

local CABIN = "Interface\\AddOns\\PitifulLoot\\Media\\Cabin-Bold.ttf"
local LATIN_ONLY = { ruRU = true, koKR = true, zhCN = true, zhTW = true }

ns.FONTS = {
	{ "cabin", "Cabin", CABIN },
	{ "game", "Friz Quadrata" }, -- the game's own: Friz Quadrata, or its version for the game's language
	{ "arialn", "Arial Narrow", "Fonts\\ARIALN.TTF" },
}

-- The chosen font's file, or nil for the game's own.
function ns.FontFile()
	local key = ns.settings and ns.settings.font
	for _, font in ipairs(ns.FONTS) do
		if font[1] == key then
			if font[3] == CABIN and LATIN_ONLY[GetLocale()] then return nil end
			return font[3]
		end
	end
	return nil
end

local copies = {} -- [the game's font object] = the addon's copy of it
local originals = {} -- [the addon's copy] = the game's font object
local count = 0

local function Apply(copy)
	local file, size, flags = originals[copy]:GetFont()
	local chosen = ns.FontFile()
	-- SetFont says false for a font the game hasn't got.
	if not chosen or copy:SetFont(chosen, size, flags or "") == false then copy:SetFont(file, size, flags or "") end
end

-- The addon's copy of a font object (or a font object's name); the copy itself is its own.
function ns.Font(original)
	if type(original) == "string" then original = _G[original] end
	if not original or originals[original] then return original end
	local copy = copies[original]
	if not copy then
		count = count + 1
		copy = CreateFont("PitifulLootFont" .. count)
		copy:CopyFontObject(original)
		copies[original], originals[copy] = copy, original
		Apply(copy)
	end
	return copy
end

-- Font strings whose font the addon sets itself (the queue's numbers), left alone.
local ownFont = setmetatable({}, { __mode = "k" })
function ns.KeepFont(fontString)
	ownFont[fontString] = true
end

-- Puts a font string, and every font string in a frame and the frames in it, in the addon's font. Changing a font
-- string's font object resets its colour and alignment to the font object's, so those are kept.
local function UseFont(fontString)
	if ownFont[fontString] then return end
	local copy = ns.Font(fontString:GetFontObject())
	if not copy or copy == fontString:GetFontObject() then return end
	local r, g, b, a = fontString:GetTextColor()
	local justifyH, justifyV = fontString:GetJustifyH(), fontString:GetJustifyV()
	fontString:SetFontObject(copy)
	if r then fontString:SetTextColor(r, g, b, a) end
	if justifyH then fontString:SetJustifyH(justifyH) end
	if justifyV then fontString:SetJustifyV(justifyV) end
end

local BUTTON_FONTS = { "Normal", "Highlight", "Disabled" }

function ns.UseAddonFont(object)
	if object:GetObjectType() == "FontString" then return UseFont(object) end
	-- A button's text changes font object as it's highlighted or disabled.
	if object.GetNormalFontObject then
		for _, state in ipairs(BUTTON_FONTS) do
			local copy = ns.Font(object["Get" .. state .. "FontObject"](object))
			if copy then object["Set" .. state .. "FontObject"](object, copy) end
		end
	end
	for _, region in ipairs({ object:GetRegions() }) do
		if region:GetObjectType() == "FontString" then UseFont(region) end
	end
	for _, child in ipairs({ object:GetChildren() }) do ns.UseAddonFont(child) end
end

local function ApplyAll()
	for copy in pairs(originals) do Apply(copy) end
	ns.Fire("FONT_CHANGED")
end
ns.Listen("SETTINGS_CHANGED", function(key)
	if key == nil or key == "font" then ApplyAll() end
end)
ns.On("PLAYER_LOGIN", ApplyAll)
