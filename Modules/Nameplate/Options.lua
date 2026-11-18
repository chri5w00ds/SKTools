-- SKTools settings tab: Nameplate.
-- Quest marks (counters, quest-starter icon, rare glow), and what sits by the
-- level badge: combo points (Rogue, Druid) or the range crescent (Hunter).
-- While the tab is open your target previews the marks and the one being adjusted.

local ADDON, ns = ...

local W = ns.W
local M = ns.Marks

local function db() return M.db end
local function K() return ns.Combo.Settings() or {} end
local function ComboChanged() ns.Combo.Refresh() end

-- a slider / check on a marks setting that redraws the nameplates when changed
local function MarkSlider(panel, label, get, set, lo, hi, step, fmt)
    return W.Slider(panel, label, lo, hi, step, get,
        function(v) set(v); M.RefreshAll() end, fmt, 220)
end
local function MarkCheck(panel, label, get, set)
    return W.Check(panel, label, get, function(v) set(v); M.RefreshAll() end, 220)
end

-- The class-specific parts (combo points, range crescent, Claw/Shred icons, Bite icon): one
-- sub-panel each, in the column at x = C3. The designer tab (Designer.lua) hosts them and
-- shows the one whose part is selected on the sample plate.
local function BuildSubs(panel, C3, CW)
    ------------------------------------------------------------------
    -- Column 3: what sits by the level badge. Combo points (Rogue, Druid)
    -- and the range crescent (Hunter) share the spot and never show on the
    -- same character, so they share this column: the two buttons switch it.
    local function Sub()
        local f = CreateFrame("Frame", nil, panel)
        f:SetAllPoints(panel)
        return W.Panel(f)
    end
    local combo, cres, feral, finis = Sub(), Sub(), Sub(), Sub()
    panel.subs = { combo = combo, crescent = cres, feral = feral, finisher = finis }

    local function ShowSub(key)
        panel.sub = key
        for k, f in pairs(panel.subs) do f:SetShown(k == key) end
        if panel.OnSubShown then panel:OnSubShown(key) end
        panel.subs[key]:SyncAll()
        -- preview whichever one is being adjusted
        if panel:IsVisible() then
            ns.Combo.Preview(key == "combo")
            ns.Crescent.Preview(key == "crescent")
            if ns.Totems then ns.Totems.Preview(key == "totems") end
            ns.Feral.Preview(key == "feral" or key == "finisher" or key == "feralR" or key == "finisherR")
        end
    end
    panel.ShowSub = ShowSub
    -- Combo points ---------------------------------------------------
    combo:Add(W.Check(combo, "Show on target (Rogue, Druid)",
        function() return K().enabled end,
        function(v) K().enabled = v; ComboChanged() end, CW), C3, -38)

    local function ComboSlider(label, key, default, lo, hi, step, fmt, y)
        combo:Add(W.Slider(combo, label, lo, hi, step,
            function() local v = K()[key]; if v == nil then return default end return v end,
            function(v) K()[key] = v; ComboChanged() end, fmt, CW), C3, y)
    end
    ComboSlider("Dot size", "size", 10, 6, 20, 1, W.px, -66)
    ComboSlider("Distance from level", "radius", 0, -8, 20, 1, W.signed, -110)
    ComboSlider("Horizontal", "x", 0, -60, 60, 1, W.signed, -154)
    ComboSlider("Vertical", "y", 0, -40, 40, 1, W.signed, -198)
    ComboSlider("Glow strength", "glow", 1.0, 0, 1, 0.05,
        function(v) return v <= 0 and "off" or W.percent(v) end, -242)
    ComboSlider("Background", "bgAlpha", 0.65, 0, 1, 0.05, W.percent, -286)
    ComboSlider("Dark outline", "edge", 0.9, 0, 1, 0.05,
        function(v) return v <= 0 and "off" or W.percent(v) end, -436)

    combo:Add(W.Swatch(combo, "Point colour",
        function()
            local c = K().color or { 1.0, 0.16, 0.13 }
            return c[1], c[2], c[3]
        end,
        function(r, g, b) K().color = { r, g, b }; ComboChanged() end), C3, -332)

    local combatChk = combo:Add(W.Check(combo, "Only in combat",
        function() return K().combatOnly ~= false end,
        function(v) K().combatOnly = v; ComboChanged() end, CW), C3, -410)
    combatChk.tooltip = "The dots appear when combat starts and go when it ends. Off: they show whenever you have a target."

    local tightChk = combo:Add(W.Check(combo, "Tight cluster",
        function() return K().tight ~= false end,
        function(v) K().tight = v; ComboChanged() end, CW), C3, -358)
    tightChk.tooltip = "Packs the five dots close to the level badge, no taller than the badge, "
        .. "which leaves room above and below for the Claw and Shred icons."


    combo:Add(W.Button(combo, "Reset combo points", 140, function()
        ns.Combo.Reset()
        combo:SyncAll()
    end), C3 + 60, -384)

    combo.note = W.Note(combo, "", C3, -480, CW)
    function combo:OnSync()
        self.note:SetText(ns.Combo.Eligible()
            and "Your target shows 3 points as a preview."
            or "This character has no combo points, so nothing shows outside this preview.")
    end

    -- Range crescent -------------------------------------------------
    local function Z() return ns.Crescent.Settings() or {} end
    local function CresChanged() ns.Crescent.Refresh() end
    local RB = ns.RangeBar

    cres.showChk = cres:Add(W.Check(cres, "Show on target (Hunter, bow)",
        function() return Z().enabled end,
        function(v) Z().enabled = v; CresChanged() end, CW), C3, -38)

    local function CresSlider(label, key, lo, hi, fmt, y)
        cres:Add(W.Slider(cres, label, lo, hi, 1,
            function() return Z()[key] end,
            function(v) Z()[key] = v; CresChanged() end, fmt, CW), C3, y)
    end
    CresSlider("Horizontal", "x", -80, 80, W.signed, -66)
    CresSlider("Vertical", "y", -60, 60, W.signed, -110)
    CresSlider("Size (grows from the centre)", "size", 16, 120, W.px, -154)

    -- two colours; in the dead zone and out of shoot range there is no crescent
    for i, entry in ipairs(ns.CRESCENT_COLOR_KEYS) do
        local key = entry[1]
        cres:Add(W.Swatch(cres, entry[2],
            function()
                local c = (Z().colors or {})[key] or ns.CRESCENT_DEFAULTS.colors[key]
                return c[1], c[2], c[3]
            end,
            function(r, g, b)
                Z().colors = Z().colors or {}
                Z().colors[key] = { r, g, b }
                CresChanged()
            end), C3 + (i - 1) * 112, -198)
    end

    local shapes = cres:Add(W.Check(cres, "Pulse in melee",
        function() return Z().shapes end,
        function(v) Z().shapes = v; CresChanged() end, 108), C3, -222)
    shapes.tooltip = "Melee range: the red crescent pulses, so the two states differ by more than colour. "
        .. "Off: a steady crescent."

    local glowChk = cres:Add(W.Check(cres, "Glow",
        function() return Z().glow ~= false end,
        function(v) Z().glow = v; CresChanged() end, 108), C3 + 112, -222)
    local rimChk = cres:Add(W.Check(cres, "Silver border",
        function() return Z().border ~= false end,
        function(v) Z().border = v; CresChanged() end, 108), C3, -246)
    rimChk.tooltip = "A thin classic silver rim round the crescent."
    cres:Add(W.Slider(cres, "Dark outline", 0, 1, 0.05,
        function() return Z().edge == nil and 1 or Z().edge end,
        function(v) Z().edge = v; CresChanged() end,
        function(v) return v <= 0 and "off" or W.percent(v) end, CW), C3, -428)
    local domeChk = cres:Add(W.Check(cres, "Dome shading",
        function() return Z().dome ~= false end,
        function(v) Z().dome = v; CresChanged() end, 108), C3 + 112, -246)
    domeChk.tooltip = "Darkens the colour next to the silver rim so the crescent looks "
        .. "domed, brightest along its middle."
    local ccChk = cres:Add(W.Check(cres, "Move CC icons aside",
        function() return Z().moveCC ~= false end,
        function(v) Z().moveCC = v; CresChanged() end, CW), C3, -270)
    ccChk.tooltip = "Blizzard draws the shared crowd-control icon under the level badge, "
        .. "where the crescent is. While the crescent shows, it is moved out to its right."
    glowChk.tooltip = "A soft glow round the crescent in the zone colour."

    -- the range detection behind it
    local function RangeSlider(label, lo, hi, get, set, fmt, y)
        cres:Add(W.Slider(cres, label, lo, hi, 1, get, set, fmt, CW), C3, y)
    end
    RangeSlider("Dead zone top (yd)", 0, 20,
        function() return RB.Settings().minRange end,
        function(v) RB.Settings().minRange = v; RB.Layout() end, nil, -296)
    RangeSlider("Max ranged range (yd)", 0, 60,
        function() return RB.Settings().maxOverride end,
        function(v) RB.Settings().maxOverride = v; RB.Layout() end,
        function(v) if v < 1 then return "auto" end return tostring(v) end, -340)
    RangeSlider("Nameplate distance (yd)", 10, 60,
        function() return RB.NameplateMax() end,
        function(v) RB.SetNameplateMax(v) end, nil, -384)

    cres:Add(W.Button(cres, "Reset crescent", 108, function()
        ns.Crescent.Reset()
        cres:SyncAll()
    end), C3, -474)
    local dbg = cres:Add(W.Button(cres, "Debug to chat", 108, function()
        SlashCmdList["SKTOOLSRANGE"]("crescent debug")
        SlashCmdList["SKTOOLSRANGE"]("debug")
    end), C3 + 112, -474)
    dbg.tooltip = "Prints what the crescent and the range checks see on your target."

    function cres:OnSync()
        self.showChk.tooltip = RB.HasBow()
            and "Bow equipped: the crescent is live on your target."
            or "Needs a Hunter with a bow equipped; until then this is only a preview."
    end

    -- Claw and Shred ready icons (Druid, Cat Form) --------------------
    local function F() return ns.Feral.Settings() or {} end
    local function FeralChanged() ns.Feral.Refresh() end
    feral:Add(W.Check(feral, "Show on target",
        function() return F().enabled end,
        function(v) F().enabled = v; FeralChanged() end, CW), C3, -38)
    local function FeralSlider(label, key, lo, hi, fmt, y)
        feral:Add(W.Slider(feral, label, lo, hi, 1,
            function() return F()[key] end,
            function(v) F()[key] = v; FeralChanged() end, fmt, CW), C3, y)
    end
    FeralSlider("Horizontal", "x", -80, 80, W.signed, -66)
    FeralSlider("Vertical", "y", -60, 60, W.signed, -110)
    FeralSlider("Icon size (when not matching)", "size", 14, 64, W.px, -154)
    FeralSlider("Gap from the level box", "gap", 0, 20, W.px, -198)
    local function FCheck(label, key, x, y, w)
        return feral:Add(W.Check(feral, label,
            function() return F()[key] ~= false and F()[key] ~= nil end,
            function(v) F()[key] = v; FeralChanged() end, w or 108), x, y)
    end
    -- one checkbox per icon of this character's class, a row per form
    -- (Druid: Claw, Shred in Cat Form; Maul, Swipe and Primal Bite in Bear Form. Hunter: Raptor Strike, Mongoose Bite)
    local row = 0
    for _, st in ipairs(ns.Feral.AllStacks()) do
        local list = {}
        for _, s in ipairs(st.skills) do list[#list + 1] = s end
        if st.finisherSkill then list[#list + 1] = st.finisherSkill end       -- Bear Form: Primal Bite, the big icon over the pair
        for i, s in ipairs(list) do
            local col = (i - 1) % 2
            local c = FCheck(s.name, s.key, C3 + col * 112, -230 - row * 24)
            local which = (s == st.finisherSkill) and "The big icon over the other two"
                or (i == 1 and "The bottom icon" or i == #st.skills and "The top icon" or "The middle icon")
            c.tooltip = which .. (st.forms and (st.forms[1] and " (Cat Form)." or " (Bear Form).") or ".")
            if col == 1 or i == #list then row = row + 1 end
        end
    end
    local sh = math.max(0, row - 1) * 24          -- extra skill rows push everything below down
    FCheck("Glow", "glow", C3, -254 - sh).tooltip = "A soft glow round an icon that is ready."
    FCheck("Pulse", "pulse", C3 + 112, -254 - sh).tooltip = "A gentle pulse on an icon that is ready."
    local hideChk = feral:Add(W.Check(feral, "Hide when not ready",
        function() return F().hideNotReady == true end,
        function(v) F().hideNotReady = v; FeralChanged() end, 108), C3, -278 - sh)
    hideChk.tooltip = "On: an icon only shows while its skill can be used right now (enough energy, "
        .. "in range, off cooldown). Off: a grey, dimmed icon stays when it cannot."
    local combatChk = feral:Add(W.Check(feral, "Only in combat",
        function() return F().combatOnly ~= false end,
        function(v) F().combatOnly = v; FeralChanged() end, 108), C3 + 112, -278 - sh)
    combatChk.tooltip = "Hides the icons while you are out of combat."
    local badgeChk = feral:Add(W.Check(feral, "Beside the level badge",
        function() return F().badge ~= false end,
        function(v) F().badge = v; FeralChanged() end, 108), C3, -302 - sh)
    badgeChk.tooltip = "On Blizzard's plates. On: the top icon above the combo points and the bottom one below them. "
        .. "Off: side by side under the health bar."
    local ccChk = feral:Add(W.Check(feral, "Move CC icons aside",
        function() return F().moveCC ~= false end,
        function(v) F().moveCC = v; FeralChanged() end, 108), C3 + 112, -302 - sh)
    ccChk.tooltip = "Blizzard draws its shared crowd-control icon right under the level badge, "
        .. "where the bottom icon sits. This moves it to just under that icon while the icons show."
    local matchChk = feral:Add(W.Check(feral, "Match level box width",
        function() return F().match ~= false end,
        function(v) F().match = v; FeralChanged() end, CW), C3, -326 - sh)
    matchChk.tooltip = "Makes each icon as wide as the level box. Off: the Icon size slider decides."
    W.Note(feral, "Lit = usable now (power, procs), in melee range and off cooldown. Shred's \"behind the "
        .. "target\" rule cannot be read by addons.", C3, -354 - sh, CW)
    feral:Add(W.Button(feral, "Reset", 108, function()
        ns.Feral.Reset()
        feral:SyncAll()
    end), C3, -404 - sh)
    feral:Add(W.Button(feral, "Debug to chat", 108, function()
        ns.Feral.Debug(function(m) print(m) end)
    end), C3 + 112, -404 - sh).tooltip = "Prints what the game says about Claw and Shred right now."

    -- Ferocious Bite / Shifting Power icon, left of the health bar -----
    local function G() return ns.Feral.Settings() or {} end
    local function FinChanged() ns.Feral.Refresh() end
    finis:Add(W.Check(finis, "Show on target (Druid, Cat Form)",
        function() return G().finisher ~= false end,
        function(v) G().finisher = v; FinChanged() end, CW), C3, -38)
    local function FinSlider(label, key, default, lo, hi, fmt, y)
        finis:Add(W.Slider(finis, label, lo, hi, 1,
            function() local v = G()[key]; if v == nil then return default end return v end,
            function(v) G()[key] = v; FinChanged() end, fmt, CW), C3, y)
    end
    FinSlider("Horizontal", "fx", 0, -80, 80, W.signed, -66)
    FinSlider("Vertical", "fy", 0, -60, 60, W.signed, -110)
    FinSlider("Gap from the health bar", "fgap", 4, 0, 30, W.px, -154)
    FinSlider("Energy from Shifting Power", "shiftEnergy", 0, 0, 100,
        function(v) return v <= 0 and "read from the spell" or tostring(v) end, -198)
    local biteChk = finis:Add(W.Check(finis, "Ferocious Bite at full energy",
        function() return G().finBite ~= false end,
        function(v) G().finBite = v; FinChanged() end, CW), C3, -230)
    biteChk.tooltip = "Shows Ferocious Bite when you have 5 combo points and full energy."
    local shiftChk = finis:Add(W.Check(finis, "Shifting Power when it gets you there",
        function() return G().finShift ~= false end,
        function(v) G().finShift = v; FinChanged() end, CW), C3, -254)
    shiftChk.tooltip = "Shows Shifting Power when you have 5 combo points, it is off cooldown, you have "
        .. "the mana, and casting it plus the energy you regenerate during the global cooldown that "
        .. "follows would put you at full energy for a Bite."
    W.Note(finis, "The global cooldown is the spell's own, shortened by your haste. Regeneration "
        .. "is the rate the game reports. If the energy from Shifting Power is not read correctly, "
        .. "set it with the slider above.", C3, -282, CW)
    finis:Add(W.Button(finis, "Reset", 108, function()
        local d = ns.Feral.Settings()
        for _, k in ipairs({ "finisher", "finBite", "finShift", "fx", "fy", "fgap", "shiftEnergy" }) do
            d[k] = ns.FERAL_DEFAULTS[k]
        end
        FinChanged(); finis:SyncAll()
    end), C3, -366)
    finis:Add(W.Button(finis, "Debug to chat", 108, function()
        ns.Feral.Debug(function(m) print(m) end)
    end), C3 + 112, -366).tooltip = "Prints what the game says about Bite, Shifting Power, energy and haste right now."
    return ShowSub
end

ns.NameplateOptions = { BuildSubs = BuildSubs, MarkSlider = MarkSlider, MarkCheck = MarkCheck }
