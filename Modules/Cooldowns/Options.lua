-- SKTools settings tab: Cooldowns (our own panes for Blizzard's Cooldown Manager).

local ADDON, ns = ...

local W = ns.W

local function DB() return (ns.Cooldowns and ns.Cooldowns.Settings()) or ns.CDM_DEFAULTS end
local function Refresh() if ns.Cooldowns then ns.Cooldowns.Refresh() end end

-- Blizzard's Cooldown Manager settings, where what is tracked is chosen
local function OpenBlizzardSettings()
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_CooldownViewer") end
    local s = _G.CooldownViewerSettings
    if s then
        if s.TogglePanel and pcall(s.TogglePanel, s) then return end
        if s.ShowUIPanel and pcall(s.ShowUIPanel, s) then return end
        if _G.ShowUIPanel and pcall(ShowUIPanel, s) then return end
        if pcall(s.Show, s) then return end
    end
    ns.Print("couldn't open Blizzard's Cooldown Manager settings here: try Edit Mode, or the /cdm command.")
end
ns.OpenCooldownManager = OpenBlizzardSettings

-- a pane's own on / off: a box left of its title
local function PaneHeader(panel, key, title, x, y, width)
    local c = panel:Add(W.Check(panel, "",
        function() local t = DB()[key]; return not (type(t) == "table" and t.show == false) end,
        function(v) DB()[key] = DB()[key] or {}; DB()[key].show = v and true or false; Refresh() end, 22), x, y + 3)
    c.tooltip = "Show this pane."
    c.paneKey = key
    W.Header(panel, title, x + 24, y, width - 24)
    return c
end

-- the cooldown panes page
local function BuildPanes(panel)
    local L, R, CW = 24, 400, 330

    ------------------------------------------------------------------ general
    W.Header(panel, "Cooldown panes", L, -8, CW)
    local on = panel:Add(W.Check(panel, "Show our cooldown panes",
        function() return ns.FeatureOn(DB()) end,
        function(v) ns.SetFeatureOn(DB(), v); Refresh() end, CW), L, -32)
    on.tooltip = "With our resource display. Berry Mode keeps its own on / off for this (off until you turn it on)."
    local hb = panel:Add(W.Check(panel, "Make Blizzard's Cooldown Manager invisible",
        function() return DB().hideBlizzard ~= false end,
        function(v) DB().hideBlizzard = v; Refresh() end, CW), L, -54)
    hb.tooltip = "It keeps running unseen: our panes read what it tracks."
    local rp = panel:Add(W.Check(panel, "Replace Blizzard's personal resource display",
        function() return DB().replacePRD ~= false end,
        function(v) DB().replacePRD = v; Refresh() end, CW), L, -76)
    rp.tooltip = "Turns Blizzard's health and power bars under your character off while ours show (changed out of combat)."
    local un = panel:Add(W.Check(panel, "Unlock the panes (move them)",
        function() return DB().unlocked == true end,
        function(v) DB().unlocked = v and true or false; Refresh() end, CW), L, -98)
    un.tooltip = "Shows every pane, with examples where nothing is tracked yet, and a sample cast bar. Drag a pane to move it."
    local sn = panel:Add(W.Check(panel, "Snap to grid",
        function() return DB().snap ~= false end,
        function(v) DB().snap = v; Refresh() end, 150), L, -120)
    sn.tooltip = "A moved pane snaps to the grid shown while unlocked (the buff widgets' panes too)."
    panel:Add(W.Slider(panel, "Grid size", 2, 32, 1,
        function() return DB().grid or 8 end,
        function(v) DB().grid = v; Refresh() end, W.px, 160), L + 170, -116)
    panel:Add(W.Button(panel, "Reset positions", 130, function()
        if ns.Cooldowns then ns.Cooldowns.ResetPositions() end
        ns.Print("cooldown pane positions reset.")
    end), L, -150)
    panel:Add(W.Button(panel, "Debug to chat", 120, function()
        if ns.Cooldowns then ns.Cooldowns.Debug(function(m) print(m) end) end
    end), L + 140, -150)

    ------------------------------------------------------------------ sizes in grid boxes
    -- every size is set in whole grid boxes (shown with its size in pixels); the count per row is a plain number
    local function Grid() return math.max(2, DB().grid or 8) end
    local function BoxFmt(v) return ("%d (%d px)"):format(v, v * Grid()) end
    local function Count(v) return tostring(v) end
    local function Sized(key, field, label, lo, hi, x, y, width)
        local isCount = (field == "cap")
        return panel:Add(W.Slider(panel, label, lo, hi, 1,
            function()
                local v = DB()[key][field] or ns.CDM_DEFAULTS[key][field]
                if isCount then return v end
                return math.max(lo, math.floor(v / Grid() + 0.5))
            end,
            function(v) DB()[key][field] = isCount and v or v * Grid(); Refresh() end,
            isCount and Count or BoxFmt, width), x, y)
    end
    PaneHeader(panel, "block", "Health, power and cast bar (sizes in grid boxes)", L, -186, CW)
    Sized("block", "width", "Bar width", 4, 60, L, -212, CW)
    Sized("block", "health", "Health height", 1, 6, L, -256, 104)
    Sized("block", "power", "Power height", 1, 6, L + 113, -256, 104)
    Sized("block", "cast", "Cast height", 1, 6, L + 226, -256, 104)
    PaneHeader(panel, "essential", "Essential cooldowns", L, -302, CW)
    Sized("essential", "size", "Icon size", 2, 10, L, -326, 160)
    Sized("essential", "cap", "Per row (at most)", 1, 12, L + 170, -326, 160)

    ------------------------------------------------------------------ the other panes: two sliders a row
    local function Pair(key, title, y, f1, l1, lo1, hi1, f2, l2, lo2, hi2)
        PaneHeader(panel, key, title, R, y, CW)
        Sized(key, f1, l1, lo1, hi1, R, y - 24, 160)
        Sized(key, f2, l2, lo2, hi2, R + 170, y - 24, 160)
    end
    Pair("buffs", "Tracked buffs", -8, "size", "Icon size", 2, 10, "cap", "Per row (at most)", 1, 12)
    Pair("utility", "Utility", -80, "size", "Icon size", 2, 10, "cap", "Per row (at most)", 1, 12)
    Pair("items", "Items (on-use trinkets)", -152, "size", "Icon size", 2, 10, "cap", "Per row (at most)", 1, 6)
    Pair("bars", "Tracked bars", -224, "width", "Width", 4, 60, "height", "Bar height", 1, 6)
end

-- the resource display page: the block's bars (the settings the Blizzard display had)
local RES = {
    { key = "health", label = "Health" }, { key = "mana", label = "Mana" }, { key = "energy", label = "Energy" },
    { key = "rage", label = "Rage" }, { key = "focus", label = "Focus" }, { key = "other", label = "Other power" },
    { key = "cast", label = "Cast bar" },
}
local function NoneOrPercent(v) return v <= 0 and "none" or ("%d%%"):format(v) end
local function R() local d = DB(); d.res = d.res or {}; d.res.colors = d.res.colors or {}; return d.res end
local function C() return ns.Cooldowns end

local function ColorRow(panel, res)
    local row = CreateFrame("Frame", nil, panel)
    row:SetSize(330, 22)
    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetText(res.label)
    local function Current()
        local c = C() and C().ResColor(res.key) or { 1, 1, 1 }
        return c[1], c[2], c[3]
    end
    local sw = W.Swatch(row, "", Current, function() end, 80, 18)
    sw:SetPoint("LEFT", 84, 0)
    -- the swatch previews the shading
    local shade = sw:CreateTexture(nil, "OVERLAY")
    shade:SetAllPoints(sw.fill)
    shade:SetTexture(C() and C().GRADIENT_TEXTURE)
    local cyl = sw:CreateTexture(nil, "OVERLAY", nil, 1)
    cyl:SetAllPoints(sw.fill)
    cyl:SetTexture(C() and C().CYLINDER_TEXTURE)
    local state = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    state:SetPoint("LEFT", sw, "RIGHT", 8, 0)
    local reset = W.Button(row, "Default", 64, function()
        R().colors[res.key] = nil
        Refresh(); panel:SyncAll()
    end, 20)
    reset:SetPoint("RIGHT", 0, 0)
    sw:SetScript("OnClick", function()
        local prev = R().colors[res.key]
        local r, g, b = Current()
        W.ColorPicker(r, g, b, function(nr, ng, nb)
            R().colors[res.key] = { r = nr, g = ng, b = nb }
            Refresh(); panel:SyncAll()
        end, function()
            R().colors[res.key] = prev and { r = prev.r, g = prev.g, b = prev.b } or nil
            Refresh(); panel:SyncAll()
        end)
    end)
    function row:Sync()
        sw:Sync()
        shade:SetVertexColor(1, 1, 1, R().gradient or 0); shade:SetShown((R().gradient or 0) > 0)
        cyl:SetVertexColor(1, 1, 1, R().cylinder or 0); cyl:SetShown((R().cylinder or 0) > 0)
        local custom = R().colors[res.key] ~= nil
        state:SetText(custom and "Custom" or "Default")
        reset:SetShown(custom)
    end
    return row
end

local function BuildResources(panel)
    local L, RX, CW = 24, 400, 330
    local GMAX = (C() and C().GRADIENT_MAX) or 0.7
    local CMAX = (C() and C().CYLINDER_MAX) or 0.9
    W.Header(panel, "Resource display", L, -8, CW)
    panel:Add(W.Slider(panel, "Background opacity", 0, 100, 5,
        function() return math.floor((R().alpha or 1) * 100 + 0.5) end,
        function(v) R().alpha = v / 100; Refresh() end, W.percentInt, 300), L, -34)
    panel:Add(W.Slider(panel, "Bar gradient (darker on the left)", 0, 100, 5,
        function() return math.floor(math.min((R().gradient or 0) / GMAX, 1) * 100 + 0.5) end,
        function(v) R().gradient = v / 100 * GMAX; Refresh(); panel:SyncAll() end, NoneOrPercent, 300), L, -80)
    panel:Add(W.Slider(panel, "Cylinder shading (top / bottom)", 0, 100, 5,
        function() return math.floor(math.min((R().cylinder or 0) / CMAX, 1) * 100 + 0.5) end,
        function(v) R().cylinder = v / 100 * CMAX; Refresh(); panel:SyncAll() end, NoneOrPercent, 300), L, -126)
    W.Header(panel, "Druid", L, -180, CW)
    local de = panel:Add(W.Check(panel, "Energy bar in caster and Travel Form",
        function() return R().druidEnergy == true end,
        function(v) R().druidEnergy = v; Refresh() end, 300), L, -206)
    de.tooltip = "An energy bar under mana while you are not in Cat Form (in Cat or Bear Form the form's power shows anyway)."
    W.Header(panel, "Cast bar", L, -240, CW)
    local hc = panel:Add(W.Check(panel, "Hide Blizzard's cast bar",
        function() return DB().hideCastBar ~= false end,
        function(v) DB().hideCastBar = v; Refresh() end, 300), L, -266)
    hc.tooltip = "While ours shows (it sits along the bottom of the bars while you cast). Changed out of combat."
    W.Note(panel, "Sizes and placing are on the Cooldown panes page. The display shows while the cooldown panes are on.",
        L, -296, CW)
    panel:Add(W.Button(panel, "Reset", 120, function()
        if C() then C().ResetResources() end
        panel:SyncAll()
        ns.Print("resource display settings reset.")
    end), L, -340)

    W.Header(panel, "Bar colours", RX, -8, CW)
    for i, res in ipairs(RES) do
        panel:Add(ColorRow(panel, res), RX, -34 - (i - 1) * 28)
    end
    W.Note(panel, "Click a colour to change it. The swatch previews the gradient and cylinder shading set on the left.",
        RX, -34 - #RES * 28 - 6, CW)
end

local function Build(panel)
    -- two pages: our cooldown panes, and our resource display (the block's bars)
    local pages, buttons = {}, {}
    local function Page(key, title, build, x)
        local pg = CreateFrame("Frame", nil, panel)
        pg:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -34)
        pg:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
        W.Panel(pg)
        local ok, err = pcall(build, pg)
        if not ok then ns.Print("|cffff5555error building " .. title .. ":|r " .. tostring(err)) end
        pg:Hide()
        pages[key] = pg
        local b = W.Button(panel, title, 170, function() panel.ShowPage(key) end)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -6)
        buttons[key] = b
    end
    function panel.ShowPage(key)
        for k, pg in pairs(pages) do
            pg:SetShown(k == key)
            if k == key then pg:SyncAll() end
            local fs = buttons[k].GetFontString and buttons[k]:GetFontString()
            if fs then fs:SetTextColor(k == key and 1 or 0.7, k == key and 0.82 or 0.7, k == key and 0 or 0.7) end
        end
        panel.page = key
    end
    Page("panes", "Cooldown panes", BuildPanes, 24)
    Page("prd", "Resource display", BuildResources, 200)
    local open = W.Button(panel, "Open Blizzard's Cooldown Manager", 240, OpenBlizzardSettings)
    open:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -24, -6)
    open.tooltip = "Choose what is tracked (Essential, Utility, Tracked Buffs, Tracked Bars). Our panes show it; "
        .. "keep its visibility on Always so it keeps updating."
    open:HookScript("OnEnter", function(self)
        if not _G.GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true); GameTooltip:Show()
    end)
    open:HookScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    panel.ShowPage("panes")
    panel.OnSync = function() local pg = pages[panel.page]; if pg then pg:SyncAll() end end
end

ns.RegisterTab({ key = "cooldowns", title = "Cooldowns", order = 2.5, Build = Build })
