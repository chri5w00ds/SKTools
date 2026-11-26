--[[-------------------------------------------------------------------------
  SKTools - quest tracker

  Our own quest panel in the style of the game's objective tracker, which it
  stands in for while it is switched on (the game's comes back when it is off).

    Out in the world   the quests you track, under the quest log's region
                       headers, regions A to Z; click a region to fold it
    In a dungeon       only that dungeon's quests (tracked or not), under its
                       name
    PvP (swords icon)  PvP quests only, kept out of the other two views

  Each quest: its marker, "[level] title" coloured by difficulty (with
  (Elite), (Dungeon), (Raid), (PvP) as the game writes them), and its
  objectives. Click a title to open the quest, shift-click it to stop
  tracking it. Spoken's Play button sits at the top right of each quest when
  Spoken is installed, as it does on the game's tracker.

  Redrawn when the quest log changes (events, gathered over a tenth of a
  second), never on a timer.
---------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function Ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return Plain(a), Plain(b), Plain(c), Plain(d) end
end

ns.QUEST_DEFAULTS = {
    enabled = true,
    berryEnabled = false,                      -- Berry Mode keeps its own switch, off until turned on
    point = "TOPRIGHT", x = -110, y = -250,
    width = 260,
    maxHeight = 520,                           -- taller than this, it scrolls
    fontSize = 13,
    dungeonAll = true,                         -- in a dungeon: its quests even when not tracked
    spoken = true,                             -- Spoken's Play buttons, when Spoken is installed
    items = true,                              -- a quest's usable item, as a button by the quest
    unlocked = false,
    pvp = false,                               -- showing the PvP list
    collapsed = {},                            -- [region name] = true: folded
    minimized = false,                         -- the whole panel folded to its title bar
}

local db
local state = { why = "not set up", view = "-", quests = 0, regions = 0, blizzard = "-" }

local function DeepFill(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            DeepFill(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

----------------------------------------------------------------------
-- The quest log
----------------------------------------------------------------------

local Q = C_QuestLog          -- looked up afresh on each redraw and click
local TAG = { GROUP = 1, PVP = 41, RAID = 62, DUNGEON = 81 }

local function IsWatched(questID, index)
    if Q and Q.GetQuestWatchType then
        local ok, w = pcall(Q.GetQuestWatchType, questID)
        if ok then return w ~= nil end
    end
    if Q and Q.IsQuestWatched then
        local w = Ask(Q.IsQuestWatched, questID)
        if w ~= nil then return w == true end
    end
    if _G.IsQuestWatched and index then return Ask(IsQuestWatched, index) and true or false end
    return false
end

local function TagOf(questID)
    if not (Q and Q.GetQuestTagInfo) then return nil end
    local t = Ask(Q.GetQuestTagInfo, questID)
    if type(t) == "table" then return Plain(t.tagID), Plain(t.tagName) end
end

local function IsComplete(questID, info)
    if Q and Q.IsComplete then
        local c = Ask(Q.IsComplete, questID)
        if c ~= nil then return c == true end
    end
    return info and Plain(info.isComplete) == 1 or (info and Plain(info.isComplete) == true) or false
end

-- every quest in the log, with the region header it sits under
local function ReadLog()
    Q = _G.C_QuestLog
    local list = {}
    if not (Q and Q.GetNumQuestLogEntries and Q.GetInfo) then return list end
    local n = Ask(Q.GetNumQuestLogEntries) or 0
    local header
    for i = 1, n do
        local info = Ask(Q.GetInfo, i)
        if type(info) == "table" then
            if info.isHeader then
                header = Plain(info.title) or header
            elseif not info.isHidden and Plain(info.questID) then
                local id = Plain(info.questID)
                local tagID, tagName = TagOf(id)
                list[#list + 1] = {
                    questID = id, index = i, title = Plain(info.title) or "?", level = Plain(info.level) or 0,
                    header = header or "Other", tagID = tagID, tagName = tagName,
                    complete = IsComplete(id, info), watched = IsWatched(id, i),
                    group = (Plain(info.suggestedGroup) or 0) > 0,
                }
                -- its usable item, as the game's tracker shows it (and once done only if the game says so)
                local link, icon, charges, whenDone = Ask(_G.GetQuestLogSpecialItemInfo, i)
                local q = list[#list]
                if link and icon and (not q.complete or whenDone) then
                    q.item = { link = link, icon = icon, charges = charges, id = tonumber(tostring(link):match("item:(%d+)")) }
                end
            end
        end
    end
    return list
end

local function IsPvP(q)
    if q.tagID == TAG.PVP then return true end
    local tn = type(q.tagName) == "string" and q.tagName:lower() or ""
    return tn == "pvp" or tn:find("pvp") ~= nil
end

-- where you are: a dungeon or raid's name, or nil out in the world
local function InstanceName()
    local okI, inside, kind = pcall(IsInInstance)
    if not (okI and Plain(inside)) then return nil end
    kind = Plain(kind)
    if kind ~= "party" and kind ~= "raid" then return nil end
    local name = Ask(GetInstanceInfo)
    return name
end

-- the quests to show, in groups: { { name = region, quests = { ... } }, ... }
local function Groups()
    local log = ReadLog()
    local groups, byName = {}, {}
    local function Put(name, q)
        local g = byName[name]
        if not g then g = { name = name, quests = {} }; byName[name] = g; groups[#groups + 1] = g end
        g.quests[#g.quests + 1] = q
    end
    local inst = InstanceName()
    if db.pvp then
        state.view = "PvP"
        for _, q in ipairs(log) do if IsPvP(q) then Put(q.header, q) end end
    elseif inst then
        state.view = "dungeon: " .. inst
        local zone = Ask(_G.GetRealZoneText)
        for _, q in ipairs(log) do
            local here = q.header == inst or (zone and q.header == zone)
            if here and not IsPvP(q) and (q.watched or db.dungeonAll) then Put(inst, q) end
        end
        if #groups == 0 then groups[1] = { name = inst, quests = {}, empty = "No quests for here." } end
    else
        state.view = "regions"
        for _, q in ipairs(log) do if q.watched and not IsPvP(q) then Put(q.header, q) end end
        table.sort(groups, function(a, b) return a.name:lower() < b.name:lower() end)
    end
    return groups
end

----------------------------------------------------------------------
-- Drawing, in the game tracker's style
----------------------------------------------------------------------

local GOLD = { 1, 0.82, 0 }
local CIRCLE = ns.MEDIA .. "Circle"
local GLOW = ns.MEDIA .. "CircleGlow"
-- the markers' colours, from the game's: fill top / bottom, rim, dots (all of them sit on a dark edge)
local EDGE = { 0.07, 0.04, 0.02 }
local LOOK = {
    arrow    = { top = { 1, 0.94, 0.48 }, bottom = { 0.91, 0.64, 0.07 }, rim = { 0.54, 0.36, 0.07 }, dot = { 0.29, 0.15, 0.02 } },
    progress = { top = { 0.48, 0.14, 0.14 }, bottom = { 0.24, 0.04, 0.04 }, rim = { 0.79, 0.65, 0.29 }, dot = { 1, 0.9, 0.75 } },
    done     = { top = { 0.98, 0.84, 0.3 }, bottom = { 0.8, 0.52, 0.05 }, rim = { 0.45, 0.29, 0.06 }, dot = { 0.22, 0.11, 0.02 } },
}
-- a texture shaded from top to bottom (falls back to one colour on clients without gradients)
local function Shade(tex, top, bottom)
    tex:SetVertexColor(1, 1, 1, 1)
    if tex.SetGradient and CreateColor then
        local ok = pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], 1), CreateColor(top[1], top[2], top[3], 1))
        if ok then return end
    end
    tex:SetVertexColor((top[1] + bottom[1]) / 2, (top[2] + bottom[2]) / 2, (top[3] + bottom[3]) / 2, 1)
end
local ITEM = 24               -- the item button's size
local itemsWork = true        -- false where the client has no secure button to use an item with
local LINE = { 0.85, 0.85, 0.85 }
local DONE = { 0.55, 0.55, 0.55 }
local PAD, INDENT, POI = 4, 24, 18

local function Atlas(tex, name)
    if not (C_Texture and C_Texture.GetAtlasInfo and tex.SetAtlas) then return false end
    local info = Ask(C_Texture.GetAtlasInfo, name)
    return type(info) == "table" and pcall(tex.SetAtlas, tex, name) or false
end
local function FontObj(name, fallback) return _G[name] or _G[fallback] or _G.GameFontNormal end
local function Size(fs, size)
    local font, _, flags = fs:GetFont()
    if font then pcall(fs.SetFont, fs, font, size, flags) end
end

local PlaceItems               -- the quest item buttons (further down)
local superTracked            -- the quest the map arrow points at

local panel = CreateFrame("Frame", "SKToolsQuestTracker", UIParent)
panel:SetFrameStrata("LOW")
panel:SetClampedToScreen(true)
panel:SetMovable(true)
panel:Hide()

-- the title bar: "All Objectives", the quest count and the fold button (the PvP switch sits on the first region line)
local bar = CreateFrame("Frame", nil, panel)
bar:SetPoint("TOPLEFT"); bar:SetPoint("TOPRIGHT")
bar:SetHeight(26)
bar.art = bar:CreateTexture(nil, "BACKGROUND")
bar.art:SetAllPoints()
if not Atlas(bar.art, "UI-QuestTracker-Primary-Objective-Header") then
    bar.art:SetColorTexture(0, 0, 0, 0)
end
bar.rule = bar:CreateTexture(nil, "ARTWORK")
bar.rule:SetPoint("BOTTOMLEFT", 2, 0); bar.rule:SetPoint("BOTTOMRIGHT", -2, 0)
bar.rule:SetHeight(1); bar.rule:SetColorTexture(0.72, 0.56, 0.24, 0.9)
bar.title = bar:CreateFontString(nil, "OVERLAY")
bar.title:SetFontObject(FontObj("ObjectiveTrackerHeaderFont", "GameFontNormalMed2"))
bar.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
bar.title:SetPoint("LEFT", 28, -2)         -- on the bar art's shadow; a little lower: room above the capitals
-- how many quests you have, of the most you can: "12/40" next to the title
bar.count = bar:CreateFontString(nil, "OVERLAY")
bar.count:SetFontObject(FontObj("ObjectiveTrackerLineFont", "GameFontHighlight"))

-- the PvP switch: crossed swords, lit while the PvP list shows. It sits at the right of the first
-- region line, before its fold sign; with no region line (nothing listed, or folded to the bar)
-- it keeps that spot on a line of its own. (Placed in Redraw.)
local pvp = CreateFrame("Button", nil, bar)
pvp:SetSize(18, 18)
pvp.icon = pvp:CreateTexture(nil, "ARTWORK"); pvp.icon:SetPoint("TOPLEFT", 2, -2); pvp.icon:SetPoint("BOTTOMRIGHT", -2, 2)
if not Atlas(pvp.icon, "pvptalents-warmode-swords") then
    pvp.icon:SetTexture("Interface\\Icons\\INV_Sword_27")
    pvp.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end
pvp.ring = CreateFrame("Frame", nil, pvp); pvp.ring:SetAllPoints()
pvp:SetScript("OnEnter", function(self)
    if not _G.GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(db and db.pvp and "Back to your quests" or "PvP quests", 1, 1, 1)
    GameTooltip:AddLine("Switches between your quests and your PvP quests.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
pvp:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)

-- fold the whole panel to its bar
local fold = CreateFrame("Button", nil, bar)
fold:SetSize(16, 16)
fold:SetPoint("RIGHT", -4, 0)
-- the count sits at the right, just before the fold button
bar.count:SetPoint("RIGHT", fold, "LEFT", -6, -2)   -- level with the title
bar.count:SetJustifyH("RIGHT")
fold.tex = fold:CreateTexture(nil, "ARTWORK"); fold.tex:SetAllPoints()
fold.text = fold:CreateFontString(nil, "OVERLAY", "GameFontNormal"); fold.text:SetPoint("CENTER")

-- the list, scrolling once taller than the panel may grow
local scroll = CreateFrame("ScrollFrame", nil, panel)
scroll:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -2)
scroll:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -2)
scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", function(self, d)
    local range = self:GetVerticalScrollRange() or 0
    self:SetVerticalScroll(math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - d * 40)))
    if PlaceItems then PlaceItems() end
end)
local list = CreateFrame("Frame", nil, scroll)
list:SetSize(1, 1)
scroll:SetScrollChild(list)

-- pools: region headers and quest blocks, reused from one redraw to the next
local heads, blocks = {}, {}
local Redraw

local function Head(i)
    local h = heads[i]
    if h then return h end
    h = CreateFrame("Button", nil, list)
    h:SetHeight(20)
    h.text = h:CreateFontString(nil, "OVERLAY")
    h.text:SetFontObject(FontObj("ObjectiveTrackerHeaderFont", "GameFontNormal"))
    h.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    h.text:SetPoint("LEFT", 4, 0)
    h.sign = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h.sign:SetPoint("RIGHT", -6, 2)         -- the font sits the minus low: raised to the middle
    h.sign:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    h.rule = h:CreateTexture(nil, "ARTWORK")
    h.rule:SetPoint("BOTTOMLEFT", 2, 0); h.rule:SetPoint("BOTTOMRIGHT", -2, 0)
    h.rule:SetHeight(1); h.rule:SetColorTexture(0.72, 0.56, 0.24, 0.6)
    h:SetScript("OnClick", function(self)
        if not (db and self.region) then return end
        db.collapsed[self.region] = not db.collapsed[self.region] or nil
        Redraw()
    end)
    heads[i] = h
    return h
end

local function Marker(b)
    -- a round marker of our own, drawn like the game's. (The game's own marker button is not used:
    -- made in a fight - a quest updating mid-fight adds one - its setup makes a call the game
    -- blocks for addons in combat: "blocked call: Button:SetPassThroughButtons()".)
    local m = CreateFrame("Button", nil, b)
    -- from our own round pictures (Media\Circle, Media\CircleGlow): a soft glow (the quest the arrow
    -- points at), the rim, the shaded fill on it, then three round dots or a question mark
    m.glow = m:CreateTexture(nil, "BACKGROUND", nil, -2)
    m.glow:SetTexture(GLOW)
    m.glow:SetPoint("CENTER")
    m.glow:SetBlendMode("ADD")
    m.glow:Hide()
    -- a dark edge round the whole marker, as the game's: the rim and the glow stand out against it
    m.edge = m:CreateTexture(nil, "BACKGROUND", nil, -1)
    m.edge:SetTexture(CIRCLE)
    m.edge:SetAllPoints()
    m.edge:SetVertexColor(EDGE[1], EDGE[2], EDGE[3], 1)
    m.ring = m:CreateTexture(nil, "BACKGROUND", nil, 0)
    m.ring:SetTexture(CIRCLE)
    m.ring:SetPoint("TOPLEFT", 1, -1); m.ring:SetPoint("BOTTOMRIGHT", -1, 1)
    m.bg = m:CreateTexture(nil, "BACKGROUND", nil, 1)
    m.bg:SetTexture(CIRCLE)
    m.bg:SetPoint("TOPLEFT", 2, -2); m.bg:SetPoint("BOTTOMRIGHT", -2, 2)
    m.dots = {}
    for k = 1, 3 do
        local d = m:CreateTexture(nil, "ARTWORK")
        d:SetTexture(CIRCLE)
        d:SetSize(3, 3)
        d:SetPoint("CENTER", m, "CENTER", (k - 2) * 4, 0)
        m.dots[k] = d
    end
    m.glyph = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    m.glyph:SetPoint("CENTER", 0.5, 0)
    m.glyph:SetText("?")
    b.poiKind = "own"
    return m
end

local function Block(i)
    local b = blocks[i]
    if b then return b end
    b = CreateFrame("Frame", nil, list)
    b.poi = Marker(b)
    b.poi:SetSize(POI, POI)
    b.poi:SetPoint("TOPLEFT", 2, -1)
    b.poi:SetScript("OnClick", function()
        -- the map's arrow points at this quest
        if b.questID and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            pcall(C_SuperTrack.SetSuperTrackedQuestID, b.questID)
        end
    end)
    b.titleBtn = CreateFrame("Button", nil, b)
    b.titleBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.title = b.titleBtn:CreateFontString(nil, "OVERLAY")
    b.title:SetFontObject(FontObj("ObjectiveTrackerLineFont", "GameFontNormal"))
    b.title:SetPoint("TOPLEFT")
    b.title:SetJustifyH("LEFT")
    b.titleBtn:SetScript("OnClick", function()
        if not b.questID then return end
        Q = _G.C_QuestLog
        if IsShiftKeyDown and IsShiftKeyDown() then
            -- stop tracking it
            if Q and Q.RemoveQuestWatch then pcall(Q.RemoveQuestWatch, b.questID)
            elseif _G.RemoveQuestWatch and b.index then pcall(RemoveQuestWatch, b.index) end
            Redraw()
            return
        end
        -- open it in the quest log
        if _G.QuestMapFrame_OpenToQuestDetails then
            pcall(QuestMapFrame_OpenToQuestDetails, b.questID)
        elseif _G.QuestLogFrame and b.index then
            pcall(ShowUIPanel, QuestLogFrame)
            if _G.QuestLog_SetSelection then pcall(QuestLog_SetSelection, b.index) end
            if _G.QuestLog_Update then pcall(QuestLog_Update) end
        end
    end)
    b.lines = {}
    blocks[i] = b
    return b
end

local function Line(b, k)
    local l = b.lines[k]
    if l then return l end
    l = b:CreateFontString(nil, "OVERLAY")
    l:SetFontObject(FontObj("ObjectiveTrackerLineFont", "GameFontHighlight"))
    l:SetJustifyH("LEFT")
    b.lines[k] = l
    return l
end

-- the quest's title as the game's tracker writes it: [level] title, with its kind
local function TitleText(q)
    local lv = q.level and q.level > 0 and tostring(q.level) or "?"
    if q.tagID == TAG.GROUP or q.group then lv = lv .. "+" end
    local kind = (q.tagID == TAG.DUNGEON and " (Dungeon)") or (q.tagID == TAG.RAID and " (Raid)")
        or (q.tagID == TAG.GROUP and " (Elite)") or (IsPvP(q) and " (PvP)") or ""
    if kind ~= "" and q.title:find(kind, 1, true) then kind = "" end
    return ("[%s] %s%s"):format(lv, q.title, kind)
end
local function TitleColor(q)
    if _G.GetQuestDifficultyColor then
        local c = Ask(GetQuestDifficultyColor, q.level or 0)
        if type(c) == "table" and c.r then return c.r, c.g, c.b end
    end
    return GOLD[1], GOLD[2], GOLD[3]
end

-- the objective lines: the game's own words, or for a quest with none, its summary
local function Objectives(q)
    local out = {}
    local objs = Q and Q.GetQuestObjectives and Ask(Q.GetQuestObjectives, q.questID)
    if type(objs) == "table" then
        for _, o in ipairs(objs) do
            local t = Plain(o.text)
            if t and t ~= "" then out[#out + 1] = { text = "- " .. t, done = Plain(o.finished) == true } end
        end
    end
    -- done, with objectives: one line saying so, in the game's words (as its tracker does)
    if q.complete and #out > 0 then
        return { { text = Plain(_G.QUEST_WATCH_QUEST_READY) or "Ready for turn-in", done = false, plain = true } }
    end
    if #out == 0 then
        local summary
        if q.complete and _G.GetQuestLogCompletionText and q.index then summary = Ask(GetQuestLogCompletionText, q.index) end
        if (not summary or summary == "") and #out == 0 and _G.GetQuestLogQuestText and q.index and q.complete then
            local _, objText = Ask(GetQuestLogQuestText, q.index); summary = objText
        end
        if summary and summary ~= "" then
            out[1] = { text = summary, done = false, plain = true }
        else
            out[1] = { text = q.complete and (Plain(_G.QUEST_WATCH_QUEST_READY) or "Ready for turn-in") or "", done = false, plain = true }
        end
    end
    return out
end

-- Spoken's Play button, as Spoken puts it on the game's tracker (see the Spoken note in Redraw)
local function SpokenButton(b, q, underItem)
    local S, VO = _G.Spoken, _G.VoiceOver
    local QO = type(VO) == "table" and VO.QuestOverlayUI
    local want = db.spoken ~= false and type(S) == "table" and S.DressBoxButton and type(QO) == "table"
        and QO.BindPlayButton and QO.ShowsTrackerButton
    if want then
        local ok, shows = pcall(QO.ShowsTrackerButton, QO, q.questID)
        want = ok and shows
    end
    if not want then
        if b.spoken then b.spoken:Hide() end
        return false
    end
    if not b.spoken then
        local btn = CreateFrame("Button", nil, b)
        btn:SetSize(14, 14)
        btn:SetHitRectInsets(1, 1, 1, 1)
        local ok = pcall(S.DressBoxButton, S, btn)
        if ok and btn.SetBox then ok = pcall(btn.SetBox, btn, "QuestLog-icon-ticksquare", 14, 14) end
        if not ok then btn:Hide(); b.spokenFailed = true; return false end
        btn.setPlayState = QO.FollowQueue
        local back = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
        back:SetPoint("TOPLEFT", 1, -1); back:SetPoint("BOTTOMRIGHT", -1, 1)
        back:SetColorTexture(0, 0, 0, 0.6)
        btn:SetFrameLevel(b:GetFrameLevel() + 3)
        b.spoken = btn
    end
    local btn = b.spoken
    -- at the quest's top right; under its item button when it has one (as Spoken does on the game's)
    btn:ClearAllPoints()
    btn:SetPoint("TOPRIGHT", b, "TOPRIGHT", underItem and -((ITEM - 14) / 2) or 0, underItem and -(ITEM + 2) or 0)
    if btn.questID ~= q.questID then btn.soundData = nil end
    btn.questID = q.questID
    pcall(QO.BindPlayButton, QO, btn, q.questID, q.title, "the SKTools tracker's Play button")
    btn:Show()
    pcall(QO.SetPlayButtonState, QO, btn)
    return true
end

local function Place()
    if not db or panel.moving then return end
    panel:ClearAllPoints()
    panel:SetPoint(db.point or "TOPRIGHT", UIParent, db.point or "TOPRIGHT", db.x or 0, db.y or 0)
end

Redraw = function()
    if not db then return end
    Q = _G.C_QuestLog
    local w = db.width or 260
    local fs = db.fontSize or 13
    panel:SetWidth(w)
    Place()
    bar.title:SetText(db.pvp and "PvP Objectives" or "All Objectives")
    Size(bar.title, fs + 2)
    -- the count: every quest in the log (tracked or not, PvP too), against the game's limit
    do
        local _, n = Ask(Q and Q.GetNumQuestLogEntries)
        if type(n) ~= "number" then n = #ReadLog() end
        local most = (Q and Q.GetMaxNumQuestsCanAccept and Ask(Q.GetMaxNumQuestsCanAccept)) or Plain(_G.MAX_QUESTS) or 40
        bar.count:SetText(("%d/%d"):format(n, most))
        Size(bar.count, fs)
        local full = n >= most
        bar.count:SetTextColor(full and 1 or 0.85, full and 0.3 or 0.85, full and 0.3 or 0.85)
        state.count = ("%d/%d"):format(n, most)
    end
    pvp.icon:SetDesaturated(not db.pvp)
    if not fold.atlasDone then
        fold.atlasDone = true
        fold.hasAtlas = Atlas(fold.tex, "UI-QuestTrackerButton-Secondary-Collapse")
    end
    if fold.hasAtlas then
        Atlas(fold.tex, db.minimized and "UI-QuestTrackerButton-Secondary-Expand" or "UI-QuestTrackerButton-Secondary-Collapse")
        fold.text:SetText("")
    else
        fold.text:SetText(db.minimized and "+" or "-")
    end

    local y, nh, nb, quests = 0, 0, 0, 0
    superTracked = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and Ask(C_SuperTrack.GetSuperTrackedQuestID) or nil
    local groups = db.minimized and {} or Groups()
    local inner = w - 2 * PAD
    for _, g in ipairs(groups) do
        nh = nh + 1
        local h = Head(nh)
        h.region = g.name
        h:ClearAllPoints(); h:SetPoint("TOPLEFT", list, "TOPLEFT", PAD, -y); h:SetWidth(inner)
        h.text:SetText(g.name); Size(h.text, fs + 1)
        local folded = db.collapsed[g.name] == true
        h.sign:SetText(folded and "+" or "-")
        h:Show()
        y = y + 22
        if g.empty and not folded then
            nb = nb + 1
            local b = Block(nb)
            b.questID, b.index = nil, nil
            b.poi:Hide(); if b.spoken then b.spoken:Hide() end
            b.titleBtn:ClearAllPoints(); b.titleBtn:SetPoint("TOPLEFT", INDENT, 0); b.titleBtn:SetSize(inner - INDENT, fs + 4)
            b.title:SetText(g.empty); b.title:SetTextColor(DONE[1], DONE[2], DONE[3]); Size(b.title, fs)
            for _, l in ipairs(b.lines) do l:Hide() end
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", list, "TOPLEFT", PAD, -y); b:SetSize(inner, fs + 6)
            b:Show()
            y = y + fs + 8
        end
        for _, q in ipairs(folded and {} or g.quests) do
            nb = nb + 1; quests = quests + 1
            local b = Block(nb)
            b.questID, b.index = q.questID, q.index
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", list, "TOPLEFT", PAD, -y); b:SetWidth(inner)
            b.item = (db.items ~= false and itemsWork) and q.item or nil
            local hasPlay = SpokenButton(b, q, b.item ~= nil)
            local right = (b.item and (ITEM + 4)) or (hasPlay and 18) or 2
            local textW = inner - INDENT - right
            -- marker: three dots in progress, a question mark once done, as the game's; the quest the map
            -- arrow points at is lit yellow, with a glow round it and a wider rim (told apart by shape too)
            b.poi:Show()
            local arrow = superTracked ~= nil and superTracked == q.questID
            local look = (arrow and not q.complete) and LOOK.arrow or (q.complete and LOOK.done or LOOK.progress)
            local m = b.poi
            m.glow:SetShown(arrow)
            m.glow:SetSize(POI * 2, POI * 2)
            m.glow:SetVertexColor(1, 0.85, 0.3, 0.85)
            m.ring:SetVertexColor(look.rim[1], look.rim[2], look.rim[3], 1)
            m.bg:ClearAllPoints()
            local rim = arrow and 3 or 2.5
            m.bg:SetPoint("TOPLEFT", rim, -rim); m.bg:SetPoint("BOTTOMRIGHT", -rim, rim)
            Shade(m.bg, look.top, look.bottom)
            for _, d in ipairs(m.dots) do
                d:SetShown(not q.complete)
                d:SetVertexColor(look.dot[1], look.dot[2], look.dot[3], 1)
            end
            m.glyph:SetShown(q.complete)
            m.glyph:SetTextColor(look.dot[1], look.dot[2], look.dot[3])
            Size(m.glyph, math.floor(POI * 0.75))
            b.poi.arrow = arrow
            -- title
            b.title:SetText(TitleText(q))
            b.title:SetTextColor(TitleColor(q))
            Size(b.title, fs)
            b.title:SetWidth(textW)
            local th = math.max(fs + 2, b.title:GetStringHeight() or 0)
            b.titleBtn:ClearAllPoints(); b.titleBtn:SetPoint("TOPLEFT", INDENT, 0); b.titleBtn:SetSize(textW, th)
            -- objectives
            local by = th + 2
            local objs = Objectives(q)
            for k, o in ipairs(objs) do
                local l = Line(b, k)
                l:ClearAllPoints(); l:SetPoint("TOPLEFT", b, "TOPLEFT", INDENT + (o.plain and 0 or 4), -by)
                l:SetWidth(textW - 4)
                l:SetText(o.text)
                local c = o.done and DONE or LINE
                l:SetTextColor(c[1], c[2], c[3])
                Size(l, fs - 1)
                l:Show()
                by = by + math.max(fs, l:GetStringHeight() or 0) + 1
            end
            for k = #objs + 1, #b.lines do b.lines[k]:Hide() end
            if b.item then by = math.max(by, ITEM + (hasPlay and 18 or 0)) end
            b:SetHeight(by)
            b:Show()
            y = y + by + 6
        end
    end
    for i = nh + 1, #heads do heads[i]:Hide() end
    -- the PvP switch: always on the line below the bar, at the right - on the first region line,
    -- or on a line of its own there when none is listed (nothing to list, or folded)
    pvp:ClearAllPoints()
    if nh >= 1 then
        pvp:SetParent(heads[1]); pvp:SetFrameLevel(heads[1]:GetFrameLevel() + 2)
        pvp:SetPoint("RIGHT", heads[1], "RIGHT", -22, 0)
    else
        pvp:SetParent(panel); pvp:SetFrameLevel(bar:GetFrameLevel() + 2)
        pvp:SetPoint("RIGHT", panel, "TOPRIGHT", -(PAD + 22), -(26 + 2 + 10))
    end
    pvp:Show()
    for i = nb + 1, #blocks do blocks[i]:Hide(); blocks[i].questID = nil; if blocks[i].spoken then blocks[i].spoken:Hide() end end

    list:SetSize(w, math.max(1, y))
    local shown = math.min(y, db.maxHeight or 520)
    scroll:SetHeight(math.max(1, shown))
    -- with no region line, room for the PvP switch's own line
    panel:SetHeight(26 + 2 + ((nh == 0) and math.max(shown, 20) or shown))
    local range = math.max(0, y - shown)
    if (scroll:GetVerticalScroll() or 0) > range then scroll:SetVerticalScroll(range) end
    state.quests, state.regions = quests, nh
    PlaceItems()                                      -- the item buttons follow (out of combat)
end

----------------------------------------------------------------------
-- The game's own tracker steps aside while ours is on, and comes back when ours is off. The game
-- shows it again whenever it updates (a quest accepted, say) and puts it back in its place, so it
-- is not moved anywhere: each time it shows, it is hidden again. Hiding it is not allowed in a
-- fight, so then it is only made see-through, and hidden once the fight is over.
----------------------------------------------------------------------

local wantHidden = false
local hiddenByUs = {}         -- [frame] = true: we hid it (so we show it again when ours goes off)
local hookedShow = {}
local pendingBlizzard

local function GameTrackers()
    local out = {}
    for _, name in ipairs({ "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" }) do
        local f = _G[name]
        if type(f) == "table" and f.Hide and f.HookScript then out[#out + 1] = f end
    end
    return out
end
local function Fighting() return InCombatLockdown and InCombatLockdown() end

local function Apply(f)
    if wantHidden then
        pcall(f.SetAlpha, f, 0)                        -- allowed even in a fight
        if Fighting() then pendingBlizzard = true; return end
        if f:IsShown() then hiddenByUs[f] = true; pcall(f.Hide, f) end
    else
        pcall(f.SetAlpha, f, 1)
        if Fighting() then pendingBlizzard = true; return end
        if hiddenByUs[f] then hiddenByUs[f] = nil; pcall(f.Show, f) end
    end
end

local function SetGameTracker(hide)
    wantHidden = hide and true or false
    pendingBlizzard = nil
    for _, f in ipairs(GameTrackers()) do
        if not hookedShow[f] then
            hookedShow[f] = true
            -- whenever the game shows it again while ours is on: straight back out of sight
            f:HookScript("OnShow", function(self) if wantHidden then Apply(self) end end)
        end
        Apply(f)
    end
    state.blizzard = (pendingBlizzard and "waiting for the fight to end; " or "")
        .. (hide and "the game's tracker hidden" or "the game's tracker shown")
end

----------------------------------------------------------------------
-- Moving it (unlocked from the Quests tab)
----------------------------------------------------------------------

local mover = CreateFrame("Frame", nil, panel)
mover:SetAllPoints()
mover:SetFrameLevel(panel:GetFrameLevel() + 20)
mover:EnableMouse(true)
mover:RegisterForDrag("LeftButton")
mover:Hide()
local function SetupMover()
    if mover.done then return end
    mover.done = true
    ns.W.Fill(mover, 0.1, 0.4, 0.6, 0.25)
    ns.W.Border(mover, 0.4, 0.8, 1, 0.9, 1)
    mover.text = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mover.text:SetPoint("BOTTOM", mover, "TOP", 0, 2)
    mover.text:SetText("Quest tracker")
    mover:SetScript("OnDragStart", function() panel.moving = true; panel:StartMoving() end)
    mover:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
        panel.moving = nil
        -- saved by its top right corner, so it grows down and to the left as the game's does
        local r, t = panel:GetRight(), panel:GetTop()
        local ur, ut = UIParent:GetRight(), UIParent:GetTop()
        if r and ur then
            local k = (panel:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
            db.point, db.x, db.y = "TOPRIGHT", math.floor(r * k - ur + 0.5), math.floor(t * k - ut + 0.5)
            if ns.Snap then db.x, db.y = ns.Snap(db.x, db.y) end
        end
        Redraw()
    end)
    mover:SetScript("OnHide", function()
        if panel.moving then panel:StopMovingOrSizing(); panel.moving = nil end
    end)
end

----------------------------------------------------------------------
-- Quest item buttons. Using an item needs the game's secure button, and in a fight such a button
-- cannot be made, moved, shown or hidden - nor can a frame it sits in, so it is NOT put inside the
-- tracker (which would then be stuck in a fight too). Each is a button of its own on the screen,
-- set over its quest's top right corner, out of combat only. In a fight they stay where they are
-- and keep working (cooldowns run); they catch up when the fight is over.
----------------------------------------------------------------------

local itemButtons, itemByQuest = {}, {}
local itemsPending = false

local function ItemButton(k)
    local btn = itemButtons[k]
    if btn then return btn end
    local ok, made = pcall(CreateFrame, "Button", "SKToolsQuestItem" .. k, UIParent, "SecureActionButtonTemplate")
    if not ok or not made then itemsWork = false; return nil end
    btn = made
    btn:SetSize(ITEM, ITEM)
    btn:SetFrameStrata("MEDIUM")
    pcall(btn.RegisterForClicks, btn, "AnyUp", "AnyDown")
    btn:SetAttribute("type", "item")
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.edge = CreateFrame("Frame", nil, btn); btn.edge:SetAllPoints()
    ns.W.Border(btn.edge, 0, 0, 0, 1, 1)
    local okC, cd = pcall(CreateFrame, "Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cd = okC and cd or nil
    btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    btn.count:SetPoint("BOTTOMRIGHT", -1, 1)
    btn:SetScript("OnEnter", function(self)
        if not (_G.GameTooltip and self.index) then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if GameTooltip.SetQuestLogSpecialItem then pcall(GameTooltip.SetQuestLogSpecialItem, GameTooltip, self.index)
        elseif self.link then pcall(GameTooltip.SetHyperlink, GameTooltip, self.link) end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    btn:Hide()
    itemButtons[k] = btn
    return btn
end

-- cooldown, charges and range: allowed any time (none of it moves the button)
local function ItemLook(btn)
    if not btn.index then return end
    local start, dur, enable = Ask(_G.GetQuestLogSpecialItemCooldown, btn.index)
    if btn.cd then
        if start and dur and dur > 0 and enable ~= 0 then pcall(btn.cd.SetCooldown, btn.cd, start, dur) else pcall(btn.cd.Clear, btn.cd) end
    end
    local inRange = Ask(_G.IsQuestLogSpecialItemInRange, btn.index)
    if inRange == 0 or inRange == false then btn.icon:SetVertexColor(1, 0.3, 0.3) else btn.icon:SetVertexColor(1, 1, 1) end
end

-- put a button over each quest with an item (out of combat only)
PlaceItems = function()
    if InCombatLockdown and InCombatLockdown() then itemsPending = true; return end
    itemsPending = false
    wipe(itemByQuest)
    local used = 0
    local showing = panel:IsShown() and db and db.items ~= false and not db.minimized
    local top, bottom = scroll:GetTop(), scroll:GetBottom()
    if showing then
        for _, b in ipairs(blocks) do
            if b:IsShown() and b.item and b.questID then
                -- only while its quest is in the visible part of the list
                local bt = b:GetTop()
                local visible = true
                if bt and top and bottom and top > bottom then visible = bt <= top + 1 and (bt - ITEM) >= bottom - 1 end
                if visible then
                    local btn = ItemButton(used + 1)
                    if not btn then break end
                    used = used + 1
                    btn.index, btn.link, btn.questID = b.index, b.item.link, b.questID
                    btn:SetAttribute("item", b.item.id and ("item:" .. b.item.id) or b.item.link)
                    btn.icon:SetTexture(b.item.icon)
                    btn.count:SetText((b.item.charges and b.item.charges > 1) and tostring(b.item.charges) or "")
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", b:GetRight() or 0, bt or 0)
                    btn:SetFrameLevel(panel:GetFrameLevel() + 10)
                    btn:Show()
                    ItemLook(btn)
                    itemByQuest[b.questID] = btn
                end
            end
        end
    end
    for k = used + 1, #itemButtons do
        local btn = itemButtons[k]
        btn:Hide(); btn.index, btn.link, btn.questID = nil, nil, nil
        btn:SetAttribute("item", nil)
    end
end

----------------------------------------------------------------------
-- On / off, and redrawing when the log changes
----------------------------------------------------------------------

local function On() return db and ns.FeatureOn(db) end

local function Refresh()
    if not db then return end
    if not On() then
        panel:Hide(); mover:Hide()
        PlaceItems()
        SetGameTracker(false)
        state.why = ns.BerryMode() and "off (Berry Mode)" or "off"
        return
    end
    SetGameTracker(true)
    Redraw()
    panel:Show()
    PlaceItems()
    if db.unlocked then SetupMover() end
    mover:SetShown(db.unlocked == true)
    state.why = "on"
end

pvp:SetScript("OnClick", function() if db then db.pvp = not db.pvp; Redraw(); PlaceItems() end end)
fold:SetScript("OnClick", function() if db then db.minimized = not db.minimized; Redraw(); PlaceItems() end end)

local driver = CreateFrame("Frame")
local pending = false
-- the items' range colour, a few times a second while any item button shows
local rangeAcc = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    rangeAcc = rangeAcc + elapsed
    if rangeAcc < 0.3 then return end
    rangeAcc = 0
    for _, btn in ipairs(itemButtons) do if btn:IsShown() then ItemLook(btn) end end
end)
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(0.1, function() pending = false; Refresh() end)
end
driver:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED",
                     "QUEST_REMOVED", "QUEST_TURNED_IN", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED",
                     "SUPER_TRACKING_CHANGED", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED" }) do
    pcall(driver.RegisterEvent, driver, e)
end
pcall(driver.RegisterUnitEvent or driver.RegisterEvent, driver, "UNIT_QUEST_LOG_CHANGED", "player")
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- kept with the other widgets' settings, in the saved table (ns.InitDB()'s own table is made
        -- afresh each session: settings put on it were lost at a reload)
        local root = ns.InitDB().range
        root.quests = root.quests or {}
        DeepFill(root.quests, ns.QUEST_DEFAULTS)
        db = root.quests
        Refresh()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" and pendingBlizzard then SetGameTracker(wantHidden) end
    if event == "PLAYER_REGEN_ENABLED" and itemsPending then PlaceItems() end
    if event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
        for _, btn in ipairs(itemButtons) do if btn:IsShown() then ItemLook(btn) end end
        return
    end
    Soon()
end)

ns.QuestTracker = {
    Settings = function() return db end,
    Refresh = function() Refresh() end,
    On = function() return On() end,
    Panel = function() return panel end,
    Blocks = function() return blocks end,
    Heads = function() return heads end,
    PvPButton = function() return pvp end,
    CountText = function() return bar.count:GetText() end,
    CountFont = function() return bar.count end,
    ItemButtons = function() return itemButtons end,
    FoldButton = function() return fold end,
    ResetPosition = function()
        if not db then return end
        db.point, db.x, db.y = ns.QUEST_DEFAULTS.point, ns.QUEST_DEFAULTS.x, ns.QUEST_DEFAULTS.y
        Refresh()
    end,
    Debug = function(print)
        print(("quest tracker: %s; view %s; %d quests in %d groups; %s"):format(state.why, state.view, state.quests, state.regions, state.blizzard))
        local spokenThere = type(_G.Spoken) == "table" and type(_G.VoiceOver) == "table" and _G.VoiceOver.QuestOverlayUI ~= nil
        print(("  Spoken: %s; markers: %s; item buttons: %s%s"):format(spokenThere and "found" or "not found",
            "own", itemsWork and "ok" or "this client has no secure button",
            itemsPending and " (waiting for the fight to end)" or ""))
        for _, q in ipairs(ReadLog()) do
            print(("  %s [%s] %s - region %s, tag %s/%s, %s%s"):format(tostring(q.questID), tostring(q.level), q.title, q.header,
                tostring(q.tagID), tostring(q.tagName), q.watched and "tracked" or "not tracked", q.complete and ", complete" or ""))
        end
    end,
}

-- timed by /skt cpu
ns.Profile("Quest tracker", driver)
