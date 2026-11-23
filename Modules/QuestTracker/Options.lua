-- SKTools settings tab: Quests (the quest tracker).

local ADDON, ns = ...

local W = ns.W

local function T() return ns.QuestTracker.Settings() or {} end
local function R() ns.QuestTracker.Refresh() end

local function Build(panel)
    local L, R2, CW = 24, 400, 330

    ------------------------------------------------------------------
    local on = panel:Add(W.Check(panel, "",
        function() return ns.FeatureOn(T()) end,
        function(v) ns.SetFeatureOn(T(), v); R() end, 22), L, -5)
    on.tooltip = "Our own quest tracker, in the style of the game's, which steps aside while this is on (and comes "
        .. "back when it is off). Berry Mode keeps its own on / off for this (off until you turn it on)."
    W.Header(panel, "Quest tracker", L + 24, -8, 680 - 24)
    W.Note(panel, "Out in the world: your tracked quests under their regions, A to Z (click a region to fold it). "
        .. "In a dungeon: only that dungeon's quests. The swords icon by the title switches to your PvP quests.",
        L, -32, 700)

    local dungeon = panel:Add(W.Check(panel, "In a dungeon, show its quests even when not tracked",
        function() return T().dungeonAll ~= false end,
        function(v) T().dungeonAll = v and true or false; R() end, CW), L, -76)
    dungeon.tooltip = "Inside a dungeon or raid, every quest of that place in your log shows, tracked or not."
    local spoken = panel:Add(W.Check(panel, "Spoken's Play buttons on the quests",
        function() return T().spoken ~= false end,
        function(v) T().spoken = v and true or false; R() end, CW), L, -100)
    spoken.tooltip = "When Spoken is installed: its Play button at the top right of each quest it has a voice for, "
        .. "as on the game's tracker. Spoken's own setting for its tracker buttons is followed too."

    ------------------------------------------------------------------
    W.Header(panel, "Size", L, -140, 680)
    panel:Add(W.Slider(panel, "Width", 180, 420, 5,
        function() return T().width or 260 end,
        function(v) T().width = v; R() end, W.px, CW), L, -166)
    panel:Add(W.Slider(panel, "Tallest before it scrolls", 150, 900, 10,
        function() return T().maxHeight or 520 end,
        function(v) T().maxHeight = v; R() end, W.px, CW), R2, -166)
    panel:Add(W.Slider(panel, "Text size", 10, 18, 1,
        function() return T().fontSize or 13 end,
        function(v) T().fontSize = v; R() end, W.px, CW), L, -220)

    ------------------------------------------------------------------ position
    local rule = panel:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(0.82, 0.68, 0.30, 0.35)
    rule:SetSize(700, 1)
    rule:SetPoint("TOPLEFT", panel, "TOPLEFT", L, -276)
    local unlock = panel:Add(W.Check(panel, "Unlock the tracker (drag to move)",
        function() return T().unlocked == true end,
        function(v) T().unlocked = v and true or false; R() end, 360), L, -290)
    unlock.tooltip = "Shows a frame over the tracker: drag it to move the tracker. It grows down from its top right "
        .. "corner, as the game's does. Untick when you are done."
    panel:Add(W.Button(panel, "Reset position", 130, function()
        ns.QuestTracker.ResetPosition()
        ns.Print("quest tracker position reset.")
    end), L + 440, -286)
    panel:Add(W.Button(panel, "Debug to log", 120, function()
        ns.Report("quests", function(out) ns.QuestTracker.Debug(out) end, true)
    end), L + 580, -286)
end

ns.RegisterTab({ key = "quests", title = "Quests", order = 2.9, Build = Build })
