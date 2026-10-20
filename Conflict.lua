local ADDON, RT = ...

-- Two talent windows both open on N. After login, if another one is enabled, the
-- player picks one: the other is turned off and the UI reloads. No way to
-- dismiss it, so the choice can't be skipped.

local OTHERS = { "Talented" }

-- Talented loads on demand, so being enabled counts, not only being loaded.
local function enabled(name)
    if IsAddOnLoaded(name) then return true end
    local _, _, _, isEnabled, _, reason = GetAddOnInfo(name)
    return isEnabled and reason ~= "MISSING" and true or false
end

local function rivals()
    local names = {}
    for _, name in ipairs(OTHERS) do
        if enabled(name) then names[#names + 1] = name end
    end
    return names
end

local function keepRatree()
    for _, name in ipairs(OTHERS) do
        if enabled(name) then DisableAddOn(name) end
    end
    ReloadUI()
end

local function keepOther()
    DisableAddOn(ADDON)
    ReloadUI()
end

StaticPopupDialogs.RATREE_CONFLICT = {
    text = "|cffe2b843Ratree|r and %s are both on, and both open your talents.\n\nPick one. The other is turned off and the UI reloads.",
    button1 = "Ratree",
    button2 = "Keep the other",
    OnAccept = keepRatree,
    OnCancel = function(_, _, reason)
        if reason == "clicked" then keepOther() end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = false,
    showAlert = 1,
}

local function ask()
    local names = rivals()
    if #names == 0 then return end
    if InCombatLockdown() then
        RT.OutOfCombat("conflict", function()
            if not StaticPopup_Visible("RATREE_CONFLICT") then ask() end
        end)
        return
    end
    StaticPopup_Show("RATREE_CONFLICT", table.concat(names, ", "))
end

-- Wait a few seconds after login so the popup lands after the loading screen.
RT.Listen("PLAYER_LOGIN", function()
    local waited, timer = 0, CreateFrame("Frame")
    timer:SetScript("OnUpdate", function(self, elapsed)
        waited = waited + elapsed
        if waited < 3 then return end
        self:SetScript("OnUpdate", nil)
        ask()
    end)
end)
