--[[-------------------------------------------------------------------------
  SKTools - quest levels in NPC dialogs

  "[12] " before each quest's name, the number in the tracker's colours, where an NPC offers or takes quests: the
  gossip list, the greeting list of an NPC with several quests, and the
  title of the quest's own page (carried over from the list it was clicked
  in). The text stays the game's; only the level goes in front. Quests tab;
  on to start, off in Berry Mode until turned on.
---------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

local DEFAULTS = { enabled = true, berryEnabled = false }

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function Ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if ok then return Plain(a) end
end

local db
local function On() return db and ns.FeatureOn(db) end

-- levels seen in the lists, for the quest's own page: by quest ID and by title
local seenByID, seenByTitle = {}, {}
local function Seen(id, title, level)
    if type(level) ~= "number" or level <= 0 then return end
    if id then seenByID[id] = level end
    if type(title) == "string" and title ~= "" then seenByTitle[title] = level end
end

-- the level, in the tracker's colours: how hard the quest is for you (red, orange, yellow, green, grey)
local function Level(level)
    local c = _G.GetQuestDifficultyColor and Ask(GetQuestDifficultyColor, level)
    if type(c) == "table" and c.r then
        return ("|cff%02x%02x%02x[%d]|r"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5), level)
    end
    return ("[%d]"):format(level)
end

local function Tag(text, level)
    if type(text) ~= "string" or type(level) ~= "number" or level <= 0 then return nil end
    if text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):find("^%[%d+%] ") then return nil end   -- tagged already
    -- keep the game's own colour for the name (ignored / trivial quests come coloured)
    local pre, rest = text:match("^(|c%x%x%x%x%x%x%x%x)(.*)$")
    if pre then return Level(level) .. " " .. pre .. rest end
    return Level(level) .. " " .. text
end

local function Retext(button, level)
    if not (button and button.GetText and button.SetText) then return end
    local t = Tag(button:GetText(), level)
    if not t then return end
    button:SetText(t)
    if button.Resize then pcall(button.Resize, button) end
end

----------------------------------------------------------------------
-- The gossip list (modern gossip frame: each quest button is Setup with its info)
----------------------------------------------------------------------

local function AfterSetup(self, info)
    if type(info) ~= "table" then return end
    local level = Plain(info.questLevel)
    Seen(Plain(info.questID), Plain(info.title), level)
    if On() then Retext(self, level) end
end
local hookedMixins = false
local function HookGossip()
    if hookedMixins then return end
    for _, name in ipairs({ "GossipSharedAvailableQuestButtonMixin", "GossipSharedActiveQuestButtonMixin" }) do
        local m = _G[name]
        if type(m) == "table" and type(m.Setup) == "function" then
            hooksecurefunc(m, "Setup", AfterSetup)
            hookedMixins = true
        end
    end
end

-- buttons made before the hook (or from an older frame): tagged from the open list on GOSSIP_SHOW
local function TagOpenGossip()
    local gf = _G.GossipFrame
    local box = gf and gf.GreetingPanel and gf.GreetingPanel.ScrollBox
    if not (box and box.ForEachFrame) then return end
    pcall(box.ForEachFrame, box, function(button, data)
        local info = type(data) == "table" and data.info
        if type(info) == "table" and info.questLevel and not hookedMixins then AfterSetup(button, info) end
    end)
end

-- the levels from the gossip info itself, for the quest page (whatever frame shows the list)
local function LearnGossip()
    local G = _G.C_GossipInfo
    for _, fn in ipairs({ G and G.GetAvailableQuests, G and G.GetActiveQuests }) do
        local list = Ask(fn)
        if type(list) == "table" then
            for _, q in ipairs(list) do Seen(Plain(q.questID), Plain(q.title), Plain(q.questLevel)) end
        end
    end
end

----------------------------------------------------------------------
-- The greeting list (an NPC with several quests and no gossip)
----------------------------------------------------------------------

local function GreetingButtons()
    local panel = _G.QuestFrameGreetingPanel
    local out = {}
    if panel and panel.titleButtonPool and panel.titleButtonPool.EnumerateActive then
        for b in panel.titleButtonPool:EnumerateActive() do out[#out + 1] = b end
    else
        for i = 1, 32 do
            local b = _G["QuestTitleButton" .. i]
            if not b then break end
            if b:IsShown() then out[#out + 1] = b end
        end
    end
    return out
end
local function TagGreeting()
    for _, b in ipairs(GreetingButtons()) do
        local i = b.GetID and b:GetID()
        local level, title
        if b.isActive == 1 or b.isActive == true then
            level, title = Ask(_G.GetActiveLevel, i), Ask(_G.GetActiveTitle, i)
        else
            level, title = Ask(_G.GetAvailableLevel, i), Ask(_G.GetAvailableTitle, i)
        end
        Seen(nil, title, level)
        if On() then Retext(b, level) end
    end
end

----------------------------------------------------------------------
-- The quest's own page: its title, with the level from the list it came from
----------------------------------------------------------------------

local function TagDetail()
    if not On() then return end
    local qi = _G.QuestInfoFrame
    if qi and qi.questLog then return end                   -- the quest log's own pages: left alone
    local header = _G.QuestInfoTitleHeader
    if not (header and header.GetText) then return end
    local id = Ask(_G.GetQuestID)
    local title = Ask(_G.GetTitleText)
    local level = (id and seenByID[id]) or (title and seenByTitle[title])
    local t = Tag(header:GetText(), level)
    if t then header:SetText(t) end
end

----------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
    pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitDB().range
        root.questLevels = root.questLevels or {}
        for k, v in pairs(DEFAULTS) do if root.questLevels[k] == nil then root.questLevels[k] = v end end
        db = root.questLevels
        HookGossip()
        if _G.QuestInfo_Display and hooksecurefunc then hooksecurefunc("QuestInfo_Display", TagDetail) end
        local gp = _G.QuestFrameGreetingPanel
        if gp and gp.HookScript then gp:HookScript("OnShow", TagGreeting) end
        return
    end
    if event == "GOSSIP_SHOW" then
        LearnGossip()
        HookGossip()
        if On() then C_Timer.After(0, TagOpenGossip) end
    elseif event == "QUEST_GREETING" then
        C_Timer.After(0, TagGreeting)
    else
        C_Timer.After(0, TagDetail)
    end
end)

ns.QuestLevels = {
    Settings = function() return db end,
    Tag = Tag,
    -- for the tests
    Retag = function() TagOpenGossip(); TagGreeting(); TagDetail() end,
}
