local ADDON, RT = ...
_G.Ratree = RT

RT.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
RT.HEADER_FONT = "Fonts\\MORPHEUS.TTF"

-- Events ------------------------------------------------------------------------------------------

local hub = CreateFrame("Frame")
local listeners = {}

hub:SetScript("OnEvent", function(_, event, ...)
    local list = listeners[event]
    if not list then return end
    for i = 1, #list do list[i](event, ...) end
end)

function RT.Listen(event, handler)
    local list = listeners[event]
    if not list then
        list = {}
        listeners[event] = list
        hub:RegisterEvent(event)
    end
    list[#list + 1] = handler
end

-- Work that touches bindings waits for the end of combat; a newer call with the same key wins.
local queued = {}

function RT.OutOfCombat(key, fn)
    if InCombatLockdown() then
        queued[key] = fn
    else
        fn()
    end
end

RT.Listen("PLAYER_REGEN_ENABLED", function()
    for key, fn in pairs(queued) do
        queued[key] = nil
        fn()
    end
end)

function RT.Notify(text, r, g, b)
    UIErrorsFrame:AddMessage(text, r or 1, g or 0.82, b or 0, 1)
end

function RT.Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cffe2b843Ratree|r " .. text)
end

-- Saved data --------------------------------------------------------------------------------------

RT.Listen("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    RatreeDB = RatreeDB or {}
    local db = RatreeDB
    db.presets = db.presets or {}
    db.scale = db.scale or 0.9
    RT.db = db
end)

-- Presets are account-wide and kept per class, so every toon of a class shares them.
function RT.ClassPresets()
    local class = RT.PlayerClass()
    local bucket = RT.db.presets[class]
    if not bucket then
        bucket = {}
        RT.db.presets[class] = bucket
    end
    return bucket
end

-- Player and view state ---------------------------------------------------------------------------

function RT.PlayerClass()
    return select(2, UnitClass("player"))
end

function RT.ActiveGroup()
    return GetActiveTalentGroup(false, false) or 1
end

function RT.NumGroups()
    return GetNumTalentGroups(false, false) or 1
end

function RT.PetHasTalents()
    return (GetNumTalentGroups(false, true) or 0) > 0
end

-- page: "talents" or "glyphs"; group: the spec shown; pet: the hunter pet tree.
RT.view = { page = "talents", group = 1, pet = false }

-- Another player's trees, opened from the inspect window: view only.
function RT.Inspecting()
    return RT.inspectGUID ~= nil
end

function RT.ViewClass()
    if RT.inspectGUID then return RT.inspectClass end
    return RT.PlayerClass()
end

function RT.Context()
    if RT.inspectGUID then
        local snap = RT.inspectSnap
        return { inspect = true, pet = false, group = snap and snap.group or 1, editable = false }
    end
    local view = RT.view
    -- A plan: your own trees, blank, every click staying inside the plan.
    if RT.plan and not view.pet then
        return { inspect = false, plan = true, pet = false, group = RT.ActiveGroup(), editable = true }
    end
    local ctx = { inspect = false, pet = view.pet and RT.PetHasTalents() or false }
    if ctx.pet then
        ctx.group = GetActiveTalentGroup(false, true) or 1
    else
        ctx.group = view.group
    end
    ctx.editable = ctx.pet or ctx.group == RT.ActiveGroup()
    return ctx
end

function RT.Browsing()
    local ctx = RT.Context()
    return RT.view.page == "talents" and not ctx.editable
end

function RT.Unspent(ctx)
    if ctx.plan then return RT.PlanBudget() end
    if not ctx.editable then return 0 end
    return GetUnspentTalentPoints(false, ctx.pet, ctx.group) or 0
end

function RT.Staged(ctx)
    if ctx.plan then return RT.PlanTotal() end
    if not ctx.editable then return 0 end
    return GetGroupPreviewTalentPointsSpent(ctx.pet, ctx.group) or 0
end

function RT.SpecName(group)
    return group == 2 and TALENT_SPEC_SECONDARY or TALENT_SPEC_PRIMARY
end

-- Per-spec look -----------------------------------------------------------------------------------

local SPECS = {
    WARRIOR = { "arms", "fury", "protection" },
    PALADIN = { "holy", "protection", "retribution" },
    HUNTER = { "beastmastery", "marksmanship", "survival" },
    ROGUE = { "assassination", "combat", "subtlety" },
    PRIEST = { "discipline", "holy", "shadow" },
    DEATHKNIGHT = { "blood", "frost", "unholy" },
    SHAMAN = { "elemental", "enhancement", "restoration" },
    MAGE = { "arcane", "fire", "frost" },
    WARLOCK = { "affliction", "demonology", "destruction" },
    DRUID = { "balance", "feral", "restoration" },
}

-- Spec art that exists as Media\Art\<class>-<spec>.blp; any spec not listed uses the class art.
RT.SPEC_ART = {}
for key in ("deathknight-blood deathknight-frost deathknight-unholy druid-balance druid-feral druid-restoration "
    .. "hunter-beastmastery hunter-marksmanship hunter-survival mage-arcane mage-fire mage-frost paladin-holy "
    .. "paladin-protection paladin-retribution priest-discipline priest-holy priest-shadow rogue-assassination rogue-combat "
    .. "rogue-subtlety shaman-elemental shaman-enhancement shaman-restoration warlock-affliction "
    .. "warlock-demonology warlock-destruction warrior-arms warrior-fury warrior-protection"):gmatch("%S+") do
    RT.SPEC_ART[key] = true
end

function RT.SpecSlug(class, tree)
    local specs = SPECS[class]
    return specs and specs[tree]
end

-- The art's path, and whether it is split: spec art is two 1024x1024 halves (<path>-l, <path>-r)
-- for twice the sharpness; the class art is one 1024x512 picture.
function RT.ArtFor(class, tree)
    local slug = class and class:lower()
    if not slug then return nil end
    local spec = RT.SpecSlug(class, tree)
    if spec and RT.SPEC_ART[slug .. "-" .. spec] then
        return RT.MEDIA .. "Art\\" .. slug .. "-" .. spec, true
    end
    return RT.MEDIA .. "Art\\" .. slug, false
end

-- Round icon: the art cut to a circle with the ring on top, whose black inner band hides the square
-- frame HD icons draw inside their art. The ring texture gets the icon's size and centre.
RT.RING = RT.MEDIA .. "ring"
-- An icon drawn at the ring's full size shows a sliver past the ring's edge; this keeps it inside.
RT.ICON_IN_RING = 0.92

function RT.SetRoundIcon(icon, path)
    SetPortraitToTexture(icon, path)
    icon:SetTexCoord(0, 1, 0, 1)
end

function RT.LeadingTree(points)
    local best, most = 1, 0
    for tree, spent in ipairs(points) do
        if spent > most then best, most = tree, spent end
    end
    return best
end

-- Calls a function the later files define, if it is there yet.
function RT.Call(name, ...)
    local fn = RT[name]
    if fn then return fn(...) end
end

function RT.Refresh()
    local win = RT.win
    if not win or not win:IsShown() then return end
    if RT.view.page == "glyphs" then
        RT.Call("PaintGlyphs")
    else
        RT.Call("PaintTrees")
    end
    RT.Call("UpdateFooter")
    RT.Call("UpdateTabs")
end
