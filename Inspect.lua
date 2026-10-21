local RT = select(2, ...)

-- The game keeps one set of inspected talents, and tooltip addons replace it with whoever is under
-- the mouse. So the inspected player's trees are copied while the data is theirs, and drawn from
-- the copy until the window moves on.

local lastInspected
hooksecurefunc("NotifyInspect", function(unit) lastInspected = UnitGUID(unit) end)

local function pack(...)
    return { n = select("#", ...), ... }
end

local function copyTrees()
    local group = GetActiveTalentGroup(true, false) or 1
    local snap = { group = group, tabs = {} }
    for tab = 1, GetNumTalentTabs(true, false) or 0 do
        local name, icon, spent, background = GetTalentTabInfo(tab, true, false, group)
        local tree = { name = name, icon = icon, spent = spent or 0, background = background, talents = {} }
        for index = 1, GetNumTalents(tab, true, false) or 0 do
            tree.talents[index] = {
                info = pack(GetTalentInfo(tab, index, true, false, group)),
                prereqs = pack(GetTalentPrereqs(tab, index, true, false, group)),
                link = GetTalentLink(tab, index, true, false, group),
            }
        end
        snap.tabs[tab] = tree
    end
    if #snap.tabs == 0 then return nil end
    return snap
end

-- Asking again: another addon's NotifyInspect can land between ours and the answer.
local retry = CreateFrame("Frame")
retry:Hide()
retry:SetScript("OnUpdate", function(self, elapsed)
    self.wait = self.wait - elapsed
    if self.wait > 0 then return end
    self:Hide()
    local unit = RT.inspectUnit
    if unit and not RT.inspectSnap and UnitGUID(unit) == RT.inspectGUID and CanInspect(unit) then
        NotifyInspect(unit)
    end
end)

local function askLater()
    retry.wait = 1
    retry:Show()
end

function RT.ShowInspect(unit)
    if not RT.win or not unit or not UnitExists(unit) then return end
    RT.inspectUnit = unit
    RT.inspectGUID = UnitGUID(unit)
    RT.inspectName = UnitName(unit)
    RT.inspectClass = select(2, UnitClass(unit))
    RT.inspectSnap = nil
    if lastInspected == RT.inspectGUID then
        RT.inspectSnap = copyTrees()
    end
    if not RT.inspectSnap and CanInspect(unit) then NotifyInspect(unit) end
    RT.view.page, RT.view.pet = "talents", false
    if RT.win:IsShown() then
        RT.ShowPage()
    else
        RT.win:Show()
    end
end

function RT.LeaveInspect()
    RT.inspectUnit, RT.inspectGUID, RT.inspectName, RT.inspectClass, RT.inspectSnap = nil, nil, nil, nil, nil
end

RT.Listen("INSPECT_TALENT_READY", function()
    if not RT.inspectGUID then return end
    if lastInspected == RT.inspectGUID then
        RT.inspectSnap = copyTrees() or RT.inspectSnap
        RT.Refresh()
    elseif not RT.inspectSnap then
        askLater()
    end
end)

-- Talent data for the trees in view: the copy while inspecting, the game's otherwise.

function RT.NumTabs(ctx)
    if ctx.inspect then return RT.inspectSnap and #RT.inspectSnap.tabs or 0 end
    return GetNumTalentTabs(false, ctx.pet) or 0
end

function RT.TabInfo(ctx, tab)
    if ctx.inspect then
        local tree = RT.inspectSnap.tabs[tab]
        return tree.name, tree.icon, tree.spent, tree.background, 0
    end
    if ctx.plan then
        local name, icon, _, background = GetTalentTabInfo(tab, false, false, ctx.group)
        return name, icon, 0, background, RT.PlanTabPoints(tab)
    end
    return GetTalentTabInfo(tab, false, ctx.pet, ctx.group)
end

function RT.NumTalents(ctx, tab)
    if ctx.inspect then return #RT.inspectSnap.tabs[tab].talents end
    return GetNumTalents(tab, false, ctx.pet) or 0
end

function RT.TalentInfo(ctx, tab, index)
    if ctx.inspect then
        local info = RT.inspectSnap.tabs[tab].talents[index].info
        return unpack(info, 1, info.n)
    end
    if ctx.plan then
        -- nothing learned: the plan's rank is the pending one
        local name, icon, tier, column, _, maxRank, exceptional = GetTalentInfo(tab, index, false, false, ctx.group)
        local met = RT.PlanMet(ctx, tab, index)
        return name, icon, tier, column, 0, maxRank, exceptional, met, RT.PlanRank(tab, index), met
    end
    return GetTalentInfo(tab, index, false, ctx.pet, ctx.group)
end

function RT.TalentPrereqs(ctx, tab, index)
    if ctx.inspect then
        local prereqs = RT.inspectSnap.tabs[tab].talents[index].prereqs
        return unpack(prereqs, 1, prereqs.n)
    end
    return GetTalentPrereqs(tab, index, false, ctx.pet, ctx.group)
end

function RT.TalentLink(ctx, tab, index)
    if ctx.inspect then return RT.inspectSnap.tabs[tab].talents[index].link end
    if ctx.plan then return RT.PlanLink(ctx, tab, index) end
    return GetTalentLink(tab, index, false, ctx.pet, ctx.group)
end
