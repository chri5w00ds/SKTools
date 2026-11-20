--[[-------------------------------------------------------------------------
  SKTools - combo points on the target's nameplate

  Five dots in an arc on the right of the level badge, filling clockwise
  from 12 o'clock. Nothing shows until you have a point; then all five
  frames appear, filled ones red with a soft glow. Rogues and Druids only.

  Forever can hide numbers like your combo points from addons. Every layer
  of every dot is therefore a tiny status bar: the game is handed the raw
  (possibly hidden) value and fills or empties each layer itself, so the
  addon never has to read or compare the number.
---------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

local MEDIA = ns.MEDIA
local MAX = 5

ns.COMBO_DEFAULTS = {
    enabled = true,
    size    = 10,        -- dot size in pixels
    radius  = 0,         -- extra distance from the level badge
    tight   = true,      -- the four outer dots curve in towards the middle one, almost touching
    x       = -4,        -- fine position of the whole arc
    y       = 0,
    glow    = 1.0,       -- glow strength, 0 = off
    combatOnly = true,   -- the dots appear when combat starts, and go when it ends
    growlColor  = { 1.0, 1.0, 1.0 },     -- Bear Form: the small dots that count Growl's last three seconds
    bgAlpha = 0.65,      -- dark background inside each frame
    edge    = 0.9,       -- dark outline round each dot, so it stands out on bright ground; 0 = off
    color   = { 1.0, 0.16, 0.13 },       -- bright red
}
-- the red before 1.6.2: settings still holding it are moved to the brighter one
local OLD_RED = { 0.92, 0.14, 0.12 }

-- base arc, hugging the badge (it's wider than it is tall)
local BASE_RX, BASE_RY = 25, 20
-- The tight cluster: the middle dot stays where the wide arc has it (25 px right of the badge
-- centre); the other four sit on a gentle curve either side of it, TIGHT_GAP px from their
-- neighbour, so all five read as one group that stays clear of the icons above and below the badge.
local TIGHT_CURVE, TIGHT_GAP = 48, 2
local boxW, boxH = 26, 16            -- the level box the dots sit beside (measured on the plate)
local LEFT_GAP = 2                   -- on our own plates: dots this far off the level box's left edge
local OWN_CURVE = 58                 -- on our own plates the curve is a little flatter (wider radius)
local COUNTER_H, COUNTER_GAP = 14, 2 -- the kill / loot boxes above and below the level box (Plates.lua)
local side = "right"                 -- "left" while the plate is ours
local GLOW_SCALE = 2.6

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local issecret = _G.issecretvalue or function() return false end
local function Plain(v)
    if v ~= nil and issecret(v) then return nil end
    return v
end

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

-- what the arc shows: "combo" (Rogue; Druid in Cat Form), "growl" (Druid in Bear Form: the dots
-- count Growl's cooldown down and all five are lit while it is ready), or nil
local function Mode()
    local _, class = UnitClass("player")
    class = Plain(class)
    if class == "ROGUE" then return "combo" end
    if class ~= "DRUID" then return nil end
    if not _G.GetShapeshiftFormID then return "combo" end
    local ok, id = pcall(_G.GetShapeshiftFormID)
    id = ok and Plain(id) or nil
    if id == 1 then return "combo" end
    if id == 5 or id == 8 then return "growl" end
    return nil
end
local function Eligible() return Mode() ~= nil end
local mode = "combo"

-- Growl: the rank you know, looked up by name now and then
local growlId, growlAt
local function GrowlId()
    if growlAt and GetTime() - growlAt < 5 then return growlId end
    growlAt, growlId = GetTime(), nil
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, "Growl")
        local id = ok and type(info) == "table" and Plain(info.spellID) or nil
        if type(id) == "number" then growlId = id end
    end
    return growlId or 6795
end

-- Growl's cooldown is 8 s. Time left -> red dots lit: all five while it is ready (nothing left),
-- then the top one goes at 7 s left, the next at 6, 5, 4 and the last at 3; during the last
-- three seconds none is red. Time left -> small white dots on the inner three: three at 3 s
-- left, two at 2, one at 1, none when ready. Step curves the game evaluates itself, so they
-- work while the time is hidden.
local STEP = 0.001
local litCurve, whiteCurve
local function Curves()
    if litCurve ~= nil then return litCurve or nil, whiteCurve or nil end
    litCurve, whiteCurve = false, false
    if C_CurveUtil and C_CurveUtil.CreateCurve then
        local function make(points)
            local ok, c = pcall(C_CurveUtil.CreateCurve)
            if not (ok and c) then return nil end
            local E = _G.Enum
            if E and E.LuaCurveType and E.LuaCurveType.Step and c.SetType then pcall(c.SetType, c, E.LuaCurveType.Step) end
            for _, p in ipairs(points) do pcall(c.AddPoint, c, p[1], p[2]) end
            return c
        end
        litCurve = make({ { 0, MAX }, { STEP, 0 }, { 3 + STEP, 1 }, { 4 + STEP, 2 }, { 5 + STEP, 3 }, { 6 + STEP, 4 }, { 7 + STEP, 5 }, { 3600, 5 } }) or false
        whiteCurve = make({ { 0, 0 }, { STEP, 1 }, { 1 + STEP, 2 }, { 2 + STEP, 3 }, { 3 + STEP, 0 }, { 3600, 0 } }) or false
    end
    return litCurve or nil, whiteCurve or nil
end
-- the same two counts from a plain number of seconds left
local function GrowlCounts(remaining)
    if remaining <= 0 then return MAX, 0 end
    if remaining <= 3 then return 0, math.ceil(remaining) end
    return math.min(MAX, math.ceil(remaining - 3)), 0
end

-- your combo points, possibly as a hidden value; nil if the game won't say
local function RawPoints()
    if _G.GetComboPoints then
        local ok, v = pcall(_G.GetComboPoints, "player", "target")
        if ok and v ~= nil then return v, "GetComboPoints" end
    end
    local pt = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
    local ok, v = pcall(UnitPower, "player", pt)
    if ok and v ~= nil then return v, "UnitPower" end
end

----------------------------------------------------------------------
-- Finding the level badge on a nameplate
----------------------------------------------------------------------

-- Looks for the font string that shows the unit's level. Works whatever
-- draws the plate, as long as the level is a piece of text on it.
local function FindLevel(frame, want, depth)
    if not frame or depth > 5 then return end
    if frame.GetRegions then
        for _, r in ipairs({ frame:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" and r:IsShown() then
                local ok, t = pcall(r.GetText, r)
                t = ok and Plain(t) or nil
                if t and want and t:gsub("%s", "") == want then return r end
            end
        end
    end
    if frame.GetChildren then
        for _, ch in ipairs({ frame:GetChildren() }) do
            local hit = FindLevel(ch, want, depth + 1)
            if hit then return hit end
        end
    end
end

local function FindHealthBar(plate)
    local uf = plate.UnitFrame
    if uf then
        local c = uf.HealthBarsContainer
        if c and c.healthBar then return c.healthBar end
        return uf.healthBar or uf.HealthBar
    end
end

-- returns the region to centre on, and how it was found
local function Anchor(plate, unit)
    if ns.Plates and ns.Plates.Active and ns.Plates.Active(plate) then
        return ns.Plates.Frame(plate), "sktools"
    end
    local lvl = Plain(UnitLevel(unit))
    local want = (lvl and lvl > 0) and tostring(lvl) or "??"
    local uf = plate.UnitFrame
    local known = uf and (uf.levelText or uf.LevelText or (uf.LevelFrame and (uf.LevelFrame.levelText or uf.LevelFrame)))
    if type(known) == "table" and known.IsShown and known:IsShown() then return known, "level frame" end
    local hit = FindLevel(plate, want, 0)
    if hit then return hit, "level text" end
    local hb = FindHealthBar(plate)
    if hb then return hb, "health bar" end
    return plate, "nameplate"
end

-- width and height of the level box (the framed number), not just its text
local function Dim(o)
    local ok, w, h = pcall(function() return o:GetWidth(), o:GetHeight() end)
    w, h = Plain(w), Plain(h)
    if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then return w, h end
end

local function BoxSize(anchor, how)
    local w, h
    if type(anchor) == "table" and (how == "level frame" or how == "level text") then
        w, h = Dim(anchor)
        if anchor.GetObjectType and anchor:GetObjectType() == "FontString" then
            -- just the text: the box round it is the parent when that is a small frame
            local p = anchor.GetParent and anchor:GetParent()
            local pw, ph
            if p then pw, ph = Dim(p) end
            if pw and ph and pw <= 60 and ph <= 40 and w and pw >= w then
                w, h = pw, ph
            else
                w, h = (w or 14) + 10, (h or 10) + 6
            end
        end
    end
    return w or 26, h or 16
end

----------------------------------------------------------------------
-- Building the dots
----------------------------------------------------------------------

local db
local holder            -- parent of all five dots
local dots = {}
local anchorInfo = "none"
local previewing = false
local cachePlate, cacheAnchor, cacheHow, cacheAge = nil, nil, nil, 0

local function Layer(parent, tex, level, min, max)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetStatusBarTexture(MEDIA .. tex)
    b:SetOrientation("HORIZONTAL")
    b:SetMinMaxValues(min, max)
    b:SetValue(0)
    b:SetFrameLevel(level)
    b:EnableMouse(false)
    return b
end

local dotHost          -- the dots' parent
local function Build()
    if holder then return end
    holder = CreateFrame("Frame", "SKToolsComboFrame", UIParent)
    holder:SetSize(1, 1)
    holder:SetFrameStrata("MEDIUM")
    holder:Hide()
    local base = holder:GetFrameLevel()
    dotHost = CreateFrame("Frame", nil, holder)
    dotHost:SetAllPoints(holder)
    dotHost:SetFrameLevel(base + 1)
    dotHost:EnableMouse(false)

    for i = 1, MAX do
        local d = {}
        -- glow and fill come on from point i; frame and background from
        -- the first point, so nothing shows at 0
        d.edge = Layer(dotHost, "ComboBG", base + 2, 0, 1)
        d.glow = Layer(dotHost, "ComboGlow", base + 1, i - 1, i)
        d.bg   = Layer(dotHost, "ComboBG",   base + 2, 0, 1)
        d.fill = Layer(dotHost, "ComboFill", base + 3, i - 1, i)
        d.ring = Layer(dotHost, "ComboRing", base + 4, 0, 1)
        -- Bear Form: a small white dot on the inner three (2, 3, 4) counts the last three seconds;
        -- dot 2 lights from one, dot 3 from two, dot 4 from three
        if i >= 2 and i <= MAX - 1 then d.white = Layer(dotHost, "ComboFill", base + 5, i - 2, i - 1) end
        dots[i] = d
    end
end

-- Bear Form: the dots count Growl's cooldown down (see Curves)
local SetPoints     -- defined below
local function Growl()
    local id = GrowlId()
    local remaining
    if id and C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, id)
        if ok and type(info) == "table" then
            local s, d = Plain(info.startTime), Plain(info.duration)
            if type(s) == "number" and type(d) == "number" then
                remaining = (d > 1.5) and math.max(0, s + d - GetTime()) or 0    -- the global cooldown is not Growl's
            end
        end
    end
    if remaining ~= nil then
        -- readable numbers (out of combat, or an older client)
        local lit, white = GrowlCounts(remaining)
        SetPoints(lit, white)
        return remaining <= 0 and "ready" or ("%.1f s left"):format(remaining)
    end
    -- hidden numbers: the game's own timer drives both counts
    if id and C_Spell and C_Spell.GetSpellCooldownDuration then
        local ok, dur = pcall(C_Spell.GetSpellCooldownDuration, id)
        if ok and dur and dur.EvaluateRemainingDuration then
            local lc, wc = Curves()
            if lc and wc then
                local done = pcall(function() SetPoints(dur:EvaluateRemainingDuration(lc), dur:EvaluateRemainingDuration(wc)) end)
                if done then return "hidden by the game: its own timer drives the dots" end
            end
        end
    end
    SetPoints(MAX, 0)
    return "no cooldown information: shown as ready"
end

local growlInfo = "-"


-- Tight cluster. The middle dot keeps the wide arc's spot; dot i is k = 3 - i steps from it
-- (top dot first). Each step turns TIGHT_GAP + dot size worth of arc along a curve of
-- radius TIGHT_CURVE that bends back towards the badge. The whole cluster is pushed right
-- if needed so the outer dots clear the icons above and below the level box.
local function ClusterPositions(s, left)
    if left == nil then left = (side == "left") end
    if db.tight == false and not left then return nil end
    local R = left and OWN_CURVE or TIGHT_CURVE
    local step = 2 * math.asin(math.min((s + TIGHT_GAP) / (2 * R), 1))
    local bend = R * (1 - math.cos(2 * step))                     -- how far the outer dots curve in
    local cx = math.max(BASE_RX + db.radius, boxW / 2 + 1 + s / 2 + bend)
    if left then cx = LEFT_GAP + s / 2 + bend end                 -- outer dots almost touch the level box
    local px, py = {}, {}
    for i = 1, MAX do
        local k = 3 - i
        local phi = k * step
        px[i] = cx - R * (1 - math.cos(phi))
        if left then px[i] = -px[i] end                              -- mirrored: the curve bends towards the bar on the right
        py[i] = R * math.sin(phi)
        if left then py[i] = -py[i] end                              -- on our plates the points fill from the bottom up
    end
    return px, py, left and -cx or cx
end

-- on our plates: the cluster's x (from the level box's left edge) with your nudge, moved left as far
-- as needed so no dot level with the kill / loot boxes reaches over them (1 px clear, dark edge
-- included). Dots level with the level box itself may still sit over it.
local function OwnX(x, y)
    x, y = x or 0, y or 0
    local px, py = ClusterPositions(db.size, true)
    local p = ns.Plates and ns.Plates.Settings and ns.Plates.Settings() or {}
    local h = p.height or 20
    local lo, hi = h / 2 + COUNTER_GAP, h / 2 + COUNTER_GAP + COUNTER_H
    local half = (db.size + 4) / 2
    local worst
    for i = 1, MAX do
        local top, bot = py[i] + y + half, py[i] + y - half
        local level = (top > lo and bot < hi) or (top > -hi and bot < -lo)
        if level then
            local right = x + px[i] + half
            if not worst or right > worst then worst = right end
        end
    end
    if worst and worst > -1 then x = x - (worst + 1) end
    return x
end

local function Style()
    if not holder then return end
    local s, c = db.size, db.color
    local wc = db.growlColor or { 1, 1, 1 }
    local rx, ry = BASE_RX + db.radius, BASE_RY + db.radius
    local px, py = ClusterPositions(s)
    for i = 1, MAX do
        local d = dots[i]
        local x, y
        if px then
            x, y = px[i], py[i]
        else
            -- the wide arc: clockwise from 12 o'clock to 6 o'clock, on the right-hand side
            local a = math.rad((i - 1) * 45)
            x, y = rx * math.sin(a), ry * math.cos(a)
        end
        d.edge:SetSize(s + 4, s + 4)
        d.edge:ClearAllPoints()
        d.edge:SetPoint("CENTER", holder, "CENTER", x, y)
        d.edge:SetStatusBarColor(0, 0, 0, db.edge or 0.9)
        d.edge:SetShown((db.edge or 0) > 0)
        for _, layer in ipairs({ d.bg, d.fill, d.ring }) do
            layer:SetSize(s, s)
            layer:ClearAllPoints()
            layer:SetPoint("CENTER", holder, "CENTER", x, y)
        end
        local g = s * GLOW_SCALE
        d.glow:SetSize(g, g)
        d.glow:ClearAllPoints()
        d.glow:SetPoint("CENTER", holder, "CENTER", x, y)

        d.bg:SetStatusBarColor(0, 0, 0, db.bgAlpha)
        d.fill:SetStatusBarColor(c[1], c[2], c[3], 1)
        d.ring:SetStatusBarColor(1, 1, 1, 1)
        d.glow:SetStatusBarColor(c[1], c[2], c[3], db.glow)
        if db.glow <= 0 then d.glow:Hide() else d.glow:Show() end
        if d.white then
            -- the small countdown dot: half the dot, centred in it
            local w = math.max(3, math.floor(s * 0.5 + 0.5))
            d.white:SetSize(w, w)
            d.white:ClearAllPoints()
            d.white:SetPoint("CENTER", holder, "CENTER", x, y)
            d.white:SetStatusBarColor(wc[1], wc[2], wc[3], 1)
        end
    end
end

-- v: red dots lit (may be a hidden value); white: small dots lit on the inner three (nil = none)
SetPoints = function(v, white)
    for i = 1, MAX do
        local d = dots[i]
        if d.white then pcall(d.white.SetValue, d.white, white or 0) end
        -- the empty frame (dark middle and ring) of all five dots is always drawn, so the row
        -- is there from the moment combat starts; only the fill and glow follow your points
        pcall(d.bg.SetValue, d.bg, MAX)
        pcall(d.ring.SetValue, d.ring, MAX)
        pcall(d.edge.SetValue, d.edge, MAX)
        for _, layer in ipairs({ d.glow, d.fill }) do
            pcall(layer.SetValue, layer, v)     -- hidden values go straight in
        end
    end
end

local placedKey, styleGen = nil, 0
local function Rgb(c)
    if type(c) ~= "table" then return "-" end
    return ("%s,%s,%s"):format(tostring(c[1] or c.r), tostring(c[2] or c.g), tostring(c[3] or c.b))
end
local function Update()
    if not holder or not db then return end
    mode = Mode()
    if not db.enabled or not mode then holder:Hide(); return end
    if db.combatOnly ~= false and not previewing and _G.UnitAffectingCombat and not UnitAffectingCombat("player") then
        holder:Hide(); return
    end

    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
        and select(2, pcall(C_NamePlate.GetNamePlateForUnit, "target"))
    if type(plate) ~= "table" or (plate.IsForbidden and plate:IsForbidden()) then
        holder:Hide(); return
    end

    -- searching the plate is cheap, but no need to do it ten times a second
    if plate ~= cachePlate or GetTime() - cacheAge > 1 or (cacheHow == "sktools") ~= (ns.Plates and ns.Plates.Frame(plate) ~= nil) then
        cacheAnchor, cacheHow = Anchor(plate, "target")
        cachePlate, cacheAge = plate, GetTime()
    end
    local anchor, how = cacheAnchor, cacheHow
    anchorInfo = how
    side = (how == "sktools") and "left" or "right"
    if how ~= "sktools" then boxW, boxH = BoxSize(anchor, how) end
    -- placed and styled again only when something about it changed (not ten times a second)
    local LE = (ns.Plates and ns.Plates.LeftEdge and ns.Plates.LeftEdge()) or 0
    local level = (plate:GetFrameLevel() or 1) + 20
    local key = table.concat({ tostring(anchor), how, tostring(plate), plate:GetFrameStrata() or "MEDIUM", level,
        db.x, db.y, LE, db.size, db.radius, boxW, boxH, styleGen, tostring(mode), tostring(previewing),
        tostring(db.tight), tostring(db.bgAlpha), tostring(db.edge), tostring(db.glow), Rgb(db.color), Rgb(db.growlColor) }, "|")
    if key ~= placedKey then
        placedKey = key
        holder:SetParent(how == "sktools" and anchor or plate)
        holder:SetFrameStrata(plate:GetFrameStrata() or "MEDIUM")
        holder:SetFrameLevel(level)
        holder:ClearAllPoints()
        if how == "sktools" then
            -- our plate: hugging the left end of the bar, scaled with it
            -- (past the level box, which stands left of the bar)
            holder:SetPoint("CENTER", anchor, "LEFT", OwnX(db.x, db.y) - LE, db.y)
        elseif how == "health bar" then
            -- no level found: sit just past the bar's right end
            holder:SetPoint("CENTER", anchor, "RIGHT", 16 + db.x, db.y)
        else
            holder:SetPoint("CENTER", anchor, "CENTER", db.x, db.y)
        end
        Style()
    end

    if mode == "growl" then
        if previewing then
            SetPoints(2, 2)                  -- a mid-countdown look on the sample
            growlInfo = "preview"
        else
            growlInfo = Growl()
        end
        holder:Show()
        return
    end
    if previewing then
        SetPoints(3)
    else
        local v = RawPoints()
        if v == nil then holder:Hide(); return end
        SetPoints(v)
    end
    holder:Show()
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

local driver = CreateFrame("Frame")
local acc = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc >= 0.1 then acc = 0; Update() end      -- cheap safety net
end)
driver:Hide()

driver:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "PLAYER_TARGET_CHANGED",
                     "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UPDATE_SHAPESHIFT_FORM",
                     "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "SPELL_UPDATE_COOLDOWN" }) do
    pcall(driver.RegisterEvent, driver, e)
end
-- power: yours only (combo points are yours). Every unit's power ticks would otherwise each run a
-- full update - hundreds a second in a crowd.
for _, e in ipairs({ "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT" }) do
    pcall(driver.RegisterUnitEvent or driver.RegisterEvent, driver, e, "player")
end
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" then cachePlate = nil end
    if event == "PLAYER_LOGIN" then
        -- kept inside the range settings
        local root = ns.InitDB().range
        root.combo = root.combo or {}
        DeepFill(root.combo, ns.COMBO_DEFAULTS)
        local c = root.combo.color
        if type(c) == "table" and math.abs((c[1] or 0) - OLD_RED[1]) < 0.001
            and math.abs((c[2] or 0) - OLD_RED[2]) < 0.001 and math.abs((c[3] or 0) - OLD_RED[3]) < 0.001 then
            root.combo.color = { ns.COMBO_DEFAULTS.color[1], ns.COMBO_DEFAULTS.color[2], ns.COMBO_DEFAULTS.color[3] }
            if root.combo.glow == 0.9 then root.combo.glow = ns.COMBO_DEFAULTS.glow end
        end
        db = root.combo
        Build()
        Style()
        driver:Show()
    end
    Update()
end)

----------------------------------------------------------------------
-- For the options window / slash commands
----------------------------------------------------------------------

ns.Combo = {
    Settings = function() return db end,
    Refresh = function() styleGen = styleGen + 1; Style(); Update() end,
    Reset = function()
        local root = ns.InitDB().range
        root.combo = {}
        DeepFill(root.combo, ns.COMBO_DEFAULTS)
        db = root.combo
        Style(); Update()
    end,
    Preview = function(on) previewing = on and true or false; Update() end,
    Eligible = Eligible,
    Anchor = Anchor,        -- the level badge; the hunter crescent sits there too
    HealthBar = FindHealthBar,
    -- the level box (width, height) the dots and the Claw/Shred icons are arranged round
    Box = function() return boxW, boxH end,
    BoxSize = BoxSize,
    -- the cluster: how far above/below the badge centre the dots reach, and the middle dot's x
    Extent = function()
        if not db then return 20, 25 end
        local px, py, cx = ClusterPositions(db.size)
        if not px then return BASE_RY + db.radius + db.size / 2, BASE_RX + db.radius end
        return py[1] + db.size / 2, cx
    end,
    -- how far left of the bar's left end the cluster reaches (middle dot's outer edge)
    LeftReach = function()
        local s = db and db.size or 10
        local step = 2 * math.asin(math.min((s + TIGHT_GAP) / (2 * OWN_CURVE), 1))
        local bend = OWN_CURVE * (1 - math.cos(2 * step))
        -- and however far the cluster was moved left to clear the kill / loot boxes
        local pushed = db and (db.x or 0) - OwnX(db.x, db.y) or 0
        return LEFT_GAP + s / 2 + bend + s / 2 + pushed
    end,
    -- for the settings sample: the curve on our plates, and the cluster's x once clear of the boxes
    OwnCurve = OWN_CURVE,
    OwnX = function(x, y) return OwnX(x, y) end,
    Dots = function() return dots end,
    ResetCurves = function() litCurve, whiteCurve = nil, nil end,
    Mode = Mode,
    Debug = function(print)
        local v, src = RawPoints()
        local shown = (v == nil) and "nil" or (issecret(v) and "hidden" or tostring(v))
        local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
            and select(2, pcall(C_NamePlate.GetNamePlateForUnit, "target"))
        print(("combo: enabled=%s, mode=%s, points=%s (via %s), target plate=%s, anchored to %s, shown=%s")
            :format(tostring(db and db.enabled), tostring(Mode()), shown, tostring(src),
                    tostring(type(plate) == "table"), anchorInfo, tostring(holder and holder:IsShown())))
        if Mode() == "growl" then
            print(("  Growl: id %s, %s; curves %s"):format(tostring(GrowlId()), tostring(growlInfo), Curves() and "yes" or "none"))
        end
    end,
}

-- timed by /skt cpu
ns.Profile("Combo points", driver)
