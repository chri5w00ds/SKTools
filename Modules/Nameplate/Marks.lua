-- SKTools - Nameplate marks: quest counters, quest-starter
-- icon and rare glow on nameplates (WoW Forever)
--   Crossed swords : mob is needed for a kill objective
--   Coin purse     : mob drops something you still need to loot
--   Paper + "!"    : mob can drop an item that starts a quest
--   Counters       : under the bar; bag + items left on the left, kills left + swords on the right
--   Glow           : mob is rare / rare elite

local ADDON, ns = ...

-- this module's own table; the quest-starter lists (QuestStarters.lua) sit on ns
local M = {}
ns.Marks = M

local MEDIA = ns.MEDIA
local ICONS = { kill = MEDIA .. "Kill", loot = MEDIA .. "Loot", starter = MEDIA .. "Starter" }
-- only the quest-starter icon sits beside the bar; kill and loot progress is
-- shown by the counters under the bar
local ORDER = { "starter" }

M.DEFAULTS = {
    -- icons (offset is from the centre of the health bar)
    iconSize = 46,
    iconX = 121,
    iconY = 60,
    iconSpacing = 1,
    show = { kill = true, loot = true, starter = true },
    starterWide = false,    -- also mark mobs for rare world drops (OOX beacons, old books...)

    -- quest counters under the health bar: items still to loot on the left
    -- (bag + numbers), kills still needed on the right (numbers + swords).
    -- x/y nudge each side from its default spot; size grows from the icon centre.
    counters = true,
    counterLeft = { x = -7, y = 0, size = 16 },
    counterRight = { x = 7, y = 0, size = 16 },
    counterEdit = "both",      -- which side the settings sliders move

    -- rare glow
    glow = true,
    glowColor = { 1.0, 0.85, 0.35 },
    glowPulse = true,

    starters = {},      -- learned: [npcID] = questID or true (false = unmarked)
}

local db
local holders = setmetatable({}, { __mode = "k" })   -- plate -> our overlay frame
local activeUnits = {}                               -- unit token -> plate
local cache = {}                                     -- guid -> last good result
local objIndex = {}                                  -- normalized objective text -> objective info
M.manualTest = false
M.previewing = false

local Q = C_QuestLog
local TT = C_TooltipInfo
local LINE = Enum and Enum.TooltipDataLineType or {}
local LINE_OBJECTIVE = LINE.QuestObjective or 8
local LINE_TITLE = LINE.QuestTitle or 17
local LINE_PLAYER = LINE.QuestPlayer or 18

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

-- WoW Forever uses Midnight's "secret value" rules: some unit data can't be
-- read or compared in combat. Anything secret is treated as unknown here.
local function safe(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end

M.Print = ns.Printer("Marks")
local Print = M.Print

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function M.ResetSettings()
    local starters = db.starters
    wipe(db)
    CopyDefaults(M.DEFAULTS, db)
    db.starters = starters          -- never throw away learned mobs
end

local function Normalize(text)
    if type(text) ~= "string" then return nil end
    local s = text:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("%d+", ""):gsub("[%p%s]", "")
    if s == "" then return nil end
    return s
end

local function NPCIDFromGUID(guid)
    guid = safe(guid)
    if not guid then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

----------------------------------------------------------------------
-- Quest log index: tells kill objectives from loot ones, and gives counts
----------------------------------------------------------------------

local charDB

local function RebuildObjectiveIndex()
    wipe(objIndex)
    local order = 0
    if not Q or not Q.GetNumQuestLogEntries then return end
    for i = 1, Q.GetNumQuestLogEntries() do
        local info = Q.GetInfo(i)
        if info and not info.isHeader and info.questID then
            -- once a quest has been in this character's log, its starter icon
            -- never shows again for this character (even if abandoned)
            if charDB then charDB.seenQuests[info.questID] = true end
            local objectives = Q.GetQuestObjectives(info.questID)
            if objectives then
                for _, obj in ipairs(objectives) do
                    local key = Normalize(obj.text)
                    if key and obj.type then
                        local have, need = obj.numFulfilled, obj.numRequired
                        if obj.type == "progressbar" and GetQuestProgressBarPercent then
                            have, need = GetQuestProgressBarPercent(info.questID) or 0, 100
                        end
                        order = order + 1          -- quest log order: top item = leftmost number
                        objIndex[key] = { type = obj.type, have = have, need = need, order = order }
                    end
                end
            end
        end
    end
end

local KILL_WORDS = { "slain", "killed", "defeated", "destroyed", "slay" }

-- returns kind ("kill"/"loot"), have, need, quest-log order (nil if not found)
local function ClassifyObjective(text)
    local key = Normalize(text)
    if not key then return nil end

    local obj = objIndex[key]
    if not obj then
        -- tooltip and quest-log wording can differ slightly; try a looser match
        for k, o in pairs(objIndex) do
            if k:find(key, 1, true) or key:find(k, 1, true) then obj = o break end
        end
    end

    -- counts straight from the tooltip line ("3/10 ..." or "...: 3/10")
    local tHave, tNeed = text:match("(%d+)%s*/%s*(%d+)")
    tHave, tNeed = tonumber(tHave), tonumber(tNeed)
    local pct = tonumber(text:match("(%d+)%%"))

    local kind, have, need
    if obj then
        kind = obj.type == "item" and "loot" or "kill"   -- monster, progressbar, event, ...
        have, need = obj.have, obj.need
    else
        local lower = text:lower()
        kind = "loot"
        for _, w in ipairs(KILL_WORDS) do
            if lower:find(w, 1, true) then kind = "kill" break end
        end
        if pct then kind = "kill" end
    end
    -- the tooltip refreshes faster than the quest log, so prefer its numbers
    if tHave and tNeed then have, need = tHave, tNeed
    elseif pct and not have then have, need = pct, 100 end

    return kind, have, need, obj and obj.order
end

----------------------------------------------------------------------
-- Scanning a unit
----------------------------------------------------------------------

local playerRace, playerClass

local function HasBit(mask, id)
    if not mask or mask == 0 or not id then return true end
    return math.floor(mask / 2 ^ (id - 1)) % 2 == 1
end

-- can this character still pick up the quest a dropped item would start?
local function StarterQuestOpen(questID)
    if type(questID) ~= "number" then return true end       -- unknown quest
    if charDB and charDB.seenQuests[questID] then return false end
    if Q then
        if Q.IsQuestFlaggedCompleted and Q.IsQuestFlaggedCompleted(questID) then return false end
        if Q.IsOnQuest and Q.IsOnQuest(questID) then return false end
    end
    local r = ns.StarterRestrict and ns.StarterRestrict[questID]
    if r then
        if not playerRace then
            playerRace = select(3, UnitRace("player"))
            playerClass = select(3, UnitClass("player"))
        end
        if not HasBit(r[1], playerRace) or not HasBit(r[2], playerClass) then return false end
    end
    if not db.starterWide and ns.StarterWide and ns.StarterWide[questID] then return false end
    return true
end

local function AnyOpen(entry)
    if entry == true then return true end
    if type(entry) == "table" then
        for _, questID in ipairs(entry) do
            if StarterQuestOpen(questID) then return true end
        end
        return false
    end
    if type(entry) == "number" then return StarterQuestOpen(entry) end
    return false
end

local function StarterInfo(npcID)
    if not npcID then return false end
    local mine = db.starters[npcID]             -- learned from loot or marked by you
    if mine == false then return false end      -- you unmarked this mob
    return AnyOpen(mine) or AnyOpen(ns.StarterSeed and ns.StarterSeed[npcID])
end

local myName

-- is this tooltip name line the player's own?
local function IsMyNameLine(line)
    if not myName then myName = UnitName("player") end
    local guid = safe(line.guid)
    if guid and guid == safe(UnitGUID("player")) then return true end
    local text = safe(line.leftText)
    if not text then return true end          -- unreadable: assume it's us rather than show nothing
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("%-.*$", "")             -- drop "-Realm"
    return text == myName
end

local function ScanUnit(unit)
    local guid = safe(UnitGUID(unit))
    local r = { kill = false, loot = false, starter = false, rare = false }

    if safe(UnitIsPlayer(unit)) then return r end

    local classification = safe(UnitClassification(unit))
    r.rare = classification == "rare" or classification == "rareelite"
    r.starter = StarterInfo(NPCIDFromGUID(guid))

    local sawSecret = false
    local found = {}        -- every unfinished counted objective on this mob
    local data = TT and TT.GetUnit and TT.GetUnit(unit)
    if data and data.lines then
        -- In a group the tooltip puts a name line above each player's progress,
        -- yours included. Only read the block under your own name (or lines
        -- with no name above them, which is how it looks when solo).
        local otherPlayers = false
        for lineNo, line in ipairs(data.lines) do
            local lineType = safe(line.type)
            if lineType == LINE_PLAYER then
                otherPlayers = not IsMyNameLine(line)
            elseif lineType == LINE_TITLE then
                otherPlayers = false
            elseif lineType == LINE_OBJECTIVE and not otherPlayers then
                local text = safe(line.leftText)
                if text == nil and line.leftText ~= nil then
                    sawSecret = true
                elseif not safe(line.completed) then
                    local kind, have, need, order = ClassifyObjective(text)
                    if kind and not (have and need and have >= need) then
                        r[kind] = true
                        if have and need then
                            found[#found + 1] = { kind = kind, left = need - have, order = order or (1000 + lineNo) }
                        end
                    end
                end
            end
        end
    end
    -- items on the left, kills on the right, each in quest-log order
    table.sort(found, function(a, b) return a.order < b.order end)
    r.counts = { loot = {}, kill = {} }
    for _, f in ipairs(found) do tinsert(r.counts[f.kind], f.left) end

    if guid then
        if sawSecret and cache[guid] then
            -- in combat and the tooltip is hidden from us: keep what we knew
            local c = cache[guid]
            r.kill, r.loot, r.counts = c.kill, c.loot, c.counts
        else
            cache[guid] = r
        end
    end
    return r
end

----------------------------------------------------------------------
-- Overlay frames
----------------------------------------------------------------------

local function FindHealthBar(plate)
    local ours = ns.Plates and ns.Plates.Frame and ns.Plates.Frame(plate)
    if ours then return ours end
    local uf = plate.UnitFrame
    if uf then
        local c = uf.HealthBarsContainer
        if c and c.healthBar then return c.healthBar end
        if uf.healthBar then return uf.healthBar end
        if uf.HealthBar then return uf.HealthBar end
    end
    return plate
end

-- Arial Narrow ships with every client and is nice and thin
local COUNTER_FONT = "Fonts\\ARIALN.TTF"
local BASE_SIZE = 14      -- the default size; the icon centre is placed for this size

-- plain numbers; two of a kind are joined like 7--8
local SEPARATOR = "--"
local function CounterText(list)
    local parts = {}
    for i, n in ipairs(list) do parts[i] = tostring(math.max(0, n)) end
    return table.concat(parts, SEPARATOR)
end

local function GetCounter(h, side)
    h.counters = h.counters or {}
    local c = h.counters[side]
    if c then return c end
    c = CreateFrame("Frame", nil, h.dotFrame)
    c:SetAllPoints(h.plate)
    c.icon = c:CreateTexture(nil, "OVERLAY")
    c.icon:SetTexture(side == "left" and ICONS.loot or ICONS.kill)
    c.text = c:CreateFontString(nil, "OVERLAY")
    c.text:SetFont(COUNTER_FONT, 11, "OUTLINE")
    c.text:SetTextColor(1, 1, 1)
    h.counters[side] = c
    return c
end

local function PlaceCounter(h, side, list)
    local c = GetCounter(h, side)
    if not db.counters or not list or #list == 0 then c:Hide() return end
    local cfg = side == "left" and db.counterLeft or db.counterRight
    local bar = h.bar
    local barH = bar.GetHeight and bar:GetHeight() or 0
    if not barH or barH <= 0 then barH = 10 end
    local curve = barH / 2                    -- where the rounded end becomes straight
    local size = cfg.size

    -- the icon's centre stays fixed whatever the size, so it grows/shrinks from
    -- its middle; by default it sits just under the bar's bottom edge
    local cy = -(BASE_SIZE / 2 + 1.5) + cfg.y
    c.icon:SetSize(size, size)
    c.icon:ClearAllPoints()
    c.text:ClearAllPoints()
    local fontSize = math.max(6, math.floor(size * 0.72 + 0.5))
    -- the drawn part of the icons sits ~3.5% below their square's centre, and
    -- WoW centres the text's whole line box (which has room for descenders
    -- below the digits), so the digits ride high; drop them to line up
    local dy = -(size * 0.035 + fontSize * 0.1)
    if side == "left" then
        c.icon:SetPoint("CENTER", bar, "BOTTOMLEFT", curve + BASE_SIZE / 2 + cfg.x, cy)
        c.text:SetPoint("LEFT", c.icon, "RIGHT", 1, dy)
    else
        c.icon:SetPoint("CENTER", bar, "BOTTOMRIGHT", -(curve + BASE_SIZE / 2) + cfg.x, cy)
        c.text:SetPoint("RIGHT", c.icon, "LEFT", -1, dy)
    end
    c.text:SetFont(COUNTER_FONT, fontSize, "OUTLINE")
    c.text:SetText(CounterText(list))
    c:Show()
end

local function LayoutCounters(h, counts)
    PlaceCounter(h, "left", counts and counts.loot)
    PlaceCounter(h, "right", counts and counts.kill)
    h.dotFrame:Show()
end

local function LayoutIcons(h)
    local size, gap = db.iconSize, db.iconSpacing
    local shown = {}
    for _, key in ipairs(ORDER) do
        local icon = h.icons[key]
        icon:SetSize(size, size)
        icon:ClearAllPoints()
        if icon:IsShown() then shown[#shown + 1] = icon end
    end
    -- the row of visible icons is centred on (bar centre + offset)
    local total = #shown * size + math.max(#shown - 1, 0) * gap
    for i, icon in ipairs(shown) do
        icon:SetPoint("LEFT", h.bar, "CENTER", db.iconX - total / 2 + (i - 1) * (size + gap), db.iconY)
    end

    local g = h.glow
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", h.bar, "TOPLEFT", -12, 10)
    g:SetPoint("BOTTOMRIGHT", h.bar, "BOTTOMRIGHT", 12, -10)
    g:SetVertexColor(unpack(db.glowColor))
end

local function GetHolder(plate)
    local h = holders[plate]
    if h then return h end

    local bar = FindHealthBar(plate)
    local level = bar.GetFrameLevel and bar:GetFrameLevel() or 1

    h = CreateFrame("Frame", nil, plate)
    h:SetAllPoints(plate)
    h:SetFrameLevel(level + 5)
    h.bar, h.plate = bar, plate

    h.icons = {}
    for _, key in ipairs(ORDER) do
        local t = h:CreateTexture(nil, "OVERLAY")
        t:SetTexture(ICONS[key])
        t:Hide()
        h.icons[key] = t
    end

    h.dotFrame = CreateFrame("Frame", nil, h)
    h.dotFrame:SetAllPoints(plate)
    h.dotFrame:SetFrameLevel(level + 6)
    h.dotList = {}

    -- glow sits on its own frame just behind the bar
    local gf = CreateFrame("Frame", nil, plate)
    gf:SetAllPoints(bar)
    gf:SetFrameLevel(math.max(level - 1, 0))
    h.gf = gf
    local g = gf:CreateTexture(nil, "BACKGROUND")
    g:SetTexture(MEDIA .. "Glow")
    g:SetBlendMode("ADD")
    g:Hide()
    h.glow = g

    local ag = g:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.9)
    a:SetSmoothing("IN_OUT")
    h.pulse = ag

    holders[plate] = h
    return h
end

local function Apply(plate, r)
    local h = GetHolder(plate)
    -- on our own nameplates the counters and the quest-starter icon are drawn by Plates.lua,
    -- beside the level box; only the rare glow stays here, around our bar
    local ours = ns.Plates and ns.Plates.Frame and ns.Plates.Frame(plate)
    h.bar = ours or FindHealthBar(plate)
    if h.gf then h.gf:ClearAllPoints(); h.gf:SetAllPoints(h.bar) end
    if ours then
        for _, key in ipairs(ORDER) do h.icons[key]:Hide() end
        for _, c in pairs(h.counters or {}) do c:Hide() end
        ns.Plates.SetMarks(plate, r)
        LayoutIcons(h)
    else
        for _, key in ipairs(ORDER) do
            h.icons[key]:SetShown(r[key] and db.show[key])
        end
        LayoutIcons(h)
        LayoutCounters(h, r.counts)
    end
    h:Show()

    local glowOn = r.rare and db.glow
    h.glow:SetShown(glowOn)
    if glowOn and db.glowPulse then
        if not h.pulse:IsPlaying() then h.pulse:Play() end
    else
        h.pulse:Stop()
        h.glow:SetAlpha(1)
    end
end

local TEST_RESULT = { kill = true, loot = true, starter = true, rare = true,
    counts = { loot = { 7, 5 }, kill = { 9 } } }

local function UpdateUnit(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
    activeUnits[unit] = plate
    -- while the settings window is open, preview only on your target (or on
    -- every plate if you have no target) so the rest show their real state
    -- Friendly players never get anything, preview and test mode included; a friendly player
    -- as target counts as no target, so the other plates show the preview.
    local function FriendlyPlayer(u)
        return safe(UnitIsPlayer(u)) == true and safe(UnitCanAttack("player", u)) == false
    end
    if FriendlyPlayer(unit) then Apply(plate, ScanUnit(unit)); return end
    local preview = M.previewing
        and (not UnitExists("target") or FriendlyPlayer("target") or UnitIsUnit(unit, "target"))
    Apply(plate, (M.manualTest or preview) and TEST_RESULT or ScanUnit(unit))
end

local function HideUnit(unit)
    local plate = activeUnits[unit]
    activeUnits[unit] = nil
    local h = plate and holders[plate]
    if h then
        h:Hide()
        h.glow:Hide()
        h.pulse:Stop()
    end
end

function M.RefreshAll()
    for unit in pairs(activeUnits) do UpdateUnit(unit) end
end
M.UpdateUnit = UpdateUnit
local RefreshAll = M.RefreshAll

-- quest log events come in bursts; coalesce them
local refreshPending = false
local function QueueRefresh(rebuild)
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0.3, function()
        refreshPending = false
        if rebuild then RebuildObjectiveIndex() end
        RefreshAll()
    end)
end

----------------------------------------------------------------------
-- Learning quest-starter drops from loot
----------------------------------------------------------------------

local function Contains(entry, questID)
    if entry == questID then return true end
    if type(entry) == "table" then
        for _, q in ipairs(entry) do if q == questID then return true end end
    end
    return false
end

-- returns true if this was new information
local function LearnStarter(npcID, questID)
    local mine = db.starters[npcID]
    if mine == false then return false end                  -- you unmarked it; respect that
    if Contains(mine, questID) then return false end
    if Contains(ns.StarterSeed and ns.StarterSeed[npcID], questID) then return false end   -- already listed
    if mine == nil or mine == true then
        db.starters[npcID] = questID
    elseif type(mine) == "number" then
        db.starters[npcID] = { mine, questID }
    else
        tinsert(mine, questID)
    end
    return true
end

local function LearnFromLoot()
    if not GetNumLootItems then return end
    for slot = 1, GetNumLootItems() do
        local _, name, _, _, _, _, _, questID = GetLootSlotInfo(slot)
        questID = safe(questID)
        if questID and questID > 0 and GetLootSourceInfo then
            local sources = { GetLootSourceInfo(slot) }
            for i = 1, #sources, 2 do
                local npcID = NPCIDFromGUID(sources[i])
                if npcID and LearnStarter(npcID, questID) then
                    Print(("learned: this mob drops %s (quest %d). All your characters will see it."):format(safe(name) or "a quest starter", questID))
                end
            end
        end
    end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        local root, char = ns.InitDB()
        db = root.marks
        CopyDefaults(M.DEFAULTS, db)
        M.db = db
        charDB = char.marks
        charDB.seenQuests = charDB.seenQuests or {}
        f:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_ENTERING_WORLD" then
        RebuildObjectiveIndex()
        QueueRefresh(false)

    elseif event == "NAME_PLATE_UNIT_ADDED" then
        UpdateUnit(arg1)

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        HideUnit(arg1)

    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        if arg1 == "player" then QueueRefresh(true) end

    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        LearnFromLoot()

    elseif event == "PLAYER_TARGET_CHANGED" then
        if M.previewing then RefreshAll() end

    elseif event == "PLAYER_REGEN_ENABLED" then
        QueueRefresh(false)   -- re-read anything that was secret in combat

    else -- QUEST_LOG_UPDATE, QUEST_ACCEPTED, QUEST_REMOVED, QUEST_TURNED_IN
        QueueRefresh(true)
    end
end)

for _, e in ipairs({
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
    "UNIT_QUEST_LOG_CHANGED", "LOOT_READY", "LOOT_OPENED", "PLAYER_REGEN_ENABLED",
    "PLAYER_TARGET_CHANGED",
}) do
    pcall(f.RegisterEvent, f, e)   -- tolerate events Forever might not have
end

----------------------------------------------------------------------
-- /skt marks ...
----------------------------------------------------------------------

local function Help()
    Print("commands:")
    print("  /skt marks test  – show every icon, dots and the glow on all nameplates")
    print("  /skt marks debug  – print what the nameplate marks see on your target")
    print("  /skt marks starter add [questID]  – mark your target as a quest-starter dropper")
    print("  /skt marks starter remove  |  /skt marks starter list")
end

function M.Command(msg)
    local cmd, a, b = strsplit(" ", (msg or ""):lower():trim())

    if cmd == "debug" then
        if not UnitExists("target") then Print("target a mob first.") return end
        Print("debug for " .. (safe(UnitName("target")) or "?") ..
            "  (test mode " .. (M.manualTest and "ON" or "off") ..
            ", settings preview " .. (M.previewing and "ON" or "off") .. ")")
        local data = TT and TT.GetUnit and TT.GetUnit("target")
        for i, line in ipairs(data and data.lines or {}) do
            local t = safe(line.type)
            local tag = t == LINE_OBJECTIVE and "objective" or t == LINE_TITLE and "quest"
                or t == LINE_PLAYER and (IsMyNameLine(line) and "player:you" or "player:other") or tostring(t)
            local kind, have, need = nil, nil, nil
            if t == LINE_OBJECTIVE and safe(line.leftText) then kind, have, need = ClassifyObjective(safe(line.leftText)) end
            print(("  %d [%s] %s%s%s"):format(i, tag, tostring(safe(line.leftText) or "<secret>"),
                safe(line.completed) and " (done)" or "",
                kind and ("  -> " .. kind .. (have and (" " .. have .. "/" .. need) or "")) or ""))
        end
        local r = ScanUnit("target")
        print(("  result: kill=%s loot=%s starter=%s rare=%s counters: %s"):format(tostring(r.kill), tostring(r.loot),
            tostring(r.starter), tostring(r.rare), "left " .. (#r.counts.loot > 0 and table.concat(r.counts.loot, "/") or "-") ..
            ", right " .. (#r.counts.kill > 0 and table.concat(r.counts.kill, "/") or "-")))
        return
    elseif cmd == "test" then
        M.manualTest = not M.manualTest
        Print("test mode " .. (M.manualTest and "ON" or "off"))
    elseif cmd == "starter" and (a == "add" or a == "remove") then
        local npcID = NPCIDFromGUID(UnitGUID("target"))
        if not npcID then Print("target a mob first.") return end
        if a == "add" then
            db.starters[npcID] = tonumber(b) or true
            Print(("%s (NPC %d) marked as a quest-starter dropper."):format(UnitName("target") or "?", npcID))
        else
            db.starters[npcID] = false   -- false also overrides the seed list
            Print(("%s (NPC %d) unmarked."):format(UnitName("target") or "?", npcID))
        end
    elseif cmd == "starter" and a == "list" then
        local n = 0
        for id, q in pairs(db.starters) do
            if q then
                n = n + 1
                local what = q == true and "unknown quest"
                    or type(q) == "table" and ("quests " .. table.concat(q, ", "))
                    or ("quest " .. q)
                print(("  NPC %d  →  %s"):format(id, what))
            end
        end
        Print(n .. " mob(s) learned or marked by you (shared by all your characters), plus the built-in list.")
    else
        Help()
        return
    end
    RefreshAll()
    ns.RefreshSettings()
end

-- timed by /skt cpu
ns.Profile("Quest marks", f)
