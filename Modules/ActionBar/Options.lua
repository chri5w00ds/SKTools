-- SKTools settings tab: Mouseover.
-- Action bars (and the XP / status bars) that hide until the mouse is over them.

local ADDON, ns = ...

local W = ns.W

local function H() return ns.Hover.Settings() or { bars = {} } end

local function Build(panel)
    local L = 24

    ------------------------------------------------------------------
    W.Header(panel, "Show bars only on mouseover", L, -8, 680)
    local master = panel:Add(W.Check(panel, "Hide action bars until hovered",
        function() return H().enabled end,
        function(v) H().enabled = v; ns.Hover.Refresh() end, 300), L, -34)
    master.tooltip = "Bars ticked below fade out and come back while the mouse is over them. All of them show "
        .. "while you drag a spell or item, in Edit Mode, and while a spell flyout is open. Their buttons "
        .. "and key bindings keep working while they are faded. Blizzard's own bars only (not Bartender4 or Dominos)."

    W.Header(panel, "Bars", L, -72, 680)
    for i, bar in ipairs(ns.Hover.Bars()) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local c = panel:Add(W.Check(panel, bar.label,
            function() return H().bars[bar.key] == true end,
            function(v) H().bars[bar.key] = v and true or false; ns.Hover.Refresh() end, 200),
            L + 14 + col * 220, -98 - row * 22)
        c.tooltip = "Ticked: this bar hides until hovered (while the switch above is on). Unticked: it always shows."
    end

    W.Header(panel, "Timing", L, -200, 680)
    panel:Add(W.Slider(panel, "Stay after the mouse leaves", 0, 2, 0.1,
        function() return H().linger or 0.5 end,
        function(v) H().linger = v end, function(v) return ("%.1f s"):format(v) end, 300), L, -226)
    panel:Add(W.Slider(panel, "Fade time", 0.05, 1, 0.05,
        function() return H().fade or 0.15 end,
        function(v) H().fade = v end, function(v) return ("%.2f s"):format(v) end, 300), L + 340, -226)

    W.Note(panel, "A bar shows while the mouse is anywhere over it - its own frame and its buttons. "
        .. "The flight path / vehicle exit button never fades with Action Bar 1.", L, -290, 660)

    panel:Add(W.Button(panel, "Debug to log", 120, function()
        ns.Report("mouseover", function(out) ns.Hover.Debug(out) end, true)
    end), L, -340)
end

ns.RegisterTab({ key = "action", title = "Mouseover", order = 3, Build = Build })
