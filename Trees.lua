local RT = select(2, ...)
local W = RT.W

local abs, max, sqrt, format = math.abs, math.max, math.sqrt, string.format

local TREE_W = RT.WIDTH / 3
local COL_STEP, ROW_STEP = 64, 46
local GRID_X0 = (TREE_W - 3 * COL_STEP) / 2
local GRID_Y0 = 82
local CAPSTONE_DROP = 28

local SOUND_ADD, SOUND_REMOVE = "igMainMenuOptionCheckBoxOn", "igMainMenuOptionCheckBoxOff"
local GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
local SHEET = RT.MEDIA .. "Talents\\talents-sheet"
local ARROWS = RT.MEDIA .. "Talents\\talents-arrows"

local trees = {}
RT.query = ""

-- Node art: regions of the talents sheet, as left, right, top, bottom.
local ATLAS = {
    ["square-gray"] = { 906, 986, 183, 263 },
    ["square-locked"] = { 904, 984, 355, 435 },
    ["square-yellow"] = { 818, 898, 271, 351 },
    ["square-shadow"] = { 818, 896, 357, 435 },
    ["circle-gray"] = { 85, 135, 385, 435 },
    ["circle-locked"] = { 253, 303, 385, 435 },
    ["circle-yellow"] = { 197, 247, 385, 435 },
    ["circle-shadow"] = { 3, 79, 385, 461 },
    ["apex-large-gray"] = { 822, 906, 3, 87 },
    ["apex-large-locked"] = { 912, 996, 93, 177 },
    ["apex-large-yellow"] = { 822, 906, 93, 177 },
}

local function atlas(tex, key)
    local c = ATLAS[key]
    tex:SetTexture(SHEET)
    tex:SetTexCoord(c[1] / 1024, c[2] / 1024, c[3] / 512, c[4] / 512)
end
RT.TalentAtlas = atlas

-- Passive talents are square, active abilities round; the deepest tier is drawn larger.
-- A square icon is 80% of its frame: the octagon's opening is 75%, so the edge tucks under the
-- metal while the corners stay inside the cut ones.
local SHAPES = {
    square = { family = "square", ring = 35, icon = 28, shadow = "square-shadow", shadowSize = 69 },
    circle = { family = "circle", ring = 40, icon = 40, shadow = "circle-shadow", shadowSize = 77, round = true },
    capstone = { family = "square", ring = 56, icon = 45, shadow = "square-shadow", shadowSize = 109 },
    apex = { family = "apex-large", ring = 84, icon = 66, shadow = "square-shadow", shadowSize = 164,
        round = true, outline = 34 / 84 },
}

local function shapeFor(entry)
    if entry.capstone then return entry.exceptional and "apex" or "capstone" end
    return entry.exceptional and "circle" or "square"
end

local function cellCentre(tier, column, capstone)
    local x = GRID_X0 + (column - 1) * COL_STEP
    local y = GRID_Y0 + (tier - 1) * ROW_STEP + (capstone and CAPSTONE_DROP or 0)
    return x, y
end

local function cellKey(tier, column)
    return tier * 8 + column
end

-- GetTalentPrereqs returns tier, column and two flags per prerequisite.
local function prereqCells(...)
    local cells = {}
    for k = 1, select("#", ...), 4 do
        local tier, column = select(k, ...)
        if tier and column then cells[#cells + 1] = { tier, column } end
    end
    return cells
end
RT.PrereqCells = prereqCells
RT.CellKey = cellKey

-- Nodes -------------------------------------------------------------------------------------------

local function nodeEnter(node)
    node.hover:Show()
    local ctx = RT.Context()
    GameTooltip:SetOwner(node, "ANCHOR_RIGHT")
    if ctx.inspect or ctx.plan then
        local link = RT.TalentLink(ctx, node.tab, node.index)
        if link then GameTooltip:SetHyperlink(link) end
        return
    end
    GameTooltip:SetTalent(node.tab, node.index, false, ctx.pet, ctx.group, ctx.editable)
end

local function nodeLeave(node)
    node.hover:Hide()
    GameTooltip_Hide()
end

local function previewRank(tab, index, ctx)
    local _, _, _, _, rank, _, _, _, preview = GetTalentInfo(tab, index, false, ctx.pet, ctx.group)
    return preview or rank or 0
end

local function nodeClick(node, button)
    local ctx = RT.Context()
    if IsModifiedClick("CHATLINK") then
        local link = RT.TalentLink(ctx, node.tab, node.index)
        if link then ChatEdit_InsertLink(link) end
        return
    end
    if not ctx.editable then return end
    local delta = (button == "LeftButton" and 1) or (button == "RightButton" and -1) or nil
    if not delta then return end
    if ctx.plan then
        if RT.PlanChange(ctx, node.tab, node.index, delta) then
            PlaySound(delta > 0 and SOUND_ADD or SOUND_REMOVE)
            RT.Refresh()
        end
        if GameTooltip:IsOwned(node) then nodeEnter(node) end
        return
    end
    local before = previewRank(node.tab, node.index, ctx)
    AddPreviewTalentPoints(node.tab, node.index, delta, ctx.pet, ctx.group)
    if previewRank(node.tab, node.index, ctx) ~= before then
        PlaySound(delta > 0 and SOUND_ADD or SOUND_REMOVE)
    end
    if GameTooltip:IsOwned(node) then nodeEnter(node) end
end

local function newNode(tree)
    local node = CreateFrame("Button", nil, tree)
    node:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- On the tree, not the node, so prerequisite lines draw above the shadow but under the node.
    node.shadow = tree:CreateTexture(nil, "BACKGROUND")
    node.icon = node:CreateTexture(nil, "ARTWORK")
    node.ring = node:CreateTexture(nil, "OVERLAY")
    node.hover = node:CreateTexture(nil, "OVERLAY")
    node.hover:SetBlendMode("ADD")
    node.hover:Hide()

    -- Search hit: a pulsing gold glow.
    node.find = node:CreateTexture(nil, "OVERLAY")
    node.find:SetTexture(GLOW)
    node.find:SetBlendMode("ADD")
    node.find:SetVertexColor(1, 0.85, 0.3)
    node.find:Hide()
    local pulse = node.find:CreateAnimationGroup()
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetDuration(0.6)
    fade:SetChange(-0.6)
    fade:SetSmoothing("IN_OUT")
    pulse:SetLooping("BOUNCE")
    node.findPulse = pulse

    for _, tex in ipairs({ node.shadow, node.icon, node.ring, node.hover, node.find }) do
        tex:SetPoint("CENTER", node, "CENTER", 0, 0)
    end
    node.rank = node:CreateFontString(nil, "OVERLAY")
    node.rank:SetFont(STANDARD_TEXT_FONT, 13, "THICKOUTLINE")
    node.rank:SetShadowOffset(1, -1)
    node.rank:SetPoint("BOTTOMRIGHT", node, "BOTTOMRIGHT", 3, -2)
    node:SetScript("OnEnter", nodeEnter)
    node:SetScript("OnLeave", nodeLeave)
    node:SetScript("OnClick", nodeClick)
    return node
end

local function setShape(node, key)
    if node.shapeKey == key then return end
    node.shapeKey = key
    local look = SHAPES[key]
    node:SetSize(look.ring, look.ring)
    node.icon:SetSize(look.icon, look.icon)
    node.ring:SetSize(look.ring, look.ring)
    node.hover:SetSize(look.ring, look.ring)
    atlas(node.shadow, look.shadow)
    node.shadow:SetSize(look.shadowSize, look.shadowSize)
    node.find:SetSize(look.ring * 2, look.ring * 2)
    node.iconPath = nil
end

-- HD icons draw a square frame inside their art; round icons are cut from the file so the ring hides it.
local function setIcon(node, path, round)
    if node.iconPath == path then return end
    node.iconPath = path
    if round then
        RT.SetRoundIcon(node.icon, path)
    else
        node.icon:SetTexture(path)
        node.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- yellow: has points, learned or planned; gray: none yet; locked: its tier is out of reach.
local function nodeState(entry)
    if entry.shown > 0 then return "yellow" end
    if not entry.tierOpen then return "locked" end
    return "gray"
end

local function dressNode(node, entry)
    local key = shapeFor(entry)
    setShape(node, key)
    local look = SHAPES[key]
    setIcon(node, entry.icon, look.round)

    local state = nodeState(entry)
    atlas(node.ring, look.family .. "-" .. state)
    atlas(node.hover, look.family .. "-" .. state)

    local dim = state == "locked" or (state == "gray" and not entry.open)
    node.icon:SetDesaturated(dim)
    local shade = dim and 0.65 or 1
    node.icon:SetVertexColor(shade, shade, shade)
    node.hover:SetAlpha(dim and 0.4 or 1)

    if dim then
        node.rank:SetTextColor(0.6, 0.6, 0.6)
    else
        node.rank:SetTextColor(1, 0.82, 0)
    end
    node.rank:SetText(entry.shown > 0 and entry.shown or "")
    node.talentName = entry.name and entry.name:lower() or ""
end

-- Prerequisite arrows -----------------------------------------------------------------------------

local LINE = 2.5
-- The arrow art is 64x64 per head drawn at 0.56; its solid tip ends 6 px past the centre.
local ARROW_SIZE = 64 * 0.56
local TIP_REACH, TIP_GAP = 6 * 0.56, 1

local function pooled(tree, pool, layer)
    tree.used[pool] = tree.used[pool] + 1
    local list = tree[pool]
    local tex = list[tree.used[pool]]
    if not tex then
        tex = tree:CreateTexture(nil, layer)
        list[tree.used[pool]] = tex
    end
    tex:Show()
    return tex
end

-- The arrow art points down; c and s are the cosine and sine of the turn onto the edge.
local function pointArrow(tex, active, c, s)
    local cu, cv = active and 0.25 or 0.75, 0.5
    local function corner(px, py)
        local qx, qy = c * px + s * py, -s * px + c * py
        return cu + qx * 0.25, cv - qy * 0.5
    end
    local ulx, uly = corner(-1, 1)
    local llx, lly = corner(-1, -1)
    local urx, ury = corner(1, 1)
    local lrx, lry = corner(1, -1)
    tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end

-- Straight shaft on one axis, in tree units with y growing down.
local function shaft(tree, x1, y1, x2, y2, active)
    local tex = pooled(tree, "lines", "BORDER")
    if active then
        tex:SetTexture(1, 0.82, 0, 0.95)
    else
        tex:SetTexture(0.45, 0.45, 0.48, 0.6)
    end
    tex:ClearAllPoints()
    local left, top = math.min(x1, x2), math.min(y1, y2)
    if x1 == x2 then
        tex:SetPoint("TOPLEFT", tree, "TOPLEFT", left - LINE / 2, -top)
        tex:SetSize(LINE, abs(y2 - y1))
    else
        tex:SetPoint("TOPLEFT", tree, "TOPLEFT", left, -(top - LINE / 2))
        tex:SetSize(abs(x2 - x1), LINE)
    end
end

-- Distance from a node's centre to its outline along an axis.
local function outlineReach(key)
    local look = SHAPES[key]
    if look.outline then return look.ring * look.outline end
    return look.ring / 2
end

local function drawLink(tree, fromX, fromY, toX, toY, active, targetShape)
    -- Off-axis links bend once: across at the source's row, then down into the target.
    local bendX, bendY = fromX, fromY
    if fromX ~= toX and fromY ~= toY then
        bendX = toX
        shaft(tree, fromX, fromY, bendX, bendY, active)
    end
    local dx, dy = toX - bendX, toY - bendY
    local length = sqrt(dx * dx + dy * dy)
    if length <= 0 then return end
    dx, dy = dx / length, dy / length
    local back = outlineReach(targetShape) + TIP_GAP + TIP_REACH
    local endX, endY = toX - back * dx, toY - back * dy
    shaft(tree, bendX, bendY, endX, endY, active)

    local arrow = pooled(tree, "arrows", "ARTWORK")
    arrow:SetTexture(ARROWS)
    arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
    pointArrow(arrow, active, dy, dx)
    arrow:ClearAllPoints()
    arrow:SetPoint("CENTER", tree, "TOPLEFT", endX, -endY)
end

-- Trees -------------------------------------------------------------------------------------------

local function newTree(body, slot)
    local tree = CreateFrame("Frame", nil, body)
    tree:SetSize(TREE_W, RT.BODY_H)
    tree:SetPoint("TOPLEFT", body, "TOPLEFT", (slot - 1) * TREE_W, 0)
    tree.nodes, tree.lines, tree.arrows = {}, {}, {}
    tree.used = { lines = 0, arrows = 0 }
    -- A dark band behind the header, fading out to both sides, keeps it readable over bright art.
    for side = 1, 2 do
        local band = tree:CreateTexture(nil, "BACKGROUND")
        band:SetTexture(1, 1, 1, 1)
        band:SetSize(TREE_W * 0.4, 38)
        if side == 1 then
            band:SetGradientAlpha("HORIZONTAL", 0, 0, 0, 0, 0, 0, 0, 0.65)
            band:SetPoint("RIGHT", tree, "TOP", 0, -32)
        else
            band:SetGradientAlpha("HORIZONTAL", 0, 0, 0, 0.65, 0, 0, 0, 0)
            band:SetPoint("LEFT", tree, "TOP", 0, -32)
        end
    end
    tree.title = W.Text(tree, 22, 1, 0.96, 0.88, RT.HEADER_FONT)
    tree.count = W.Text(tree, 22, 1, 0.82, 0, RT.HEADER_FONT)
    for _, text in ipairs({ tree.title, tree.count }) do
        text:SetFont(RT.HEADER_FONT, 22, "OUTLINE")
        text:SetShadowColor(0, 0, 0, 1)
        text:SetShadowOffset(2, -2)
    end
    tree.count:SetPoint("LEFT", tree.title, "RIGHT", 8, 0)
    tree:Hide()
    return tree
end

function RT.BuildTrees(body)
    for slot = 1, 3 do trees[slot] = newTree(body, slot) end
end

function RT.HideTrees()
    for slot = 1, 3 do
        if trees[slot] then trees[slot]:Hide() end
    end
end

local function setHeader(tree, name, points)
    tree.title:SetText(name and name:upper() or "")
    tree.count:SetText(points or 0)
    if (points or 0) > 0 then
        tree.count:SetTextColor(1, 0.82, 0)
    else
        tree.count:SetTextColor(0.55, 0.55, 0.55)
    end
    local span = tree.title:GetStringWidth() + 8 + tree.count:GetStringWidth()
    tree.title:ClearAllPoints()
    tree.title:SetPoint("LEFT", tree, "TOPLEFT", (TREE_W - span) / 2, -32)
end

-- The deepest tier any of the class's trees reach; 51-point talents sit there and draw larger.
local depthByClass = {}

local function classDepth(ctx)
    local class = RT.ViewClass()
    if depthByClass[class] then return depthByClass[class] end
    local deepest = 0
    for tab = 1, RT.NumTabs(ctx) do
        for index = 1, RT.NumTalents(ctx, tab) do
            local _, _, tier = RT.TalentInfo(ctx, tab, index)
            if tier and tier > deepest then deepest = tier end
        end
    end
    if deepest > 0 then depthByClass[class] = deepest end
    return deepest
end

local function readTree(ctx, tab, perTier, available, depth)
    local name, _, spent, _, previewSpent = RT.TabInfo(ctx, tab)
    local treePoints = (spent or 0) + (ctx.editable and (previewSpent or 0) or 0)
    local talents, byCell = {}, {}
    for index = 1, RT.NumTalents(ctx, tab) do
        local tname, icon, tier, column, rank, maxRank, exceptional, met, preview, previewMet =
            RT.TalentInfo(ctx, tab, index)
        if tname and tier then
            rank = rank or 0
            local shown = ctx.editable and (preview or rank) or rank
            local ok = ctx.editable and previewMet or met
            local tierOpen = (tier - 1) * perTier <= treePoints
            local open = ctx.editable and ok and tierOpen and shown < (maxRank or 1) and available > 0
            local entry = {
                index = index, name = tname, icon = icon, tier = tier, column = column,
                shown = shown, pending = shown - rank, maxRank = maxRank or 1,
                exceptional = exceptional and true or false,
                met = ok and true or false, open = open and true or false, tierOpen = tierOpen,
                capstone = not ctx.pet and depth >= 9 and tier >= depth,
                needs = prereqCells(RT.TalentPrereqs(ctx, tab, index)),
            }
            talents[#talents + 1] = entry
            byCell[cellKey(tier, column)] = entry
        end
    end
    return { name = name, points = treePoints, committed = spent or 0, talents = talents, byCell = byCell }
end

local function paintTree(tree, tab, data)
    tree:Show()
    setHeader(tree, data.name, data.points)
    tree.used.lines, tree.used.arrows = 0, 0
    for k, entry in ipairs(data.talents) do
        local node = tree.nodes[k] or newNode(tree)
        tree.nodes[k] = node
        node.tab, node.index = tab, entry.index
        dressNode(node, entry)
        local x, y = cellCentre(entry.tier, entry.column, entry.capstone)
        node:ClearAllPoints()
        node:SetPoint("CENTER", tree, "TOPLEFT", x, -y)
        node:Show()
        node.shadow:Show()
        for _, cell in ipairs(entry.needs) do
            local source = data.byCell[cellKey(cell[1], cell[2])]
            if source then
                local fx, fy = cellCentre(source.tier, source.column, source.capstone)
                drawLink(tree, fx, fy, x, y, entry.met and source.shown > 0, shapeFor(entry))
            end
        end
    end
    for k = #data.talents + 1, #tree.nodes do
        tree.nodes[k]:Hide()
        tree.nodes[k].shadow:Hide()
    end
    for k = tree.used.lines + 1, #tree.lines do tree.lines[k]:Hide() end
    for k = tree.used.arrows + 1, #tree.arrows do tree.arrows[k]:Hide() end
end


function RT.PaintTrees()
    local ctx = RT.Context()
    local perTier = ctx.pet and (PET_TALENTS_PER_TIER or 3) or (PLAYER_TALENTS_PER_TIER or 5)
    local available = RT.Unspent(ctx) - RT.Staged(ctx)
    local depth = classDepth(ctx)
    local count = RT.NumTabs(ctx)
    if ctx.pet then count = math.min(count, 1) end

    local committed = {}
    for slot = 1, 3 do trees[slot]:Hide() end
    for tab = 1, count do
        local data = readTree(ctx, tab, perTier, available, depth)
        -- a plan has nothing learned: its art follows the planned points
        committed[tab] = ctx.plan and data.points or data.committed
        local tree = trees[ctx.pet and 2 or tab]
        if tree then paintTree(tree, tab, data) end
    end

    local class = RT.ViewClass()
    RT.SetArt(class, RT.LeadingTree(committed), not ctx.editable and not ctx.inspect)
    RT.ApplySearch()
    RT.lastAvailable = max(0, available)

    local owner = GameTooltip:GetOwner()
    if owner and owner.tab and owner:IsVisible() then nodeEnter(owner) end
end

local function markFound(node, found)
    if found then
        node.find:SetAlpha(1)
        node.find:Show()
        if not node.findPulse:IsPlaying() then node.findPulse:Play() end
    else
        node.findPulse:Stop()
        node.find:Hide()
    end
end

function RT.ApplySearch()
    local query = RT.query
    local found = 0
    for slot = 1, 3 do
        for _, node in ipairs(trees[slot].nodes) do
            if node:IsShown() then
                local hit = query ~= "" and node.talentName:find(query, 1, true) and true or false
                if hit then found = found + 1 end
                local alpha = (query == "" or hit) and 1 or 0.2
                node:SetAlpha(alpha)
                node.shadow:SetAlpha(alpha)
                markFound(node, hit)
            end
        end
    end
    RT.Call("SetFoundText", query ~= "" and found or nil)
end

-- Footer controls ---------------------------------------------------------------------------------

local bar = {}

local function learnStaged()
    LearnPreviewTalents(RT.Context().pet and true or false)
    PlaySound("igQuestListComplete")
end

StaticPopupDialogs["RATREE_LEARN"] = {
    text = CONFIRM_LEARN_PREVIEW_TALENTS,
    button1 = YES,
    button2 = NO,
    OnAccept = learnStaged,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

local function activateClicked()
    local ctx = RT.Context()
    if ctx.plan then
        if RT.Staged(ctx) > 0 then StaticPopup_Show("RATREE_SAVE_PRESET") end
        return
    end
    if not ctx.editable then
        SetActiveTalentGroup(ctx.group)
        return
    end
    if RT.Staged(ctx) > 0 then StaticPopup_Show("RATREE_LEARN") end
end

local function discardClicked()
    local ctx = RT.Context()
    if ctx.plan then
        RT.PlanClear()
        RT.Refresh()
        return
    end
    if ctx.editable then ResetGroupPreviewTalentPoints(ctx.pet, ctx.group) end
end

function RT.ClearSearchFocus()
    if bar.search then bar.search:ClearFocus() end
end

local function buildSearch(footer)
    local box = CreateFrame("EditBox", nil, footer, "InputBoxTemplate")
    box:SetSize(190, 20)
    box:SetAutoFocus(false)
    box:SetTextInsets(16, 4, 0, 0)
    local glass = box:CreateTexture(nil, "OVERLAY")
    glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    glass:SetSize(14, 14)
    glass:SetPoint("LEFT", box, "LEFT", 1, -1)
    local hint = W.Text(box, 11, W.DIM[1], W.DIM[2], W.DIM[3])
    hint:SetPoint("LEFT", box, "LEFT", 18, 0)
    hint:SetText(SEARCH)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function() hint:Hide() end)
    box:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then hint:Show() end
    end)
    box:SetScript("OnTextChanged", function(self)
        local query = self:GetText():lower()
        if query ~= "" then hint:Hide() end
        if query ~= RT.query then
            RT.query = query
            RT.ApplySearch()
        end
    end)
    bar.search = box
    return box
end

function RT.BuildFooterControls(footer)
    local presets = W.Button("RatreePresetsButton", footer, 96, 24, "Presets")
    presets:SetPoint("LEFT", footer, "LEFT", 16, 0)
    presets:SetScript("OnClick", function(self) RT.Call("TogglePresetMenu", self) end)
    bar.presets = presets

    local points = W.Text(footer, 13, 0.718, 0.678, 0.596)
    points:SetPoint("LEFT", presets, "RIGHT", 14, 0)
    bar.points = points

    local search = buildSearch(footer)
    search:SetPoint("CENTER", footer, "CENTER", -110, 0)

    -- Inside the box on the right, so it hides with the box on the glyph page.
    local found = W.Text(search, 11, 1, 0.85, 0.3)
    found:SetPoint("RIGHT", search, "RIGHT", -4, 0)
    search:SetTextInsets(16, 64, 0, 0)
    bar.found = found

    local activate = W.Button("RatreeLearnButton", footer, 180, 24)
    activate:SetPoint("LEFT", search, "RIGHT", 18, 0)
    activate:SetScript("OnClick", activateClicked)
    bar.activate = activate

    local discard = W.Button("RatreeDiscardButton", footer, 90, 24, "Discard")
    discard:SetPoint("LEFT", activate, "RIGHT", 8, 0)
    discard:SetScript("OnClick", discardClicked)
    W.TipOnHover(discard, "Discard", "Take back every point you have not learned yet.")
    bar.discard = discard

    -- Mirrors Presets on the right: Glyphs from the trees, Talents back from the glyph page.
    local glyphs = W.Button("RatreeGlyphsButton", footer, 96, 24, GLYPHS)
    glyphs:SetPoint("RIGHT", footer, "RIGHT", -16, 0)
    glyphs:SetScript("OnClick", function()
        RT.OpenPage(RT.view.page == "glyphs" and "talents" or "glyphs")
    end)
    bar.glyphs = glyphs

    -- A blank plan of your trees, saved as a preset; Back leaves it.
    local plan = W.Button("RatreePlanButton", footer, 80, 24, "Plan")
    plan:SetPoint("RIGHT", glyphs, "LEFT", -8, 0)
    plan:SetScript("OnClick", function()
        if RT.Planning() then RT.EndPlan() else RT.StartPlan() end
    end)
    W.TipOnHover(plan, "Plan", "A blank set of your trees: click a build in without touching your talents, "
        .. "then save it as a preset.")
    bar.plan = plan

    -- In a plan: paste a Wowhead talent link into it.
    local import = W.Button("RatreeImportButton", footer, 80, 24, "Import")
    import:SetPoint("RIGHT", plan, "LEFT", -8, 0)
    import:SetScript("OnClick", function() StaticPopup_Show("RATREE_IMPORT") end)
    W.TipOnHover(import, "Import", "Paste a Wowhead talent calculator link: the build fills the plan.")
    bar.import = import

    RT.BuildCastBar(footer)

    RT.Listen("PLAYER_REGEN_DISABLED", RT.ClearSearchFocus)
    RT.win:HookScript("OnMouseDown", RT.ClearSearchFocus)
end

function RT.SetFoundText(count)
    if not bar.found then return end
    if not count then
        bar.found:SetText("")
    elseif count == 0 then
        bar.found:SetText("|cffff5050no match|r")
    else
        bar.found:SetText(count .. " found")
    end
end

local function setActivate(text, enabled)
    local button = bar.activate
    button:SetText(text)
    button:SetWidth(button:GetTextWidth() + 40)
    if enabled then button:Enable() else button:Disable() end
    button:Show()
end

function RT.UpdateFooter()
    if not bar.activate then return end
    local glyphs = RT.view.page == "glyphs"
    local ctx = RT.Context()
    local live = not glyphs and ctx.editable
    local browsing = not glyphs and not ctx.editable

    -- Inspecting someone: their name and split, and search; nothing that changes talents.
    if ctx.inspect then
        bar.search:Show()
        bar.points:Show()
        for _, widget in ipairs({ bar.presets, bar.activate, bar.discard, bar.glyphs, bar.plan, bar.import }) do widget:Hide() end
        local split = {}
        for tab = 1, RT.NumTabs(ctx) do
            local _, _, spent = RT.TabInfo(ctx, tab)
            split[#split + 1] = spent or 0
        end
        bar.points:SetText((RT.inspectName or "") .. "  |cffe2b843" .. table.concat(split, " / ") .. "|r")
        RT.Call("UpdateGlyphSwitch")
        return
    end

    for _, widget in ipairs({ bar.search, bar.points }) do
        if glyphs then widget:Hide() else widget:Show() end
    end
    if glyphs or ctx.pet then bar.presets:Hide() else bar.presets:Show() end
    if glyphs or ctx.pet then bar.plan:Hide() else bar.plan:Show() end
    bar.plan:SetText(ctx.plan and "Back" or "Plan")
    if ctx.plan and not glyphs then bar.import:Show() else bar.import:Hide() end
    bar.discard:SetText(ctx.plan and "Clear" or "Discard")

    if ctx.plan and not glyphs then
        local planned = RT.Staged(ctx)
        bar.points:SetText(format("Plan  ·  points left |cff8fdc7a%d|r", max(0, RT.Unspent(ctx) - planned)))
        setActivate("Save as preset", planned > 0)
        if planned > 0 then bar.discard:Show() else bar.discard:Hide() end
    elseif live then
        local staged = RT.Staged(ctx)
        local left = max(0, RT.Unspent(ctx) - staged)
        bar.points:SetText(format("Points left |cff8fdc7a%d|r", left))
        setActivate(staged > 0 and format("Learn Talents (%d)", staged) or "Learn Talents",
            staged > 0)
        if staged > 0 then bar.discard:Show() else bar.discard:Hide() end
    elseif browsing then
        local split = {}
        for tab = 1, RT.NumTabs(ctx) do
            local _, _, spent = RT.TabInfo(ctx, tab)
            split[#split + 1] = spent or 0
        end
        bar.points:SetText(RT.SpecName(ctx.group) .. "  |cffe2b843" .. table.concat(split, " / ") .. "|r")
        setActivate("Switch to this spec", true)
        bar.discard:Hide()
    else
        bar.activate:Hide()
        bar.discard:Hide()
    end
    bar.glyphs:SetText(glyphs and TALENTS or GLYPHS)
    if UnitLevel("player") >= (SHOW_INSCRIPTION_LEVEL or 15) then bar.glyphs:Show() else bar.glyphs:Hide() end

    -- While the spec switch casts, its bar takes the middle of the footer.
    if bar.cast:IsShown() then
        bar.search:Hide()
        bar.activate:Hide()
        bar.discard:Hide()
    end
    RT.Call("UpdateGlyphSwitch")
end

-- Spec switch cast bar ----------------------------------------------------------------------------

-- The two dual-spec activation spells, by name as UnitCastingInfo reports them.
local function isSpecSwitch(name)
    for _, spell in ipairs(TALENT_ACTIVATION_SPELLS or { 63645, 63644 }) do
        if name and name == GetSpellInfo(spell) then return true end
    end
    return false
end

-- Retail's cast bar art: background, border and name plate share one atlas.
local CAST_ATLAS = RT.MEDIA .. "Castbar\\uicastingbar2x"
local CAST_FILL = RT.MEDIA .. "Castbar\\CastingBarStandard2"
local CAST_SPARK = RT.MEDIA .. "Castbar\\CastingBarSpark"
local CAST_BG = { 0.0009765625, 0.4130859375, 0.3671875, 0.41796875 }
local CAST_BORDER = { 0.412109375, 0.828125, 0.001953125, 0.060546875 }
local CAST_PLATE = { 0.001953125, 0.410109375, 0.00390625, 0.11328125 }
local CAST_W, CAST_H = 300, 16

local function atlasTexture(parent, layer, coords)
    local tex = parent:CreateTexture(nil, layer)
    tex:SetTexture(CAST_ATLAS)
    tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    return tex
end

local function castTick(holder)
    local name, _, _, _, startMs, endMs = UnitCastingInfo("player")
    if not name or not isSpecSwitch(name) then
        holder:Hide()
        RT.UpdateFooter()
        return
    end
    local now = math.min(GetTime() * 1000, endMs)
    local cast = holder.bar
    cast:SetMinMaxValues(startMs, endMs)
    cast:SetValue(now)
    local share = (endMs > startMs) and (now - startMs) / (endMs - startMs) or 0
    holder.spark:ClearAllPoints()
    holder.spark:SetPoint("CENTER", cast, "LEFT", share * CAST_W, 0)
    holder.name:SetText(name)
    holder.time:SetText(format("%.1f", math.max(0, (endMs - now) / 1000)))
end

function RT.BuildCastBar(footer)
    local holder = CreateFrame("Frame", nil, footer)
    holder:SetSize(CAST_W, CAST_H + 18)
    holder:SetPoint("CENTER", footer, "CENTER", 0, 0)
    holder:SetFrameLevel(footer:GetFrameLevel() + 5)

    -- Name plate under the bar, its top tucked behind the bar's lower edge.
    local plate = atlasTexture(holder, "BACKGROUND", CAST_PLATE)
    plate:SetSize(CAST_W, 22)
    plate:SetPoint("BOTTOM", holder, "BOTTOM", 0, 0)

    local cast = CreateFrame("StatusBar", nil, holder)
    cast:SetSize(CAST_W, CAST_H)
    cast:SetPoint("TOP", holder, "TOP", 0, 0)
    cast:SetStatusBarTexture(CAST_FILL)
    cast:SetStatusBarColor(1, 0.7, 0, 1)
    -- Background and border overhang the bar by 2px, as the art is cut.
    local bg = atlasTexture(cast, "BACKGROUND", CAST_BG)
    bg:SetPoint("TOPLEFT", cast, "TOPLEFT", -2, 0)
    bg:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", 2, 0)
    local border = atlasTexture(cast, "OVERLAY", CAST_BORDER)
    border:SetPoint("TOPLEFT", cast, "TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", 2, -2)
    holder.bar = cast

    local spark = cast:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(CAST_SPARK)
    spark:SetBlendMode("ADD")
    spark:SetSize(16, 32)
    holder.spark = spark

    holder.name = W.Text(holder, 11, 1, 0.82, 0)
    holder.name:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 8, 4)
    holder.time = W.Text(holder, 11, 1, 1, 1)
    holder.time:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -8, 4)

    holder:SetScript("OnUpdate", castTick)
    holder:Hide()
    bar.cast = holder

    RT.Listen("UNIT_SPELLCAST_START", function(_, unit)
        if unit ~= "player" or not isSpecSwitch(UnitCastingInfo("player")) then return end
        holder:Show()
        castTick(holder)
        RT.UpdateFooter()
    end)
    for _, event in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
        RT.Listen(event, function(_, unit)
            if unit == "player" and holder:IsShown() and not UnitCastingInfo("player") then
                holder:Hide()
                RT.UpdateFooter()
            end
        end)
    end
end

-- Live refresh ------------------------------------------------------------------------------------

local function onTalentEvent(event, unit)
    if event == "UNIT_PET" and unit ~= "player" then return end
    if event == "UNIT_PET" and not RT.PetHasTalents() then RT.view.pet = false end
    if event == "ACTIVE_TALENT_GROUP_CHANGED" then RT.view.group = RT.ActiveGroup() end
    RT.Refresh()
end

for event in ("PLAYER_TALENT_UPDATE CHARACTER_POINTS_CHANGED PREVIEW_TALENT_POINTS_CHANGED "
    .. "PREVIEW_PET_TALENT_POINTS_CHANGED PET_TALENT_UPDATE PLAYER_LEVEL_UP "
    .. "ACTIVE_TALENT_GROUP_CHANGED UNIT_PET"):gmatch("%S+") do
    RT.Listen(event, onTalentEvent)
end
