--[[-------------------------------------------------------------------------
  SKTools - Hunter range crescent on the target's nameplate

  Replaces the old vertical range bar (test). A crescent moon hugs the level
  badge on your target's nameplate, in the spot the combo points use for
  Rogues and Druids, and has two states:

      melee range   red     (and it pulses)
      shoot range   green   (solid, steady)

  In the dead zone and out past shoot range there is no crescent at all.
  The pulse is there so the two differ by more than colour; "Pulse in melee"
  in the settings switches it off.

  A thin silver rim (the classic rare-elite trim) runs round the moon, inside
  the dark surround; "Silver border" in the settings switches it off.
  Blizzard draws the shared crowd-control icon right under the level badge,
  where the crescent sits. While the crescent is up, that icon is moved to
  its right ("Move CC icons aside" in the settings), and handed back to
  Blizzard's own position when the crescent hides.
  Melee and shoot range also glow (grey does not). The crescent only shows
  for a Hunter with a bow equipped.

  The zone itself comes from the range detection in
  Modules/HunterBar/RangeBar.lua, unchanged.
---------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

local MEDIA = ns.MEDIA

ns.CRESCENT_DEFAULTS = {
    enabled = true,
    size    = 34,        -- pixels; grows and shrinks around its centre
    x       = -3,        -- offset from the level badge
    y       = 0,
    shapes  = true,      -- pulse in melee range
    border  = true,      -- classic silver rim round the moon
    moveCC  = true,      -- push Blizzard's shared crowd-control icon out beside the moon
    dome    = true,      -- dark shading under the rim, full colour along the middle
    glow    = true,      -- soft glow in the zone colour (melee and shoot range)
    edge    = 1.0,       -- dark outline round the crescent, for bright ground; 0 = off
    colors  = {
        melee = { 0.92, 0.14, 0.12 },
        shoot = { 0.20, 0.85, 0.30 },
    },
}
-- range zone (from RangeBar.lua) -> colour key; any other zone hides the crescent
local ZONE_KEY = { MELEE = "melee", SHOOT = "shoot" }
ns.CRESCENT_COLOR_KEYS = {
    { "shoot", "Shoot range" },
    { "melee", "Melee range" },
}

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

local db
-- Smooth curves: no snapping to the pixel grid (that is what makes round edges jagged) and
-- the smoothest filtering the game offers. Each call is guarded for clients without it.
local function Smooth(tex, name)
    pcall(tex.SetTexture, tex, MEDIA .. name, nil, nil, "TRILINEAR")
    if not tex.GetTexture or tex:GetTexture() == nil then tex:SetTexture(MEDIA .. name) end
    if tex.SetSnapToPixelGrid then pcall(tex.SetSnapToPixelGrid, tex, false) end
    if tex.SetTexelSnappingBias then pcall(tex.SetTexelSnappingBias, tex, 0) end
end

local holder, edge, rim, glow, fill, shade, pulse
local artMode = "moon"       -- "moon" beside the old level badge, "arc" on the left of our own bar
local ART = {
    moon = { edge = "CrescentEdge", rim = "CrescentRim", glow = "CrescentGlow", fill = "Crescent", shade = "CrescentShade" },
    arc  = { edge = "ArcCrescentEdge", rim = "ArcCrescentRim", glow = "ArcCrescentGlow", fill = "ArcCrescent", shade = "ArcCrescentShade" },
}
local function SetArt(mode)
    if artMode == mode or not holder then return end
    artMode = mode
    local a = ART[mode]
    Smooth(edge, a.edge); Smooth(rim, a.rim); Smooth(glow, a.glow); Smooth(fill, a.fill); Smooth(shade, a.shade)
end
local previewing = false
local cachePlate, cacheAnchor, cacheHow, cacheAge = nil, nil, nil, 0
local eligible, eligibleAge = false, -100
local state = "not run yet"       -- for /skr crescent debug

local function Build()
    holder = CreateFrame("Frame", "SKToolsCrescent", UIParent)
    holder:SetSize(1, 1)
    holder:EnableMouse(false)
    holder:Hide()

    -- dark surround so it reads over any background
    -- (below the rim: the black only ever shows outside the silver line, never over it)
    edge = holder:CreateTexture(nil, "ARTWORK", nil, -1)
    Smooth(edge, "CrescentEdge")
    edge:SetVertexColor(0, 0, 0, 0.8)
    edge:SetPoint("CENTER")
    -- classic silver rim, between the dark surround and the moon
    rim = holder:CreateTexture(nil, "ARTWORK", nil, 0)
    Smooth(rim, "CrescentRim")
    rim:SetVertexColor(0.82, 0.84, 0.89, 1)
    rim:SetPoint("CENTER")
    -- soft glow behind the moon, added on top of whatever is behind it
    glow = holder:CreateTexture(nil, "ARTWORK", nil, -2)
    Smooth(glow, "CrescentGlow")
    glow:SetBlendMode("ADD")
    glow:SetPoint("CENTER")
    fill = holder:CreateTexture(nil, "ARTWORK", nil, 1)
    Smooth(fill, "Crescent")
    fill:SetPoint("CENTER")
    -- dome shading: black, strongest next to the rim, clear along the middle of the moon
    shade = holder:CreateTexture(nil, "ARTWORK", nil, 2)
    Smooth(shade, "CrescentShade")
    shade:SetVertexColor(0, 0, 0, 1)
    shade:SetPoint("CENTER")

    pulse = holder:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.4)
    a:SetSmoothing("IN_OUT")
end

-- Blizzard's crowd-control icon: plate.UnitFrame.AurasFrame.CrowdControlListFrame.
-- Blizzard re-anchors it on its own updates, so it is re-applied every tick
-- while the crescent is up, and its own points are kept to hand back.
local CC_GAP = 4
local ccSaved = setmetatable({}, { __mode = "k" })     -- cc frame -> Blizzard's points
local ccHeld, ccSize

local function ReleaseCC()
    local cc = ccHeld
    ccHeld = nil
    local pts = cc and ccSaved[cc]
    ccSaved[cc or 0] = nil
    if not pts then return end
    pcall(function()
        cc:ClearAllPoints()
        for _, p in ipairs(pts) do cc:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    end)
end

local function PushCC(plate)
    local uf = plate.UnitFrame
    local auras = type(uf) == "table" and uf.AurasFrame
    local cc = type(auras) == "table" and auras.CrowdControlListFrame
    if type(cc) ~= "table" then cc = nil end
    if cc ~= ccHeld then ReleaseCC() end
    if not cc then return end
    pcall(function()
        local _, rel = cc:GetPoint(1)
        if rel == holder then
            if ccHeld == cc and ccSize == db.size then return end      -- already placed
        else
            local pts = {}                                             -- Blizzard (re)anchored it: keep those
            for i = 1, cc:GetNumPoints() do
                local a, b, c, x, y = cc:GetPoint(i)
                pts[i] = { a, b, c, x, y }
            end
            ccSaved[cc] = pts
        end
        ccHeld, ccSize = cc, db.size
        cc:ClearAllPoints()
        cc:SetPoint("LEFT", holder, "CENTER", db.size * 0.46 + CC_GAP, 0)
    end)
end

local function Paint(zone)
    local key = ZONE_KEY[zone]
    local c = db.colors[key] or ns.CRESCENT_DEFAULTS.colors[key]
    local s = db.size
    if artMode == "arc" then
        -- the arc textures fill the holder, which is sized to them
        for _, t in ipairs({ edge, rim, glow, fill, shade }) do t:ClearAllPoints(); t:SetAllPoints(holder) end
    else
        for _, t in ipairs({ edge, rim, glow, fill, shade }) do t:ClearAllPoints(); t:SetPoint("CENTER") end
        edge:SetSize(s, s); rim:SetSize(s, s); fill:SetSize(s, s); shade:SetSize(s, s)
        glow:SetSize(s * 1.5, s * 1.5)       -- the texture keeps the moon at two thirds of its width
    end
    shade:SetShown(db.dome ~= false)
    rim:SetShown(db.border ~= false)
    edge:SetVertexColor(0, 0, 0, db.edge or 1)
    edge:SetShown((db.edge or 0) > 0)
    glow:SetVertexColor(c[1], c[2], c[3], 0.45)
    glow:SetShown(db.glow ~= false)
    fill:SetVertexColor(c[1], c[2], c[3], 1)

    if db.shapes and zone == "MELEE" then
        if not pulse:IsPlaying() then pulse:Play() end
    else
        pulse:Stop()
        holder:SetAlpha(1)
    end
end

local function Hide(why)
    state = why
    ReleaseCC()
    if holder:IsShown() then
        pulse:Stop()
        holder:Hide()
    end
end

local function Update()
    if not holder or not db then return end
    if not db.enabled then return Hide("turned off in settings") end
    local RB = ns.RangeBar
    if not RB then return Hide("range detection not loaded") end

    local zone
    if previewing then
        zone = "SHOOT"
    else
        -- Hunter with a bow; checked once a second, not every frame
        local now = GetTime()
        if now - eligibleAge > 1 then eligible, eligibleAge = RB.HasBow(), now end
        if not eligible then return Hide("needs a Hunter with a bow equipped") end
        if not RB.ShouldShow("target") then return Hide("no attackable target") end
        zone = RB.Zone("target")
        if not ZONE_KEY[zone] then return Hide("zone " .. tostring(zone) .. " (no crescent: only shoot range and melee range show one)") end
    end

    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
        and select(2, pcall(C_NamePlate.GetNamePlateForUnit, "target"))
    if type(plate) ~= "table" or (plate.IsForbidden and plate:IsForbidden()) then
        return Hide("zone " .. tostring(zone) .. ", but the target has no nameplate")
    end

    -- same anchor as the combo points: the level badge, found once a second
    if plate ~= cachePlate or GetTime() - cacheAge > 1 or (cacheHow == "sktools") ~= (ns.Plates and ns.Plates.Frame(plate) ~= nil) then
        cacheAnchor, cacheHow = ns.Combo.Anchor(plate, "target")
        cachePlate, cacheAge = plate, GetTime()
    end
    local ours = cacheHow == "sktools"
    SetArt(ours and "arc" or "moon")
    holder:SetParent(ours and cacheAnchor or plate)
    holder:SetFrameStrata(plate:GetFrameStrata() or "MEDIUM")
    holder:SetFrameLevel((plate:GetFrameLevel() or 1) + 20)
    holder:ClearAllPoints()
    if ours then
        -- on the same arc as the combo points: its right edge is the left end of the bar
        local k = db.size / 46
        holder:SetSize(32 * k, 64 * k)
        holder:SetPoint("RIGHT", cacheAnchor, "LEFT", db.x - ((ns.Plates and ns.Plates.LeftEdge and ns.Plates.LeftEdge()) or 0), db.y)      -- past the level box
    elseif cacheHow == "health bar" then
        -- no level found: sit just past the bar's right end
        holder:SetPoint("CENTER", cacheAnchor, "RIGHT", 16 + db.x, db.y)
    else
        holder:SetPoint("CENTER", cacheAnchor, "CENTER", db.x, db.y)
    end
    if ours then ReleaseCC() elseif db.moveCC ~= false then PushCC(plate) else ReleaseCC() end
    Paint(zone)
    holder:Show()
    state = "showing " .. zone .. ", anchored to " .. tostring(cacheHow)
end

local driver = CreateFrame("Frame")
local acc = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.05 then return end       -- the same pace the range bar ran at
    acc = 0
    Update()
end)
driver:Hide()

driver:RegisterEvent("PLAYER_LOGIN")
pcall(driver.RegisterEvent, driver, "PLAYER_TARGET_CHANGED")
pcall(driver.RegisterEvent, driver, "PLAYER_EQUIPMENT_CHANGED")
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- kept inside the range settings, next to the tint and the combo points
        local root = ns.InitDB().range
        root.crescent = root.crescent or {}
        DeepFill(root.crescent, ns.CRESCENT_DEFAULTS)
        db = root.crescent
        Build()
        driver:Show()
    end
    cachePlate = nil
    eligibleAge = -100
    Update()
end)

ns.Crescent = {
    ReleaseCC = ReleaseCC,     -- hand Blizzard's CC icon back (our plates take it over)
    Settings = function() return db end,
    Refresh = Update,
    Reset = function()
        local root = ns.InitDB().range
        root.crescent = {}
        DeepFill(root.crescent, ns.CRESCENT_DEFAULTS)
        db = root.crescent
        Update()
    end,
    -- show it green on the target while the settings are open, on any class
    Preview = function(on) previewing = on and true or false; Update() end,
    Debug = function(print)
        print(("crescent: enabled=%s, %s"):format(tostring(db and db.enabled), state))
    end,
}

-- timed by /skt cpu
ns.Profile("Hunter crescent", driver)
