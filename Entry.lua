local RT = select(2, ...)

local TOGGLE_NAME = "RatreeToggle"

-- Opening and closing -----------------------------------------------------------------------------

local function levelAllows(level)
    if UnitLevel("player") >= level then return true end
    RT.Notify(string.format(FEATURE_BECOMES_AVAILABLE_AT_LEVEL, level), 1, 0.1, 0.1)
    return false
end

local function show(page)
    RT.Call("LeaveInspect")
    local view = RT.view
    view.page, view.pet = page, false
    view.group = RT.ActiveGroup()
    if RT.win:IsShown() then
        RT.ShowPage()
    else
        RT.win:Show()
    end
end

function RT.ToggleTalents()
    if not RT.win then return end
    if RT.win:IsShown() and RT.view.page == "talents" and not RT.Inspecting() then
        RT.win:Hide()
    elseif levelAllows(SHOW_TALENT_LEVEL or 10) then
        show("talents")
    end
end

function RT.ToggleGlyphs()
    if not RT.win then return end
    if RT.win:IsShown() and RT.view.page == "glyphs" then
        RT.win:Hide()
    elseif levelAllows(SHOW_INSCRIPTION_LEVEL or 15) then
        show("glyphs")
    end
end

function RT.OpenGlyphs()
    if RT.win and levelAllows(SHOW_INSCRIPTION_LEVEL or 15) then show("glyphs") end
end

-- Key bindings: the game's talent and glyph keys click a hidden button of ours --------------------

local bindingOwner, lastBindings

local function rebuildBindings()
    local talentKeys = { GetBindingKey("TOGGLETALENTS") }
    local glyphKeys = { GetBindingKey("TOGGLEINSCRIPTION") }
    local signature = table.concat(talentKeys, ",") .. "|" .. table.concat(glyphKeys, ",")
    if signature == lastBindings then return end
    lastBindings = signature
    ClearOverrideBindings(bindingOwner)
    for _, key in ipairs(talentKeys) do
        SetOverrideBindingClick(bindingOwner, false, key, TOGGLE_NAME, "LeftButton")
    end
    for _, key in ipairs(glyphKeys) do
        SetOverrideBindingClick(bindingOwner, false, key, TOGGLE_NAME, "RightButton")
    end
end

local function queueBindings()
    RT.OutOfCombat("bindings", rebuildBindings)
end

local function buildToggle()
    local toggle = CreateFrame("Button", TOGGLE_NAME, UIParent)
    toggle:Hide()
    toggle:RegisterForClicks("AnyUp")
    toggle:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            RT.ToggleGlyphs()
        else
            RT.ToggleTalents()
        end
    end)
    bindingOwner = CreateFrame("Frame")
end

-- Blizzard's talent frame -------------------------------------------------------------------------

local talentFrameHooked

-- Hiding it inside its own ShowUIPanel re-enters the panel manager, so wait one frame.
local redirect = CreateFrame("Frame")
redirect:Hide()
redirect:SetScript("OnUpdate", function(self)
    self:Hide()
    local frame = PlayerTalentFrame
    if not frame or not frame:IsShown() then return end
    local glyphs = GLYPH_TALENT_TAB and PanelTemplates_GetSelectedTab(frame) == GLYPH_TALENT_TAB
    HideUIPanel(frame)
    show(glyphs and "glyphs" or "talents")
end)

local function hookTalentFrame()
    if talentFrameHooked or not PlayerTalentFrame then return end
    talentFrameHooked = true
    PlayerTalentFrame:HookScript("OnShow", function() redirect:Show() end)
end

-- Inspect window ----------------------------------------------------------------------------------
-- Its Talents tab opens this window on the inspected player's trees instead.

local inspectHooked

local function hookInspect()
    if inspectHooked or not InspectFrame or not InspectFrameTab3 then return end
    inspectHooked = true
    InspectFrameTab3:SetScript("OnClick", function()
        PlaySound("igCharacterInfoTab")
        if InspectFrame.unit then RT.ShowInspect(InspectFrame.unit) end
    end)
    InspectFrame:HookScript("OnHide", function()
        if RT.Inspecting() and RT.win then RT.win:Hide() end
    end)
    hooksecurefunc("InspectFrame_UnitChanged", function()
        if RT.Inspecting() and InspectFrame.unit then RT.ShowInspect(InspectFrame.unit) end
    end)
end

-- Start -------------------------------------------------------------------------------------------

local function start()
    RT.BuildWindow()
    buildToggle()
    queueBindings()
    RT.Listen("UPDATE_BINDINGS", queueBindings)

    -- The micro button's handler is bound by value in Blizzard's XML, so the script is replaced.
    if TalentMicroButton then
        TalentMicroButton:SetScript("OnClick", function() RT.ToggleTalents() end)
    end
    hooksecurefunc("UpdateMicroButtons", function()
        if RT.win and RT.win:IsShown() and TalentMicroButton then
            TalentMicroButton:SetButtonState("PUSHED", 1)
        end
    end)

    UIParent:UnregisterEvent("USE_GLYPH")
    RT.Listen("USE_GLYPH", RT.OpenGlyphs)

    RT.Listen("ADDON_LOADED", function(_, name)
        if name == "Blizzard_TalentUI" then hookTalentFrame() end
        if name == "Blizzard_InspectUI" then hookInspect() end
    end)
    if IsAddOnLoaded("Blizzard_TalentUI") then hookTalentFrame() end
    if IsAddOnLoaded("Blizzard_InspectUI") then hookInspect() end
end

RT.Listen("PLAYER_LOGIN", start)

-- Slash command -----------------------------------------------------------------------------------

SLASH_RATREE1 = "/ratree"
SLASH_RATREE2 = "/rtree"
SlashCmdList["RATREE"] = function(msg)
    local command, value = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "scale" then
        local scale = tonumber(value)
        if scale and scale >= 0.5 and scale <= 1.5 then
            RT.db.scale = scale
            RT.ApplyScale()
            RT.Print("window scale " .. scale)
        else
            RT.Print("scale goes from 0.5 to 1.5, e.g. /ratree scale 0.85")
        end
    elseif command == "glyphs" then
        RT.ToggleGlyphs()
    else
        RT.ToggleTalents()
    end
end
