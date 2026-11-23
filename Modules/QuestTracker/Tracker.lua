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
local LINE = { 0.85, 0.85, 0.85 }
local DONE = { 0.55, 0.55, 0.55 }
local PAD, INDENT, POI = 4, 22, 16

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

local panel = CreateFrame("Frame", "SKToolsQuestTracker", UIParent)
panel:SetFrameStrata("LOW")
panel:SetClampedToScreen(true)
panel:SetMovable(true)
panel:Hide()

-- the title bar: PvP switch on the left, "All Objectives", fold button on the right
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
bar.title:SetPoint("LEFT", 28, 0)

-- the PvP switch: crossed swords, lit while the PvP list shows
local pvp = CreateFrame("Button", nil, bar)
pvp:SetSize(18, 18)
pvp:SetPoint("LEFT", 4, 0)
pvp.bg = pvp:CreateTexture(nil, "BACKGROUND"); pvp.bg:SetAllPoints(); pvp.bg:SetColorTexture(0.08, 0.08, 0.08, 0.9)
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
    h.sign:SetPoint("RIGHT", -6, 0)
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
    -- the game's round quest marker where the client has it; else a gold ring of our own
    local ok, m = pcall(CreateFrame, "Button", nil, b, "POIButtonTemplate")
    if ok and m and m.SetQuestID then
        b.poiKind = "game"
        return m
    end
    m = CreateFrame("Button", nil, b)
    m.bg = m:CreateTexture(nil, "BACKGROUND"); m.bg:SetAllPoints()
    m.bg:SetColorTexture(0.35, 0.08, 0.08, 1)
    m.ring = m:CreateTexture(nil, "BORDER"); m.ring:SetPoint("TOPLEFT", -1, 1); m.ring:SetPoint("BOTTOMRIGHT", 1, -1)
    m.ring:SetColorTexture(0.79, 0.65, 0.29, 1)
    if m.bg.SetMask then
        pcall(m.bg.SetMask, m.bg, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
        pcall(m.ring.SetMask, m.ring, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
    end
    m.glyph = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    m.glyph:SetPoint("CENTER", 0, 1)
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
    if #out == 0 or q.complete then
        local summary
        if q.complete and _G.GetQuestLogCompletionText and q.index then summary = Ask(GetQuestLogCompletionText, q.index) end
        if (not summary or summary == "") and #out == 0 and _G.GetQuestLogQuestText and q.index and q.complete then
            local _, objText = Ask(GetQuestLogQuestText, q.index); summary = objText
        end
        if summary and summary ~= "" then
            if #out == 0 then out[1] = { text = summary, done = false, plain = true }
            else out[#out + 1] = { text = summary, done = false, plain = true } end
        elseif #out == 0 then
            out[1] = { text = q.complete and "Ready to hand in" or "", done = false, plain = true }
        end
    end
    return out
end

-- Spoken's Play button, as Spoken puts it on the game's tracker (see the Spoken note in Redraw)
local function SpokenButton(b, q)
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
        btn:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
        b.spoken = btn
    end
    local btn = b.spoken
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
    pvp.bg:SetColorTexture(db.pvp and 0.45 or 0.08, 0.08, 0.08, 0.9)
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
            local hasPlay = SpokenButton(b, q)
            local textW = inner - INDENT - (hasPlay and 18 or 2)
            -- marker: in progress, or done (a question mark, as the game's)
            b.poi:Show()
            if b.poiKind == "game" then
                pcall(b.poi.SetQuestID, b.poi, q.questID)
                if POIButtonUtil and POIButtonUtil.Style and b.poi.SetStyle then
                    pcall(b.poi.SetStyle, b.poi, q.complete and POIButtonUtil.Style.QuestComplete or POIButtonUtil.Style.QuestInProgress)
                end
                if b.poi.UpdateButtonStyle then pcall(b.poi.UpdateButtonStyle, b.poi) end
            else
                b.poi.glyph:SetText(q.complete and "?" or "...")
                b.poi.bg:SetColorTexture(q.complete and 0.35 or 0.35, q.complete and 0.28 or 0.08, 0.08, 1)
            end
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
            b:SetHeight(by)
            b:Show()
            y = y + by + 6
        end
    end
    for i = nh + 1, #heads do heads[i]:Hide() end
    for i = nb + 1, #blocks do blocks[i]:Hide(); blocks[i].questID = nil; if blocks[i].spoken then blocks[i].spoken:Hide() end end

    list:SetSize(w, math.max(1, y))
    local shown = math.min(y, db.maxHeight or 520)
    scroll:SetHeight(math.max(1, shown))
    panel:SetHeight(26 + 2 + shown)
    local range = math.max(0, y - shown)
    if (scroll:GetVerticalScroll() or 0) > range then scroll:SetVerticalScroll(range) end
    state.quests, state.regions = quests, nh
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
-- On / off, and redrawing when the log changes
----------------------------------------------------------------------

local function On() return db and ns.FeatureOn(db) end

local function Refresh()
    if not db then return end
    if not On() then
        panel:Hide(); mover:Hide()
        SetGameTracker(false)
        state.why = ns.BerryMode() and "off (Berry Mode)" or "off"
        return
    end
    SetGameTracker(true)
    Redraw()
    panel:Show()
    if db.unlocked then SetupMover() end
    mover:SetShown(db.unlocked == true)
    state.why = "on"
end

pvp:SetScript("OnClick", function() if db then db.pvp = not db.pvp; Redraw() end end)
fold:SetScript("OnClick", function() if db then db.minimized = not db.minimized; Redraw() end end)

local driver = CreateFrame("Frame")
local pending = false
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(0.1, function() pending = false; Refresh() end)
end
driver:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED",
                     "QUEST_REMOVED", "QUEST_TURNED_IN", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED",
                     "SUPER_TRACKING_CHANGED" }) do
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
    FoldButton = function() return fold end,
    ResetPosition = function()
        if not db then return end
        db.point, db.x, db.y = ns.QUEST_DEFAULTS.point, ns.QUEST_DEFAULTS.x, ns.QUEST_DEFAULTS.y
        Refresh()
    end,
    Debug = function(print)
        print(("quest tracker: %s; view %s; %d quests in %d groups; %s"):format(state.why, state.view, state.quests, state.regions, state.blizzard))
        local spokenThere = type(_G.Spoken) == "table" and type(_G.VoiceOver) == "table" and _G.VoiceOver.QuestOverlayUI ~= nil
        print(("  Spoken: %s; markers: %s"):format(spokenThere and "found" or "not found", tostring(blocks[1] and blocks[1].poiKind or "-")))
        for _, q in ipairs(ReadLog()) do
            print(("  %s [%s] %s - region %s, tag %s/%s, %s%s"):format(tostring(q.questID), tostring(q.level), q.title, q.header,
                tostring(q.tagID), tostring(q.tagName), q.watched and "tracked" or "not tracked", q.complete and ", complete" or ""))
        end
    end,
}

-- timed by /skt cpu
ns.Profile("Quest tracker", driver)
