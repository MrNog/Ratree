local RT = select(2, ...)

local format, strtrim = string.format, strtrim

-- A preset can carry each character's action bars: preset.bars["Name-Realm"] = { saved, slots }, where
-- slots[slot] = what sat there. Slots are the game's action slots 1-120, under every bar addon, so any
-- layout is covered, the stance and form bars too (73-120).

local NUM_SLOTS = 120
-- Blizzard_MacroUI is load-on-demand, so its MAX_*_MACROS globals stay nil until the macro window has
-- been opened; these are the 3.3.5a values. Character macros are indexed above the account ones.
local ACCOUNT_MACROS, CHARACTER_MACROS = 36, 18

local function charKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

-- Reading -----------------------------------------------------------------------------------------

local function readSlot(slot)
    local kind, id, sub, spellID = GetActionInfo(slot)
    if kind == "spell" then
        local book = sub == "pet" and BOOKTYPE_PET or BOOKTYPE_SPELL
        local name = spellID and GetSpellInfo(spellID)
        if not name and id then name = GetSpellName(id, book) end
        if name then return { t = "spell", name = name, book = book } end
    elseif kind == "macro" then
        local name, icon, body = GetMacroInfo(id)
        if name then
            return { t = "macro", name = name, icon = icon, body = body, char = id > ACCOUNT_MACROS }
        end
    elseif kind == "item" then
        return { t = "item", id = id }
    elseif kind == "companion" then
        local _, _, spell = GetCompanionInfo(sub, id)
        if spell then return { t = "companion", sub = sub, spell = spell } end
    elseif kind == "equipmentset" then
        return { t = "set", name = id }
    end
end

local function same(a, b)
    if not (a and b) or a.t ~= b.t then return false end
    if a.t == "item" then return a.id == b.id end
    if a.t == "companion" then return a.spell == b.spell end
    return a.name == b.name
end

function RT.PresetBars(preset)
    return preset.bars and preset.bars[charKey()]
end

function RT.SaveBars(preset)
    local slots, count = {}, 0
    for slot = 1, NUM_SLOTS do
        local entry = readSlot(slot)
        if entry then
            slots[slot] = entry
            count = count + 1
        end
    end
    preset.bars = preset.bars or {}
    preset.bars[charKey()] = { saved = time(), slots = slots }
    return count
end

-- Finding what to put back ------------------------------------------------------------------------

-- The highest rank wins: the last match in the book.
local function findSpell(name, book)
    local found, i = nil, 1
    while true do
        local spell = GetSpellName(i, book)
        if not spell then return found end
        if spell == name then found = i end
        i = i + 1
    end
end

local function iconFile(path)
    return path and (path:match("([^\\]+)$") or path):lower()
end

-- CreateMacro takes an index into the macro icon list, not a path.
local function macroIconIndex(path)
    local wanted = iconFile(path)
    for i = 1, GetNumMacroIcons() do
        if iconFile(GetMacroIconInfo(i)) == wanted then return i end
    end
    return 1
end

-- The macro is found by name, then by body. One edited since the save is used as it is now; one
-- deleted is made again from the saved copy, in the slot type it had when there is room.
local function macroIndex(entry)
    local account, perChar = GetNumMacros()
    local wanted = strtrim(entry.body or "")
    local function scan(test)
        for i = 1, account or 0 do
            if test(i) then return i end
        end
        for i = ACCOUNT_MACROS + 1, ACCOUNT_MACROS + (perChar or 0) do
            if test(i) then return i end
        end
    end
    local found = scan(function(i) return GetMacroInfo(i) == entry.name end)
        or scan(function(i) return strtrim(select(3, GetMacroInfo(i)) or "") == wanted end)
    if found then return found end

    local charRoom = (perChar or 0) < CHARACTER_MACROS
    local accountRoom = (account or 0) < ACCOUNT_MACROS
    local perCharacter
    if entry.char then
        perCharacter = charRoom or not accountRoom
    else
        perCharacter = not accountRoom
    end
    if perCharacter and not charRoom then return nil end
    CreateMacro(entry.name, macroIconIndex(entry.icon), entry.body or "", perCharacter and 1 or nil)
    return GetMacroIndexByName(entry.name)
end

local function findCompanion(sub, spell)
    for i = 1, GetNumCompanions(sub) or 0 do
        if select(3, GetCompanionInfo(sub, i)) == spell then return i end
    end
end

-- Puts the entry on the cursor; false when there is nothing to pick up.
local function pickup(entry)
    if entry.t == "spell" then
        local index = findSpell(entry.name, entry.book or BOOKTYPE_SPELL)
        if not index then return false end
        PickupSpell(index, entry.book or BOOKTYPE_SPELL)
    elseif entry.t == "macro" then
        local index = macroIndex(entry)
        if not index or index == 0 then return false end
        PickupMacro(index)
    elseif entry.t == "item" then
        PickupItem(entry.id)
    elseif entry.t == "companion" then
        local index = findCompanion(entry.sub, entry.spell)
        if not index then return false end
        PickupCompanion(entry.sub, index)
    elseif entry.t == "set" then
        PickupEquipmentSetByName(entry.name)
    end
    return GetCursorInfo() ~= nil
end

local function place(slot, entry)
    ClearCursor()
    if not pickup(entry) then
        ClearCursor()
        return false
    end
    PlaceAction(slot)
    ClearCursor()
    return true
end

-- Putting back ------------------------------------------------------------------------------------

-- Spells the build has not learned yet: placed as soon as they are learned, if the slot is still empty.
local waiting = {}

local function restore(snap)
    wipe(waiting)
    local placed, wait, missing = 0, 0, 0
    for slot = 1, NUM_SLOTS do
        local entry = snap.slots[slot]
        if not entry then
            if HasAction(slot) then
                PickupAction(slot)
                ClearCursor()
            end
        elseif same(readSlot(slot), entry) or place(slot, entry) then
            placed = placed + 1
        elseif entry.t == "spell" then
            if HasAction(slot) then
                PickupAction(slot)
                ClearCursor()
            end
            waiting[slot] = entry
            wait = wait + 1
        else
            -- an item not in the bags right now can't be picked up; the slot is left as it is
            missing = missing + 1
        end
    end
    local text = format("Bars loaded: %d placed", placed)
    if wait > 0 then text = text .. format(", %d wait for talents", wait) end
    if missing > 0 then text = text .. format(", %d missing", missing) end
    RT.Notify(text .. ".", 0.2, 1, 0.2)
end

function RT.LoadBars(preset)
    local snap = RT.PresetBars(preset)
    if not snap then return end
    RT.OutOfCombat("bars", function() restore(snap) end)
end

local function fillWaiting()
    if not next(waiting) then return end
    RT.OutOfCombat("bars-waiting", function()
        for slot, entry in pairs(waiting) do
            if HasAction(slot) then
                -- something else was put there meanwhile: that wins
                waiting[slot] = nil
            elseif place(slot, entry) then
                waiting[slot] = nil
            end
        end
    end)
end

RT.Listen("LEARNED_SPELL_IN_TAB", fillWaiting)
RT.Listen("SPELLS_CHANGED", fillWaiting)
