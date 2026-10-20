local RT = select(2, ...)
local W = RT.W

RT.WIDTH = 1100
RT.TITLE_H = 24
RT.BODY_H = 620
RT.FOOTER_H = 64

-- The art is 2:1; the body is wider than tall by less, so the left side is cut and the rat stays.
local ART_LEFT = 1 - (RT.WIDTH / RT.BODY_H) / 2

-- Art ---------------------------------------------------------------------------------------------

-- Full colour; a spec you are only browsing is shown darker.
function RT.SetArt(class, tree, browsing)
    local art = RT.art
    art:SetTexture(RT.ArtFor(class, tree))
    art:SetTexCoord(ART_LEFT, 1, 0, 1)
    art:SetDesaturated(false)
    local shade = browsing and 0.55 or 1
    art:SetVertexColor(shade, shade, shade)
end

local function buildArt(body)
    local art = body:CreateTexture(nil, "BACKGROUND", nil, 1)
    art:SetAllPoints(body)
    RT.art = art

    -- Darkens the left two thirds where the trees sit; the rat on the right stays visible.
    local left = body:CreateTexture(nil, "BACKGROUND", nil, 2)
    left:SetTexture(1, 1, 1, 1)
    left:SetGradientAlpha("HORIZONTAL", 0.04, 0.04, 0.045, 0.9, 0.04, 0.04, 0.045, 0.6)
    left:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", body, "BOTTOMLEFT", RT.WIDTH * 0.45, 0)
    local right = body:CreateTexture(nil, "BACKGROUND", nil, 2)
    right:SetTexture(1, 1, 1, 1)
    right:SetGradientAlpha("HORIZONTAL", 0.04, 0.04, 0.045, 0.6, 0.04, 0.04, 0.045, 0)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
end

-- Title bar and portrait --------------------------------------------------------------------------

local function buildTitle(win)
    local bar = CreateFrame("Frame", nil, win)
    bar:SetHeight(RT.TITLE_H)
    bar:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(1, 1, 1, 1)
    bg:SetGradientAlpha("VERTICAL", 0.082, 0.075, 0.059, 1, 0.141, 0.125, 0.102, 1)
    bg:SetAllPoints(bar)
    local line = W.Solid(bar, "BORDER", W.EDGE[1], W.EDGE[2], W.EDGE[3])
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)

    local title = W.Text(bar, 12, 0.878, 0.761, 0.478)
    title:SetPoint("CENTER", bar, "CENTER", 0, 0)
    RT.title = title

    local close = W.CloseButton("RatreeCloseButton", bar)
    close:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    close:SetScript("OnClick", function() win:Hide() end)

    -- The class icon in a gold ring, sitting over the window's top-left corner.
    local holder = CreateFrame("Frame", nil, win)
    holder:SetSize(64, 64)
    holder:SetPoint("CENTER", win, "TOPLEFT", 12, -10)
    holder:SetFrameLevel(win:GetFrameLevel() + 10)
    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetSize(64 * RT.ICON_IN_RING, 64 * RT.ICON_IN_RING)
    icon:SetPoint("CENTER", holder, "CENTER", 0, 0)
    RT.classIcon = icon
    local ring = holder:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(RT.RING)
    ring:SetVertexColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
    ring:SetAllPoints(holder)
end

function RT.SetTitle(text)
    RT.title:SetText(text)
end

-- Footer ------------------------------------------------------------------------------------------

local function buildFooter(win)
    local footer = CreateFrame("Frame", nil, win)
    footer:SetHeight(RT.FOOTER_H)
    footer:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
    -- Retail's stone bottom bar from the talents sheet, in two halves: one strip would need a
    -- 2048-wide texture, which the client cannot load.
    local sheet = RT.MEDIA .. "Talents\\talents-sheet"
    local west = footer:CreateTexture(nil, "BACKGROUND")
    west:SetTexture(sheet)
    west:SetTexCoord(0.005740792, 809 / 1024, 209 / 512, 0.562353516)
    west:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    west:SetPoint("BOTTOMRIGHT", footer, "BOTTOM", 0, 0)
    local east = footer:CreateTexture(nil, "BACKGROUND")
    east:SetTexture(sheet)
    east:SetTexCoord(6 / 1024, 0.790157645, 297 / 512, 0.734228516)
    east:SetPoint("TOPLEFT", footer, "TOP", 0, 0)
    east:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", 0, 0)
    RT.footer = footer
end

-- Side tabs ---------------------------------------------------------------------------------------
-- Square tabs joined to the window's right edge: one per spec, then the hunter pet.

local SIDE, SIDE_FRAME, SIDE_ICON = 46, 34, 27
local EMPTY_SPEC = "Interface\\Icons\\INV_Misc_QuestionMark"
local sideTabs = {}

-- key: 1 or 2 for a spec, "pet", "talents" (the active spec) or "glyphs".
function RT.OpenPage(key)
    PlaySound("igCharacterInfoTab")
    local view = RT.view
    if key == "glyphs" or key == "talents" then
        view.page, view.pet = key, false
        view.group = RT.ActiveGroup()
    elseif key == "pet" then
        view.page, view.pet = "talents", true
    else
        view.page, view.pet = "talents", false
        view.group = key
    end
    RT.ShowPage()
end

-- The tree a spec has the most points in stands for it: its name and icon.
local function specLead(group)
    local lead, most, split = nil, 0, {}
    for tab = 1, GetNumTalentTabs(false, false) or 0 do
        -- Planned points count too, so a freshly planned spec shows its tree before it is learned.
        local name, icon, spent, _, planned = GetTalentTabInfo(tab, false, false, group)
        spent = (spent or 0) + (group == RT.ActiveGroup() and planned or 0)
        split[#split + 1] = spent
        if spent > most then lead, most = { name = name, icon = icon }, spent end
    end
    return lead, split
end

local function sideTip(tab)
    GameTooltip:SetOwner(tab, "ANCHOR_RIGHT")
    if tab.key == "pet" then
        GameTooltip:AddLine(PET, 1, 1, 1)
    else
        local lead, split = specLead(tab.key)
        GameTooltip:AddLine(RT.SpecName(tab.key) .. (lead and ("  ·  " .. lead.name) or ""), 1, 1, 1)
        GameTooltip:AddLine(table.concat(split, " / "), 1, 0.82, 0)
        if tab.key == RT.ActiveGroup() then
            GameTooltip:AddLine(TALENT_ACTIVE_SPEC_STATUS or "Active", 0.1, 1, 0.1)
        end
    end
    GameTooltip:Show()
end

-- A plate in the window's own colours, open on its left side so it reads as part of the window.
local function newSideTab(win, key)
    local tab = CreateFrame("Button", nil, win)
    tab:SetSize(SIDE, SIDE)
    tab.key = key
    local fill = W.Solid(tab, "BACKGROUND", 0.043, 0.043, 0.047)
    fill:SetAllPoints(tab)
    for _, side in ipairs({ "TOP", "BOTTOM" }) do
        local edge = W.Solid(tab, "BORDER", W.EDGE[1], W.EDGE[2], W.EDGE[3])
        edge:SetHeight(1)
        edge:SetPoint(side .. "LEFT", tab, side .. "LEFT", 0, 0)
        edge:SetPoint(side .. "RIGHT", tab, side .. "RIGHT", 0, 0)
    end
    local right = W.Solid(tab, "BORDER", W.EDGE[1], W.EDGE[2], W.EDGE[3])
    right:SetWidth(1)
    right:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)

    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetSize(SIDE_ICON, SIDE_ICON)
    tab.icon:SetPoint("CENTER", tab, "CENTER", 0, 0)
    tab.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- The same frame the talent icons wear: gold when selected, grey otherwise.
    tab.frame = tab:CreateTexture(nil, "OVERLAY")
    tab.frame:SetSize(SIDE_FRAME, SIDE_FRAME)
    tab.frame:SetPoint("CENTER", tab, "CENTER", 0, 0)
    local hover = tab:CreateTexture(nil, "HIGHLIGHT")
    hover:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hover:SetBlendMode("ADD")
    hover:SetAllPoints(tab.icon)
    tab:SetScript("OnClick", function(self) RT.OpenPage(self.key) end)
    tab:SetScript("OnEnter", sideTip)
    tab:SetScript("OnLeave", GameTooltip_Hide)
    return tab
end

local function buildSideTabs(win)
    for i, key in ipairs({ 1, 2, "pet" }) do sideTabs[i] = newSideTab(win, key) end
end

local function setSideIcon(tab, path)
    if tab.iconPath == path then return end
    tab.iconPath = path
    tab.icon:SetTexture(path)
end

function RT.UpdateTabs()
    local view = RT.view
    local mine = not RT.Inspecting()
    local shown = { mine, mine and RT.NumGroups() >= 2, mine and RT.PetHasTalents() }
    local previous
    for i, tab in ipairs(sideTabs) do
        if shown[i] then
            local selected
            if tab.key == "pet" then
                local _, icon = GetTalentTabInfo(1, false, true)
                setSideIcon(tab, icon or EMPTY_SPEC)
                selected = view.page == "talents" and view.pet
            else
                local lead = specLead(tab.key)
                setSideIcon(tab, lead and lead.icon or EMPTY_SPEC)
                selected = view.page == "talents" and not view.pet and view.group == tab.key
            end
            RT.TalentAtlas(tab.frame, selected and "square-yellow" or "square-gray")
            tab.icon:SetDesaturated(not selected)
            tab.icon:SetAlpha(selected and 1 or 0.8)
            tab:ClearAllPoints()
            if previous then
                tab:SetPoint("TOP", previous, "BOTTOM", 0, -4)
            else
                -- One pixel over the window's edge, so the tab and window share the border line.
                tab:SetPoint("TOPLEFT", RT.win, "TOPRIGHT", -1, -(RT.TITLE_H + 20))
            end
            tab:Show()
            previous = tab
        else
            tab:Hide()
        end
    end
end

-- Pages -------------------------------------------------------------------------------------------

function RT.ShowPage()
    RT.classIcon:SetTexture(RT.MEDIA .. "Class\\" .. RT.ViewClass())
    if RT.view.page == "glyphs" then
        RT.Call("HideTrees")
        RT.Call("ShowGlyphRoot")
        RT.SetTitle(GLYPHS)
    else
        RT.Call("HideGlyphRoot")
        RT.SetTitle(RT.Inspecting() and (RT.inspectName or TALENTS) or TALENTS)
    end
    RT.Call("ClosePresetMenu")
    RT.Refresh()
end

function RT.ApplyScale()
    if RT.win then RT.win:SetScale(RT.db and RT.db.scale or 0.9) end
end

-- Construction ------------------------------------------------------------------------------------

local function onShow()
    -- Every click is staged as a preview point until Learn Talents; this window always works that way.
    SetCVar("previewTalents", "1")
    RT.ApplyScale()
    RT.ShowPage()
    PlaySound("TalentScreenOpen")
    if TalentMicroButton then SetButtonPulse(TalentMicroButton, 0, 1) end
    UpdateMicroButtons()
end

local function onHide()
    PlaySound("TalentScreenClose")
    UpdateMicroButtons()
    RT.Call("ClosePresetMenu")
    RT.Call("ClearSearchFocus")
    RT.Call("LeaveInspect")
end

function RT.BuildWindow()
    if RT.win then return RT.win end
    local win = CreateFrame("Frame", "RatreeFrame", UIParent)
    RT.win = win
    win:Hide()
    win:SetSize(RT.WIDTH, RT.TITLE_H + RT.BODY_H + RT.FOOTER_H)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    tinsert(UISpecialFrames, win:GetName())

    local fill = W.Solid(win, "BACKGROUND", 0.043, 0.043, 0.047)
    fill:SetAllPoints(win)
    W.Border(win, W.EDGE[1], W.EDGE[2], W.EDGE[3], 1, "OVERLAY")

    local body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -RT.TITLE_H)
    body:SetSize(RT.WIDTH, RT.BODY_H)
    RT.body = body

    buildArt(body)
    buildTitle(win)
    buildFooter(win)
    buildSideTabs(win)

    RT.Call("BuildTrees", body)
    RT.Call("BuildFooterControls", RT.footer)
    RT.Call("BuildGlyphRoot", body)

    win:SetScript("OnShow", onShow)
    win:SetScript("OnHide", onHide)
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
    end)
    return win
end
