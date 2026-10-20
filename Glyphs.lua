local RT = select(2, ...)
local W = RT.W

local abs, sin, sqrt = math.abs, math.sin, math.sqrt

local MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
local LINE = "Interface\\TaxiFrame\\UI-Taxi-Line"

local MAJOR = { ring = 84 }
local MINOR = { ring = 64 }

-- Offsets from the hexagram's centre, y up; odd slots are the major triangle, even the minor one.
local SLOT_XY = { { 0, 120 }, { 104, 60 }, { 104, -60 }, { 0, -120 }, { -104, -60 }, { -104, 60 } }
local HUB_PAIRS = { { 1, 3 }, { 3, 5 }, { 5, 1 }, { 2, 4 }, { 4, 6 }, { 6, 2 } }
local HUB_X, HUB_Y = 300, -330

local CARD_X, CARD_Y, CARD_W = 590, -96, 460

local root, hub, card, switch
local sockets, hubLines, slotOfSocket = {}, {}, {}
local cardTexts, cardIcons = {}, {}
local descriptions, abilityIcons = {}, {}

-- Glyph text and icons ----------------------------------------------------------------------------

local function glyphName(spell)
    local name = spell and GetSpellInfo(spell)
    if not name then return "?" end
    return (name:gsub("^Glyph of ", ""))
end

-- Spell text arrives late, so only a non-empty read is cached.
local function glyphDescription(spell)
    if descriptions[spell] then return descriptions[spell] end
    local scratch = _G.RatreeScratchTip
    if not scratch then
        scratch = CreateFrame("GameTooltip", "RatreeScratchTip", UIParent, "GameTooltipTemplate")
    end
    scratch:SetOwner(UIParent, "ANCHOR_NONE")
    scratch:SetHyperlink("spell:" .. spell)
    local found = ""
    for line = scratch:NumLines(), 2, -1 do
        local region = _G["RatreeScratchTipTextLeft" .. line]
        local text = region and region:GetText()
        if text and text:find("%S") then
            found = text
            break
        end
    end
    scratch:Hide()
    if found ~= "" then descriptions[spell] = found end
    return found
end

-- The game gives a glyph only its rune, so the ability it changes is looked up by name among the
-- spellbook and every talent of the class (talent spells of the other spec are not in the book).
local pool

local function abilityPool()
    if pool then return pool end
    pool = {}
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, count = GetSpellTabInfo(tab)
        for i = offset + 1, offset + count do
            local name = GetSpellName(i, BOOKTYPE_SPELL)
            if name then pool[#pool + 1] = { name = name, icon = GetSpellTexture(i, BOOKTYPE_SPELL) } end
        end
    end
    for tab = 1, GetNumTalentTabs(false, false) or 0 do
        for index = 1, GetNumTalents(tab, false, false) or 0 do
            local name, icon = GetTalentInfo(tab, index, false, false)
            if name then pool[#pool + 1] = { name = name, icon = icon } end
        end
    end
    return pool
end

-- "Glyph of Obliterate" is Obliterate; "Glyph of Judgement" is the shortest spell starting with
-- Judgement; otherwise the longest ability the glyph's text names.
local function findIcon(name, text)
    local starts, startsLen, named, namedLen
    for _, entry in ipairs(abilityPool()) do
        local candidate = entry.name
        if candidate == name then return entry.icon end
        if candidate:sub(1, #name) == name and (not startsLen or #candidate < startsLen) then
            starts, startsLen = entry.icon, #candidate
        end
        if #candidate > 3 and text:find(candidate, 1, true) and (not namedLen or #candidate > namedLen) then
            named, namedLen = entry.icon, #candidate
        end
    end
    return starts or named
end

local function abilityIcon(spell, rune)
    if abilityIcons[spell] then return abilityIcons[spell] end
    local icon = findIcon(glyphName(spell), glyphDescription(spell))
    if icon then abilityIcons[spell] = icon end
    return icon or rune
end

RT.Listen("SPELLS_CHANGED", function() pool = nil end)

local function emptyIcon(kind)
    local class = RT.PlayerClass()
    local proper = class == "DEATHKNIGHT" and "DeathKnight" or (class:sub(1, 1) .. class:sub(2):lower())
    return "Interface\\Icons\\INV_Glyph_" .. (kind == MINOR and "Minor" or "Major") .. proper
end

-- Sockets -----------------------------------------------------------------------------------------

local function socketTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetGlyph(button.socket, RT.view.group)
end

local function socketClicked(button, mouse)
    local socket, group = button.socket, RT.view.group
    if not socket then return end
    local active = group == RT.ActiveGroup()
    if IsModifiedClick("CHATLINK") and ChatEdit_GetActiveWindow() then
        local link = GetGlyphLink(socket, group)
        if link then ChatEdit_InsertLink(link) end
    elseif mouse == "RightButton" then
        if IsShiftKeyDown() and active and button.hasGlyph then
            local _, _, spell = GetGlyphSocketInfo(socket, group)
            if spell then StaticPopup_Show("RATREE_GLYPH_REMOVE", GetSpellInfo(spell), nil, socket) end
        end
    elseif active then
        if button.hasGlyph and GlyphMatchesSocket(socket) then
            StaticPopup_Show("RATREE_GLYPH_REPLACE", nil, nil, socket)
        else
            PlaceGlyphInSocket(socket)
        end
    end
end

local function disc(parent, layer)
    local tex = parent:CreateTexture(nil, layer)
    tex:SetTexture(MASK)
    tex:SetPoint("CENTER", parent, "CENTER", 0, 0)
    return tex
end

local function newSocket(slot)
    local button = CreateFrame("Button", nil, hub)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetPoint("CENTER", hub, "CENTER", SLOT_XY[slot][1], SLOT_XY[slot][2])
    button.glow = button:CreateTexture(nil, "BACKGROUND")
    button.glow:SetTexture(GLOW)
    button.glow:SetBlendMode("ADD")
    button.glow:SetVertexColor(1, 0.84, 0.28)
    button.glow:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.glow:SetAlpha(0)
    button.back = disc(button, "BORDER")
    button.back:SetVertexColor(0.03, 0.03, 0.035)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.ring = button:CreateTexture(nil, "OVERLAY")
    button.ring:SetTexture(RT.RING)
    button.ring:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetScript("OnClick", socketClicked)
    button:SetScript("OnEnter", function(self)
        self.hovered = true
        socketTooltip(self)
    end)
    button:SetScript("OnLeave", function(self)
        self.hovered = false
        GameTooltip_Hide()
    end)
    return button
end

local function paintSocket(button, socket, group, activeGroup)
    button.socket = socket
    local enabled, glyphType, spell, rune = GetGlyphSocketInfo(socket, group)
    local kind = glyphType == 2 and MINOR or MAJOR
    local hasGlyph = enabled and spell and true or false
    local lit = hasGlyph and group == activeGroup
    button.enabled, button.hasGlyph = enabled and true or false, hasGlyph

    local ring = kind.ring
    button:SetSize(ring, ring)
    button.glow:SetSize(ring * 1.9, ring * 1.9)
    button.back:SetSize(ring - 2, ring - 2)
    button.icon:SetSize(ring * RT.ICON_IN_RING, ring * RT.ICON_IN_RING)
    button.ring:SetSize(ring, ring)

    if not enabled then
        button.ring:SetVertexColor(0.3, 0.3, 0.3)
    elseif lit then
        button.ring:SetVertexColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
    else
        button.ring:SetVertexColor(0.55, 0.45, 0.25)
    end

    if hasGlyph then
        RT.SetRoundIcon(button.icon, abilityIcon(spell, rune))
        button.icon:SetDesaturated(false)
        button.icon:SetAlpha(lit and 1 or 0.7)
        button.icon:Show()
    elseif enabled then
        RT.SetRoundIcon(button.icon, emptyIcon(kind))
        button.icon:SetDesaturated(true)
        button.icon:SetAlpha(0.3)
        button.icon:Show()
    else
        button.icon:Hide()
    end
    button:SetAlpha(enabled and 1 or 0.55)
    button:Show()
end

-- Hexagram lines ----------------------------------------------------------------------------------

local function drawHub(active)
    for index, pair in ipairs(HUB_PAIRS) do
        local line = hubLines[index]
        local a, b = sockets[pair[1]], sockets[pair[2]]
        if a:IsShown() and b:IsShown() then
            local ax, ay = SLOT_XY[pair[1]][1], SLOT_XY[pair[1]][2]
            local bx, by = SLOT_XY[pair[2]][1], SLOT_XY[pair[2]][2]
            local dx, dy = bx - ax, by - ay
            local length = sqrt(dx * dx + dy * dy)
            dx, dy = dx / length, dy / length
            local trimA, trimB = a:GetWidth() / 2, b:GetWidth() / 2
            DrawRouteLine(line, hub, ax + dx * trimA, ay + dy * trimA, bx - dx * trimB, by - dy * trimB, 32, "CENTER")
            if active then
                line:SetVertexColor(1, 0.84, 0.18, 0.95)
            else
                line:SetVertexColor(0.62, 0.49, 0.24, 0.45)
            end
            line:Show()
        else
            line:Hide()
        end
    end
end

-- Effects card ------------------------------------------------------------------------------------

local function cardText(index)
    local text = cardTexts[index]
    if not text then
        text = card:CreateFontString(nil, "OVERLAY")
        text:SetShadowOffset(1, -1)
        text:SetJustifyH("LEFT")
        cardTexts[index] = text
    end
    text:ClearAllPoints()
    return text
end

local function cardIcon(index)
    local icon = cardIcons[index]
    if not icon then
        icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(30 * RT.ICON_IN_RING, 30 * RT.ICON_IN_RING)
        icon.ring = card:CreateTexture(nil, "OVERLAY")
        icon.ring:SetTexture(RT.RING)
        icon.ring:SetVertexColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
        icon.ring:SetSize(30, 30)
        icon.ring:SetPoint("CENTER", icon, "CENTER", 0, 0)
        cardIcons[index] = icon
    end
    icon:ClearAllPoints()
    return icon
end

local function paintCard(group)
    local majors, minors = {}, {}
    for socket = 1, GetNumGlyphSockets() or 0 do
        local enabled, glyphType, spell, rune = GetGlyphSocketInfo(socket, group)
        if enabled and spell then
            local list = glyphType == 2 and minors or majors
            list[#list + 1] = { name = glyphName(spell), icon = abilityIcon(spell, rune), text = glyphDescription(spell) }
        end
    end

    local y, texts, icons = -20, 0, 0
    local function line(size, r, g, b, value, x, width, font)
        texts = texts + 1
        local text = cardText(texts)
        text:SetFont(font or STANDARD_TEXT_FONT, size)
        text:SetTextColor(r, g, b)
        text:SetWidth(width)
        text:SetText(value)
        text:SetPoint("TOPLEFT", card, "TOPLEFT", x, y)
        text:Show()
        y = y - text:GetStringHeight()
        return text
    end

    for _, section in ipairs({ { MAJOR_GLYPH, majors }, { MINOR_GLYPH, minors } }) do
        line(19, 0.91, 0.77, 0.42, section[1], 24, CARD_W - 48, RT.HEADER_FONT)
        y = y - 8
        if #section[2] == 0 then
            line(12, 0.5, 0.5, 0.5, "None", 64, CARD_W - 88)
            y = y - 6
        end
        for _, glyph in ipairs(section[2]) do
            local top = y
            line(13, 1, 0.82, 0, glyph.name, 64, CARD_W - 88)
            if glyph.text ~= "" then
                y = y - 2
                line(11, 0.7, 0.7, 0.7, glyph.text, 64, CARD_W - 88)
            end
            icons = icons + 1
            local icon = cardIcon(icons)
            RT.SetRoundIcon(icon, glyph.icon)
            icon.ring:Show()
            icon:SetPoint("LEFT", card, "TOPLEFT", 26, (top + y) / 2)
            icon:Show()
            y = y - 10
        end
        y = y - 10
    end
    for i = texts + 1, #cardTexts do cardTexts[i]:Hide() end
    for i = icons + 1, #cardIcons do
        cardIcons[i]:Hide()
        cardIcons[i].ring:Hide()
    end
    card:SetHeight(-y + 10)
end

-- Spec switch in the footer -----------------------------------------------------------------------

local function switchColors()
    for group = 1, 2 do
        local button = switch.buttons[group]
        if group == RT.view.group then
            button.text:SetTextColor(1, 1, 1)
            button.underline:Show()
        else
            local grey = button.hovered and 0.8 or 0.5
            button.text:SetTextColor(grey, grey, grey)
            button.underline:Hide()
        end
    end
end

local function buildSwitch()
    local footer = RT.footer
    switch = CreateFrame("Frame", nil, footer)
    switch:SetHeight(26)
    switch:SetPoint("CENTER", footer, "CENTER", 0, 0)
    switch.buttons = {}
    for group = 1, 2 do
        local button = CreateFrame("Button", nil, switch)
        button:SetHeight(26)
        button.text = W.Text(button, 16, 1, 1, 1, RT.HEADER_FONT)
        button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.underline = W.Solid(button, "OVERLAY", W.GOLD[1], W.GOLD[2], W.GOLD[3])
        button.underline:SetHeight(2)
        button.underline:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 0)
        button.underline:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 0)
        button:SetScript("OnClick", function()
            if RT.view.group == group then return end
            PlaySound("igCharacterInfoTab")
            RT.view.group = group
            RT.Refresh()
        end)
        button:SetScript("OnEnter", function(self)
            self.hovered = true
            switchColors()
        end)
        button:SetScript("OnLeave", function(self)
            self.hovered = false
            switchColors()
        end)
        switch.buttons[group] = button
    end
    switch.dot = W.Text(switch, 16, 0.5, 0.5, 0.5, RT.HEADER_FONT)
    switch.dot:SetText("·")
    switch:Hide()
end

function RT.UpdateGlyphSwitch()
    if not switch then return end
    local shown = RT.view.page == "glyphs" and RT.NumGroups() >= 2
    if not shown then
        switch:Hide()
        return
    end
    switch:Show()
    local widths = {}
    for group = 1, 2 do
        local button = switch.buttons[group]
        button.text:SetText(RT.SpecName(group):upper())
        widths[group] = button.text:GetStringWidth() + 8
        button:SetWidth(widths[group])
    end
    switch.buttons[1]:ClearAllPoints()
    switch.buttons[1]:SetPoint("LEFT", switch, "LEFT", 0, 0)
    switch.buttons[2]:ClearAllPoints()
    switch.buttons[2]:SetPoint("RIGHT", switch, "RIGHT", 0, 0)
    switch:SetWidth(widths[1] + 36 + widths[2])
    switch.dot:ClearAllPoints()
    switch.dot:SetPoint("CENTER", switch, "LEFT", widths[1] + 18, 0)
    switchColors()
end

-- Page --------------------------------------------------------------------------------------------

-- Sockets that fit the glyph on the cursor pulse while it is being placed.
local function animate(self, elapsed)
    self.wait = self.wait + elapsed
    if self.wait < 0.05 then return end
    self.wait = 0
    local targeting = SpellIsTargeting()
    local beat = 0.4 + 0.4 * abs(sin(2 * GetTime()))
    for _, button in ipairs(sockets) do
        if button:IsShown() then
            local fits = targeting and button.enabled and button.socket and GlyphMatchesSocket(button.socket)
            button.glow:SetAlpha(fits and beat or 0)
            if button.hovered and targeting then
                SetCursor(fits and "CAST_CURSOR" or "CAST_ERROR_CURSOR")
            end
        end
    end
end

function RT.BuildGlyphRoot(body)
    root = CreateFrame("Frame", nil, body)
    root:SetAllPoints(body)
    root:Hide()

    local heading = W.Text(root, 26, 1, 1, 1, RT.HEADER_FONT)
    heading:SetPoint("TOP", root, "TOP", 0, -26)
    heading:SetText(GLYPHS:upper())

    hub = CreateFrame("Frame", nil, root)
    hub:SetSize(10, 10)
    hub:SetPoint("CENTER", root, "TOPLEFT", HUB_X, HUB_Y)
    for index = 1, #HUB_PAIRS do
        local line = hub:CreateTexture(nil, "BACKGROUND")
        line:SetTexture(LINE)
        hubLines[index] = line
    end
    for slot = 1, 6 do sockets[slot] = newSocket(slot) end

    card = CreateFrame("Frame", nil, root)
    card:SetWidth(CARD_W)
    card:SetPoint("TOPLEFT", root, "TOPLEFT", CARD_X, CARD_Y)
    W.Solid(card, "BACKGROUND", 0.03, 0.03, 0.04, 0.85):SetAllPoints(card)
    W.Border(card, 0.29, 0.25, 0.19)

    buildSwitch()
    root.wait = 0
    root:SetScript("OnUpdate", animate)
end

function RT.ShowGlyphRoot()
    if root then root:Show() end
end

function RT.HideGlyphRoot()
    if root then root:Hide() end
end

function RT.PaintGlyphs()
    if not root then return end
    local group, activeGroup = RT.view.group, RT.ActiveGroup()
    root:Show()

    local spent = {}
    for tab = 1, GetNumTalentTabs(false, false) or 0 do
        local _, _, points = GetTalentTabInfo(tab, false, false, group)
        spent[tab] = points or 0
    end
    RT.SetArt(RT.PlayerClass(), RT.LeadingTree(spent), group ~= activeGroup)

    wipe(slotOfSocket)
    local nextMajor, nextMinor, bySlot = 1, 2, {}
    for socket = 1, GetNumGlyphSockets() or 0 do
        local _, glyphType = GetGlyphSocketInfo(socket, group)
        if glyphType == 2 then
            if nextMinor <= 6 then bySlot[nextMinor], nextMinor = socket, nextMinor + 2 end
        elseif nextMajor <= 5 then
            bySlot[nextMajor], nextMajor = socket, nextMajor + 2
        end
    end
    for slot = 1, 6 do
        local socket = bySlot[slot]
        if socket then
            slotOfSocket[socket] = slot
            paintSocket(sockets[slot], socket, group, activeGroup)
        else
            sockets[slot].socket = nil
            sockets[slot]:Hide()
        end
    end
    drawHub(group == activeGroup)
    paintCard(group)

    local owner = GameTooltip:GetOwner()
    if owner and owner.socket and owner:IsVisible() then socketTooltip(owner) end
end

-- Events ------------------------------------------------------------------------------------------

local function onGlyphEvent(event, socket)
    if not root or not root:IsVisible() then return end
    RT.PaintGlyphs()
    socket = tonumber(socket)
    if not socket then return end
    local _, glyphType = GetGlyphSocketInfo(socket, RT.ActiveGroup())
    local size = glyphType == 2 and "Minor" or "Major"
    PlaySound("Glyph_" .. size .. (event == "GLYPH_REMOVED" and "Destroy" or "Create"))
end

RT.Listen("GLYPH_ADDED", onGlyphEvent)
RT.Listen("GLYPH_REMOVED", onGlyphEvent)
RT.Listen("GLYPH_UPDATED", onGlyphEvent)

StaticPopupDialogs["RATREE_GLYPH_REMOVE"] = {
    text = CONFIRM_REMOVE_GLYPH,
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, socket) RemoveGlyphFromSocket(socket) end,
    timeout = 0,
    hideOnEscape = 1,
}

StaticPopupDialogs["RATREE_GLYPH_REPLACE"] = {
    text = CONFIRM_GLYPH_PLACEMENT,
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, socket) PlaceGlyphInSocket(socket) end,
    timeout = 0,
    hideOnEscape = 1,
}
