local RT = select(2, ...)
local W = RT.W

local max, format = math.max, string.format

-- A preset is { name = "Frost DK", ranks = { [tab] = { [talentIndex] = rank } } }.

local STAGE_ATTEMPTS = 400
local ROW_H = 34
local SAVE_H = 24
local MENU_W = 350

-- Reading the character ---------------------------------------------------------------------------

-- The ranks shown for the spec in view: staged points count, so a plan can be saved before it is learned.
local function currentRanks(ctx)
    local ranks = {}
    if ctx.plan then
        for tab = 1, GetNumTalentTabs(false, false) or 0 do
            local tree = {}
            for index, rank in pairs(RT.plan.ranks[tab] or {}) do
                if rank > 0 then tree[index] = rank end
            end
            ranks[tab] = tree
        end
        return ranks
    end
    for tab = 1, GetNumTalentTabs(false, false) or 0 do
        local tree = {}
        for index = 1, GetNumTalents(tab, false, false) or 0 do
            local _, _, _, _, rank, _, _, _, preview = GetTalentInfo(tab, index, false, false, ctx.group)
            local shown = ctx.editable and (preview or rank) or rank
            if (shown or 0) > 0 then tree[index] = shown end
        end
        ranks[tab] = tree
    end
    return ranks
end

local function rankIn(preset, tab, index)
    local tree = preset.ranks and preset.ranks[tab]
    return tree and tonumber(tree[index]) or 0
end

local function treeSplit(preset)
    local split = {}
    for tab = 1, GetNumTalentTabs(false, false) or 3 do
        local sum = 0
        for _, rank in pairs(preset.ranks and preset.ranks[tab] or {}) do sum = sum + (tonumber(rank) or 0) end
        split[tab] = sum
    end
    return split
end

-- Talents in the order the game lets them be bought: top tier first.
local function talentOrder()
    local order = {}
    for tab = 1, GetNumTalentTabs(false, false) or 0 do
        for index = 1, GetNumTalents(tab, false, false) or 0 do
            local _, _, tier = GetTalentInfo(tab, index, false, false)
            if tier then order[#order + 1] = { tab = tab, index = index, tier = tier } end
        end
    end
    table.sort(order, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.tab ~= b.tab then return a.tab < b.tab end
        return a.index < b.index
    end)
    return order
end

-- Applying ----------------------------------------------------------------------------------------

local function stagedRank(tab, index, group)
    local _, _, _, _, rank, _, _, _, preview = GetTalentInfo(tab, index, false, false, group)
    return preview or rank or 0
end

-- The game refuses a point whose tier or prerequisite is not staged yet, so sweep until nothing moves.
local function stage(preset, order, group)
    local attempts, moved = 0, true
    while moved and attempts < STAGE_ATTEMPTS do
        moved = false
        for _, talent in ipairs(order) do
            local want = rankIn(preset, talent.tab, talent.index)
            local have = stagedRank(talent.tab, talent.index, group)
            while have < want and attempts < STAGE_ATTEMPTS do
                attempts = attempts + 1
                AddPreviewTalentPoints(talent.tab, talent.index, 1, false, group)
                local now = stagedRank(talent.tab, talent.index, group)
                if now <= have then break end
                have, moved = now, true
            end
        end
    end
    local missing = 0
    for _, talent in ipairs(order) do
        missing = missing + max(0, rankIn(preset, talent.tab, talent.index) - stagedRank(talent.tab, talent.index, group))
    end
    return missing
end

function RT.ApplyPreset(preset)
    -- In a plan, a preset is loaded into the plan, to look at or change; nothing is staged.
    if RT.Context().plan then
        RT.PlanLoad(preset)
        RT.Refresh()
        RT.Notify(preset.name .. " loaded into the plan.", 0.2, 1, 0.2)
        return
    end
    if InCombatLockdown() then
        RT.Notify(ERR_NOT_IN_COMBAT, 1, 0.3, 0.3)
        return
    end
    local ctx = RT.Context()
    if ctx.pet or not ctx.editable then
        RT.Notify("Switch to this spec first, then apply the preset.", 1, 0.3, 0.3)
        return
    end
    local group = ctx.group
    local order = talentOrder()
    local needed = 0
    for _, talent in ipairs(order) do
        local _, _, _, _, learned = GetTalentInfo(talent.tab, talent.index, false, false, group)
        local want = rankIn(preset, talent.tab, talent.index)
        learned = learned or 0
        if want < learned then
            -- Wrath cannot take back a learned point; only a trainer reset can.
            RT.Notify("This spec has other talents learned. Reset them at your class trainer first.", 1, 0.3, 0.3)
            return
        end
        needed = needed + (want - learned)
    end
    if needed == 0 then
        RT.Notify("You already have this preset.", 0.2, 1, 0.2)
        return
    end
    local unspent = GetUnspentTalentPoints(false, false, group) or 0
    if unspent < needed then
        RT.Notify(format("This preset needs %d points; you have %d.", needed, unspent), 1, 0.3, 0.3)
        return
    end

    SetCVar("previewTalents", "1")
    ResetGroupPreviewTalentPoints(false, group)
    local missing = stage(preset, order, group)
    RT.Refresh()
    if missing > 0 then
        RT.Notify(format("Only %d of %d points fit. Check the trees before you learn them.", needed - missing, needed),
            1, 0.3, 0.3)
    else
        RT.Notify(preset.name .. " is ready. Check it, then Learn Talents.", 0.2, 1, 0.2)
    end
end

-- Saving and deleting -----------------------------------------------------------------------------

local function defaultName()
    local ctx = RT.Context()
    local ranks = currentRanks(ctx)
    local points = {}
    for tab = 1, GetNumTalentTabs(false, false) or 0 do
        local sum = 0
        for _, rank in pairs(ranks[tab] or {}) do sum = sum + rank end
        points[tab] = sum
    end
    local lead = RT.LeadingTree(points)
    return (GetTalentTabInfo(lead, false, false, ctx.group)) or "Preset"
end

local function savePreset(name)
    name = name and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then return end
    local ranks = currentRanks(RT.Context())
    local bucket = RT.ClassPresets()
    for _, preset in ipairs(bucket) do
        if preset.name == name then
            preset.ranks = ranks
            RT.Notify("Preset updated: " .. name, 0.2, 1, 0.2)
            return
        end
    end
    bucket[#bucket + 1] = { name = name, ranks = ranks }
    RT.Notify("Preset saved: " .. name, 0.2, 1, 0.2)
end

StaticPopupDialogs["RATREE_SAVE_PRESET"] = {
    text = "Save this build as a preset.\nA preset with the same name is replaced.",
    button1 = SAVE,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 40,
    OnShow = function(self)
        self.editBox:SetText(defaultName())
        self.editBox:HighlightText()
    end,
    OnAccept = function(self) savePreset(self.editBox:GetText()) end,
    EditBoxOnEnterPressed = function(self)
        savePreset(self:GetText())
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

StaticPopupDialogs["RATREE_DELETE_PRESET"] = {
    text = "Delete the preset %s?",
    button1 = DELETE,
    button2 = CANCEL,
    OnAccept = function(_, preset)
        local bucket = RT.ClassPresets()
        for i = #bucket, 1, -1 do
            if bucket[i] == preset then table.remove(bucket, i) end
        end
        RT.Call("PaintPresetMenu")
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

-- Menu --------------------------------------------------------------------------------------------

local menu
local rows = {}

local function newRow(index)
    local row = CreateFrame("Frame", nil, menu)
    row:SetSize(MENU_W - 2, ROW_H)
    row:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -24 - (index - 1) * ROW_H)
    -- The icon of the tree the preset puts the most points in, in a talent frame.
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(21, 21)
    row.icon:SetPoint("LEFT", row, "LEFT", 15, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local frame = row:CreateTexture(nil, "OVERLAY")
    frame:SetSize(26, 26)
    frame:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
    RT.TalentAtlas(frame, "square-yellow")
    row.name = W.Text(row, 13)
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 46, -4)
    row.split = W.Text(row, 11, W.DIM[1], W.DIM[2], W.DIM[3])
    row.split:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)

    row.delete = W.CloseButton("RatreePresetDelete" .. index, row)
    row.delete:SetSize(24, 24)
    row.delete:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.delete:SetScript("OnClick", function()
        StaticPopup_Show("RATREE_DELETE_PRESET", row.preset.name, nil, row.preset)
    end)
    W.TipOnHover(row.delete, "Delete preset")

    row.apply = W.Button("RatreePresetApply" .. index, row, 64, 24, "Apply")
    row.apply:SetPoint("RIGHT", row.delete, "LEFT", -6, 0)

    -- Move the preset up or down the list: the order is yours, not the order they were saved in.
    -- side by side, up then down, each in a fixed place
    -- (the up arrow is drawn in the bottom of its texture and the down arrow in the top, so each
    -- is moved by `y` to line them up on the row's middle)
    local function mover(dir, tex, x, y)
        local b = CreateFrame("Button", nil, row)
        b:SetSize(20, 20)
        b:SetPoint("RIGHT", row.apply, "LEFT", x, y)
        b:SetNormalTexture(tex .. "-Up")
        b:SetPushedTexture(tex .. "-Down")
        b:SetHighlightTexture(tex .. "-Highlight", "ADD")
        b:SetScript("OnClick", function()
            local bucket = RT.ClassPresets()
            local i = row.slot
            local j = i + dir
            if not (bucket[i] and bucket[j]) then return end
            bucket[i], bucket[j] = bucket[j], bucket[i]
            PlaySound("igMainMenuOptionCheckBoxOn")
            RT.PaintPresetMenu()
        end)
        return b
    end
    -- a long name is cut before the arrows
    row.name:SetPoint("RIGHT", row.apply, "LEFT", -52, 0)
    row.name:SetJustifyH("LEFT")
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.up = mover(-1, "Interface\\Buttons\\Arrow-Up", -26, 5)
    row.down = mover(1, "Interface\\Buttons\\Arrow-Down", -4, -5)
    W.TipOnHover(row.up, "Move up")
    W.TipOnHover(row.down, "Move down")
    row.apply:SetScript("OnClick", function()
        menu:Hide()
        RT.ApplyPreset(row.preset)
    end)
    W.TipOnHover(row.apply, "Apply", "Stages the preset's points. Nothing is learned until you press Learn Talents.")
    return row
end

local function buildMenu()
    menu = CreateFrame("Frame", nil, RT.win)
    menu:SetFrameLevel(RT.win:GetFrameLevel() + 20)
    menu:SetWidth(MENU_W)
    menu:EnableMouse(true)
    W.Solid(menu, "BACKGROUND", 0.063, 0.059, 0.051):SetAllPoints(menu)
    W.Border(menu, 0.42, 0.337, 0.188)
    local head = W.Text(menu, 10, W.DIM[1], W.DIM[2], W.DIM[3])
    head:SetPoint("TOPLEFT", menu, "TOPLEFT", 14, -9)
    head:SetText("SAVED PRESETS")

    menu.empty = W.Text(menu, 12, W.DIM[1], W.DIM[2], W.DIM[3])
    menu.empty:SetPoint("TOPLEFT", menu, "TOPLEFT", 14, -30)
    menu.empty:SetText("No presets for this class yet.")

    menu.save = W.Button("RatreePresetSave", menu, MENU_W - 24, SAVE_H, "Save current build as a preset")
    menu.save:SetScript("OnClick", function()
        menu:Hide()
        StaticPopup_Show("RATREE_SAVE_PRESET")
    end)
    menu:Hide()
end

function RT.PaintPresetMenu()
    if not menu or not menu:IsShown() then return end
    local bucket = RT.ClassPresets()
    for i, preset in ipairs(bucket) do
        local row = rows[i] or newRow(i)
        rows[i] = row
        row.preset, row.slot = preset, i
        row.name:SetText(preset.name)
        -- the first can't go up, the last can't go down
        if i > 1 then row.up:Show() else row.up:Hide() end
        if i < #bucket then row.down:Show() else row.down:Hide() end
        local split = treeSplit(preset)
        row.split:SetText(table.concat(split, " / "))
        local _, icon = GetTalentTabInfo(RT.LeadingTree(split), false, false)
        row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row:Show()
    end
    for i = #bucket + 1, #rows do rows[i]:Hide() end
    local listH = math.max(#bucket, 1) * ROW_H
    if #bucket == 0 then menu.empty:Show() else menu.empty:Hide() end
    menu.save:ClearAllPoints()
    menu.save:SetPoint("TOPLEFT", menu, "TOPLEFT", 12, -24 - listH - 8)
    menu:SetHeight(24 + listH + 8 + SAVE_H + 12)
end

function RT.TogglePresetMenu(anchor)
    if not menu then buildMenu() end
    if menu:IsShown() then
        menu:Hide()
        return
    end
    menu:ClearAllPoints()
    menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 8)
    menu:Show()
    RT.PaintPresetMenu()
end

function RT.ClosePresetMenu()
    if menu then menu:Hide() end
end
