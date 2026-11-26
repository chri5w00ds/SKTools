--[[-------------------------------------------------------------------------
  SKTools - nameplates (replaces the Blizzard look)

  Every enemy nameplate is redrawn as a small set of frames of our own:

      [ level ] [ health bar: name on the left, percent over value on the right ] [ ! ]
                [ spell icon | cast bar: spell name                              ]
      kill count above the level box,
      loot count below it

  Colour: bosses purple, casters light blue, everything else green. Players use
  their class colour, friendly units grey-blue, tapped mobs grey. Your target is
  drawn bigger with a white border.

  Blizzard's own plate is not replaced, only quietened: its health bar, name,
  cast bar, level and highlights are made invisible (and kept that way), while its
  buff/debuff rows, crowd-control icon, raid marker and widgets stay as they were.
  "Use these nameplates" in the settings switches everything back.

  Forever can hide health, cast and name values from addons. Health and the cast
  timer are therefore only ever handed to status bars, and text is only ever set
  with SetText / SetFormattedText, never compared or calculated with.

  The combo points, Hunter crescent, Claw/Shred and Bite icons (Combo.lua,
  Crescent.lua, Feral.lua) hang on the left of the bar, and the quest counters and
  the quest-starter icon (Marks.lua) are drawn here; they find us through ns.Plates.
---------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

local MEDIA = ns.MEDIA
local SOLID = "Interface\\Buttons\\WHITE8X8"
local FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

ns.PLATES_DEFAULTS = {
    enabled     = true,
    width       = 220,
    height      = 28,
    scale       = 0.8,           -- everything on the plates, overall
    targetScale = 1.2,           -- your target is drawn this much bigger
    dimAlpha    = 0.7,           -- plates that are neither your target nor the soft target: a little see-through
    x           = 0,
    y           = 0,
    levelWidth  = 34,
    levelGap    = 0,             -- bar to level box: 0 = joined to the bar
    eliteIcon   = true,          -- the game's elite dragon left of the name: gold = elite or boss, silver = rare
    levelColors = true,          -- the level number coloured like the game does: red, orange, yellow, green; white = no XP
    gcd         = true,          -- GCD meter in your target's level box: a dark radial sweep while it runs
    gcdDark     = 85,            -- how dark the sweep is (%); a white edge rides it and the box gets a white frame
    cast        = true,
    castHeight  = 18,
    castGap     = 2,
    fontSize    = 11,
    classColors = true,          -- enemy players in their class colour
    classSet    = "auto",        -- which class the designer shows: "auto" = this character's own, or DRUID / ROGUE / HUNTER (subSet, unset by default, picks its subclass)
    berry       = false,         -- Berry Mode: every enemy bar is red, whatever it is
    berryColor  = { 0.80, 0.10, 0.12 },
    colors = {
        melee    = { 0.25, 0.62, 0.30 },
        caster   = { 0.45, 0.72, 0.92 },
        boss     = { 0.62, 0.38, 0.88 },
        friendly = { 0.55, 0.62, 0.72 },
        neutral  = { 0.86, 0.78, 0.52 },     -- soft yellow with a hint of beige
        tapped   = { 0.50, 0.50, 0.50 },
    },
    castColor   = { 0.95, 0.78, 0.25 },     -- yellow
    castMeColor = { 0.88, 0.30, 0.06 },     -- deep orange: the cast is aimed at you
    aggro       = true,                     -- the bar turns red while the mob is on you
    aggroFlash  = true,                     -- ...and flashes three times when it gets on you
    aggroColor  = { 0.85, 0.10, 0.08 },
    auras       = true,                     -- your debuffs on the target, above the bar
    auraSize    = 20,
    auraMax     = 8,
    auraGap     = 2,
    blink       = true,                     -- an icon blinks for the last seconds of its time
    blinkSeconds = 3,
    debuffX     = 0,                        -- Blizzard's debuff row, when it stands in: nudge left or right
    swing       = true,                     -- swing timer strip above the target's bar, under the debuffs
    swingHeight = 4,
    swingColor  = { 0.10, 0.10, 0.11 },     -- the strip itself: one colour, a little see-through
    swingAlpha  = 0.8,
    swingRed    = { 0.88, 0.15, 0.12 },     -- ranged: the last moments of the swing (stand still)
    swingWindow = 0.5,                      -- ...how long that is, in seconds
    hideBlizzAuras = true,                  -- Blizzard's own buff and debuff rows are hidden (the CC icon stays)
}
-- NPC classes that mean "casts spells": everything else counts as melee
local CASTER_CLASS = { MAGE = true, WARLOCK = true, PRIEST = true, SHAMAN = true, DRUID = true, EVOKER = true }

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

-- is there a value at all (a hidden one counts)
local function Present(v)
    local ok, r = pcall(function() return v ~= nil end)
    if not ok then return true end
    return r
end

local db
local lateLog          -- set in "Showing and hiding"
local LogPlate         -- set in "Events"
local LevelColor       -- set beside Static
local EliteIcon        -- set beside Static
local ReadoutSize      -- set beside Layout
-- the swing strip is pulled in at each end so its white outline's outer edge lines up with where the
-- bar's rounded corners meet its flat top (PlateMask/PlateBorder: 4 of 512 px), plus the outline's 1
local function SwingInset(w) return w * 4 / 512 + 1 end

local function Clamp(v) return math.max(0, math.min(1, v)) end

-- light at the top, dark at the bottom, like the resource bars
local function Gradient(tex, c, lift)
    lift = lift or 1
    local top = { Clamp(c[1] * 1.15 + 0.12), Clamp(c[2] * 1.15 + 0.12), Clamp(c[3] * 1.15 + 0.12) }
    local bot = { c[1] * 0.55 * lift, c[2] * 0.55 * lift, c[3] * 0.55 * lift }
    local ok = false
    if tex.SetGradient and _G.CreateColor then
        ok = pcall(tex.SetGradient, tex, "VERTICAL",
            CreateColor(bot[1], bot[2], bot[3], 1), CreateColor(top[1], top[2], top[3], 1))
    end
    if not ok then tex:SetVertexColor(c[1], c[2], c[3], 1) end
end

local function Lines(frame, r, g, b, a, t)
    local l = {}
    for i = 1, 4 do l[i] = frame:CreateTexture(nil, "OVERLAY"); l[i]:SetColorTexture(r, g, b, a) end
    l[1]:SetPoint("TOPLEFT"); l[1]:SetPoint("TOPRIGHT"); l[1]:SetHeight(t)
    l[2]:SetPoint("BOTTOMLEFT"); l[2]:SetPoint("BOTTOMRIGHT"); l[2]:SetHeight(t)
    l[3]:SetPoint("TOPLEFT"); l[3]:SetPoint("BOTTOMLEFT"); l[3]:SetWidth(t)
    l[4]:SetPoint("TOPRIGHT"); l[4]:SetPoint("BOTTOMRIGHT"); l[4]:SetWidth(t)
    return l
end

local function Text(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size, "OUTLINE")
    fs:SetTextColor(1, 1, 1, 1)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end


----------------------------------------------------------------------
-- What colour is this unit
----------------------------------------------------------------------

local function Classify(unit)
    if UnitIsPlayer and Plain(UnitIsPlayer(unit)) then
        if db.classColors ~= false then
            local _, token = UnitClass(unit)
            token = Plain(token)
            local cc = token and _G.RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
            if cc then return { cc.r, cc.g, cc.b }, "player" end
        end
    end
    local attackable = UnitCanAttack and Plain(UnitCanAttack("player", unit))
    if attackable == false then return db.colors.friendly, "friendly" end
    if UnitIsTapDenied and Plain(UnitIsTapDenied(unit)) then return db.colors.tapped, "tapped" end
    -- neutral: attackable, but not hostile until you pull it
    local react = UnitReaction and Plain(UnitReaction(unit, "player"))
    if react == 4 then return db.colors.neutral, "neutral" end
    local cls = UnitClassification and Plain(UnitClassification(unit))
    local lvl = Plain(UnitLevel(unit))
    if cls == "worldboss" or lvl == -1 then return db.colors.boss, "boss" end
    local _, token = UnitClass(unit)
    token = Plain(token)
    if token and CASTER_CLASS[token] then return db.colors.caster, "caster" end
    return db.colors.melee, "melee"
end

----------------------------------------------------------------------
-- Quietening Blizzard's plate
----------------------------------------------------------------------

local AuraLift
local active = {}                                    -- unit token -> plate object
local plates = setmetatable({}, { __mode = "k" })    -- plate -> our object
local hidden = setmetatable({}, { __mode = "k" })    -- Blizzard object -> our plate object (while quietened)

local function Quiet(obj, pl)
    if not obj or not obj.SetAlpha then return end
    if hidden[obj] == nil then
        hidden[obj] = pl
        if _G.hooksecurefunc then
            hooksecurefunc(obj, "SetAlpha", function(self, a)
                local p = hidden[self]
                if p and p.quiet and a ~= 0 and not self.ownBusy then
                    self.ownBusy = true
                    self:SetAlpha(0)
                    self.ownBusy = false
                end
            end)
        end
    end
    hidden[obj] = pl
    obj.ownBusy = true
    obj:SetAlpha(0)
    obj.ownBusy = false
end

-- how far above the bar the debuff row starts: clear of the swing timer strip when that is on
AuraLift = function()
    if db.swing == false then return 2 end
    return 2 + (db.swingHeight or 4) + 3
end

-- hands one Blizzard object back (alpha restored, no longer kept hidden)
local function Unquiet(obj)
    if hidden[obj] then
        hidden[obj] = false
        obj.ownBusy = true
        pcall(obj.SetAlpha, obj, 1)
        obj.ownBusy = false
    end
end

local function QuietPlate(pl)
    local plate = pl.plate
    local uf = plate.UnitFrame
    if type(uf) ~= "table" then return end
    pl.quiet = true
    local keep = {}
    for _, k in ipairs({ "AurasFrame", "WidgetContainer", "RaidTargetFrame", "BuffFrame", "ClassificationFrame" }) do
        if type(uf[k]) == "table" then keep[uf[k]] = true end
    end
    for _, ch in ipairs({ uf:GetChildren() }) do
        if not keep[ch] then Quiet(ch, pl) end
    end
    for _, r in ipairs({ uf:GetRegions() }) do Quiet(r, pl) end
    -- Blizzard's own elite dragon: hidden while ours shows, so a mob doesn't get two; given back
    -- when ours is switched off
    local cf = uf.ClassificationFrame
    if type(cf) == "table" then
        if db.eliteIcon ~= false then Quiet(cf, pl) else Unquiet(cf) end
    end
    -- Blizzard's own buff and debuff rows: ours replace them; only the crowd-control icon stays
    local af = uf.AurasFrame
    if type(af) == "table" and db.hideBlizzAuras ~= false then
        local ccf = af.CrowdControlListFrame
        -- when the game will not tell addons what auras a unit has, Blizzard's own debuff row is
        -- the only way to see them: it is left showing
        local dbf = pl.auraBlocked and db.auras ~= false and af.DebuffListFrame or nil
        for _, ch in ipairs({ af:GetChildren() }) do
            if ch ~= ccf and ch ~= dbf then Quiet(ch, pl) end
        end
        for _, k in ipairs({ "DebuffListFrame", "BuffListFrame" }) do
            if type(af[k]) == "table" and af[k] ~= ccf and af[k] ~= dbf then Quiet(af[k], pl) end
        end
        if dbf then Unquiet(dbf) end
    end
    -- a few known ones that live on the plate itself rather than the unit frame
    for _, k in ipairs({ "name", "healthBar", "castBar", "HealthBarsContainer", "LevelFrame", "selectionHighlight" }) do
        if type(uf[k]) == "table" and not keep[uf[k]] then Quiet(uf[k], pl) end
    end
end

local function RestorePlate(pl)
    pl.quiet = false
    for obj, p in pairs(hidden) do
        if p == pl then
            obj.ownBusy = true
            pcall(obj.SetAlpha, obj, 1)
            obj.ownBusy = false
            hidden[obj] = false
        end
    end
end

-- Blizzard's own debuff row, when it is the one showing: above the bar at the left if it lets us
local function PlaceBlizzDebuffs(pl)
    if not pl.auraBlocked or db.auras == false then return end
    local uf = pl.plate.UnitFrame
    local af = type(uf) == "table" and uf.AurasFrame
    local dl = type(af) == "table" and af.DebuffListFrame
    if type(dl) ~= "table" then return end
    local function put()
        dl.ownPlacing = true
        local ok, err = pcall(function()
            dl:ClearAllPoints()
            dl:SetPoint("BOTTOMLEFT", pl.frame, "TOPLEFT", db.debuffX or 0, AuraLift())
        end)
        pl.dlMove = ok and "accepted" or ("refused: " .. tostring(err))
        dl.ownPlacing = false
    end
    -- Blizzard lays its rows out again now and then: whenever it sets the row's position, ours goes back
    if _G.hooksecurefunc and not dl.ownHooked then
        dl.ownHooked = true
        pcall(hooksecurefunc, dl, "SetPoint", function(self)
            if not self.ownPlacing and pl.auraBlocked and pl.unit and plates[pl.plate] == pl then
                self.ownPlacing = true
                pcall(function()
                    self:ClearAllPoints()
                    self:SetPoint("BOTTOMLEFT", pl.frame, "TOPLEFT", db.debuffX or 0, AuraLift())
                end)
                self.ownPlacing = false
            end
        end)
    end
    put()
    -- Blizzard's row is anchored to the left end of ITS health bar, which is narrower than ours and
    -- hidden. If the row will not be moved, make that bar the same size as ours instead, so the
    -- row's left end is ours too.
    local box = uf.HealthBarsContainer
    if type(box) == "table" and box.SetSize and pl.frame.GetEffectiveScale then
        local function fit(self)
            local fe, be = pl.frame:GetEffectiveScale(), self:GetEffectiveScale()
            if type(fe) ~= "number" or type(be) ~= "number" or be <= 0 then return end
            -- on-screen size of our bar, in this frame's own units
            local w, h = db.width * fe / be, db.height * fe / be
            self.ownFitting = true
            local ok, err = pcall(self.SetSize, self, w, h)
            pl.boxFit = ok and ("accepted, %.0f x %.0f"):format(w, h) or ("refused: " .. tostring(err))
            self.ownFitting = false
        end
        fit(box)
        if _G.hooksecurefunc and not box.ownHooked then
            box.ownHooked = true
            for _, fn in ipairs({ "SetSize", "SetWidth", "SetHeight" }) do
                if box[fn] then
                    pcall(hooksecurefunc, box, fn, function(self)
                        if not self.ownFitting and pl.auraBlocked and pl.unit and plates[pl.plate] == pl then fit(self) end
                    end)
                end
            end
        end
    end
end

-- Blizzard's shared crowd-control icon stays, but moves to sit under our cast bar
local ccSaved = setmetatable({}, { __mode = "k" })
local function PlaceCC(pl)
    -- first, and on its own: in combat the game refuses to let addons measure nameplate pieces
    -- ("Can't measure restricted regions"), and nothing below may stop this from running
    PlaceBlizzDebuffs(pl)
    local uf = pl.plate.UnitFrame
    local auras = type(uf) == "table" and uf.AurasFrame
    local cc = type(auras) == "table" and auras.CrowdControlListFrame
    if type(cc) ~= "table" then return end
    -- remember where Blizzard had it, when the game lets us look (it does not in combat)
    if pl.cc ~= cc then
        -- the Feral icons or the crescent may be holding it (they move it on plates that are not
        -- ours): they put it back first, so what we remember is Blizzard's own spot
        for _, m in ipairs({ ns.Feral, ns.Crescent }) do
            if m and m.ReleaseCC then pcall(m.ReleaseCC) end
        end
        pcall(function()
            local _, rel = cc:GetPoint(1)
            if rel ~= pl.frame then
                local pts = {}
                for i = 1, cc:GetNumPoints() do
                    local a, b, c, x, y = cc:GetPoint(i)
                    pts[i] = { a, b, c, x, y }
                end
                ccSaved[cc] = pts
            end
        end)
    end
    pl.cc = cc
    pcall(function()
        cc:ClearAllPoints()
        -- over the right-hand end of the cast bar, whether or not anything is being cast
        cc:SetPoint("RIGHT", pl.frame, "BOTTOMRIGHT", -2, -(db.castGap + db.castHeight / 2))
        if cc.SetFrameLevel then cc:SetFrameLevel(pl.cast:GetFrameLevel() + 10) end
    end)
end
local function ReleaseCC(pl)
    local cc = pl.cc
    pl.cc = nil
    local pts = cc and ccSaved[cc]
    ccSaved[cc or 0] = nil
    if not pts then return end
    pcall(function()
        cc:ClearAllPoints()
        for _, p in ipairs(pts) do cc:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    end)
end

----------------------------------------------------------------------
-- Building one plate
----------------------------------------------------------------------

local function Create(plate)
    local pl = { plate = plate }
    local f = CreateFrame("Frame", nil, plate)
    f:SetFrameLevel((plate:GetFrameLevel() or 1) + 10)
    f:EnableMouse(false)
    pl.frame = f

    pl.bar = CreateFrame("StatusBar", nil, f)
    pl.bar:SetAllPoints()
    pl.bar:SetStatusBarTexture(SOLID)
    pl.bar:SetMinMaxValues(0, 1)
    pl.bar:SetValue(1)
    pl.bar:SetFrameLevel(f:GetFrameLevel() + 1)

    -- the dark background lives on the bar's own frame, above the level box, so the bar
    -- sits on top of the box; rounded corners come from one mask over background and fill
    pl.bg = pl.bar:CreateTexture(nil, "BACKGROUND")
    pl.bg:SetTexture(SOLID)
    pl.bg:SetAllPoints()
    Gradient(pl.bg, { 0.25, 0.25, 0.25 }, 0.5)
    pl.barMask = pl.bar:CreateMaskTexture()
    pl.barMask:SetTexture(MEDIA .. "PlateMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    pl.barMask:SetAllPoints()
    pl.bg:AddMaskTexture(pl.barMask)
    local barTex = pl.bar:GetStatusBarTexture()
    if barTex then barTex:AddMaskTexture(pl.barMask) end

    -- aggro: a red copy of the bar over the colour, shown while the mob is on you ...
    pl.red = CreateFrame("StatusBar", nil, f)
    pl.red:SetAllPoints()
    pl.red:SetStatusBarTexture(SOLID)
    pl.red:SetMinMaxValues(0, 1)
    pl.red:SetValue(1)
    pl.red:SetFrameLevel(f:GetFrameLevel() + 2)
    pl.red:SetAlpha(0)
    pl.redMask = pl.red:CreateMaskTexture()
    pl.redMask:SetTexture(MEDIA .. "PlateMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    pl.redMask:SetAllPoints()
    local redTex = pl.red:GetStatusBarTexture()
    if redTex then redTex:AddMaskTexture(pl.redMask) end
    -- ... and a bright flash over it that blinks three times when the mob gets on you
    local fl = CreateFrame("Frame", nil, f)
    fl:SetAllPoints()
    fl:SetFrameLevel(f:GetFrameLevel() + 3)
    pl.flash = fl:CreateTexture(nil, "OVERLAY")
    pl.flash:SetTexture(SOLID)
    pl.flash:SetAllPoints()
    pl.flash:SetVertexColor(1, 0.45, 0.4, 1)
    pl.flash:SetBlendMode("ADD")
    pl.flash:SetAlpha(0)
    pl.flashMask = fl:CreateMaskTexture()
    pl.flashMask:SetTexture(MEDIA .. "PlateMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    pl.flashMask:SetAllPoints()
    pl.flash:AddMaskTexture(pl.flashMask)
    pl.flashAnim = pl.flash:CreateAnimationGroup()
    for i = 1, 6 do
        local a = pl.flashAnim:CreateAnimation("Alpha")
        a:SetOrder(i)
        a:SetDuration(0.12)
        if i % 2 == 1 then a:SetFromAlpha(0); a:SetToAlpha(0.85) else a:SetFromAlpha(0.85); a:SetToAlpha(0) end
    end
    pl.flashAnim:SetScript("OnFinished", function() pl.flash:SetAlpha(0) end)
    -- Berry Mode: the bar is red already, so a red flash would not show. Instead the whole bar flashes
    -- white and its frame flashes thick white with it, three times, a little slower
    pl.berryFlash = fl:CreateTexture(nil, "OVERLAY", nil, 1)
    pl.berryFlash:SetTexture(SOLID)
    pl.berryFlash:SetAllPoints()
    pl.berryFlash:SetVertexColor(1, 1, 1, 1)
    pl.berryFlash:SetBlendMode("ADD")
    pl.berryFlash:SetAlpha(0)
    pl.berryFlash:AddMaskTexture(pl.flashMask)
    pl.berryEdge = fl:CreateTexture(nil, "OVERLAY", nil, 2)
    pl.berryEdge:SetTexture(MEDIA .. "PlateBorderThick")
    pl.berryEdge:SetVertexColor(1, 1, 1, 1)
    pl.berryEdge:SetPoint("TOPLEFT", fl, "TOPLEFT", -1, 1)
    pl.berryEdge:SetPoint("BOTTOMRIGHT", fl, "BOTTOMRIGHT", 1, -1)
    pl.berryEdge:SetAlpha(0)
    pl.berryAnims = {}
    for _, tex in ipairs({ pl.berryFlash, pl.berryEdge }) do
        local g = tex:CreateAnimationGroup()
        for i = 1, 6 do
            local a = g:CreateAnimation("Alpha")
            a:SetOrder(i)
            a:SetDuration(0.15)
            if i % 2 == 1 then a:SetFromAlpha(0); a:SetToAlpha(1) else a:SetFromAlpha(1); a:SetToAlpha(0) end
        end
        g:SetScript("OnFinished", function() tex:SetAlpha(0) end)
        pl.berryAnims[#pl.berryAnims + 1] = g
    end

    pl.auras = {}

    -- swing timer: a thin strip over the bar (not over the level box) with a pip that travels along it
    local sw = CreateFrame("Frame", nil, f)
    sw:SetFrameLevel(f:GetFrameLevel() + 5)
    sw.bg = sw:CreateTexture(nil, "BACKGROUND"); sw.bg:SetAllPoints()
    sw.red = sw:CreateTexture(nil, "BORDER")
    sw.red:SetPoint("TOPLEFT"); sw.red:SetPoint("BOTTOMLEFT")
    -- a very thin white outline round the whole strip, just outside it (so the strip keeps its height)
    sw.lines = {}
    for i = 1, 4 do
        local l = sw:CreateTexture(nil, "ARTWORK", nil, -1)
        l:SetColorTexture(1, 1, 1, 0.9)
        sw.lines[i] = l
    end
    local T = 1
    local L = sw.lines
    L[1]:SetPoint("BOTTOMLEFT", sw, "TOPLEFT", -T, 0); L[1]:SetPoint("BOTTOMRIGHT", sw, "TOPRIGHT", T, 0); L[1]:SetHeight(T)
    L[2]:SetPoint("TOPLEFT", sw, "BOTTOMLEFT", -T, 0); L[2]:SetPoint("TOPRIGHT", sw, "BOTTOMRIGHT", T, 0); L[2]:SetHeight(T)
    L[3]:SetPoint("TOPRIGHT", sw, "TOPLEFT", 0, 0); L[3]:SetPoint("BOTTOMRIGHT", sw, "BOTTOMLEFT", 0, 0); L[3]:SetWidth(T)
    L[4]:SetPoint("TOPLEFT", sw, "TOPRIGHT", 0, 0); L[4]:SetPoint("BOTTOMLEFT", sw, "BOTTOMRIGHT", 0, 0); L[4]:SetWidth(T)
    -- the marker: a tall faceted diamond, its centre raised towards you (Media\SwingDiamond.tga, 64x128),
    -- drawn smooth and free of the pixel grid so it glides rather than steps
    sw.pip = sw:CreateTexture(nil, "OVERLAY")
    pcall(sw.pip.SetTexture, sw.pip, MEDIA .. "SwingDiamond", nil, nil, "TRILINEAR")
    if not sw.pip.GetTexture or sw.pip:GetTexture() == nil then sw.pip:SetTexture(MEDIA .. "SwingDiamond") end
    if sw.pip.SetSnapToPixelGrid then pcall(sw.pip.SetSnapToPixelGrid, sw.pip, false) end
    if sw.pip.SetTexelSnappingBias then pcall(sw.pip.SetTexelSnappingBias, sw.pip, 0) end
    sw:Hide()
    pl.swing = sw

    -- Blizzard enlarges the selected plate itself; the moment it does, ours is put right
    -- again instead of waiting for the next sweep
    if hooksecurefunc and plate.SetScale then
        pcall(hooksecurefunc, plate, "SetScale", function() if pl.unit and pl.applyScale then pl.applyScale() end end)
    end

    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f:GetFrameLevel() + 4)
    pl.top = top
    -- a thin black line just outside the white target border
    pl.outline = top:CreateTexture(nil, "BORDER")
    pl.outline:SetTexture(MEDIA .. "PlateOutline")
    pl.outline:SetVertexColor(0, 0, 0, 1)
    pl.outline:SetPoint("TOPLEFT", top, "TOPLEFT", -1, 1)
    pl.outline:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", 1, -1)
    pl.outline:Hide()
    pl.border = top:CreateTexture(nil, "OVERLAY")
    pl.border:SetAllPoints()
    pl.border:SetTexture(MEDIA .. "PlateBorder")
    pl.name = Text(top, 11, "LEFT")
    pl.elite = top:CreateTexture(nil, "OVERLAY", nil, 2)
    pl.elite:Hide()
    pl.eliteBack = top:CreateTexture(nil, "OVERLAY", nil, 1)     -- rare elite: the silver one behind, framing it
    pl.eliteBack:Hide()
    pl.pct = Text(top, 10, "RIGHT")

    -- level box: the level number, centred
    local lv = CreateFrame("Frame", nil, f)
    lv:SetFrameLevel(f:GetFrameLevel())     -- behind the bar
    lv.bg = lv:CreateTexture(nil, "BACKGROUND")
    lv.bg:SetTexture(SOLID); lv.bg:SetAllPoints()
    Gradient(lv.bg, { 0.25, 0.25, 0.25 }, 0.5)
    lv.lines = Lines(lv, 0.75, 0.77, 0.80, 1, 1)
    -- where it meets the bar: the box runs on a few pixels under the bar's left end, but only shows
    -- outside the bar's shape (an inverted copy of the bar's mask, laid over the bar; white beyond
    -- it). So it fills the bar's rounded corners - the top and bottom lines run straight on, the bar's
    -- own curved edge is the line between them - and nothing sits behind the bar to show through a
    -- faded plate. No right edge of its own.
    lv.join = lv:CreateMaskTexture()
    lv.joinOk = pcall(lv.join.SetTexture, lv.join, MEDIA .. "PlateMaskInv", "CLAMPTOWHITE", "CLAMPTOWHITE")
    if lv.joinOk then
        lv.join:SetAllPoints(pl.bar)
        lv.bg:AddMaskTexture(lv.join)
        lv.lines[1]:AddMaskTexture(lv.join); lv.lines[2]:AddMaskTexture(lv.join)
        lv.lines[4]:Hide()
    end
    -- GCD meter: a dark radial sweep over the box while your global cooldown runs, receding clockwise
    -- (as on SKTools-ESO's skill bars), with a white line on its edge and a white frame round the box.
    -- The game's own cooldown spiral draws it, so it runs from the
    -- game's timer when the numbers are hidden (in combat).
    local g = CreateFrame("Frame", nil, lv)
    pcall(g.SetClipsChildren, g, true)          -- the sweep stays inside the box
    local okS, sw = pcall(CreateFrame, "Cooldown", nil, g, "CooldownFrameTemplate")
    if not okS or not sw then sw = CreateFrame("Cooldown", nil, g) end
    sw:SetAllPoints(g)
    pcall(sw.SetDrawEdge, sw, true)             -- a white line rides the sweep's moving edge
    pcall(sw.SetDrawBling, sw, false)
    pcall(sw.SetHideCountdownNumbers, sw, true)
    pcall(sw.SetSwipeTexture, sw, SOLID)
    pcall(sw.SetEdgeTexture, sw, "Interface\\Cooldown\\edge")
    pcall(sw.SetEdgeColor, sw, 1, 1, 1, 1)
    g.sweep = sw
    g:Hide()
    lv.gcd = g
    -- and a white frame round the box while it runs, so the GCD shows from the corner of your eye
    g.ring = CreateFrame("Frame", nil, lv)
    g.ring.lines = Lines(g.ring, 1, 1, 1, 1, 2)
    g.ring:Hide()
    -- the level number sits above the meter
    lv.top = CreateFrame("Frame", nil, lv)
    lv.top:SetAllPoints()
    lv.top:SetFrameLevel(lv:GetFrameLevel() + 6)
    lv.text = Text(lv.top, 10, "CENTER")
    pl.lv = lv

    -- kill count above the level box, loot count below it
    local function Counter(icon)
        local c = CreateFrame("Frame", nil, f)
        c:SetFrameLevel(f:GetFrameLevel() + 2)
        c.bg = c:CreateTexture(nil, "BACKGROUND")
        c.bg:SetTexture(SOLID); c.bg:SetAllPoints()
        Gradient(c.bg, { 0.25, 0.25, 0.25 }, 0.5)
        c.lines = Lines(c, 0.75, 0.77, 0.80, 1, 1)
        c.icon = c:CreateTexture(nil, "ARTWORK")
        c.icon:SetTexture(MEDIA .. icon)
        c.text = Text(c, 10, "RIGHT")
        c:Hide()
        return c
    end
    pl.kill = Counter("Kill")
    pl.loot = Counter("Loot")

    pl.starter = f:CreateTexture(nil, "OVERLAY")
    pl.starter:SetTexture(MEDIA .. "Starter")
    pl.starter:Hide()

    -- cast bar under the health bar
    local c = CreateFrame("Frame", nil, f)
    c:SetFrameLevel(f:GetFrameLevel() + 2)
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetTexture(SOLID); c.bg:SetAllPoints()
    Gradient(c.bg, { 0.25, 0.25, 0.25 }, 0.5)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT"); c.icon:SetPoint("BOTTOMLEFT")
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.yellow = CreateFrame("StatusBar", nil, c)
    c.yellow:SetStatusBarTexture(SOLID)
    c.yellow:SetPoint("TOPLEFT", c.icon, "TOPRIGHT"); c.yellow:SetPoint("BOTTOMRIGHT")
    c.orange = CreateFrame("StatusBar", nil, c)
    c.orange:SetStatusBarTexture(SOLID)
    c.orange:SetPoint("TOPLEFT", c.icon, "TOPRIGHT"); c.orange:SetPoint("BOTTOMRIGHT")
    c.orange:SetFrameLevel(c.yellow:GetFrameLevel() + 1)
    c.lines = Lines(c, 0, 0, 0, 1, 1)
    local ct = CreateFrame("Frame", nil, c)
    ct:SetAllPoints(); ct:SetFrameLevel(c.orange:GetFrameLevel() + 2)
    c.name = Text(ct, 11, "LEFT")
    c.time = Text(ct, 11, "RIGHT")
    c:Hide()
    pl.cast = c

    plates[plate] = pl
    return pl
end

----------------------------------------------------------------------
-- Sizes, colours and contents
----------------------------------------------------------------------

-- text size for the health percentage: one less than the name's, and small enough to fit inside the
-- bar (about 1.15 x the size, outline included) with 3 px to spare top and bottom
ReadoutSize = function(h, fontSize)
    return math.max(7, math.min((fontSize or 11) - 1, math.floor((h - 6) / 1.15)))
end

local function Layout(pl)
    local w, h = db.width, db.height
    local f = pl.frame
    f:ClearAllPoints()
    f:SetPoint("CENTER", pl.plate, "CENTER", db.x, db.y)
    f:SetSize(w, h)

    -- the elite dragon, when the mob has one, stands where the name starts and moves the name right
    local es = math.max(10, math.floor(h * 0.8))
    pl.eliteSize = es
    pl.eliteBack:ClearAllPoints(); pl.eliteBack:SetSize(es, es); pl.eliteBack:SetPoint("LEFT", pl.top, "LEFT", 4, 0)
    pl.elite:ClearAllPoints(); pl.elite:SetPoint("CENTER", pl.eliteBack, "CENTER", 0, 0)
    pl.elite:SetSize(pl.eliteKind == "rareelite" and math.floor(es * 0.72 + 0.5) or es, pl.eliteKind == "rareelite" and math.floor(es * 0.72 + 0.5) or es)
    pl.eliteShift = es + 1
    local shift = pl.elite:IsShown() and pl.eliteShift or 0
    pl.name:ClearAllPoints()
    pl.name:SetPoint("LEFT", pl.top, "LEFT", 7 + shift, 0)
    pl.name:SetWidth(w * 0.58 - shift)
    pl.name:SetFont(FONT, db.fontSize, "OUTLINE")
    -- the health percentage, on the bar's centre line at the right end; sized to stay clear of the
    -- bar's border (and the white target border inside it)
    pl.pct:SetFont(FONT, ReadoutSize(h, db.fontSize), "OUTLINE")
    pl.pct:ClearAllPoints(); pl.pct:SetPoint("RIGHT", pl.top, "RIGHT", -6, 0)

    local lv, lw = pl.lv, db.levelWidth
    -- the level box stands left of the bar and runs on under its rounded left end (as far as the
    -- corners reach: 7 of the mask's 512 px, and a pixel more), masked to the corners (see the box)
    -- (joined to the bar only: with a gap between them the box keeps to itself)
    local OVER = (lv.joinOk and (db.levelGap or 0) == 0) and (math.ceil(w * 7 / 512) + 1) or 0
    lv.lines[4]:SetShown(OVER == 0)
    lv:ClearAllPoints(); lv:SetPoint("RIGHT", f, "LEFT", OVER - db.levelGap, 0); lv:SetSize(lw + OVER, h)
    local g = lv.gcd
    g:ClearAllPoints(); g:SetPoint("TOPLEFT", lv, "TOPLEFT", 1, -1); g:SetSize(lw - 2, h - 2)
    g:SetFrameLevel(lv:GetFrameLevel() + 3)
    g.ring:ClearAllPoints(); g.ring:SetPoint("TOPLEFT", lv, "TOPLEFT", 0, 0); g.ring:SetSize(lw, h)
    g.ring:SetFrameLevel(lv:GetFrameLevel() + 5)
    local small = math.max(8, db.fontSize - 1)        -- the level number and the cast timer
    lv.text:ClearAllPoints(); lv.text:SetPoint("CENTER", lv, "LEFT", lw / 2, 0)
    lv.text:SetWidth(lw - 2)
    lv.text:SetFont(FONT, small, "OUTLINE")

    for _, c in ipairs({ pl.kill, pl.loot }) do
        c:SetSize(lw, 14)
        c.icon:ClearAllPoints(); c.icon:SetSize(10, 10); c.icon:SetPoint("LEFT", c, "LEFT", 3, 0)
        c.text:ClearAllPoints(); c.text:SetPoint("RIGHT", c, "RIGHT", -3, 0); c.text:SetWidth(lw - 16)
        c.text:SetFont(FONT, 10, "OUTLINE")
    end
    local sw, sh = pl.swing, db.swingHeight or 4
    local si = SwingInset(w)
    sw:ClearAllPoints(); sw:SetPoint("BOTTOMLEFT", f, "TOPLEFT", si, 3); sw:SetSize(w - 2 * si, sh)
    local sc = db.swingColor or { 0.78, 0.80, 0.83 }
    sw.bg:SetColorTexture(sc[1], sc[2], sc[3], db.swingAlpha or 0.35)
    local sr = db.swingRed or { 0.88, 0.15, 0.12 }
    -- darker towards the left end (where the swing finishes), full red at its right edge
    local redDone = false
    if sw.red.SetGradient and _G.CreateColor then
        sw.red:SetColorTexture(1, 1, 1, 0.85)
        redDone = pcall(sw.red.SetGradient, sw.red, "HORIZONTAL",
            CreateColor(sr[1] * 0.3, sr[2] * 0.3, sr[3] * 0.3, 1), CreateColor(sr[1], sr[2], sr[3], 1))
    end
    if not redDone then sw.red:SetColorTexture(sr[1], sr[2], sr[3], 0.85) end
    sw.pip:SetSize(sh * 2, sh * 4.5)                -- 8 x 18 on the default 4-high strip
    pl.kill:ClearAllPoints(); pl.kill:SetPoint("BOTTOMLEFT", lv, "TOPLEFT", 0, 2)
    pl.loot:ClearAllPoints(); pl.loot:SetPoint("TOPLEFT", lv, "BOTTOMLEFT", 0, -2)

    -- the quest-item icon: over the right end of the debuff row (which fills from the left), its
    -- right edge on the bar's right end and its bottom level with the debuffs' bottom
    local qs = 18
    pl.starter:ClearAllPoints(); pl.starter:SetSize(qs, qs); pl.starter:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, AuraLift())

    local c, ch = pl.cast, db.castHeight
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -db.castGap); c:SetSize(w, ch)
    c.icon:SetWidth(ch)
    c.name:ClearAllPoints(); c.name:SetPoint("LEFT", c.icon, "RIGHT", 5, 0); c.name:SetWidth(w - ch - 40)
    c.time:ClearAllPoints(); c.time:SetPoint("RIGHT", c, "RIGHT", -5, 0)
    c.name:SetFont(FONT, db.fontSize, "OUTLINE")
    c.time:SetFont(FONT, small, "OUTLINE")
    local cc, mc = db.castColor, db.castMeColor
    Gradient(c.yellow:GetStatusBarTexture(), cc)
    Gradient(c.orange:GetStatusBarTexture(), mc)
end

-- is this plate's unit your target (or action targeting's pick)? Asked first by comparing plate
-- frames: the game hands out the target's plate, and a frame is never a hidden value. Asking
-- UnitIsUnit can come back hidden in combat, which used to read as "no": no target size, no swing
-- timer, no GCD meter in a fight. That is only the fallback now.
local function PlateIs(unit, token)
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local okP, tp = pcall(C_NamePlate.GetNamePlateForUnit, token)
        local okU, up = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if okP and okU and type(up) == "table" then
            return tp == up
        end
    end
    local ok, r = pcall(UnitIsUnit, unit, token)
    return ok and Plain(r) == true
end
local function IsTarget(unit) return PlateIs(unit, "target") end

-- the enemy action targeting has picked, when it is not also your target
local function IsSoft(unit) return PlateIs(unit, "softenemy") end

-- Blizzard may scale the plate itself (its own bigger-target setting, distance scaling); the
-- bar is drawn at the size you asked for whatever it does
local function ApplyScale(pl)
    -- what counts is the plate's size on screen, whoever scales it (the plate, a parent of it,
    -- distance scaling, the selected-plate enlargement): ours is set so that it ends up at
    -- (wanted size x the UI scale) whatever that is
    local pe = pl.plate.GetEffectiveScale and pl.plate:GetEffectiveScale()
    local ue = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
    local want
    if type(pe) == "number" and pe > 0 and type(ue) == "number" and ue > 0 then
        -- nothing moved since last frame: nothing to do (this runs every frame for every plate)
        if pe == pl.lastPe and ue == pl.lastUe and pl.wantScale == pl.lastWant then
            pl.stable = (pl.stable or 0) + 1
            return
        end
        pl.lastUe, pl.lastWant = ue, pl.wantScale
        want = (pl.wantScale or 1) * ue / pe
        if pe == pl.lastPe then pl.stable = (pl.stable or 0) + 1 else pl.lastPe = pe; pl.stable = 0 end
    else
        local ps = pl.plate.GetScale and pl.plate:GetScale() or 1
        if type(ps) ~= "number" or ps <= 0 then ps = 1 end
        want = (pl.wantScale or 1) / ps
        pl.stable = 0
    end
    if pl.frame:GetScale() ~= want then pl.frame:SetScale(want) end
end

-- the level number in the game's own colours, by how far the mob is from your level: red 5 or more
-- above you (and "??"), orange 3-4 above, yellow within 2, green below that while it still gives XP,
-- white once it gives none (the game would show grey)
local function GrayLevel(me)
    -- the highest mob level that gives you no experience (the Classic rule)
    if me <= 5 then return 0 end
    if me <= 39 then return me - math.floor(me / 10) - 5 end
    if me <= 59 then return me - math.floor(me / 5) - 1 end
    return me - 9
end
LevelColor = function(lvl)
    if db.levelColors == false then return 1, 1, 1 end
    if not lvl or lvl <= 0 then return 1, 0.2, 0.2 end
    local me = Plain(UnitLevel("player"))
    if type(me) ~= "number" or me <= 0 then return 1, 1, 1 end
    local diff = lvl - me
    if diff >= 5 then return 1, 0.2, 0.2 end
    if diff >= 3 then return 1, 0.58, 0.3 end
    if diff >= -2 then return 1, 0.9, 0.15 end
    if lvl > GrayLevel(me) then return 0.35, 0.88, 0.35 end
    return 1, 1, 1
end

-- the elite dragon left of the name, as the game marks them: gold for elites and bosses, silver for
-- rares, and for a rare elite the gold one in front of a bigger silver one that frames it. The game's
-- own nameplate pictures where it has them, else our crest.
local ELITE_ART = {
    gold = { atlas = "nameplates-icon-elite-gold", file = "EliteGold" },
    silver = { atlas = "nameplates-icon-elite-silver", file = "EliteSilver" },
}
local function HasAtlas(name)
    if C_Texture and C_Texture.GetAtlasInfo then
        local ok, info = pcall(C_Texture.GetAtlasInfo, name)
        return ok and info ~= nil
    end
    return false
end
-- put one picture on a texture: the game's, else ours; says which it used
local function Art(tex, which)
    local art = ELITE_ART[which]
    if HasAtlas(art.atlas) then
        tex:SetAtlas(art.atlas)
        return "game"
    end
    tex:SetTexture(MEDIA .. art.file)
    tex:SetTexCoord(0, 1, 0, 1)
    return "SKTools crest"
end
EliteIcon = function(pl, unit)
    local cls = UnitClassification and Plain(UnitClassification(unit))
    local lvl = Plain(UnitLevel(unit))
    local kind
    if cls == "rareelite" then kind = "rareelite"
    elseif cls == "elite" or cls == "worldboss" or lvl == -1 then kind = "gold"
    elseif cls == "rare" then kind = "silver" end
    if db.eliteIcon == false then kind = nil end
    local was = pl.elite:IsShown()
    if kind then
        if pl.eliteKind ~= kind then
            local es = pl.eliteSize or 22
            if kind == "rareelite" then
                pl.eliteArt = Art(pl.elite, "gold")
                Art(pl.eliteBack, "silver")
                local fs = math.floor(es * 0.72 + 0.5)
                pl.elite:SetSize(fs, fs)
                pl.eliteBack:Show()
            else
                pl.eliteArt = Art(pl.elite, kind)
                pl.elite:SetSize(es, es)
                pl.eliteBack:Hide()
            end
            pl.eliteKind = kind
        end
        pl.elite:Show()
    else
        pl.elite:Hide()
        pl.eliteBack:Hide()
        pl.eliteKind = nil
    end
    -- the name makes room for it
    if was ~= pl.elite:IsShown() and pl.eliteShift then
        local shift = pl.elite:IsShown() and pl.eliteShift or 0
        pl.name:ClearAllPoints()
        pl.name:SetPoint("LEFT", pl.top, "LEFT", 7 + shift, 0)
        pl.name:SetWidth((db.width or 220) * 0.58 - shift)
    end
end

local function Static(pl)
    pl.applyScale = pl.applyScale or function() ApplyScale(pl) end
    local unit = pl.unit
    if not unit then return end
    local color, kind = Classify(unit)
    pl.kind = kind
    -- Berry Mode: every enemy bar red, except enemy players, who keep their class colour, mobs
    -- someone else has tagged, which stay grey, and neutral mobs, which keep their yellow-beige until
    -- they turn on someone (in combat, or you are on their threat list)
    local calmNeutral = false
    if kind == "neutral" then
        local okC, fighting = pcall(_G.UnitAffectingCombat or function() return false end, unit)
        local okT, threat = pcall(_G.UnitThreatSituation or function() return nil end, "player", unit)
        calmNeutral = not ((okC and Plain(fighting) == true) or (okT and Plain(threat) ~= nil))
    end
    if ns.BerryMode() and kind ~= "player" and kind ~= "tapped" and not calmNeutral then color = db.berryColor or { 0.80, 0.10, 0.12 } end
    Gradient(pl.bar:GetStatusBarTexture(), color)
    pcall(pl.name.SetText, pl.name, UnitName(unit))
    EliteIcon(pl, unit)
    Gradient(pl.red:GetStatusBarTexture(), db.aggroColor or { 0.85, 0.1, 0.08 })
    local lvl = Plain(UnitLevel(unit))
    pl.lv.text:SetText((lvl and lvl > 0) and tostring(lvl) or "??")
    pl.lv.text:SetTextColor(LevelColor(lvl))

    local target = IsTarget(unit)
    pl.isTarget = target
    local soft = not target and IsSoft(unit)
    pl.isSoft = soft
    pl.wantScale = (target and db.targetScale or 1) * (db.scale or 1)
    -- your target and the action-targeting (soft) target are solid, the rest a little see-through
    pl.wantAlpha = (target or soft) and 1 or (db.dimAlpha or 1)
    if not pl.holdAge then pl.frame:SetAlpha(pl.wantAlpha) end
    ApplyScale(pl)
    if target then
        pl.border:SetTexture(MEDIA .. "PlateBorderThick")
        pl.outline:Show()
        pl.border:SetVertexColor(1, 1, 1, 1)
    else
        pl.border:SetTexture(MEDIA .. "PlateBorder")
        pl.outline:Hide()
        pl.border:SetVertexColor(0.75, 0.77, 0.80, 1)
    end
end

local function Health(pl)
    local unit = pl.unit
    if not unit then return end
    local mx, cur = UnitHealthMax(unit), UnitHealth(unit)
    pcall(pl.bar.SetMinMaxValues, pl.bar, 0, mx)        -- hidden values go straight in
    pcall(pl.bar.SetValue, pl.bar, cur)
    pcall(pl.red.SetMinMaxValues, pl.red, 0, mx)
    pcall(pl.red.SetValue, pl.red, cur)
    local done = false
    if _G.UnitHealthPercent then
        local ok, pct = pcall(UnitHealthPercent, unit, true, _G.CurveConstants and CurveConstants.ScaleTo100)
        if ok and pct ~= nil then
            done = pcall(pl.pct.SetFormattedText, pl.pct, "%.0f%%", pct)
        end
    end
    if not done then
        local c, m = Plain(cur), Plain(mx)
        if type(c) == "number" and type(m) == "number" and m > 0 then
            pl.pct:SetFormattedText("%.0f%%", c / m * 100)
        else
            pl.pct:SetText("")
        end
    end
end

-- the spell being cast (or channelled) and whether it is aimed at you
local function CastInfo(unit)
    local ok, name, _, tex, startMs, endMs = pcall(UnitCastingInfo, unit)
    local channel = false
    if not ok or not Present(name) then
        ok, name, _, tex, startMs, endMs = pcall(UnitChannelInfo, unit)
        channel = true
        if not ok or not Present(name) then return nil end
    end
    return name, tex, startMs, endMs, channel
end

local function Cast(pl)
    local c = pl.cast
    if not db.cast or not pl.unit then c:Hide(); c.active = false; return end
    local unit = pl.unit
    local name, tex, startMs, endMs, channel = CastInfo(unit)
    if name == nil then c:Hide(); c.active = false; c.dur = nil; return end
    c.active = true
    pcall(c.name.SetText, c.name, name)
    pcall(c.icon.SetTexture, c.icon, tex)

    -- timer: a duration object when the game offers one, else start and end times, else just full
    local dur
    local fn = channel and _G.UnitChannelDuration or _G.UnitCastingDuration
    if fn and c.yellow.SetTimerDuration then
        local ok, d = pcall(fn, unit)
        if ok and d ~= nil then dur = d end
    end
    c.dur, c.channel = dur, channel
    local ok = false
    if dur then
        local E = _G.Enum
        local interp = E and E.StatusBarInterpolation and E.StatusBarInterpolation.Immediate
        local dir = E and E.StatusBarTimerDirection
        dir = dir and (channel and dir.RemainingTime or dir.ElapsedTime)
        ok = pcall(c.yellow.SetTimerDuration, c.yellow, dur, interp, dir)
        pcall(c.orange.SetTimerDuration, c.orange, dur, interp, dir)
    end
    c.fallback = nil
    if not ok then
        local s, e = Plain(startMs), Plain(endMs)
        if type(s) == "number" and type(e) == "number" and e > s then
            c.fallback = { s = s, e = e, channel = channel }
            c.yellow:SetMinMaxValues(s, e); c.orange:SetMinMaxValues(s, e)
        else
            c.yellow:SetMinMaxValues(0, 1); c.orange:SetMinMaxValues(0, 1)
            c.yellow:SetValue(1); c.orange:SetValue(1)
        end
    end

    -- deep orange when the caster is aiming at you: the orange bar is shown or not
    -- depending on a yes/no the game may keep hidden
    local ok2, aimed = pcall(UnitIsUnit, unit .. "target", "player")
    if ok2 then
        if issecret(aimed) and c.orange.SetAlphaFromBoolean then
            pcall(c.orange.SetAlphaFromBoolean, c.orange, aimed, 1, 0)
        else
            c.orange:SetAlpha(aimed == true and 1 or 0)
        end
    else
        c.orange:SetAlpha(0)
    end
    c:Show()
end

----------------------------------------------------------------------
-- Aggro: red bar, three flashes when the mob gets on you
----------------------------------------------------------------------

-- true / false when the game says; nil and a hidden yes/no when it keeps it to itself
local function HasAggro(unit)
    local can = UnitCanAttack and Plain(UnitCanAttack("player", unit))
    if can == false then return false end
    if _G.UnitThreatSituation then
        local ok, s = pcall(UnitThreatSituation, "player", unit)
        s = ok and Plain(s) or nil
        if type(s) == "number" then return s >= 2 end
        if ok and s == nil and not issecret(s) then
            -- no threat entry: not on the mob's list at all
            local ok2, a = pcall(UnitIsUnit, unit .. "target", "player")
            if ok2 and not issecret(a) then return a == true end
        end
    end
    local ok2, a = pcall(UnitIsUnit, unit .. "target", "player")
    if not ok2 then return false end
    if issecret(a) then return nil, a end
    return a == true
end

local function Aggro(pl)
    local unit = pl.unit
    if not unit then return end
    if not db.aggro then
        pl.red:SetAlpha(0); pl.hadAggro = false
        return
    end
    local has, hidden = HasAggro(unit)
    if has ~= nil then
        pl.red:SetAlpha(has and 1 or 0)
        if has and not pl.hadAggro and db.aggroFlash ~= false and pl.flashAnim then
            if ns.BerryMode() and pl.berryAnims then
                -- Berry Mode: white bar and white frame, which show against the red
                for _, g in ipairs(pl.berryAnims) do g:Stop(); g:Play() end
                pl.lastFlash = "berry"
            else
                pl.flashAnim:Stop()
                pl.flashAnim:Play()
                pl.lastFlash = "normal"
            end
        end
        pl.hadAggro = has
    else
        -- the game keeps it hidden: it shows or hides the red bar itself
        if pl.red.SetAlphaFromBoolean then pcall(pl.red.SetAlphaFromBoolean, pl.red, hidden, 1, 0) end
        pl.hadAggro = nil
    end
end

----------------------------------------------------------------------
-- Your debuffs, above the bar at the left; icons blink for their last seconds
----------------------------------------------------------------------

local blinkCurve, blinkFor
-- a step curve over the time left: dim and bright every quarter second inside the last
-- seconds, fully bright outside them. The game evaluates it, so it also works when the
-- time left is hidden from addons.
local function BlinkCurve()
    local secs = db.blinkSeconds or 3
    if blinkFor == secs then return blinkCurve or nil end
    blinkFor, blinkCurve = secs, false
    if C_CurveUtil and C_CurveUtil.CreateCurve then
        local ok, c = pcall(C_CurveUtil.CreateCurve)
        if ok and c then
            local E = _G.Enum
            if E and E.LuaCurveType and E.LuaCurveType.Step and c.SetType then pcall(c.SetType, c, E.LuaCurveType.Step) end
            local n = math.floor(secs * 4)
            for k = 0, n - 1 do pcall(c.AddPoint, c, k * 0.25, (k % 2 == 0) and 0.25 or 1) end
            pcall(c.AddPoint, c, secs, 1)
            blinkCurve = c
        end
    end
    return blinkCurve or nil
end

local function AuraIcon(pl, i)
    local a = pl.auras[i]
    if a then return a end
    a = CreateFrame("Frame", nil, pl.frame)
    a:SetFrameLevel(pl.frame:GetFrameLevel() + 3)
    a.back = a:CreateTexture(nil, "BACKGROUND")
    a.back:SetColorTexture(0, 0, 0, 1); a.back:SetAllPoints()
    a.tex = a:CreateTexture(nil, "ARTWORK")
    a.tex:SetPoint("TOPLEFT", 1, -1); a.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    a.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, a, "CooldownFrameTemplate")
    if not ok then ok, cd = pcall(CreateFrame, "Cooldown", nil, a) end
    -- a client with no cooldown frame at all just gets no swipe
    a.cd = ok and cd or setmetatable({}, { __index = function() return function() end end })
    pcall(a.cd.SetAllPoints, a.cd, a.tex)
    pcall(a.cd.SetDrawEdge, a.cd, false)
    pcall(a.cd.SetHideCountdownNumbers, a.cd, true)
    a.count = Text(a, 10, "RIGHT")
    a.count:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", -1, 1)
    a.count:SetDrawLayer("OVERLAY", 7)
    a:Hide()
    pl.auras[i] = a
    return a
end

-- Your own debuffs on the unit. The game has changed how auras are listed, so several ways
-- are tried in turn; the first one that answers is used, and /skt debug plates says which.
local AURA_FILTER = "HARMFUL|PLAYER"

-- While the game keeps auras secret (in combat, and a moment before it), every reader that
-- hands an addon the list of auras refuses with "Auras cannot be accessed when secret while
-- tainted". What still works is asking for the aura instance numbers (never secret) and then
-- handing each one to the widgets: the icon, the timer and the stack count are only passed
-- on, never read.
local function FetchByInstanceID(unit, max)
    local A = C_UnitAuras
    if not (A and A.GetUnitAuraInstanceIDs) then return nil end
    local ok, ids = pcall(A.GetUnitAuraInstanceIDs, unit, AURA_FILTER, max)
    if not ok or type(ids) ~= "table" then return nil, tostring(ids) end
    local out = {}
    for _, id in ipairs(ids) do
        local d = { auraInstanceID = id }
        if A.GetAuraDataByAuraInstanceID then
            local ok2, data = pcall(A.GetAuraDataByAuraInstanceID, unit, id)
            if ok2 and type(data) == "table" then d.icon = data.icon end
        end
        out[#out + 1] = d
    end
    return out, "GetUnitAuraInstanceIDs"
end

local function AurasSecret()
    local S = _G.C_Secrets
    if S and S.ShouldAurasBeSecret then
        local ok, r = pcall(S.ShouldAurasBeSecret)
        return ok and r == true
    end
    return false
end

local function FetchAuras(unit, max)
    local A = C_UnitAuras
    if not A then return nil, "no C_UnitAuras" end
    -- secret right now: no point asking the readers that refuse, go the instance-number way
    if AurasSecret() then
        local l, src = FetchByInstanceID(unit, max)
        if l then return l, src .. " (auras secret)" end
    end
    local why
    if A.GetUnitAuras then
        local ok, l = pcall(A.GetUnitAuras, unit, AURA_FILTER, max)
        if ok and type(l) == "table" and #l > 0 then return l, "GetUnitAuras" end
        why = ok and "GetUnitAuras gave " .. type(l) or "GetUnitAuras: " .. tostring(l)
        local first = ok and type(l) == "table" and l or nil
        ok, l = pcall(A.GetUnitAuras, unit, AURA_FILTER)
        if ok and type(l) == "table" and #l > 0 then return l, "GetUnitAuras (no limit)" end
        first = first or (ok and type(l) == "table" and l) or nil
        -- some clients leave out auras flagged as nameplate-only unless asked for them
        ok, l = pcall(A.GetUnitAuras, unit, AURA_FILTER .. "|INCLUDE_NAME_PLATE_ONLY", max)
        if ok and type(l) == "table" and #l > 0 then return l, "GetUnitAuras (+nameplate-only)" end
        -- last resort: every debuff, keeping the ones that are yours (that flag is never hidden)
        ok, l = pcall(A.GetUnitAuras, unit, "HARMFUL|INCLUDE_NAME_PLATE_ONLY")
        if not ok or type(l) ~= "table" then ok, l = pcall(A.GetUnitAuras, unit, "HARMFUL") end
        if ok and type(l) == "table" then
            local mine = {}
            for _, d in ipairs(l) do
                if type(d) == "table" and d.isFromPlayerOrPlayerPet == true then mine[#mine + 1] = d end
            end
            if #mine > 0 then return mine, "GetUnitAuras (all debuffs, yours picked out)" end
        end
        if first then return first, "GetUnitAuras (empty)" end
    end
    do
        local l, src = FetchByInstanceID(unit, max)
        if l then return l, src end
        why = why or src
    end
    if A.GetAuraSlots and A.GetAuraDataBySlot then
        local out = {}
        local ok = pcall(function()
            local r = { A.GetAuraSlots(unit, AURA_FILTER, max) }
            for i = 2, #r do
                local d = A.GetAuraDataBySlot(unit, r[i])
                if d then out[#out + 1] = d end
            end
        end)
        if ok then return out, "GetAuraSlots" end
    end
    if A.GetAuraDataByIndex then
        local out = {}
        for i = 1, max do
            local ok, d = pcall(A.GetAuraDataByIndex, unit, i, AURA_FILTER)
            if not ok then
                if i == 1 then return nil, "GetAuraDataByIndex: " .. tostring(d) end
                break
            end
            if not d then break end
            out[#out + 1] = d
        end
        return out, "GetAuraDataByIndex"
    end
    return nil, why or "no way to list auras"
end

local function Auras(pl)
    local unit = pl.unit
    if not unit then return end
    local list
    local canAttack = UnitCanAttack and Plain(UnitCanAttack("player", unit))
    if db.auras ~= false and canAttack ~= false then
        list, pl.auraSrc = FetchAuras(unit, db.auraMax)
    end
    -- nothing the game would give us: Blizzard's own debuff row takes over (see QuietPlate)
    local blocked = db.auras ~= false and list == nil and canAttack ~= false
    if blocked ~= (pl.auraBlocked or false) then
        pl.auraBlocked = blocked
        QuietPlate(pl)
        PlaceCC(pl)
    end
    local size, gap = db.auraSize, db.auraGap
    local used = 0
    if list then
        for i = 1, math.min(#list, db.auraMax) do
            local d = list[i]
            local a = AuraIcon(pl, i)
            used = i
            a:SetSize(size, size)
            a:ClearAllPoints()
            a:SetPoint("BOTTOMLEFT", pl.frame, "TOPLEFT", (i - 1) * (size + gap), AuraLift())
            pcall(a.tex.SetTexture, a.tex, d.icon)
            -- the swipe and the blink need the end time: plain numbers when the game allows,
            -- otherwise the game's own timer object
            local dur, exp = Plain(d.duration), Plain(d.expirationTime)
            a.exp, a.timer = nil, nil
            if type(dur) == "number" and type(exp) == "number" then
                if dur > 0 then
                    a.exp = exp
                    pcall(a.cd.SetCooldown, a.cd, exp - dur, dur)
                else
                    pcall(a.cd.Clear, a.cd)
                end
            elseif C_UnitAuras.GetAuraDuration and d.auraInstanceID ~= nil then
                local ok, t = pcall(C_UnitAuras.GetAuraDuration, unit, d.auraInstanceID)
                if ok and t ~= nil then
                    a.timer = t
                    pcall(a.cd.SetCooldownFromDurationObject, a.cd, t)
                end
            end
            -- stack count
            local shown = false
            if C_UnitAuras.GetAuraApplicationDisplayCount and d.auraInstanceID ~= nil then
                shown = pcall(function() a.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(unit, d.auraInstanceID, 2, 99)) end)
            end
            if not shown then
                local n = Plain(d.applications)
                a.count:SetText((type(n) == "number" and n > 1) and tostring(n) or "")
            end
            a:SetAlpha(1)
            a:Show()
        end
    end
    for i = used + 1, #pl.auras do pl.auras[i]:Hide() end
    pl.auraCount = used
end

-- called ten times a second while any icon is up
local function Blink(pl)
    if not pl.auraCount or pl.auraCount == 0 then return end
    local secs = db.blinkSeconds or 3
    for i = 1, pl.auraCount do
        local a = pl.auras[i]
        if db.blink == false then
            a:SetAlpha(1)
        elseif a.exp then
            local left = a.exp - GetTime()
            if left > 0 and left <= secs then
                a:SetAlpha((math.floor(left * 4) % 2 == 0) and 0.25 or 1)
            else
                a:SetAlpha(1)
            end
        elseif a.timer and a.timer.EvaluateRemainingDuration then
            local c = BlinkCurve()
            if c then pcall(function() a:SetAlpha(a.timer:EvaluateRemainingDuration(c)) end) end
        end
    end
end

----------------------------------------------------------------------
-- Swing timer (on your target's plate)
--
-- WoW Forever tells addons about each of your swings itself: PLAYER_SWING(duration, type),
-- type 0 = main hand, 1 = off hand, 2 = ranged. No combat log is needed (and none is given).
-- Melee runs left to right; ranged runs right to left, with the last half second in red at the
-- left end: the time you must stand still for the shot to go off.
----------------------------------------------------------------------

local SWING_MAIN, SWING_RANGED = 0, 2
local swings = { [SWING_MAIN] = {}, [SWING_RANGED] = {} }
local swingKind = SWING_MAIN
local zoneKind, zoneAge = nil, 0

-- the game's number when it gives one; otherwise the weapon's own speed
local function SwingLength(given, kind)
    local d = Plain(given)
    if type(d) == "number" and d > 0 then return d end
    if kind == SWING_RANGED and _G.UnitRangedDamage then
        local ok, s = pcall(UnitRangedDamage, "player")
        s = ok and Plain(s) or nil
        if type(s) == "number" and s > 0 then return s end
    end
    if _G.UnitAttackSpeed then
        local ok, s = pcall(UnitAttackSpeed, "player")
        s = ok and Plain(s) or nil
        if type(s) == "number" and s > 0 then return s end
    end
    return kind == SWING_RANGED and 2.8 or 2.0
end

-- what the swing timer last heard, for /skt debug plates
local swingLog = { count = 0 }

local function StartSwing(kind, duration, src)
    if kind ~= SWING_MAIN and kind ~= SWING_RANGED then return end       -- off hand: not shown
    local s = swings[kind]
    s.start, s.dur = GetTime(), SwingLength(duration, kind)
    swingKind = kind
    swingLog.count = swingLog.count + 1
    swingLog.src, swingLog.kind, swingLog.dur = src, kind, s.dur
end

-- PLAYER_SWING: a swing type (0 main hand, 1 off hand, 2 ranged) and, it seems, its length. Which
-- comes first is not written down anywhere we could check, so either order is taken, or the type
-- alone (the length then comes from your weapon speed). When both look like a type (a 2.0 speed
-- weapon), the one matching your weapon speed is the length.
local function IsType(v) return v == 0 or v == 1 or v == 2 end
local function OnSwing(a, b, c)
    a, b, c = Plain(a), Plain(b), Plain(c)
    swingLog.raw = ("%s, %s, %s"):format(tostring(a), tostring(b), tostring(c))
    local kind, dur
    if a == nil and type(b) == "number" then
        kind = IsType(b) and b or nil                 -- the length kept back, the type second
    elseif type(a) == "number" and type(b) ~= "number" then
        kind = IsType(a) and a or nil
    elseif type(a) == "number" and type(b) == "number" then
        if IsType(a) and not IsType(b) then kind, dur = a, b
        elseif IsType(b) and not IsType(a) then kind, dur = b, a
        elseif IsType(a) and IsType(b) then
            -- a swing cannot last 0 s, so a 0 is the type; else the one nearer your weapon speed is
            -- the length; else length first (the order this was first written for)
            local ok, speed = pcall(_G.UnitAttackSpeed or function() return nil end, "player")
            speed = ok and Plain(speed)
            if a == 0 then kind, dur = a, b
            elseif b == 0 then kind, dur = b, a
            elseif type(speed) == "number" and math.abs(speed - b) < math.abs(speed - a) then kind, dur = a, b
            else kind, dur = b, a end
        end
    end
    if kind == nil then swingLog.miss = "could not read: " .. swingLog.raw; return end
    StartSwing(kind, dur, "PLAYER_SWING")
end

-- a backup, if PLAYER_SWING never comes: Auto Shot going off. (Not the combat log: registering
-- for it is a protected action in this client and brings up an "action blocked" warning.)
local AUTO_SHOT = 75
local function OnCast(spellID)
    if Plain(spellID) == AUTO_SHOT and (swingLog.src ~= "PLAYER_SWING" or GetTime() - (swings[SWING_RANGED].start or 0) > 0.2) then
        StartSwing(SWING_RANGED, nil, "Auto Shot")
    end
end

-- which timer the strip shows: the one that swung last, except that a Hunter's strip follows
-- the range zone at once (bow range -> ranged, melee range -> main hand), before the first swing
local function SwingKind()
    local RB = ns.RangeBar
    if RB and RB.Eligible and RB.Zone then
        local now = GetTime()
        if now - zoneAge > 0.1 then
            zoneAge, zoneKind = now, nil
            local ok, can = pcall(RB.Eligible)
            if ok and can then
                local ok2, zone = pcall(RB.Zone, "target")
                if ok2 and zone == "MELEE" then zoneKind = SWING_MAIN
                elseif ok2 and zone == "SHOOT" then zoneKind = SWING_RANGED end
            end
        end
        if zoneKind then return zoneKind end
    end
    return swingKind
end

local function Swing(pl)
    local sw = pl.swing
    if not sw then return end
    if db.swing == false or not pl.isTarget then
        if sw:IsShown() then sw:Hide() end
        return
    end
    local kind = SwingKind()
    local s = swings[kind]
    local now = GetTime()
    local inCombat = _G.UnitAffectingCombat and Plain(UnitAffectingCombat("player")) == true
    if not inCombat and not (s.start and now - s.start < s.dur + 1.5) then sw:Hide(); return end
    local w = db.width - 2 * SwingInset(db.width)
    local dur = s.dur or SwingLength(nil, kind)
    local p = 1                                   -- no swing running: the pip rests at the end
    if s.start then p = math.min(1, math.max(0, (now - s.start) / dur)) end
    if kind == SWING_RANGED then
        sw.red:SetWidth(math.max(1, w * math.min(1, (db.swingWindow or 0.5) / dur)))
        sw.red:Show()
        p = 1 - p                                 -- right to left
    else
        sw.red:Hide()
    end
    sw.pip:ClearAllPoints(); sw.pip:SetPoint("CENTER", sw, "LEFT", p * w, 0)
    sw.kind, sw.at = kind, p
    sw:Show()
end

----------------------------------------------------------------------
-- Quest counters and the quest-starter icon (called by Marks.lua)
----------------------------------------------------------------------

local function CounterText(list)
    local parts = {}
    for i, n in ipairs(list) do parts[i] = tostring(math.max(0, n)) end
    return table.concat(parts, "-")
end

local function ApplyMarks(pl)
    local r = pl.marks
    local M = ns.Marks
    local mdb = M and M.db
    if not (r and mdb) then
        pl.kill:Hide(); pl.loot:Hide(); pl.starter:Hide()
        return
    end
    local counts = r.counts or {}
    local function Show(c, list)
        if mdb.counters and list and #list > 0 then
            c.text:SetText(CounterText(list)); c:Show()
        else
            c:Hide()
        end
    end
    Show(pl.kill, counts.kill)
    Show(pl.loot, counts.loot)
    pl.starter:SetShown(r.starter and mdb.show and mdb.show.starter and true or false)
end

----------------------------------------------------------------------
-- Showing and hiding
----------------------------------------------------------------------

-- what /skt debug plates reports about plates that came late (see Rescan)
lateLog = { late = 0, stepErrors = 0 }

-- each step on its own: one that fails (a value the game will not give yet, say) must not leave
-- the bar unshown or the rest of the plate undone
local REFRESH_STEPS
local function Refresh(pl)
    if not pl.unit then return end
    pl.frame:Show()
    REFRESH_STEPS = REFRESH_STEPS or { Layout, Static, Health, Cast, Aggro, Auras, ApplyMarks, QuietPlate, PlaceCC }
    for _, step in ipairs(REFRESH_STEPS) do
        local ok, err = pcall(step, pl)
        if not ok then lateLog.stepErrors = lateLog.stepErrors + 1; lateLog.lastError = tostring(err) end
    end
end

local function Release(pl)
    pl.frame:Hide()
    if pl.swing then pl.swing:Hide() end
    pl.cast:Hide()
    ReleaseCC(pl)
    RestorePlate(pl)
    pl.unit = nil
end

-- only enemies get our plates; friendly players and NPCs keep Blizzard's own
local function IsEnemy(unit)
    local can = UnitCanAttack and Plain(UnitCanAttack("player", unit))
    return can ~= false
end

local Remove

-- the game's own buff row on friendly plates (your heals over time, mostly): hidden. In an
-- instance friendly plates are the game's alone and can't be touched; elsewhere they go.
local friendlyHidden = setmetatable({}, { __mode = "k" })
local function BuffRows(plate)
    local uf = plate and plate.UnitFrame
    if type(uf) ~= "table" then return {} end
    local rows = {}
    local af = uf.AurasFrame
    if type(af) == "table" and type(af.BuffListFrame) == "table" then rows[#rows + 1] = af.BuffListFrame end
    if type(uf.BuffFrame) == "table" then rows[#rows + 1] = uf.BuffFrame end
    return rows
end
local function FriendlyBuffs(plate, friendly)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
    for _, row in ipairs(BuffRows(plate)) do
        if row.SetAlpha then
            if friendly then
                if not friendlyHidden[row] and _G.hooksecurefunc then
                    hooksecurefunc(row, "SetAlpha", function(self, a)
                        if friendlyHidden[self] == true and a ~= 0 and not self.sktBusy then
                            self.sktBusy = true; self:SetAlpha(0); self.sktBusy = false
                        end
                    end)
                end
                friendlyHidden[row] = true
                row:SetAlpha(0)
            elseif friendlyHidden[row] then
                friendlyHidden[row] = false
                row:SetAlpha(1)
            end
        end
    end
end

local function Add(unit)
    if not db then return end
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    local enemy = IsEnemy(unit)
    if type(plate) == "table" then pcall(FriendlyBuffs, plate, not enemy) end
    if not db.enabled then return end
    if not enemy then
        if active[unit] then Remove(unit) end
        return
    end
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
    local pl = plates[plate] or Create(plate)
    pl.unit = unit
    active[unit] = pl
    -- invisible until the next frame has sized it: no pop in at the wrong size
    pl.holdAge, pl.stable, pl.lastPe = 0, 0, nil
    pl.frame:SetAlpha(0)
    Refresh(pl)
    -- Marks may have drawn this plate before we existed: have it redo the plate, now beside our bar
    if ns.Marks and ns.Marks.UpdateUnit then ns.Marks.UpdateUnit(unit) end
end

function Remove(unit)
    local pl = active[unit]
    active[unit] = nil
    if pl then
        Release(pl)
        if ns.Marks and ns.Marks.UpdateUnit then ns.Marks.UpdateUnit(unit) end
    end
end

-- enemy plates we are not drawing yet. The first time you meet a mob in an area the game may not
-- know it is hostile when its plate appears (we leave it alone then), and it does not always send an
-- event when it finds out; Questie's icon, which only looks at the mob's id, shows up regardless.
-- So a few times a second we look again.
local function Rescan()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    local ok, list = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(list) ~= "table" then return end
    for _, plate in ipairs(list) do
        local unit = plate.namePlateUnitToken or (type(plate.UnitFrame) == "table" and plate.UnitFrame.unit)
        if unit and not active[unit] and IsEnemy(unit) then
            lateLog.late = lateLog.late + 1
            lateLog.lastLate = Plain(UnitName(unit)) or unit
            Add(unit)
            -- it has been on screen already: no hold for it to settle
            local pl = active[unit]
            if pl and pl.holdAge then pl.holdAge = 0.5 end
        end
    end
end

local function EachActive(fn)
    for _, pl in pairs(active) do fn(pl) end
end

local function RefreshAll()
    if not db then return end
    if not db.enabled then
        EachActive(Release)
        wipe(active)
        if ns.Marks and ns.Marks.RefreshAll then ns.Marks.RefreshAll() end
        return
    end
    -- plates that were skipped while we were off, or are new since login
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
            local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            if unit and not active[unit] then Add(unit) end
        end
    end
    EachActive(Refresh)
    if ns.Marks and ns.Marks.RefreshAll then ns.Marks.RefreshAll() end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

----------------------------------------------------------------------
-- GCD meter (your target's level box)
----------------------------------------------------------------------

local GCD_SPELL = 61304          -- the game's own "global cooldown" spell
local gcd = { how = "idle" }     -- start/dur when the game tells us; obj when it only gives its timer
local ReadGcd

-- ask the game where the GCD is: after you cast, and whenever cooldowns change. In order:
--   1. the game's own "global cooldown" spell (Forever may not have it)
--   2. the spell you just cast: its cooldown is the GCD, unless it has a longer one of its own
--   3. a guess when you cast: 1 s for energy users, else 1.5 s shortened by haste
-- When the game keeps the numbers to itself (in combat), its timer object for 1 or 2 drives the meter.
local function TryCooldown(id, src, castSpell)
    local ok, info = pcall(C_Spell.GetSpellCooldown, id)
    if not ok or type(info) ~= "table" then gcd.last = src .. ": no answer"; return false end
    local st, du = Plain(info.startTime), Plain(info.duration)
    if type(st) == "number" and type(du) == "number" then
        if du <= 0 or GetTime() >= st + du then gcd.last = src .. ": nothing running"; return false end
        if castSpell and du > 1.6 then gcd.last = src .. ": its own cooldown"; return false end
        gcd.how, gcd.start, gcd.dur, gcd.obj, gcd.src = "plain", st, du, nil, src
        return true
    end
    -- hidden numbers: the game's timer object. Not for a cast spell, whose timer may be its own
    -- longer cooldown: the guess, which starts at the cast like the GCD, is surer there
    if castSpell then gcd.last = src .. ": numbers hidden"; return false end
    if C_Spell.GetSpellCooldownDuration then
        local ok2, obj = pcall(C_Spell.GetSpellCooldownDuration, id)
        if ok2 and obj then
            gcd.how, gcd.obj, gcd.since, gcd.src = "timer", obj, GetTime(), src .. " (hidden numbers)"
            return true
        end
    end
    gcd.last = src .. ": numbers hidden, no timer"
    return false
end
local function GcdGuess()
    local okP, pt = pcall(UnitPowerType, "player")
    if okP and Plain(pt) == ((Enum and Enum.PowerType and Enum.PowerType.Energy) or 3) then return 1.0 end
    local okH, haste = pcall(_G.UnitSpellHaste or function() return 0 end, "player")
    haste = okH and Plain(haste) or 0
    return math.max(1.0, 1.5 / (1 + (type(haste) == "number" and haste or 0) / 100))
end
ReadGcd = function(castId)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return end
    if TryCooldown(GCD_SPELL, "GCD spell") then return end
    castId = Plain(castId)
    if type(castId) ~= "number" then return end
    if TryCooldown(castId, "spell cast (" .. castId .. ")", true) then return end
    gcd.how, gcd.start, gcd.dur, gcd.obj, gcd.src = "plain", GetTime(), GcdGuess(), nil, "guess"
end

-- the meter on one plate: only your target's, only while a GCD runs
-- the GCD meter's switch: its own in Berry Mode (off there until turned on), as the newer features have
local function GcdOn()
    if not db then return false end
    if ns.BerryMode and ns.BerryMode() then return db.gcdBerry == true end
    return db.gcd ~= false
end

local function GcdDraw(pl)
    local g = pl.lv.gcd
    local function Off() if g:IsShown() then g:Hide(); g.ring:Hide() end; g.key = nil end
    if not GcdOn() or not pl.isTarget or gcd.how == "idle" then return Off() end
    local now, sw = GetTime(), g.sweep
    pcall(sw.SetSwipeColor, sw, 0, 0, 0, (db.gcdDark or 85) / 100)
    if gcd.how == "plain" then
        if now - gcd.start >= gcd.dur or now < gcd.start then gcd.how = "idle"; return Off() end
        local key = gcd.start .. ":" .. gcd.dur
        if g.key ~= key then g.key = key; pcall(sw.SetCooldown, sw, gcd.start, gcd.dur) end
        pl.gcdPath = "numbers"
    else
        -- no GCD lasts 2 seconds: past that the timer is stale
        if now - (gcd.since or 0) > 2 then gcd.how = "idle"; return Off() end
        local key = "timer:" .. tostring(gcd.since)
        if g.key ~= key then
            g.key = key
            if not (sw.SetCooldownFromDurationObject and pcall(sw.SetCooldownFromDurationObject, sw, gcd.obj)) then
                pl.gcdPath = "none worked"; return Off()
            end
        end
        pl.gcdPath = "the game's timer"
    end
    if not g:IsShown() then g:Show(); g.ring:Show() end
end

-- the last few plates added and removed, for /skt debug platelist
local plateLog = {}
LogPlate = function(what, unit)
    local name = unit and Plain(UnitName(unit))
    table.insert(plateLog, 1, ("%.1f %s %s (%s)%s"):format(GetTime(), what, tostring(unit), tostring(name or "?"),
        (unit and what == "added" and not IsEnemy(unit)) and " not an enemy yet" or ""))
    plateLog[11] = nil
end

local driver = CreateFrame("Frame")
local acc, slow, rescan = 0, 0, 0
local softBurst = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    if not db or not db.enabled then return end
    acc = acc + elapsed
    slow = slow + elapsed
    if softBurst > 0 then softBurst = softBurst - elapsed end
    -- every frame: Blizzard's own scaling of the selected plate must never show
    rescan = rescan + elapsed
    if rescan >= 0.2 then rescan = 0; Rescan() end
    for _, pl in pairs(active) do
        -- the hold below must count down even if something else about this plate fails
        pcall(ApplyScale, pl)
        pcall(Swing, pl)
        pcall(GcdDraw, pl)
        if pl.holdAge then
            -- a new plate shows on its first frame, once ApplyScale above has sized it. (It used to
            -- wait for the plate's size to settle, up to half a second; but the game removes and re-adds
            -- a plate each time a mob crosses the edge of the screen, and a moving mob's plate never
            -- settles, so the bar kept lagging behind, e.g. behind Questie's icon on the same plate.)
            pl.holdAge = nil
            pl.frame:SetAlpha(pl.wantAlpha or 1)
        end
        -- action targeting: Blizzard re-selects, re-scales and re-lights plates each time the soft
        -- target moves; for a moment after that, keep its own plate hidden and ours the right size
        if softBurst > 0 then QuietPlate(pl); PlaceCC(pl) end
    end
    -- the cast bars' time text, and a fallback timer for clients without duration objects
    if acc >= 0.1 then
        local dt = acc
        acc = 0
        EachActive(Blink)
        EachActive(function(pl)
            local c = pl.cast
            if not c.active then return end
            if c.dur and c.dur.GetRemainingDuration then
                pcall(function() c.time:SetFormattedText("%.1f", c.dur:GetRemainingDuration()) end)
            elseif c.fallback then
                local fb = c.fallback
                local now = GetTime() * 1000
                c.yellow:SetValue(fb.channel and (fb.e - (now - fb.s)) or now)
                c.orange:SetValue(fb.channel and (fb.e - (now - fb.s)) or now)
                c.time:SetFormattedText("%.1f", math.max(0, (fb.e - now) / 1000))
            end
        end)
    end
    -- Blizzard re-shows things now and then: keep them quiet and the CC icon in place
    if slow >= 0.5 then
        slow = 0
        EachActive(function(pl) QuietPlate(pl); PlaceCC(pl); ApplyScale(pl) end)
    end
end)

local UNIT_EVENTS = {
    UNIT_HEALTH = Health, UNIT_MAXHEALTH = Health,
    UNIT_NAME_UPDATE = Static, UNIT_LEVEL = Static, UNIT_FACTION = Static, UNIT_CLASSIFICATION_CHANGED = Static,
    UNIT_SPELLCAST_START = Cast, UNIT_SPELLCAST_STOP = Cast, UNIT_SPELLCAST_FAILED = Cast,
    UNIT_SPELLCAST_INTERRUPTED = Cast, UNIT_SPELLCAST_DELAYED = Cast, UNIT_SPELLCAST_CHANNEL_START = Cast,
    UNIT_SPELLCAST_CHANNEL_STOP = Cast, UNIT_SPELLCAST_CHANNEL_UPDATE = Cast,
    UNIT_TARGET = function(pl) Cast(pl); Aggro(pl) end,
    UNIT_SPELLCAST_EMPOWER_START = Cast, UNIT_SPELLCAST_EMPOWER_STOP = Cast,
    UNIT_THREAT_SITUATION_UPDATE = Aggro, UNIT_AURA = Auras,
    -- a neutral mob going into or out of combat changes its Berry Mode colour
    UNIT_FLAGS = function(pl) if pl.kind == "neutral" then Static(pl) end end,
    UNIT_THREAT_LIST_UPDATE = function(pl) Aggro(pl); if pl.kind == "neutral" then Static(pl) end end,
}
driver:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED",
                     "PLAYER_SOFT_ENEMY_CHANGED", "PLAYER_SOFT_FRIEND_CHANGED", "PLAYER_SOFT_INTERACT_CHANGED",
                     "PLAYER_SWING", "SPELL_UPDATE_COOLDOWN", "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_LEVEL_UP" }) do
    pcall(driver.RegisterEvent, driver, e)
end
for e in pairs(UNIT_EVENTS) do pcall(driver.RegisterEvent, driver, e) end

driver:SetScript("OnEvent", function(_, event, unit, arg2, arg3)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitDB().range
        root.plates = root.plates or {}
        DeepFill(root.plates, ns.PLATES_DEFAULTS)
        db = root.plates
        -- 2.2.0: the level box joins the bar (the old default left a 4 px gap)
        -- keys from versions that are gone
        db.softScale, db.scaleHalf, db.gapJoined = nil, nil, nil
        RefreshAll()
        return
    end
    if not db then return end
    if event == "PLAYER_SWING" then OnSwing(unit, arg2, arg3); return end
    if event == "SPELL_UPDATE_COOLDOWN" then ReadGcd(); return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then ReadGcd(arg3); OnCast(arg3); return end
    if event == "PLAYER_LEVEL_UP" then EachActive(Static); return end
    if event == "NAME_PLATE_UNIT_ADDED" then LogPlate("added", unit); Add(unit); return end
    if event == "NAME_PLATE_UNIT_REMOVED" then LogPlate("removed", unit); Remove(unit); return end
    if event == "PLAYER_TARGET_CHANGED" then EachActive(Static); return end
    if event:find("^PLAYER_SOFT_") then
        softBurst = 0.6
        Rescan()
        EachActive(function(pl) Static(pl); QuietPlate(pl); PlaceCC(pl) end)
        return
    end
    if event == "UNIT_FACTION" and unit then
        -- a mind control, a duel, a flag: who counts as an enemy changed
        if IsEnemy(unit) and not active[unit] then Add(unit); return end
        if not IsEnemy(unit) then Add(unit); return end        -- drops ours, hides the game's buff row
    end
    local pl = unit and active[unit]
    local fn = UNIT_EVENTS[event]
    if pl and fn then fn(pl) end
end)

----------------------------------------------------------------------
-- For the other modules and the settings window
----------------------------------------------------------------------

-- every plate the game has right now, ours or not, and what is showing on each
local function List(print)
    local function vis(o)
        if type(o) ~= "table" then return "none" end
        local ok, r = pcall(function()
            return ("%s%s a=%.2f"):format(o:IsShown() and "shown" or "hidden", o:IsVisible() and "" or " (not visible)", o:GetAlpha())
        end)
        return ok and r or "unreadable"
    end
    local list = (C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates()) or {}
    print(("platelist: the game has %d plate(s); %s"):format(#list, (function()
        local n = 0 for _ in pairs(active) do n = n + 1 end return n .. " drawn by us" end)()))
    for _, plate in ipairs(list) do
        local unit = plate.namePlateUnitToken or (type(plate.UnitFrame) == "table" and plate.UnitFrame.unit)
        local pl = plates[plate]
        local name = unit and Plain(UnitName(unit))
        local x, y = nil, nil
        pcall(function() x, y = plate:GetCenter() end)
        print(("  %s (%s): enemy=%s, ours=%s; plate %s at %s,%s"):format(tostring(unit), tostring(name or "?"),
            tostring(unit and IsEnemy(unit)), tostring(unit and active[unit] ~= nil), vis(plate),
            x and ("%.0f"):format(x) or "?", y and ("%.0f"):format(y) or "?"))
        print(("    Blizzard UnitFrame %s; our bar %s%s"):format(vis(plate.UnitFrame), pl and vis(pl.frame) or "none",
            (pl and pl.holdAge) and (" (holding, %.2fs)"):format(pl.holdAge) or ""))
        -- anything else hung on the plate (Questie's icon, other addons)
        pcall(function()
            for _, ch in ipairs({ plate:GetChildren() }) do
                if ch ~= plate.UnitFrame and not (pl and ch == pl.frame) then
                    print(("    other frame %s, %s, %.0fx%.0f, strata %s"):format(tostring(ch:GetName() or ch:GetObjectType()),
                        vis(ch), ch:GetWidth() or 0, ch:GetHeight() or 0, tostring(ch:GetFrameStrata())))
                end
            end
        end)
    end
    print("  last plate events (newest first, game time):")
    for _, l in ipairs(plateLog) do print("    " .. l) end
end

ns.Plates = {
    List = List,
    SwingState = function() return swingLog end,
    ReadoutSize = function(h, fs) return ReadoutSize(h, fs) end,
    LevelColor = function(lvl) if not db then return 1, 1, 1 end return LevelColor(lvl) end,
    Gcd = function() return gcd end,
    GcdOn = function() return GcdOn() end,
    -- how far left of the bar's left end the level box reaches: the combo points, crescent, totems
    -- and the left icons stand past it
    LeftEdge = function() return ((db and db.levelGap) or 0) + ((db and db.levelWidth) or 34) end,
    SetGcdOn = function(v)
        if not db then return end
        if ns.BerryMode() then db.gcdBerry = v and true or false else db.gcd = v and true or false end
    end,
    Settings = function() return db end,
    Refresh = RefreshAll,
    Reset = function()
        local root = ns.InitDB().range
        root.plates = {}
        DeepFill(root.plates, ns.PLATES_DEFAULTS)
        db = root.plates
        RefreshAll()
    end,
    -- our plate for a Blizzard plate, while we are drawing it
    Active = function(plate)
        local pl = db and db.enabled and plates[plate]
        if pl and pl.unit and pl.frame:IsShown() then return pl end
    end,
    -- the frame (health bar sized, scaled for the target) that overlays hang on
    Frame = function(plate)
        local pl = db and db.enabled and plates[plate]
        return pl and pl.unit and pl.frame or nil
    end,
    Kind = function(plate) local pl = plates[plate]; return pl and pl.kind end,
    Object = function(plate) return plates[plate] end,
    SetMarks = function(plate, r)
        local pl = plates[plate]
        if not pl then return end
        pl.marks = r
        ApplyMarks(pl)
    end,
    Debug = function(print)
        print(("plates: enabled=%s, drawing %d plate(s)"):format(tostring(db and db.enabled),
            (function() local n = 0 for _ in pairs(active) do n = n + 1 end return n end)()))
        print(("  swing timer: %s; swings heard %d, last from %s (%s, %.2fs); last PLAYER_SWING values: %s%s"):format(
            db.swing == false and "off" or "on", swingLog.count, tostring(swingLog.src or "-"),
            swingLog.kind == SWING_RANGED and "ranged" or swingLog.kind == SWING_MAIN and "main hand" or "-", swingLog.dur or 0,
            tostring(swingLog.raw or "none yet"), swingLog.miss and ("; " .. swingLog.miss) or ""))
        print(("  GCD meter: %s, now %s, from %s; last miss: %s%s"):format((GcdOn() and "on" or "off") .. (ns.BerryMode() and " (Berry Mode)" or ""), tostring(gcd.how),
            tostring(gcd.src or "-"), tostring(gcd.last or "-"),
            (function() for _, p in pairs(active) do if p.isTarget then return ", drawn by " .. tostring(p.gcdPath) end end return "" end)()))
        print(("  picked up late: %d (last: %s); setup steps that failed: %d%s"):format(lateLog.late,
            tostring(lateLog.lastLate or "-"), lateLog.stepErrors,
            lateLog.lastError and (" (last: " .. lateLog.lastError .. ")") or ""))
        for unit, pl in pairs(active) do
            local uf = pl.plate.UnitFrame
            local kids = {}
            if type(uf) == "table" then
                for k, v in pairs(uf) do
                    if type(v) == "table" and v.GetObjectType then kids[#kids + 1] = k .. "=" .. v:GetObjectType() end
                end
                table.sort(kids)
            end
            print(("  %s: %s, target=%s, quiet=%s"):format(unit, tostring(pl.kind), tostring(pl.isTarget), tostring(pl.quiet)))
            print("    Blizzard UnitFrame holds: " .. table.concat(kids, ", "))
            print(("    plate scale %.2f, ours %.2f; debuffs: %s via %s, %d icon(s) up"):format(
                pl.plate:GetScale() or 0, pl.frame:GetScale() or 0, tostring(db.auras), tostring(pl.auraSrc), pl.auraCount or 0))
            local c = pl.cast
            print(("    cast: active=%s, timer=%s"):format(tostring(c.active),
                c.dur and "duration object" or (c.fallback and "start/end times" or "none")))
        end
        -- what the game says about debuffs on the first plate, with each way of asking
        local _, p1 = next(active)
        if p1 and C_UnitAuras and C_UnitAuras.GetUnitAuras then
            local function ask(label, ...)
                local ok, l = pcall(C_UnitAuras.GetUnitAuras, p1.unit, ...)
                print(("    %s -> %s"):format(label, ok and (type(l) == "table" and (#l .. " aura(s)") or type(l)) or ("error: " .. tostring(l))))
            end
            do
                local uf1 = p1.plate.UnitFrame
                local box = type(uf1) == "table" and uf1.HealthBarsContainer
                local af1 = type(uf1) == "table" and uf1.AurasFrame
                local dl = type(af1) == "table" and af1.DebuffListFrame
                local function geo(o)
                    if type(o) ~= "table" then return "none" end
                    local ok, l, w = pcall(function() return o:GetLeft(), o:GetWidth() end)
                    return ok and ("left=" .. tostring(l) .. " width=" .. tostring(w)) or ("unreadable: " .. tostring(l))
                end
                local function pts(o)
                    if type(o) ~= "table" then return "none" end
                    local ok, r = pcall(function()
                        local t = {}
                        for i = 1, o:GetNumPoints() do
                            local a, rel, b, x, y = o:GetPoint(i)
                            local rn = "?"
                            if rel == p1.frame then rn = "OUR BAR" elseif rel == box then rn = "Blizzard bar box"
                            elseif rel == af1 then rn = "AurasFrame" elseif rel == uf1 then rn = "UnitFrame"
                            elseif type(rel) == "table" and rel.GetName then rn = tostring(rel:GetName() or rel:GetObjectType()) end
                            t[#t + 1] = ("%s -> %s %s (%.0f, %.0f)"):format(tostring(a), rn, tostring(b), x or 0, y or 0)
                        end
                        return (#t > 0 and table.concat(t, "; ") or "no points") .. (", scale %.2f"):format(o:GetScale())
                    end)
                    return ok and r or ("unreadable: " .. tostring(r))
                end
                local kids = "?"
                pcall(function()
                    local t = {}
                    for i, ch in ipairs({ dl:GetChildren() }) do
                        if i <= 4 then t[#t + 1] = ("%s left=%s w=%s"):format(tostring(ch:IsShown()), tostring(ch:GetLeft()), tostring(ch:GetWidth())) end
                    end
                    kids = #t .. "+ children: " .. table.concat(t, " | ")
                end)
                print("  debuff row: move " .. tostring(p1.dlMove) .. "; bar box resize " .. tostring(p1.boxFit))
                print("  debuff row anchors: " .. pts(dl))
                print("  AurasFrame anchors: " .. pts(af1))
                print("  debuff row " .. kids)
                print("  geometry: ours " .. geo(p1.frame) .. "; Blizzard bar box " .. geo(box) .. "; Blizzard debuff row " .. geo(dl))
            end
            print("  debuff lookup on " .. p1.unit .. ": ShouldAurasBeSecret=" .. tostring(AurasSecret())
                .. ", GetUnitAuraInstanceIDs=" .. tostring(C_UnitAuras.GetUnitAuraInstanceIDs ~= nil))
            do
                local l, src = FetchByInstanceID(p1.unit, db.auraMax)
                print(("    by instance number -> %s"):format(l and (#l .. " aura(s), icons " .. (l[1] and tostring(l[1].icon ~= nil) or "-")) or ("failed: " .. tostring(src))))
            end
            ask("HARMFUL|PLAYER", "HARMFUL|PLAYER", db.auraMax)
            ask("HARMFUL|PLAYER (no limit)", "HARMFUL|PLAYER")
            ask("HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY", "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY")
            ask("HARMFUL (anyone's)", "HARMFUL")
            local a1 = p1.auras[1]
            print(("    first icon: %s, shown=%s, size=%s, alpha=%s, parent shown=%s; plate alpha=%s"):format(
                tostring(a1 ~= nil), tostring(a1 and a1:IsShown()), tostring(a1 and a1:GetWidth()),
                tostring(a1 and a1:GetEffectiveAlpha()), tostring(p1.frame:IsShown()), tostring(p1.frame:GetAlpha())))
        end
        local sb = CreateFrame("StatusBar")
        print(("  API: UnitHealthPercent=%s, AbbreviateNumbers=%s, UnitCastingDuration=%s, SetTimerDuration=%s, SetAlphaFromBoolean=%s")
            :format(tostring(_G.UnitHealthPercent ~= nil), tostring(_G.AbbreviateNumbers ~= nil),
                tostring(_G.UnitCastingDuration ~= nil), tostring(sb.SetTimerDuration ~= nil), tostring(sb.SetAlphaFromBoolean ~= nil)))
    end,
}

-- timed by /skt cpu
ns.Profile("Nameplates", driver)
