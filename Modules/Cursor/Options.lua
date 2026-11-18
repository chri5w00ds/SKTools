-- SKTools settings tab: Cursor (a glow that follows it in combat; Alt for tooltips at the cursor).

local ADDON, ns = ...
local W = ns.W

local function C() return ns.Cursor.Settings() or ns.CURSOR_DEFAULTS end

local function Build(panel)
    local L, R, CW = 24, 400, 330
    local function Refresh() ns.Cursor.Refresh() end

    W.Header(panel, "Combat glow", L, -8, CW)
    local on = panel:Add(W.Check(panel, "A soft glow behind the cursor",
        function() return ns.FeatureOn(C().glow) end,
        function(v) ns.SetFeatureOn(C().glow, v); Refresh() end, CW), L, -32)
    on.tooltip = "Easier to find your cursor in a busy fight. Berry Mode keeps its own on / off for this "
        .. "(off until you turn it on)."
    panel:Add(W.Check(panel, "Only in combat",
        function() return C().glow.combatOnly ~= false end,
        function(v) C().glow.combatOnly = v; Refresh() end, CW), L, -54)
    panel:Add(W.Slider(panel, "Size", 32, 160, 4,
        function() return C().glow.size or 72 end,
        function(v) C().glow.size = v; Refresh() end, nil, 300), L, -90)
    panel:Add(W.Slider(panel, "Brightness", 10, 100, 5,
        function() return math.floor((C().glow.alpha or 0.8) * 100 + 0.5) end,
        function(v) C().glow.alpha = v / 100; Refresh() end, W.percentInt, 300), L, -136)
    local sw = panel:Add(W.Swatch(panel, "Colour",
        function() local c = C().glow.color; return c.r, c.g, c.b end,
        function(r, g, b) C().glow.color = { r = r, g = g, b = b }; Refresh() end, 40, 18), L, -184)
    panel:Add(W.Button(panel, "Default colour", 120, function()
        C().glow.color = { r = 1, g = 0.55, b = 0.18 }; Refresh(); panel:SyncAll()
    end), L + 120, -182)
    panel:Add(W.Slider(panel, "Dark halo (for bright ground)", 0, 100, 5,
        function() return math.floor((C().glow.shadow or 0.7) * 100 + 0.5) end,
        function(v) C().glow.shadow = v / 100; Refresh() end, function(v) return v <= 0 and "none" or ("%d%%"):format(v) end, 300), L, -222)
    panel:Add(W.Check(panel, "Pulse gently",
        function() return C().glow.pulse == true end,
        function(v) C().glow.pulse = v; Refresh() end, CW), L, -268)
    W.Note(panel, "While this tab is open the glow shows, so you can see your changes. An addon can't change "
        .. "the cursor's own picture: the glow is drawn behind it, a dark halo under a bright glow so it shows "
        .. "on dark and bright ground alike.", L, -296, CW)

    W.Header(panel, "Alt tooltips", R, -8, CW)
    local alt = panel:Add(W.Check(panel, "Hold Alt: tooltips at the cursor",
        function() return ns.FeatureOn(C().altTip) end,
        function(v) ns.SetFeatureOn(C().altTip, v) end, CW), R, -32)
    alt.tooltip = "Berry Mode keeps its own on / off for this (off until you turn it on)."
    W.Note(panel, "Hold Alt as you point at something and its tooltip shows beside your cursor, following it, "
        .. "instead of in its usual corner. Pressing or letting go of Alt while pointing at someone moves "
        .. "their tooltip straight away.", R, -58, CW)
end

ns.RegisterTab({
    key = "cursor", title = "Cursor", order = 2.8, Build = Build,
    OnShow = function() ns.Cursor.Preview(true) end,
    OnHide = function() ns.Cursor.Preview(false) end,
})
