-- SKTools settings tab: Action Bar.
-- Tints action bar icons when a skill is out of range or you can't afford it.

local ADDON, ns = ...

local W = ns.W

local function T() return ns.Tint.Settings() or {} end
local function Changed() ns.Tint.Refresh() end

local function ColorSwatch(panel, key, label)
    return W.Swatch(panel, label,
        function()
            local c = (T().colors or {})[key] or { 1, 1, 1 }
            return c[1], c[2], c[3]
        end,
        function(r, g, b)
            T().colors = T().colors or {}
            T().colors[key] = { r, g, b }
            Changed()
        end)
end

local function Build(panel)
    local L, R = 24, 400

    ------------------------------------------------------------------
    W.Header(panel, "Action bar tint", L, -8, 330)

    panel:Add(W.Check(panel, "Tint action bar icons",
        function() return T().enabled end,
        function(v) T().enabled = v; Changed() end, 300), L, -34)

    panel:Add(W.Check(panel, "Out of range tint",
        function() return T().range ~= false end,
        function(v) T().range = v; Changed() end, 280), L + 14, -56)

    panel:Add(W.Check(panel, "Not enough resource tint (mana, rage, energy, focus)",
        function() return T().resource ~= false end,
        function(v) T().resource = v; Changed() end, 300), L + 14, -78)

    panel:Add(W.Slider(panel, "Tint opacity", 0.1, 0.9, 0.05,
        function() return T().alpha or 0.45 end,
        function(v) T().alpha = v; Changed() end, W.percent, 300), L, -112)

    W.Header(panel, "Resource tint edge", L, -164, 330)

    local shrink = panel:Add(W.Check(panel, "Shrink the tint as the resource fills",
        function() return T().partial end,
        function(v) T().partial = v; Changed() end, 300), L, -190)
    shrink.tooltip = "The resource tint only covers the share you are still missing, and recedes "
        .. "towards the top-right corner as the resource comes back."

    panel:Add(W.Check(panel, "Ripple on the edge",
        function() return T().animate end,
        function(v) T().animate = v; Changed() end, 300), L, -212)

    -- extra contrast lines: a toggle and a colour each, on one row
    local function LineRow(key, label, y)
        panel:Add(W.Check(panel, label,
            function() return T()[key] end,
            function(v) T()[key] = v; Changed() end, 150), L + 14, y)
        panel:Add(ColorSwatch(panel, key, ""), L + 180, y)
    end
    LineRow("darkLine", "Dark edge line", -234)
    LineRow("lightLine", "Light edge line", -256)

    W.Note(panel, "The wavy edge and its two lines are what set the resource tint apart from "
        .. "the flat out-of-range tint, so the two can be told apart by shape as well as colour.",
        L, -286, 330)

    ------------------------------------------------------------------
    W.Header(panel, "Tint colours", R, -8, 330)
    local y = -34
    for _, entry in ipairs(ns.TINT_COLOR_KEYS or {}) do
        panel:Add(ColorSwatch(panel, entry[1], entry[2]), R, y)
        y = y - 24
    end

    W.Note(panel, "Out of range and short at once: the resource colour sits on top, and the "
        .. "range colour shows where it has receded.", R, y - 8, 330)

    W.Note(panel, "Works on the default action bars, Bartender4 and Dominos.", R, y - 52, 330)

    ------------------------------------------------------------------
    -- bars that only show on mouseover
    local function H() return ns.Hover.Settings() or { bars = {} } end
    W.Header(panel, "Show bars only on mouseover", R, -230, 330)
    local master = panel:Add(W.Check(panel, "Hide action bars until hovered",
        function() return H().enabled end,
        function(v) H().enabled = v; ns.Hover.Refresh() end, 300), R, -254)
    master.tooltip = "Bars ticked below fade out and come back while the mouse is over them. All of them show "
        .. "while you drag a spell or item, in Edit Mode, and while a spell flyout is open. Their buttons "
        .. "and key bindings keep working while they are faded. Blizzard's own bars only (not Bartender4 or Dominos)."
    for i, bar in ipairs(ns.Hover.Bars()) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local c = panel:Add(W.Check(panel, bar.label,
            function() return H().bars[bar.key] == true end,
            function(v) H().bars[bar.key] = v and true or false; ns.Hover.Refresh() end, 150),
            R + 14 + col * 160, -276 - row * 20)
        c.tooltip = "Ticked: this bar hides until hovered (while the switch above is on). Unticked: it always shows."
    end

    panel:Add(W.Button(panel, "Reset tint", 120, function()
        ns.Tint.Reset()
        panel:SyncAll()
        ns.Print("action bar tint settings reset.")
    end), R, -406)

    panel:Add(W.Button(panel, "Debug to chat", 120, function()
        ns.Tint.Debug(ns.Printer("Tint"))
        ns.Hover.Debug(ns.Printer("Bars"))
    end), R + 130, -406)
end

ns.RegisterTab({ key = "action", title = "Action Bar", order = 3, Build = Build })
