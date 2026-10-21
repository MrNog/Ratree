local RT = select(2, ...)

-- Plan mode: a blank set of your own class's trees, with a level's worth of points, that never
-- touches the character. Points are clicked in and out freely and the result saved as a preset.
-- RT.plan = { ranks = { [tab] = { [talentIndex] = rank } } } while a plan is open.

local max = math.max

local function perTier()
    return PLAYER_TALENTS_PER_TIER or 5
end

function RT.Planning()
    return RT.plan ~= nil
end

function RT.StartPlan()
    local view = RT.view
    view.page, view.pet, view.group = "talents", false, RT.ActiveGroup()
    RT.plan = { ranks = {} }
    RT.ShowPage()
end

function RT.EndPlan()
    RT.plan = nil
    RT.ShowPage()
end

function RT.PlanClear()
    if RT.plan then RT.plan.ranks = {} end
end

-- Loads a preset's ranks into the plan, to look at it or change it.
function RT.PlanLoad(preset)
    if not RT.plan then return end
    local ranks = {}
    for tab, tree in pairs(preset.ranks or {}) do
        ranks[tab] = {}
        for index, rank in pairs(tree) do
            if (tonumber(rank) or 0) > 0 then ranks[tab][index] = tonumber(rank) end
        end
    end
    RT.plan.ranks = ranks
end

function RT.PlanRank(tab, index)
    local tree = RT.plan and RT.plan.ranks[tab]
    return tree and tree[index] or 0
end

function RT.PlanTabPoints(tab)
    local sum = 0
    for _, rank in pairs(RT.plan and RT.plan.ranks[tab] or {}) do sum = sum + rank end
    return sum
end

function RT.PlanTotal()
    local sum = 0
    for tab in pairs(RT.plan and RT.plan.ranks or {}) do sum = sum + RT.PlanTabPoints(tab) end
    return sum
end

-- A level's worth of points: one at 10, 71 at 80.
function RT.PlanBudget()
    return max(0, (UnitLevel("player") or 80) - 9)
end

-- The talent at a tier and column of a tree, by index.
local function indexAt(tab, group, tier, column)
    for index = 1, GetNumTalents(tab, false, false) or 0 do
        local _, _, t, c = GetTalentInfo(tab, index, false, false, group)
        if t == tier and c == column then return index end
    end
end

-- Every talent this one needs is planned to its full rank.
function RT.PlanMet(ctx, tab, index)
    local prereqs = { GetTalentPrereqs(tab, index, false, false, ctx.group) }
    for k = 1, #prereqs, 3 do
        local need = indexAt(tab, ctx.group, prereqs[k], prereqs[k + 1])
        if need then
            local _, _, _, _, _, maxRank = GetTalentInfo(tab, need, false, false, ctx.group)
            if RT.PlanRank(tab, need) < (maxRank or 1) then return false end
        end
    end
    return true
end

-- A tree is valid when every planned talent has its tier open by the points below it, and the
-- talents it needs at full rank.
local function treeValid(ctx, tab)
    local below = {}
    local talents = {}
    for index, rank in pairs(RT.plan.ranks[tab] or {}) do
        if rank > 0 then
            local _, _, tier = GetTalentInfo(tab, index, false, false, ctx.group)
            talents[#talents + 1] = { index = index, tier = tier or 1 }
            below[tier or 1] = (below[tier or 1] or 0) + rank
        end
    end
    for _, t in ipairs(talents) do
        local under = 0
        for tier, points in pairs(below) do
            if tier < t.tier then under = under + points end
        end
        if under < (t.tier - 1) * perTier() then return false end
        if not RT.PlanMet(ctx, tab, t.index) then return false end
    end
    return true
end

-- One point in (+1) or out (-1). Returns true when the plan changed.
function RT.PlanChange(ctx, tab, index, delta)
    if not RT.plan then return false end
    local _, _, tier, _, _, maxRank = GetTalentInfo(tab, index, false, false, ctx.group)
    if not tier then return false end
    local ranks = RT.plan.ranks
    ranks[tab] = ranks[tab] or {}
    local rank = ranks[tab][index] or 0
    if delta > 0 then
        if rank >= (maxRank or 1) or RT.PlanTotal() >= RT.PlanBudget() then return false end
        if RT.PlanTabPoints(tab) < (tier - 1) * perTier() then return false end
        if not RT.PlanMet(ctx, tab, index) then return false end
        ranks[tab][index] = rank + 1
        return true
    end
    if rank <= 0 then return false end
    ranks[tab][index] = rank - 1 > 0 and rank - 1 or nil
    if treeValid(ctx, tab) then return true end
    ranks[tab][index] = rank
    return false
end

-- Import from a Wowhead talent-calculator link (or just its code):
--   .../wotlk/talent-calc/paladin/50350151020013053100515221-50023131203_<glyphs>
-- One digit per talent, tree by tree ("-" between trees), in the calculator's order: by tier, then
-- column. Trailing zeros are left out. The glyph part after "_" is not read.
local CLASS_SLUG = {
    deathknight = "DEATHKNIGHT", ["death-knight"] = "DEATHKNIGHT", druid = "DRUID", hunter = "HUNTER",
    mage = "MAGE", paladin = "PALADIN", priest = "PRIEST", rogue = "ROGUE", shaman = "SHAMAN",
    warlock = "WARLOCK", warrior = "WARRIOR",
}

local function calcOrder(tab, group)
    local order = {}
    for index = 1, GetNumTalents(tab, false, false) or 0 do
        local _, _, tier, column = GetTalentInfo(tab, index, false, false, group)
        if tier then order[#order + 1] = { index = index, tier = tier, column = column or 0 } end
    end
    table.sort(order, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        return a.column < b.column
    end)
    return order
end

-- Returns true, or false and why.
function RT.PlanImport(text)
    if not RT.plan then return false, "Open Plan first." end
    text = (text or ""):gsub("%s+", "")
    local slug, code = text:match("talent%-calc/([%a%-]+)/([%d%-]+)")
    if not code then code = text:match("^([%d%-]+)") end
    if not code or not code:find("%d") then return false, "That is not a Wowhead talent link." end
    local class = slug and CLASS_SLUG[slug:lower()]
    if class and class ~= RT.PlayerClass() then
        return false, "That build is for another class (" .. slug .. ")."
    end
    local ctx = RT.Context()
    local ranks, total, tab = {}, 0, 0
    for part in (code .. "-"):gmatch("([%d]*)%-") do
        tab = tab + 1
        if tab > (GetNumTalentTabs(false, false) or 3) then break end
        local order = calcOrder(tab, ctx.group)
        if #part > #order then return false, "The link does not fit this class's trees." end
        ranks[tab] = {}
        for k = 1, #part do
            local rank = tonumber(part:sub(k, k)) or 0
            if rank > 0 then
                local t = order[k]
                local _, _, _, _, _, maxRank = GetTalentInfo(tab, t.index, false, false, ctx.group)
                if rank > (maxRank or 1) then return false, "The link does not fit this class's trees." end
                ranks[tab][t.index] = rank
                total = total + rank
            end
        end
    end
    if total > RT.PlanBudget() then
        return false, ("That build needs %d points; your level gives %d."):format(total, RT.PlanBudget())
    end
    RT.PlanLoad({ ranks = ranks })
    return true
end

StaticPopupDialogs["RATREE_IMPORT"] = {
    text = "Paste a Wowhead talent link (Ctrl+V).",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 300,
    editBoxWidth = 350,
    OnAccept = function(self)
        local ok, why = RT.PlanImport(self.editBox:GetText())
        if ok then RT.Refresh(); RT.Notify("Build imported into the plan.", 0.2, 1, 0.2)
        else RT.Notify(why, 1, 0.3, 0.3) end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["RATREE_IMPORT"].OnAccept(parent)
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

-- The talent's link at its planned rank, for the tooltip.
function RT.PlanLink(ctx, tab, index)
    local link = GetTalentLink(tab, index, false, false, ctx.group)
    if not link then return nil end
    return (link:gsub("(|Htalent:%d+:)%-?%d+", "%1" .. (RT.PlanRank(tab, index) - 1)))
end
