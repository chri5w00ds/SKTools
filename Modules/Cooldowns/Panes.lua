--[[-------------------------------------------------------------------------
  SKTools - cooldown panes

  Our own display of Blizzard's Cooldown Manager. You choose what is tracked
  in the Cooldown Manager; its own panes are made invisible and SKTools
  shows everything:

    The main block, top to bottom: the Essential cooldowns, health, your main
      power, a Druid form's power when in one, and the cast bar along the
      bottom while casting (nothing above it moves).
    Tracked buffs, Utility, Items (on-use trinkets) and Tracked bars, each a
      pane of its own.

  Icons: cooldown sweep and its number in the middle; stacks and charges top
  right; out of range turns the icon red; short of the resource for it, the
  icon greys and a thin frame in the resource's colour fills clockwise from
  12 o'clock as you build up to the cost (red too when out of range).
  Tracked buffs and tracked bars show only while their buff is up.

  Icons are a fixed size, grown from the centre line. Icons per row is a cap:
  as few rows as it allows, spread evenly. The main block and the tracked
  buffs keep their shorter rows on top (the full row meets the bars); Utility
  and Items keep them at the bottom. A thin white outline follows the shape,
  its outer corners rounded.

  How it reads Blizzard's panes: each of their icons is mirrored. When the
  game sets a cooldown or a stack count on its icon, the same values (hidden
  ones too) are passed on to ours, so ours run in combat as theirs do.
---------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function Ask(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e
end

local FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_THIN = "Fonts\\ARIALN.TTF"            -- condensed, for the bar numbers
local BAR_TEX = "Interface\\Buttons\\WHITE8X8"

-- the SKTools pastels (as on the nameplates), plus a pastel rage
local COLORS = {
    health = { 0.25, 0.62, 0.30 },
    mana   = { 0.45, 0.72, 0.92 },
    energy = { 0.86, 0.78, 0.52 },
    rage   = { 0.84, 0.42, 0.44 },
    focus  = { 0.90, 0.62, 0.40 },
    other  = { 0.75, 0.75, 0.80 },
    cast   = { 0.93, 0.52, 0.72 },        -- pink, a pastel like the rest
    range  = { 0.95, 0.22, 0.20 },
    track  = { 0.055, 0.055, 0.065 },
}
ns.CDM_COLORS = COLORS

local PT = (Enum and Enum.PowerType) or {}
local MANA, RAGE, FOCUS, ENERGY = PT.Mana or 0, PT.Rage or 1, PT.Focus or 2, PT.Energy or 3
local POWER_KEY = { [MANA] = "mana", [RAGE] = "rage", [FOCUS] = "focus", [ENERGY] = "energy" }

ns.CDM_DEFAULTS = {
    enabled      = true,
    berryEnabled = false,     -- Berry Mode keeps its own switch, off until turned on
    snap         = true,      -- moved panes snap to a grid (the buff widgets' too)
    grid         = 8,
    hideBlizzard = true,      -- Blizzard's Cooldown Manager panes invisible (they keep updating: ours read them)
    replacePRD   = true,      -- Blizzard's personal resource display off while the block shows health and power
    hideCastBar  = true,      -- Blizzard's own cast bar off while ours shows
    unlocked     = false,
    -- x, y: from the middle of the screen to each pane's fixed edge: the bottom of the Essential icons
    -- and of the tracked buffs (they grow up), the top of the others
    -- sizes in pixels; while snapping to the grid they are taken in whole grid boxes
    block   = { x = 0,    y = -136, width = 224, health = 16, power = 8, cast = 16 },
    essential = { x = 0,  y = -135, size = 40, cap = 6 },      -- a pixel above the bars: their frames share a line
    buffs   = { x = 0,    y = -87,  size = 32, cap = 6 },
    utility = { x = 0,    y = -200, size = 32, cap = 7 },
    items   = { x = 152,  y = -96,  size = 32, cap = 2 },
    bars    = { x = -240, y = -96,  width = 168, height = 16 },
    -- our resource display (the block's bars): the settings the Blizzard one had
    res     = { alpha = 1, gradient = 0, cylinder = 0, druidEnergy = false, colors = {} },
}
local GRADIENT_MAX, CYLINDER_MAX = 0.70, 0.90
local GRADIENT_TEXTURE = ns.MEDIA .. "gradient.tga"   -- black on the left, clear on the right
local CYLINDER_TEXTURE = ns.MEDIA .. "cylinder.tga"   -- dark top and bottom edges

local VIEWERS = {
    essential = "EssentialCooldownViewer",
    utility = "UtilityCooldownViewer",
    buffs   = "BuffIconCooldownViewer",
    bars    = "BuffBarCooldownViewer",
}
local GROW = { essential = "up", buffs = "up", utility = "down", items = "down" }

local db
local panes = {}
local state = { panes = {}, blizzard = "-" }

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

-- on: its own switch for the mode in use (off in Berry Mode until turned on there: see Core.lua)
local function On()
    return db and ns.FeatureOn(db) or false
end

-- one pane: the panes on, and that pane not switched off on its own
local function PaneOn(key)
    if not On() then return false end
    local t = db[key]
    return not (type(t) == "table" and t.show == false)
end

local function InCombat()
    local ok, r = pcall(_G.InCombatLockdown or function() return false end)
    if ok and Plain(r) == true then return true end
    local ok2, r2 = pcall(UnitAffectingCombat, "player")
    return ok2 and Plain(r2) == true
end

-- the nameplates' bar look: light at the top, dark at the bottom
local function Clamp01(v) return math.max(0, math.min(1, v)) end
local function Gradient(tex, c, lift)
    lift = lift or 1
    local top = { Clamp01(c[1] * 1.15 + 0.12), Clamp01(c[2] * 1.15 + 0.12), Clamp01(c[3] * 1.15 + 0.12) }
    local bot = { c[1] * 0.55 * lift, c[2] * 0.55 * lift, c[3] * 0.55 * lift }
    local ok = false
    if tex.SetGradient and _G.CreateColor then
        ok = pcall(tex.SetGradient, tex, "VERTICAL",
            CreateColor(bot[1], bot[2], bot[3], 1), CreateColor(top[1], top[2], top[3], 1))
    end
    if not ok then tex:SetVertexColor(c[1], c[2], c[3], 1) end
end

----------------------------------------------------------------------
-- Snap to grid: a faint grid on the screen while panes are unlocked; a dropped pane's place is
-- rounded to the nearest grid point (from the middle of the screen, where the grid's bright lines
-- cross). Used by the buff widgets' panes too.
----------------------------------------------------------------------
-- one screen pixel, in the frame's units
local function Px(frame)
    local scale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    if PixelUtil and PixelUtil.GetNearestPixelSize then
        local ok, v = pcall(PixelUtil.GetNearestPixelSize, 1, scale, 1)
        if ok and type(v) == "number" and v > 0 then return v end
    end
    local okH, h = pcall(function() return select(2, GetPhysicalScreenSize()) end)
    if okH and type(h) == "number" and h > 0 and scale > 0 then return 768 / h / scale end
    return 1
end

local gridFrame
local function GridSize() return math.max(2, (db and db.grid) or 8) end
local function Snap(x, y)
    if not (db and db.snap ~= false) then return x, y end
    local g = GridSize()
    return math.floor(x / g + 0.5) * g, math.floor(y / g + 0.5) * g
end
local function SnapOne(v)
    if not (db and db.snap ~= false) then return v end
    local g = GridSize()
    return math.floor(v / g + 0.5) * g
end
-- a size in whole grid boxes (at least one) while snapping is on
local function Boxes(v)
    if not (db and db.snap ~= false) then return v end
    local g = GridSize()
    return math.max(g, math.floor(v / g + 0.5) * g)
end
-- the pixel taken off a pane's far side while snapping, so its far frame line lands on a grid line too
-- (each frame line sits a pixel outside the pane; a grid line starts at its position)
local function Trim(p) return (db and db.snap ~= false) and Px(p) or 0 end
local function ShowGrid(on)
    if not on then if gridFrame then gridFrame:Hide() end; return end
    local g = GridSize()
    if not gridFrame then
        gridFrame = CreateFrame("Frame", "SKToolsGrid", UIParent)
        gridFrame:SetAllPoints(UIParent)
        gridFrame:SetFrameStrata("BACKGROUND")
        gridFrame.lines = {}
    end
    local onePx = Px(gridFrame)
    if gridFrame.size ~= g or gridFrame.px ~= onePx then
        gridFrame.size, gridFrame.px = g, onePx
        for _, t in ipairs(gridFrame.lines) do t:Hide() end
        local w, h = UIParent:GetWidth() or 1920, UIParent:GetHeight() or 1080
        local n = 0
        local function Line(vertical, off)
            n = n + 1
            local t = gridFrame.lines[n]
            if not t then t = gridFrame:CreateTexture(nil, "BACKGROUND"); gridFrame.lines[n] = t end
            t:ClearAllPoints()
            local centre = math.abs(off) < 0.5
            local major = (math.floor(off / g + 0.5) % 8 == 0)
            t:SetColorTexture(centre and 1 or 0.6, centre and 0.85 or 0.8, centre and 0.3 or 1, centre and 0.5 or (major and 0.22 or 0.09))
            -- one screen pixel wide, starting at its grid position: a pane's frame line snaps onto it
            if vertical then t:SetPoint("TOPLEFT", gridFrame, "TOP", off, 0); t:SetSize(onePx, h)
            else t:SetPoint("BOTTOMLEFT", gridFrame, "LEFT", 0, off); t:SetSize(w, onePx) end
            t:Show()
        end
        for x = 0, w / 2, g do Line(true, x); if x > 0 then Line(true, -x) end end
        for y = 0, h / 2, g do Line(false, y); if y > 0 then Line(false, -y) end end
    end
    gridFrame:Show()
end
ns.Snap = function(x, y) return Snap(x, y) end

----------------------------------------------------------------------
-- Layout: icons per row as a cap
----------------------------------------------------------------------

-- rows for count icons with at most cap per row: as few rows as possible, spread evenly. Returned
-- top to bottom; the fuller rows sit on the side the pane grows from ("up": the bottom, "down": the top).
local function Rows(count, cap, grow)
    cap = math.max(1, cap or 6)
    if count <= 0 then return {}, 0 end
    local rows = math.ceil(count / cap)
    local base, extra = math.floor(count / rows), count % rows
    local sizes = {}
    for r = 1, rows do
        local full
        if grow == "up" then full = r > rows - extra else full = r <= extra end
        sizes[r] = base + (full and 1 or 0)
    end
    return sizes, math.ceil(count / rows)
end
ns.CDM_Rows = Rows

----------------------------------------------------------------------
-- Panes that grow by rows: the line pool (seams)
----------------------------------------------------------------------

local function LinePool(parent)
    local pool = { n = 0, parent = parent, list = {} }
    function pool:Get()
        self.n = self.n + 1
        local t = self.list[self.n]
        if not t then
            t = self.parent:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetColorTexture(0, 0, 0, 1)
            self.list[self.n] = t
        end
        t:ClearAllPoints()
        t:SetVertexColor(1, 1, 1, 1)
        t:SetAlpha(1)
        t:Show()
        return t
    end
    function pool:Done() for i = self.n + 1, #self.list do self.list[i]:Hide() end; self.n = 0 end
    return pool
end
----------------------------------------------------------------------
-- Frames: a ring round each pane (or round each set of equal-width rows of one), drawn on top of the
-- content: four corner pieces (Media\RingCorner: a smooth rounded band that also covers the
-- content's square corner) and four one-pixel edges. The buff widget frames' silver, bright at the
-- top of the pane and darker towards the bottom. Sizes are whole screen pixels at your UI scale, so
-- every edge is equally thin.
----------------------------------------------------------------------

local RING_CORNER = ns.MEDIA .. "RingCorner"
local SILVER_TOP, SILVER_BOTTOM = { 0.94, 0.94, 0.96 }, { 0.58, 0.59, 0.63 }
local function SilverAt(f)
    f = math.max(0, math.min(1, f))
    return SILVER_TOP[1] + (SILVER_BOTTOM[1] - SILVER_TOP[1]) * f, SILVER_TOP[2] + (SILVER_BOTTOM[2] - SILVER_TOP[2]) * f,
        SILVER_TOP[3] + (SILVER_BOTTOM[3] - SILVER_TOP[3]) * f
end

local CORNERS = {          -- the piece is drawn for the top-left corner; flipped for the others
    { "tl", 0, 1, 0, 1 }, { "tr", 1, 0, 0, 1 }, { "bl", 0, 1, 1, 0 }, { "br", 1, 0, 1, 0 },
}
local function RingPool(p)
    local pool = { n = 0, list = {} }
    function pool:Get()
        self.n = self.n + 1
        local r = self.list[self.n]
        if not r then
            r = { corner = {}, edge = {} }
            for i, c in ipairs(CORNERS) do
                local t = p.over:CreateTexture(nil, "OVERLAY", nil, 6)
                pcall(t.SetTexture, t, RING_CORNER, nil, nil, "TRILINEAR")
                t:SetTexCoord(c[2], c[3], c[4], c[5])
                r.corner[i] = t
            end
            for i = 1, 4 do r.edge[i] = p.over:CreateTexture(nil, "OVERLAY", nil, 6) end
            self.list[self.n] = r
        end
        for _, t in ipairs(r.corner) do t:Show() end
        for _, t in ipairs(r.edge) do t:Show() end
        return r
    end
    function pool:Done()
        for i = self.n + 1, #self.list do
            for _, t in ipairs(self.list[i].corner) do t:Hide() end
            for _, t in ipairs(self.list[i].edge) do t:Hide() end
        end
        self.n = 0
    end
    return pool
end
-- a ring round a box (x from the pane's centre line, y down from its top), its edges one pixel
-- outside the box; total: the pane's height, for the silver's shading
-- where the pane is on the screen, to put a line on whole pixels: a one-pixel line between two pixels
-- can be drawn as no pixels at all (the right-hand line of a pane went missing that way)
local function PixelSnapper(p, t)
    local okL, L = pcall(p.GetLeft, p)
    local okT, T = pcall(p.GetTop, p)
    local okW, Wp = pcall(p.GetWidth, p)
    if not (okL and okT and okW and type(L) == "number" and type(T) == "number" and type(Wp) == "number" and t > 0) then
        return function(v) return v end, function(v) return v end
    end
    local cx = L + Wp / 2
    local function SX(x) return math.floor((cx + x) / t + 0.5) * t - cx end
    local function SY(y) return T - math.floor((T - y) / t + 0.5) * t end
    return SX, SY
end

local function Ring(p, x, y, w, h, total, white)
    local r = p.rings:Get()
    local t = Px(p)
    local C = 3 * t
    local SX, SY = PixelSnapper(p, t)
    -- the box's edges, each on a pixel boundary; the lines just outside them
    local X0, Y0 = SX(x) - t, SY(y) - t
    local W, H = (SX(x + w) + t) - X0, (SY(y + h) + t) - Y0
    local function At(yy)
        if white then return 1, 1, 1 end
        return SilverAt(total > 0 and yy / total or 0)
    end
    local pos = { tl = { X0, Y0 }, tr = { X0 + W - C, Y0 }, bl = { X0, Y0 + H - C }, br = { X0 + W - C, Y0 + H - C } }
    for i, c in ipairs(CORNERS) do
        local tex = r.corner[i]
        tex:ClearAllPoints()
        tex:SetSize(C, C)
        tex:SetPoint("TOPLEFT", p, "TOP", pos[c[1]][1], -pos[c[1]][2])
        tex:SetVertexColor(At(pos[c[1]][2] + C / 2))
    end
    local e = r.edge
    -- top, bottom
    e[1]:ClearAllPoints(); e[1]:SetColorTexture(At(Y0)); e[1]:SetSize(math.max(0, W - 2 * C), t)
    e[1]:SetPoint("TOPLEFT", p, "TOP", X0 + C, -Y0)
    e[2]:ClearAllPoints(); e[2]:SetColorTexture(At(Y0 + H)); e[2]:SetSize(math.max(0, W - 2 * C), t)
    e[2]:SetPoint("TOPLEFT", p, "TOP", X0 + C, -(Y0 + H - t))
    -- left, right: shaded down their length
    for i, ex in ipairs({ X0, X0 + W - t }) do
        local s = e[2 + i]
        s:ClearAllPoints()
        s:SetColorTexture(1, 1, 1, 1)
        local r0, g0, b0 = At(Y0 + C); local r1, g1, b1 = At(Y0 + H - C)
        if not (s.SetGradient and _G.CreateColor and pcall(s.SetGradient, s, "VERTICAL",
            CreateColor(r1, g1, b1, 1), CreateColor(r0, g0, b0, 1))) then s:SetColorTexture(r0, g0, b0, 1) end
        s:SetSize(t, math.max(0, H - 2 * C))
        s:SetPoint("TOPLEFT", p, "TOP", ex, -(Y0 + C))
    end
    return r
end
-- rings for a stack of rows ({ w, h, y } each, centred): one per run of equal-width rows
local function FrameRows(p, rows, total)
    local i = 1
    while i <= #rows do
        local j = i
        while rows[j + 1] and math.abs(rows[j + 1][1] - rows[i][1]) < 0.5 do j = j + 1 end
        local top = rows[i][3]
        Ring(p, -rows[i][1] / 2, top, rows[i][1], rows[j][3] + rows[j][2] - top, total)
        i = j + 1
    end
end
-- a fine dark seam across a pane at y (between bars), or down it at x (between icons)
local function Seam(p, x, y, w, h)
    local t = p.lines:Get()
    t:SetTexture(nil); t:SetColorTexture(0, 0, 0, 0.6); t:SetTexCoord(0, 1, 0, 1)
    t:SetPoint("TOPLEFT", p, "TOP", x, -y); t:SetSize(w, h)
end

----------------------------------------------------------------------
-- Icons
----------------------------------------------------------------------

-- the resource frame: five little bars round the edge, filling clockwise from 12 o'clock. Each covers
-- a share of the cost, so given your power (even hidden) the frame fills as far as you have.
local FRAME_SEGS = {
    -- share of the perimeter, where it sits, how it fills
    { 0.125, "top-right" }, { 0.25, "right" }, { 0.25, "bottom" }, { 0.25, "left" }, { 0.125, "top-left" },
}
local function MakeResourceFrame(f)
    local rf = CreateFrame("Frame", nil, f)
    rf:SetAllPoints()
    rf:SetFrameLevel(f:GetFrameLevel() + 4)
    rf.segs = {}
    for i, sg in ipairs(FRAME_SEGS) do
        local b = CreateFrame("StatusBar", nil, rf)
        b:SetStatusBarTexture(BAR_TEX)
        b.track = b:CreateTexture(nil, "BACKGROUND")
        b.track:SetAllPoints()
        b.track:SetColorTexture(0, 0, 0, 0.75)                -- the part not yet filled: black, 75%
        b.where = sg[2]
        if b.where == "right" or b.where == "left" then b:SetOrientation("VERTICAL") end
        -- clockwise: the right edge fills downwards, the bottom leftwards
        if b.where == "right" or b.where == "bottom" then b:SetReverseFill(true) end
        b:SetMinMaxValues(0, 1)
        b:SetValue(0)
        rf.segs[i] = b
    end
    rf:Hide()
    return rf
end
local function LayoutResourceFrame(rf, s)
    local t = math.max(1.5, s * 2 / 36)                       -- on the icon's own edge
    for _, b in ipairs(rf.segs) do
        b:ClearAllPoints()
        if b.where == "top-right" then b:SetPoint("TOPLEFT", rf, "TOP", 0, 0); b:SetPoint("TOPRIGHT", rf, "TOPRIGHT", 0, 0); b:SetHeight(t)
        elseif b.where == "right" then b:SetPoint("TOPRIGHT"); b:SetPoint("BOTTOMRIGHT"); b:SetWidth(t)
        elseif b.where == "bottom" then b:SetPoint("BOTTOMLEFT"); b:SetPoint("BOTTOMRIGHT"); b:SetHeight(t)
        elseif b.where == "left" then b:SetPoint("TOPLEFT"); b:SetPoint("BOTTOMLEFT"); b:SetWidth(t)
        else b:SetPoint("TOPLEFT"); b:SetPoint("TOPRIGHT", rf, "TOP", 0, 0); b:SetHeight(t) end
    end
end
-- have / cost: given the cost and your power (plain or hidden), each segment covers its share of it
local function FillResourceFrame(rf, power, cost, color)
    local at = 0
    for i, b in ipairs(rf.segs) do
        local share = FRAME_SEGS[i][1]
        b:SetMinMaxValues(cost * at, cost * (at + share))
        at = at + share
        if not pcall(b.SetValue, b, power) then b:SetValue(0) end
        b:SetStatusBarColor(color[1], color[2], color[3], 1)
    end
    rf:Show()
end

local function MakeIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- rounded corners on the picture (and the cooldown sweep below), so nothing square shows past the
    -- frame's rounded corners; made once, its texture picked by the icon's size in SizeIcon
    if f.CreateMaskTexture and f.tex.AddMaskTexture then
        local okM, m = pcall(f.CreateMaskTexture, f)
        if okM and m then
            m:SetAllPoints(f.tex)
            pcall(f.tex.AddMaskTexture, f.tex, m)
            f.mask = m
        end
    end
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, f, "CooldownFrameTemplate")
    if ok and cd then
        cd:SetAllPoints()
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        if cd.SetDrawBling then cd:SetDrawBling(false) end
        if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(false) end   -- the number in the middle
        if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.62) end
        f.cd = cd
    end
    f.top = CreateFrame("Frame", nil, f)
    f.top:SetAllPoints()
    f.top:SetFrameLevel(f:GetFrameLevel() + 6)
    f.stack = f.top:CreateFontString(nil, "OVERLAY")
    f.stack:SetPoint("TOPRIGHT", -2, -2)
    f.stack:SetJustifyH("RIGHT")
    f.res = MakeResourceFrame(f)
    -- the "use it now" glow (Blizzard's spell alert on its icon): a pulsing gold glow round ours
    f.glow = f.top:CreateTexture(nil, "OVERLAY", nil, -1)
    f.glow:SetTexture(ns.MEDIA .. "IconGlow")
    f.glow:SetBlendMode("ADD")
    f.glow:SetVertexColor(1, 0.85, 0.35, 1)
    f.glow:SetPoint("CENTER")
    f.glow:Hide()
    if f.glow.CreateAnimationGroup or f.CreateAnimationGroup then
        local ok, ag = pcall(function() return (f.top.CreateAnimationGroup and f.top:CreateAnimationGroup()) end)
        if ok and ag then
            ag:SetLooping("BOUNCE")
            local a = ag:CreateAnimation("Alpha")
            a:SetFromAlpha(1); a:SetToAlpha(0.45); a:SetDuration(0.5)
            a:SetTarget(f.glow)
            f.glowAnim = ag
        end
    end
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        if not _G.GameTooltip or not self.spellID then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if not pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID) then GameTooltip:SetText(tostring(self.name or "")) end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    return f
end
-- the rounded-corner mask for an icon s units wide: a corner of about 3.5 screen pixels at any size
local function IconMask(f, s)
    local px = s / math.max(Px(f), 0.01)
    local r = math.max(3, math.min(12, math.floor(3.5 * 64 / math.max(px, 1) + 0.5)))
    return ns.MEDIA .. "IconMask" .. r
end

local function SizeIcon(f, s)
    f:SetSize(s, s)
    local mask = IconMask(f, s)
    if f.maskPath ~= mask then
        f.maskPath = mask
        if f.mask then pcall(f.mask.SetTexture, f.mask, mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
        if f.cd and f.cd.SetSwipeTexture then pcall(f.cd.SetSwipeTexture, f.cd, mask) end
    end
    f.glow:SetSize(s * 1.6, s * 1.6)
    f.stack:SetFont(FONT, math.max(8, math.floor(s * 0.32)), "OUTLINE")
    LayoutResourceFrame(f.res, s)
    if f.cd and f.cd.GetRegions then
        -- the countdown number: sized to the icon
        for _, r in ipairs({ f.cd:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" and r.SetFont then
                pcall(r.SetFont, r, FONT, math.max(8, math.floor(s * 0.36)), "OUTLINE")
            end
        end
    end
end

----------------------------------------------------------------------
-- Mirroring Blizzard's icons
----------------------------------------------------------------------

local mirrorOf = setmetatable({}, { __mode = "k" })   -- Blizzard's widget -> our icon or bar currently fed by it
local hooked = setmetatable({}, { __mode = "k" })

local function Hook(obj, method, fn)
    if type(obj) ~= "table" or type(obj[method]) ~= "function" then return end
    hooked[obj] = hooked[obj] or {}
    if hooked[obj][method] then return end
    hooked[obj][method] = true
    pcall(hooksecurefunc, obj, method, fn)
end

local function ItemCall(item, method)
    if type(item[method]) ~= "function" then return nil end
    local ok, r = pcall(item[method], item)
    return ok and r or nil
end
local function ItemSpell(item)
    local id = Plain(ItemCall(item, "GetSpellID"))
    if id then return id end
    local info = item.cooldownInfo or ItemCall(item, "GetCooldownInfo")
    if type(info) == "table" then
        return Plain(info.overrideSpellID) or Plain(info.spellID)
    end
    return nil
end
local function ItemActive(item)
    local a = Plain(item.isActive)
    if a ~= nil then return a end
    if item.auraDataCached ~= nil or item.totemData ~= nil then return true end
    local c = ItemCall(item, "GetAuraDataCached")
    return c ~= nil
end

-- one of Blizzard's widgets feeds one of our icons or bars. An icon of ours can be handed another of
-- Blizzard's (the tracked buffs come and go): the widget it had before is let go, so it can no longer
-- clear or overwrite what the icon shows now. Returns true when the link is new.
local function Link(target, slot, widget)
    target.src = target.src or {}
    local old = target.src[slot]
    if old == widget and (widget == nil or mirrorOf[widget] == target) then return false end
    if old ~= nil and mirrorOf[old] == target then mirrorOf[old] = nil end
    target.src[slot] = widget
    if widget ~= nil then mirrorOf[widget] = target end
    return true
end

-- Blizzard's spell alerts ("use it now"): which item frames have one, shown on the icon fed by each
local alertOn = setmetatable({}, { __mode = "k" })
local itemIcon = setmetatable({}, { __mode = "k" })         -- Blizzard's item frame -> our icon
local function ShowGlow(icon, on)
    if not icon or not icon.glow then return end
    icon.glow:SetShown(on and true or false)
    if icon.glowAnim then if on then icon.glowAnim:Play() else icon.glowAnim:Stop() end end
end
local alertsHooked = false
local function HookAlerts()
    if alertsHooked then return end
    local m = _G.ActionButtonSpellAlertManager
    if type(m) ~= "table" then return end
    alertsHooked = true
    Hook(m, "ShowAlert", function(_, frame) if type(frame) == "table" then alertOn[frame] = true; ShowGlow(itemIcon[frame], true) end end)
    Hook(m, "HideAlert", function(_, frame) if type(frame) == "table" then alertOn[frame] = nil; ShowGlow(itemIcon[frame], false) end end)
end

-- In combat the game hides cooldown and buff times from addons, and a cooldown spiral will not take
-- them from us. What it does take is the game's own duration objects: one for the buff (while it is
-- up) or for the spell's cooldown, asked for by spell and by aura.
local function Hidden(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v ~= nil and Plain(v) == nil then return true end
    end
    return false
end
local function DurationFallback(cd, item)
    if not (cd and cd.SetCooldownFromDurationObject and item) then return false end
    -- the buff, while it is up
    local aura = item.auraDataCached
    if aura == nil then aura = ItemCall(item, "GetAuraDataCached") end
    local api = _G.C_UnitAuras
    if type(aura) == "table" and aura.auraInstanceID ~= nil and api and api.GetAuraDuration then
        local unit = ItemCall(item, "GetAuraDataUnit") or "player"
        local ok, d = pcall(api.GetAuraDuration, unit, aura.auraInstanceID)
        if ok and d ~= nil and pcall(cd.SetCooldownFromDurationObject, cd, d) then return true end
    end
    -- the spell's cooldown (or the cooldown of its next charge)
    local id = ItemSpell(item)
    local sp = _G.C_Spell
    if id and sp then
        for _, fn in ipairs({ sp.GetSpellCooldownDuration, sp.GetSpellChargeDuration }) do
            if fn then
                local ok, d = pcall(fn, id)
                if ok and d ~= nil and pcall(cd.SetCooldownFromDurationObject, cd, d) then return true end
            end
        end
    end
    return false
end

-- the cooldown an item shows right now, put on our icon when the icon is first given it (the game's
-- numbers may be hidden from us: they are handed on as they are, never worked with)
local function Seed(item, cd, cdf)
    -- a spell: the values Blizzard worked out for its own icon
    if item.cooldownStartTime ~= nil then
        if Plain(item.cooldownStartTime) == 0 or item.cooldownEnabled == false then pcall(cd.Clear, cd); return end
        if Hidden(item.cooldownStartTime, item.cooldownDuration) and DurationFallback(cd, item) then return end
        if pcall(cd.SetCooldown, cd, item.cooldownStartTime, item.cooldownDuration, item.cooldownModRate or 1) then return end
    end
    -- a buff: when it runs out, and how long it lasts
    if type(item.GetCooldownValues) == "function" then
        local ok, exp, dur, mod = pcall(item.GetCooldownValues, item)
        if ok and exp ~= nil and dur ~= nil then
            local pe, pd = Plain(exp), Plain(dur)
            if pe and pd then
                if pe - GetTime() > 0 and pd > 0 then pcall(cd.SetCooldown, cd, pe - pd, pd, Plain(mod) or 1) else pcall(cd.Clear, cd) end
                return
            end
            if DurationFallback(cd, item) then return end
            if cd.SetCooldownFromExpirationTime and pcall(cd.SetCooldownFromExpirationTime, cd, exp, dur, mod) then return end
        end
    end
    -- what Blizzard's own cooldown frame shows
    if cdf.GetCooldownTimes then
        local ok, start, dur = pcall(cdf.GetCooldownTimes, cdf)
        if ok and start ~= nil and dur ~= nil then
            local ps, pd = Plain(start), Plain(dur)
            if ps and pd then
                if pd > 0 then pcall(cd.SetCooldown, cd, ps / 1000, pd / 1000) else pcall(cd.Clear, cd) end
            end
        end
    end
end

-- feed one of our icons from one of Blizzard's: its cooldown (and how it is drawn), its count text,
-- and its spell alert, as the game sets them
local function Mirror(item, icon)
    HookAlerts()
    -- this icon now stands for this item
    if icon.item ~= item then
        if icon.item and itemIcon[icon.item] == icon then itemIcon[icon.item] = nil end
        icon.item = item
    end
    itemIcon[item] = icon
    ShowGlow(icon, alertOn[item])
    local cdf = ItemCall(item, "GetCooldownFrame") or item.Cooldown
    if type(cdf) == "table" then
        local fresh = Link(icon, "cd", cdf)
        local function Pass(method)
            Hook(cdf, method, function(self, ...)
                local m = mirrorOf[self]
                if m and m.cd and m.cd[method] then pcall(m.cd[method], m.cd, ...) end
            end)
        end
        -- Blizzard setting its spiral from times: hidden ones (in combat) go by the game's duration objects
        for _, method in ipairs({ "SetCooldown", "SetCooldownFromExpirationTime" }) do
            Hook(cdf, method, function(self, ...)
                local m = mirrorOf[self]
                if not (m and m.cd and m.cd[method]) then return end
                if Hidden(...) and DurationFallback(m.cd, m.item) then return end
                pcall(m.cd[method], m.cd, ...)
            end)
        end
        for _, method in ipairs({ "SetCooldownFromDurationObject", "SetCooldownDuration", "Clear", "Pause", "Resume",
            "SetSwipeColor", "SetUseAuraDisplayTime", "SetReverse" }) do
            Pass(method)
        end
        if fresh and icon.cd then
            -- how it is drawn: a buff's time (gold) or a cooldown (dark), as Blizzard has it
            local c = item.cooldownSwipeColor
            if type(c) == "table" and c.r then pcall(icon.cd.SetSwipeColor, icon.cd, c.r, c.g, c.b, c.a or 0.7)
            elseif not item.cooldownStartTime and type(item.GetCooldownValues) == "function" then
                pcall(icon.cd.SetSwipeColor, icon.cd, 0, 0, 0, 0.7)
            end
            if item.cooldownUseAuraDisplayTime ~= nil and icon.cd.SetUseAuraDisplayTime then
                pcall(icon.cd.SetUseAuraDisplayTime, icon.cd, item.cooldownUseAuraDisplayTime == true)
            end
            Seed(item, icon.cd, cdf)
        end
    end
    -- stacks (buffs) or charges (cooldowns)
    local fs = ItemCall(item, "GetApplicationsFontString")
    if not fs then
        local cf = ItemCall(item, "GetChargeCountFrame") or item.ChargeCount
        fs = type(cf) == "table" and cf.Current or nil
    end
    if type(fs) == "table" and fs.SetText then
        local fresh = Link(icon, "stack", fs)
        Hook(fs, "SetText", function(self, text) local m = mirrorOf[self]; if m and m.stack then pcall(m.stack.SetText, m.stack, text) end end)
        if fresh then
            local okT, txt = pcall(fs.GetText, fs)
            if okT then pcall(icon.stack.SetText, icon.stack, txt) end
        end
    end
end

-- a tracked bar: its fill, name and time left, as the game sets them
local function MirrorBar(item, bar)
    local sb = ItemCall(item, "GetBarFrame") or item.Bar
    if type(sb) == "table" then
        Link(bar, "bar", sb)
        Hook(sb, "SetMinMaxValues", function(self, ...) local m = mirrorOf[self]; if m then pcall(m.bar.SetMinMaxValues, m.bar, ...) end end)
        Hook(sb, "SetValue", function(self, v) local m = mirrorOf[self]; if m then pcall(m.bar.SetValue, m.bar, v) end end)
        if sb.GetMinMaxValues then
            local ok, lo, hi = pcall(sb.GetMinMaxValues, sb)
            if ok then pcall(bar.bar.SetMinMaxValues, bar.bar, lo, hi) end
            local okV, v = pcall(sb.GetValue, sb)
            if okV then pcall(bar.bar.SetValue, bar.bar, v) end
        end
    end
    for _, pair in ipairs({ { "GetNameFontString", "name" }, { "GetDurationFontString", "time" } }) do
        local fs = ItemCall(item, pair[1])
        if type(fs) == "table" and fs.SetText then
            local key = pair[2]
            Link(bar, key, fs)
            Hook(fs, "SetText", function(self, text) local m = mirrorOf[self]; if m then pcall(m[key].SetText, m[key], text) end end)
            local ok, t = pcall(fs.GetText, fs)
            if ok then pcall(bar[key].SetText, bar[key], t) end
        end
    end
end

-- Blizzard's icons of one pane, in their order
local function Items(viewerName)
    local v = _G[viewerName]
    if type(v) ~= "table" or not v.GetItemFrames then return nil end
    local ok, items = pcall(v.GetItemFrames, v)
    if not ok or type(items) ~= "table" then return {} end
    local list = {}
    for _, it in ipairs(items) do
        if type(it) == "table" and (it.cooldownID or it.cooldownInfo or ItemSpell(it)) then list[#list + 1] = it end
    end
    table.sort(list, function(a, b) return (Plain(a.layoutIndex) or 0) < (Plain(b.layoutIndex) or 0) end)
    return list
end

-- Blizzard's panes: invisible (and not catching the mouse) while ours show
local blizzHidden = {}
local function HideBlizzard(on)
    for key, name in pairs(VIEWERS) do
        local v = _G[name]
        if type(v) == "table" and v.SetAlpha then
            if on then
                if v:GetAlpha() ~= 0 then pcall(v.SetAlpha, v, 0) end
                local list = Items(name) or {}
                for _, it in ipairs(list) do if it.EnableMouse then pcall(it.EnableMouse, it, false) end end
                blizzHidden[name] = true
            elseif blizzHidden[name] then
                pcall(v.SetAlpha, v, 1)
                for _, it in ipairs(Items(name) or {}) do if it.EnableMouse then pcall(it.EnableMouse, it, true) end end
                blizzHidden[name] = nil
            end
        end
    end
end

----------------------------------------------------------------------
-- Range and resource for a spell
----------------------------------------------------------------------

local function SpellRange(spellID)
    if not spellID then return nil end
    local ok, e = pcall(UnitExists, "target")
    if not (ok and Plain(e)) then return nil end
    local fn = (C_Spell and C_Spell.IsSpellInRange) or _G.IsSpellInRange
    local r = Plain(Ask(fn, spellID, "target"))
    if r == false or r == 0 then return false end
    if r == true or r == 1 then return true end
    return nil
end
-- short of power for it? returns the cost, your power (maybe hidden) and its colour key; nil when not short
local function SpellShort(spellID)
    if not spellID then return nil end
    local fn = (C_Spell and C_Spell.GetSpellPowerCost) or _G.GetSpellPowerCost
    local costs = Plain(Ask(fn, spellID))
    if type(costs) ~= "table" then return nil end
    for _, c in ipairs(costs) do
        local cost, ptype = Plain(c.cost), Plain(c.type)
        if cost and cost > 0 and ptype then
            local ok, raw = pcall(UnitPower, "player", ptype)
            if not ok then return nil end
            local have = Plain(raw)
            if have and have >= cost then return nil end
            if have == nil then
                -- hidden: the game's own "not enough" flag says whether to show it
                local usable = (C_Spell and C_Spell.IsSpellUsable) or _G.IsUsableSpell
                local _, noPower = Ask(usable, spellID)
                if Plain(noPower) ~= true then return nil end
            end
            return cost, raw, POWER_KEY[ptype] or "other"
        end
    end
    return nil
end

----------------------------------------------------------------------
-- Panes
----------------------------------------------------------------------

local function Settings(key) return db and db[key] end

local function MakeMover(p, key, label)
    p.mover = CreateFrame("Frame", nil, p)
    p.mover:SetFrameLevel(p:GetFrameLevel() + 50)
    ns.W.Fill(p.mover, 0.1, 0.4, 0.6, 0.18)
    ns.W.Border(p.mover, 0.4, 0.8, 1, 0.9, 1)
    p.mover.text = p.mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.mover.text:SetPoint("BOTTOM", p.mover, "TOP", 0, 2)
    p.mover.text:SetText(label)
    p.mover:EnableMouse(true)
    p.mover:RegisterForDrag("LeftButton")
    p:SetMovable(true)
    p:SetClampedToScreen(true)
    -- dragging moves the pane box by box: it follows the cursor in grid steps, its frame lines on grid
    -- lines, so where it shows while dragging is where it stays
    local function Moved()
        local d = p.drag
        local s = Settings(key)
        if not (d and s) then return end
        local cx, cy = GetCursorPosition()
        local sc = UIParent:GetEffectiveScale() or 1
        local dx, dy = (cx - d.cx) / sc, (cy - d.cy) / sc
        local onePx = Px(p)
        local w, h = p:GetWidth() or 0, p:GetHeight() or 0
        local half = w / 2
        -- the frame's left line onto a grid line (it sits a pixel left of the pane; a grid line starts
        -- at its position), and the frame line along the fixed edge
        local left = SnapOne(d.x - half + dx - onePx) + onePx
        local x = left + half
        local e = d.y + dy
        local y
        if p.fixed == "bottom" then y = SnapOne(e - onePx) + onePx else y = SnapOne(e) end
        -- other panes win over the grid: within a few pixels of one's top or bottom it sits flush (the two
        -- frames sharing a line); within a few of its centre line, it lines up on it
        if db and db.snap ~= false then
            local ux, uy = UIParent:GetCenter()
            -- measured from where the cursor has it (not the grid's step)
            local rx, ry = d.x + dx, e
            local me = { l = rx - half, r = rx + half }
            if p.fixed == "bottom" then me.b = ry; me.t = ry + h else me.t = ry + (p.drop or 0); me.b = me.t - h end
            local NEAR = 3
            local bdx, bdy
            for _, q in pairs(panes) do
                if q ~= p and q:IsShown() and q.GetLeft then
                    local l, r, t, b = q:GetLeft(), q:GetRight(), q:GetTop(), q:GetBottom()
                    if l and r and t and b and ux then
                        local fk = (q:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
                        local o = { l = l * fk - ux, r = r * fk - ux, t = t * fk - uy, b = b * fk - uy }
                        local below = (o.t + onePx) - me.b                -- sitting on top of it
                        local above = (o.b - onePx) - me.t                -- hanging under it
                        if math.abs(below) <= NEAR and (not bdy or math.abs(below) < math.abs(bdy)) then bdy = below end
                        if math.abs(above) <= NEAR and (not bdy or math.abs(above) < math.abs(bdy)) then bdy = above end
                        local oc = ((o.l + o.r) / 2) - rx
                        if math.abs(oc) <= NEAR and (not bdx or math.abs(oc) < math.abs(bdx)) then bdx = oc end
                    end
                end
            end
            if bdx then x = rx + bdx end
            if bdy then y = ry + bdy end
        end
        s.x, s.y = x, y
        p:ClearAllPoints()
        if p.fixed == "bottom" then p:SetPoint("BOTTOM", UIParent, "CENTER", x, y)
        else p:SetPoint("TOP", UIParent, "CENTER", x, y + (p.drop or 0)) end
    end
    p.mover:SetScript("OnDragStart", function()
        local s = Settings(key)
        if not s then return end
        local cx, cy = GetCursorPosition()
        p.drag = { cx = cx, cy = cy, x = s.x or 0, y = s.y or 0 }
        p.moving = true
    end)
    p.mover:SetScript("OnUpdate", function() if p.drag then Moved() end end)
    p.mover:SetScript("OnDragStop", function()
        if p.drag then Moved() end
        p.drag, p.moving = nil, nil
        ns.Cooldowns.Refresh()
    end)
    p.mover:SetScript("OnHide", function() p.drag, p.moving = nil, nil end)
    p.mover:Hide()
end

local function MakePane(key, label)
    local p = CreateFrame("Frame", "SKToolsCD" .. key:gsub("^%l", string.upper), UIParent)
    p:SetFrameStrata("MEDIUM")
    p:SetSize(10, 10)
    p.key = key
    p.icons = {}
    -- the outline sits on its own layer above the icons and bars
    p.over = CreateFrame("Frame", nil, p)
    p.over:SetAllPoints()
    p.over:SetFrameLevel(p:GetFrameLevel() + 40)
    p.lines = LinePool(p.over)
    p.rings = RingPool(p)
    p.back = p:CreateTexture(nil, "BACKGROUND")
    p.back:SetColorTexture(0, 0, 0, 0.5)
    p.back:Hide()
    MakeMover(p, key, label)
    panes[key] = p
    return p
end

-- place a pane by its fixed edge (so rows grow away from it): fixed = "top" or "bottom"; drop: how far
-- below the top the fixed line is (the main block's line between icons and bars)
local function Place(p, s, w, h, fixed, drop)
    p:SetSize(math.max(1, w), math.max(1, h))
    p.fixed, p.drop = fixed, drop or 0
    if not p.moving then
        p:ClearAllPoints()
        if fixed == "bottom" then
            p:SetPoint("BOTTOM", UIParent, "CENTER", s.x or 0, s.y or 0)
        else
            p:SetPoint("TOP", UIParent, "CENTER", s.x or 0, (s.y or 0) + (drop or 0))
        end
    end
    p.mover:ClearAllPoints()
    p.mover:SetAllPoints(p)                                   -- exactly what you see
    p.mover:SetShown(db.unlocked == true)
end

-- the icons of one pane (entries from Blizzard's, or examples while unlocked), a fixed size, rows
-- centred on the pane's centre line, laid out from its top edge; returns the rows (for the outline),
-- the height used and the widest row
local function LayIcons(p, entries, size, cap, grow, top)
    local sizes, widest = Rows(#entries, cap, grow)
    local s = size
    local rows = {}
    local cells = {}
    p.cells = cells
    local k, y = 0, top
    local px = Px(p)
    local trim = Trim(p)
    -- the row farthest from the pane's fixed edge is a pixel shorter, the last icon of each row a pixel
    -- narrower: then the pane's far frame lines land on grid lines too
    local far = (grow == "up") and 1 or #sizes
    for r, n in ipairs(sizes) do
        local rw = n * s - trim
        local rh = (r == far) and (s - trim) or s
        -- a row of another width gets its own frame: leave a pixel for the line the two share
        if r > 1 and n ~= sizes[r - 1] then y = y + px end
        for c = 1, n do
            k = k + 1
            local e = entries[k]
            local f = p.icons[k]
            if not f then f = MakeIcon(p); p.icons[k] = f end
            SizeIcon(f, s)
            f:SetSize((c == n) and (s - trim) or s, rh)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", p, "TOP", -rw / 2 + (c - 1) * s, -y)
            f:Show()
            e.icon = f
            -- its frame (drawn once the pane is placed): the left and top lines a pixel outside the
            -- icon, the right and bottom ones on its last pixel, which is where the next icon's left
            -- (or the next row's top) line falls: neighbours share one line. The row's last icon, and
            -- the last row (or one above a row of another width, a pixel apart), keep theirs outside.
            local cw = (c == n) and (s - trim) or s
            local sharedBelow = sizes[r + 1] ~= nil and sizes[r + 1] == n
            cells[#cells + 1] = { -rw / 2 + (c - 1) * s, y, (c == n) and cw or (cw - px), sharedBelow and (rh - px) or rh }
        end
        rows[#rows + 1] = { rw, rh, y }
        y = y + rh
    end
    for i = k + 1, #p.icons do p.icons[i]:Hide(); p.icons[i].spellID = nil end
    return rows, y - top, widest * s - trim
end

-- one icon's look from its entry: texture, dimmed, range, resource
local function Paint(e)
    local f = e.icon
    f.spellID, f.name = e.spellID, e.name
    local tex = e.texture
    if not tex and e.spellID then
        local fn = (C_Spell and C_Spell.GetSpellTexture) or _G.GetSpellTexture
        tex = Ask(fn, e.spellID)
    end
    pcall(f.tex.SetTexture, f.tex, tex or "Interface\\Icons\\INV_Misc_QuestionMark")
    local dim = e.inactive == true
    local inRange = (not dim) and SpellRange(e.spellID)
    local cost, power, pkey
    if not dim and not e.sample then cost, power, pkey = SpellShort(e.spellID) end
    if e.sample and e.sampleFill then cost, power, pkey = 1, e.sampleFill, "energy" end
    local red = (inRange == false) or e.sampleRed
    f.tex:SetDesaturated(dim or cost ~= nil)
    if red then f.tex:SetVertexColor(1, 0.3, 0.3)
    elseif dim then f.tex:SetVertexColor(0.45, 0.45, 0.45)
    elseif cost then f.tex:SetVertexColor(0.7, 0.7, 0.7)
    else f.tex:SetVertexColor(1, 1, 1) end
    f:SetAlpha(dim and 0.75 or 1)
    if cost then
        FillResourceFrame(f.res, power, cost, red and COLORS.range or COLORS[pkey] or COLORS.other)
    else
        f.res:Hide()
    end
    if not e.item then ShowGlow(f, false) end
    if e.sample then
        f.stack:SetText(e.sampleStack or "")
        if f.cd then if e.sampleCd then pcall(f.cd.SetCooldown, f.cd, GetTime() - e.sampleCd * 20, 20) else pcall(f.cd.Clear, f.cd) end end
    end
end

-- entries of an icon pane: from Blizzard's pane, or examples while unlocked
local function Entries(key)
    local list = {}
    if key == "items" then
        for _, slot in ipairs({ 13, 14 }) do
            local id = Plain(Ask(GetInventoryItemID, "player", slot))
            if id then
                local spell = C_Item and C_Item.GetItemSpell and Plain(Ask(C_Item.GetItemSpell, id)) or (_G.GetItemSpell and Plain(Ask(GetItemSpell, id)))
                if spell then
                    list[#list + 1] = { slot = slot, texture = Ask(GetInventoryItemTexture, "player", slot), name = spell }
                end
            end
        end
    else
        local items = Items(VIEWERS[key])
        for _, it in ipairs(items or {}) do
            local id = ItemSpell(it)
            -- shown elsewhere: Lightning Shield's charges on the nameplate
            local elsewhere = ns.Totems and ns.Totems.ShowsShield and ns.Totems.ShowsShield(id)
            -- tracked buffs: only the ones up right now
            local skip = elsewhere or (key == "buffs" and not ItemActive(it))
            if not skip then
                list[#list + 1] = { item = it, spellID = id }
            end
        end
    end
    if #list == 0 and db.unlocked then
        local n = ({ essential = 6, buffs = 5, utility = 7, items = 2 })[key] or 4
        for i = 1, n do
            list[i] = { sample = true, texture = "Interface\\Icons\\INV_Misc_QuestionMark",
                sampleCd = (i == 2) and 0.6 or nil, sampleStack = (i == 4) and "2" or nil,
                sampleFill = (key == "essential" and i == 3) and 0.6 or nil, inactive = (key == "buffs" and i % 2 == 0) or nil }
        end
    end
    return list
end

local function FeedIcons(key, entries)
    for _, e in ipairs(entries) do
        if e.item then Mirror(e.item, e.icon) end
        if e.slot and e.icon.cd then
            local start, dur, enable = Ask(GetInventoryItemCooldown, "player", e.slot)
            local pd = Plain(dur)
            if pd ~= nil and pd <= 0 then pcall(e.icon.cd.Clear, e.icon.cd)
            elseif dur ~= nil then pcall(e.icon.cd.SetCooldown, e.icon.cd, start, dur) end
            e.icon.stack:SetText("")
        end
        Paint(e)
    end
end

----------------------------------------------------------------------
-- The main block's bars
----------------------------------------------------------------------

local function MakeBar(parent, withText)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetStatusBarTexture(BAR_TEX)
    b:SetMinMaxValues(0, 1); b:SetValue(0)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetTexture(BAR_TEX)
    Gradient(b.bg, { 0.25, 0.25, 0.25 }, 0.5)                 -- the dark track, as on the nameplates
    -- the resource display's shading, over the fill (it follows the fill as it grows and shrinks)
    local fill = b:GetStatusBarTexture()
    b.shade = b:CreateTexture(nil, "ARTWORK", nil, 6)
    b.shade:SetTexture(GRADIENT_TEXTURE); b.shade:SetAllPoints(fill); b.shade:Hide()
    b.cyl = b:CreateTexture(nil, "ARTWORK", nil, 7)
    b.cyl:SetTexture(CYLINDER_TEXTURE); b.cyl:SetAllPoints(fill); b.cyl:Hide()
    b.left = b:CreateFontString(nil, "OVERLAY")
    b.left:SetPoint("LEFT", 3, 0); b.left:SetJustifyH("LEFT")
    b.right = b:CreateFontString(nil, "OVERLAY")
    b.right:SetPoint("RIGHT", -3, 0); b.right:SetJustifyH("RIGHT")
    return b
end
-- the bar numbers: no outline (at this size the game draws it unevenly round each figure and it
-- clogs the gaps in 6, 8 and 9), a crisp drop shadow instead, one step down and right; the text set
-- on whole pixels (a figure between two pixels is drawn soft)
local function BarFonts(b, h)
    local size = math.max(8, math.floor(h * 0.68 + 0.5))
    local px = Px(b)
    local inset = math.floor(3 / px + 0.5) * px
    for i, fs in ipairs({ b.left, b.right }) do
        fs:SetFont(FONT_THIN, size, "")
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
        fs:SetTextColor(1, 1, 1, 1)
        fs:ClearAllPoints()
        if i == 1 then fs:SetPoint("LEFT", b, "LEFT", inset, 0) else fs:SetPoint("RIGHT", b, "RIGHT", -inset, 0) end
        if fs.SetSnapToPixelGrid then pcall(fs.SetSnapToPixelGrid, fs, true) end
    end
end
local function SetColor(b, c)
    if b.color and b.color[1] == c[1] and b.color[2] == c[2] and b.color[3] == c[3] then return end
    b.color = { c[1], c[2], c[3] }
    b:SetStatusBarColor(1, 1, 1, 1)
    Gradient(b:GetStatusBarTexture(), c)
end

-- the resource display's settings: a colour of your own, the track's opacity and the shading
local function Res() return (db and db.res) or ns.CDM_DEFAULTS.res end
local function ResColor(key)
    local c = Res().colors and Res().colors[key]
    if type(c) == "table" and c.r then return { c.r, c.g, c.b } end
    return COLORS[key] or COLORS.other
end
local function ResStyle(b)
    local r = Res()
    b.bg:SetAlpha(math.max(0, math.min(1, r.alpha or 1)))
    local g = math.max(0, math.min(GRADIENT_MAX, r.gradient or 0))
    local c = math.max(0, math.min(CYLINDER_MAX, r.cylinder or 0))
    b.shade:SetVertexColor(1, 1, 1, g); b.shade:SetShown(g > 0)
    b.cyl:SetVertexColor(1, 1, 1, c); b.cyl:SetShown(c > 0)
end

-- a value and its percentage on a bar: plain numbers are written out; hidden ones go to the bar,
-- and to the text as far as the game allows
local function FillBar(b, cur, max, pct)
    pcall(b.SetMinMaxValues, b, 0, max)
    pcall(b.SetValue, b, cur)
    local pc, pm = Plain(cur), Plain(max)
    if pc and pm then
        b.right:SetText(tostring(pc))
        b.left:SetText(pm > 0 and (math.floor(pc / pm * 100 + 0.5) .. "%") or "")
    else
        if not pcall(b.right.SetText, b.right, cur) then b.right:SetText("") end
        if pct == nil or not pcall(b.left.SetFormattedText, b.left, "%d%%", pct) then b.left:SetText("") end
    end
end

local function HealthPercent()
    if _G.UnitHealthPercent then
        local curve = _G.CurveConstants and CurveConstants.ScaleTo100
        local ok, r = pcall(UnitHealthPercent, "player", true, curve)
        if ok then return r end
    end
    return nil
end
local function PowerPercent(ptype)
    if _G.UnitPowerPercent then
        local curve = _G.CurveConstants and CurveConstants.ScaleTo100
        local ok, r = pcall(UnitPowerPercent, "player", ptype, true, curve)
        if ok then return r end
    end
    return nil
end

-- the powers to show: the class's main one (mana for any class that has it), and the current form's
-- when that is another one (a Druid in Cat or Bear Form)
local function Powers()
    local main
    local okM, mm = pcall(UnitPowerMax, "player", MANA)
    if okM and (Plain(mm) or 0) > 0 then main = MANA end
    local okT, cur = pcall(UnitPowerType, "player")
    cur = okT and Plain(cur) or nil
    if not main then main = cur or MANA end
    local extra = (cur and cur ~= main) and cur or nil
    -- Druid: the energy bar in caster and Travel Form too, when that is chosen
    if not extra and main == MANA and Res().druidEnergy then
        local okC, _, class = pcall(UnitClass, "player")
        if okC and class == "DRUID" then extra = ENERGY end
    end
    return main, extra
end

----------------------------------------------------------------------
-- The cast bar
----------------------------------------------------------------------

local cast = { active = false }
local CastFrame
local function ReadCast()
    local name, _, texture, startMS, endMS, spellID
    if UnitCastingInfo then
        local r = { pcall(UnitCastingInfo, "player") }
        if r[1] then name, texture, startMS, endMS, spellID = r[2], r[4], r[5], r[6], r[10] end
    end
    local channel = false
    cast.spellID = (name ~= nil) and spellID or nil      -- a cast (not a channel): its cost is paid at the end
    if name == nil then
        name, _, texture, startMS, endMS = Ask(UnitChannelInfo, "player")
        channel = name ~= nil
    end
    if name == nil then cast.active = false; return end
    local start, stop = Plain(startMS), Plain(endMS)
    if not cast.active or start ~= cast.start or stop ~= cast.stop or channel ~= cast.channel then
        cast.id = (cast.id or 0) + 1                    -- a new cast (or a pushed-back one)
    end
    cast.active, cast.name, cast.channel = true, name, channel
    cast.start, cast.stop = start, stop
end

-- the cast bar's fill, worked out afresh every frame (smooth at any frame rate)
CastFrame = function(bar)
    if not (cast.active and cast.start and cast.stop and cast.stop > cast.start) then return end
    local now = GetTime() * 1000
    local f = (now - cast.start) / (cast.stop - cast.start)
    if cast.channel then f = 1 - f end
    bar:SetMinMaxValues(0, 1); bar:SetValue(math.max(0, math.min(1, f)))
    bar.right:SetText(("%.1f"):format(math.max(0, (cast.stop - now) / 1000)))
end

-- a tracked bar's fill and time, every frame, from Blizzard's own numbers where they can be read
-- (where they are hidden, the copy of Blizzard's bar, which it also sets every frame, does it)
local function TrackedFrame(b)
    local it = b.item
    if not (it and it.GetCooldownValues) then return end
    local ok, exp, dur = pcall(it.GetCooldownValues, it)
    if not ok then return end
    local pe, pd = Plain(exp), Plain(dur)
    if not (pe and pd and pd > 0) then return end
    local left = pe - GetTime()
    if left <= 0 then return end
    b.bar:SetMinMaxValues(0, pd); b.bar:SetValue(left)
    b.time:SetText(("%.1f"):format(left))
end

----------------------------------------------------------------------
-- Drawing it all
----------------------------------------------------------------------

local function DrawIconPane(key, label)
    local p = panes[key] or MakePane(key, label)
    local s = Settings(key)
    p.lines:Done(); p.rings:Done()
    if not PaneOn(key) then p:Hide(); state.panes[key] = On() and "switched off" or nil; return end
    local entries = Entries(key)
    if #entries == 0 then p:Hide(); state.panes[key] = "nothing to show (none tracked, or none up)"; return end
    local rows, h, w = LayIcons(p, entries, Boxes(s.size or 32), s.cap, GROW[key], 0)
    Place(p, s, w, h, GROW[key] == "up" and "bottom" or "top")
    -- after placing (the lines are put on whole pixels): a white frame round each icon, rounded at all
    -- four corners, neighbours sharing a line
    for _, c in ipairs(p.cells or {}) do Ring(p, c[1], c[2], c[3], c[4], h, true) end
    FeedIcons(key, entries)
    p:Show()
    state.panes[key] = #entries .. " icons in " .. #rows .. " rows"
end

-- healing on its way (a heal being cast on you, yours or anyone's), as on Blizzard's bars: a lighter
-- segment starting where the health fill ends, as long as the heal is, cut off at the bar's end. It
-- works on hidden numbers too: a bar as wide as the health bar, on the same scale, filled to the heal.
local function HealPrediction(p, maxHP)
    local hb = p.health
    if not p.heal then
        -- the bar's text above the heal segment
        p.healthText = CreateFrame("Frame", nil, hb)
        p.healthText:SetAllPoints(hb)
        p.healthText:SetFrameLevel(hb:GetFrameLevel() + 3)
        pcall(hb.left.SetParent, hb.left, p.healthText)
        pcall(hb.right.SetParent, hb.right, p.healthText)
        -- the segment, clipped to the bar
        p.healClip = CreateFrame("Frame", nil, hb)
        p.healClip:SetAllPoints(hb)
        p.healClip:SetFrameLevel(hb:GetFrameLevel() + 1)
        if p.healClip.SetClipsChildren then pcall(p.healClip.SetClipsChildren, p.healClip, true) end
        p.heal = CreateFrame("StatusBar", nil, p.healClip)
        p.heal:SetStatusBarTexture(BAR_TEX)
        p.heal:SetPoint("LEFT", hb:GetStatusBarTexture(), "RIGHT", 0, 0)
        p.heal:SetMinMaxValues(0, 1); p.heal:SetValue(0)
    end
    local c = ResColor("health")
    local light = { c[1] * 0.45 + 0.55, c[2] * 0.45 + 0.55, c[3] * 0.45 + 0.55 }
    if not (p.heal.color and p.heal.color[1] == light[1] and p.heal.color[2] == light[2] and p.heal.color[3] == light[3]) then
        p.heal.color = light
        p.heal:SetStatusBarColor(1, 1, 1, 1)
        Gradient(p.heal:GetStatusBarTexture(), light)
    end
    p.heal:SetAlpha(0.75)
    p.heal:SetSize(hb:GetWidth(), hb:GetHeight())
    pcall(p.heal.SetMinMaxValues, p.heal, 0, maxHP)
    local incoming = _G.UnitGetIncomingHeals and Ask(UnitGetIncomingHeals, "player")
    if incoming == nil or not pcall(p.heal.SetValue, p.heal, incoming) then p.heal:SetValue(0) end
end

-- what a cast will spend, as on Blizzard's bars: the end of the power fill picked out in a lighter
-- shade, as long as the cost, while you cast a spell that costs that power. A bar on the power bar's
-- scale, filling right to left from the fill's end (works on hidden numbers), cut off at the bar.
local function CostOverlay(bar)
    if bar.costBar then return bar.costBar end
    bar.textF = CreateFrame("Frame", nil, bar)
    bar.textF:SetAllPoints(bar)
    bar.textF:SetFrameLevel(bar:GetFrameLevel() + 3)
    pcall(bar.left.SetParent, bar.left, bar.textF)
    pcall(bar.right.SetParent, bar.right, bar.textF)
    local clip = CreateFrame("Frame", nil, bar)
    clip:SetAllPoints(bar)
    clip:SetFrameLevel(bar:GetFrameLevel() + 1)
    if clip.SetClipsChildren then pcall(clip.SetClipsChildren, clip, true) end
    local c = CreateFrame("StatusBar", nil, clip)
    c:SetStatusBarTexture(BAR_TEX)
    if c.SetReverseFill then pcall(c.SetReverseFill, c, true) end
    c:SetPoint("RIGHT", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    c:SetMinMaxValues(0, 1); c:SetValue(0)
    c:Hide()
    bar.costBar = c
    return c
end

local function CostPrediction(bar, ptype)
    local c = CostOverlay(bar)
    local cost
    if cast.active and not cast.channel and cast.spellID and ptype then
        local fn = (C_Spell and C_Spell.GetSpellPowerCost) or _G.GetSpellPowerCost
        local costs = Ask(fn, cast.spellID)
        if type(costs) == "table" then
            for _, e in ipairs(costs) do
                if type(e) == "table" and Plain(e.type) == ptype then cost = e.cost; break end
            end
        end
    end
    if cost == nil or Plain(cost) == 0 then c:Hide(); return end
    local col = bar.color or COLORS.mana
    local light = { col[1] * 0.4 + 0.6, col[2] * 0.4 + 0.6, col[3] * 0.4 + 0.6 }
    if not (c.color and c.color[1] == light[1] and c.color[2] == light[2] and c.color[3] == light[3]) then
        c.color = light
        c:SetStatusBarColor(1, 1, 1, 1)
        Gradient(c:GetStatusBarTexture(), light)
    end
    c:SetAlpha(0.8)
    c:SetSize(bar:GetWidth(), bar:GetHeight())
    local okM, mx = pcall(UnitPowerMax, "player", ptype)
    pcall(c.SetMinMaxValues, c, 0, okM and mx or 1)
    if not pcall(c.SetValue, c, cost) then c:Hide(); return end
    c:Show()
end

local function DrawBlock()
    local p = panes.block or MakePane("block", "Cooldowns: health, power, cast bar")
    local s = Settings("block")
    p.lines:Done(); p.rings:Done()
    if not PaneOn("block") then p:Hide(); return end
    if not p.cast then
        p.cast = MakeBar(p)
        p.cast:SetScript("OnUpdate", function(self) if cast.active then CastFrame(self) end end)
        p.health = MakeBar(p)
        p.power = MakeBar(p)
        p.extra = MakeBar(p)
    end
    SetColor(p.cast, ResColor("cast")); SetColor(p.health, ResColor("health"))
    for _, b in ipairs({ p.health, p.power, p.extra, p.cast }) do ResStyle(b) end
    local trim = Trim(p)
    local w = Boxes(s.width) - trim
    local px = Px(p)
    local y = 0
    local n = 0
    local lastStrip
    local function Strip(b, h)
        if n > 0 then Seam(p, -w / 2, y - px / 2, w, px) end
        n = n + 1
        lastStrip = b
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", p, "TOP", -w / 2, -y)
        b:SetSize(w, h)
        BarFonts(b, h)
        b:Show()
        y = y + h
    end
    Strip(p.health, Boxes(s.health or 16))
    local okH, hp = pcall(UnitHealth, "player")
    local okHM, hm = pcall(UnitHealthMax, "player")
    FillBar(p.health, okH and hp or 0, okHM and hm or 1, HealthPercent())
    HealPrediction(p, okHM and hm or 1)
    local main, extra = Powers()
    Strip(p.power, Boxes(s.power or 8))
    SetColor(p.power, ResColor(POWER_KEY[main] or "other"))
    local okP, pw = pcall(UnitPower, "player", main)
    local okPM, pm = pcall(UnitPowerMax, "player", main)
    FillBar(p.power, okP and pw or 0, okPM and pm or 1, PowerPercent(main))
    if extra then
        Strip(p.extra, Boxes(s.power or 8))
        SetColor(p.extra, ResColor(POWER_KEY[extra] or "other"))
        local okE, ev = pcall(UnitPower, "player", extra)
        local okEM, em = pcall(UnitPowerMax, "player", extra)
        FillBar(p.extra, okE and ev or 0, okEM and em or 1, PowerPercent(extra))
    else
        p.extra:Hide()
    end
    -- the cast bar: along the bottom, below whatever bars there are; only while casting (or moving it)
    ReadCast()
    -- what the cast will spend, on the bar of its power
    CostPrediction(p.power, main)
    if extra then CostPrediction(p.extra, extra) elseif p.extra.costBar then p.extra.costBar:Hide() end
    if cast.active or db.unlocked then
        Strip(p.cast, Boxes(s.cast or 16))
        if cast.active then
            p.cast.left:SetText("")
            pcall(p.cast.left.SetText, p.cast.left, cast.name)
            if cast.start and cast.stop and cast.stop > cast.start then
                CastFrame(p.cast)                       -- and every frame after, from its own OnUpdate
            elseif p.cast.timerId ~= cast.id then
                -- hidden times: the game's own timer drives the bar, started once per cast
                p.cast.timerId = cast.id
                p.cast.right:SetText("")
                local dur = Ask(_G.UnitCastingDuration, "player") or Ask(_G.UnitChannelDuration, "player")
                if not (dur and p.cast.SetTimerDuration and pcall(p.cast.SetTimerDuration, p.cast, dur)) then
                    p.cast:SetMinMaxValues(0, 1); p.cast:SetValue(0.5)
                end
            end
        else
            p.cast.left:SetText("Cast bar"); p.cast.right:SetText("")
            p.cast:SetMinMaxValues(0, 1); p.cast:SetValue(0.6)
        end
    else
        p.cast:Hide()
    end
    -- the bottom bar a pixel shorter: the frame's bottom line lands on a grid line
    if trim > 0 and lastStrip then
        lastStrip:SetHeight(lastStrip:GetHeight() - trim)
        y = y - trim
    end
    -- placed by its top: the bars grow down
    Place(p, s, w, y, "top")
    Ring(p, -w / 2, 0, w, y, y)
    p:Show()
    state.panes.block = (extra and "form power shown" or "health and power") .. (cast.active and ", casting" or "")
end

local function DrawBars()
    local p = panes.bars or MakePane("bars", "Cooldowns: tracked bars")
    local s = Settings("bars")
    p.lines:Done(); p.rings:Done()
    if not PaneOn("bars") then p:Hide(); return end
    p.bars = p.bars or {}
    local list = {}
    -- only the bars whose buff is up right now
    for _, it in ipairs(Items(VIEWERS.bars) or {}) do
        if ItemActive(it) then list[#list + 1] = { item = it, spellID = ItemSpell(it) } end
    end
    if #list == 0 and db.unlocked then
        for i = 1, 3 do list[i] = { sample = true, name = "Tracked bar " .. i, inactive = (i == 3) } end
    end
    if #list == 0 then p:Hide(); state.panes.bars = "nothing to show (none tracked, or none up)"; return end
    local trim = Trim(p)
    local w, h = Boxes(s.width) - trim, Boxes(s.height or 16)
    for i, e in ipairs(list) do
        local b = p.bars[i]
        if not b then
            b = CreateFrame("Frame", nil, p)
            -- the icon has a frame of its own, so its rounded corners are cut to the icon (not the row)
            b.iconF = CreateFrame("Frame", nil, b)
            b.icon = b.iconF:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints(); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b.bar = MakeBar(b); SetColor(b.bar, COLORS.mana)
            b.name, b.time = b.bar.left, b.bar.right
            b:SetScript("OnUpdate", TrackedFrame)
            p.bars[i] = b
        end
        b.item = (not e.inactive) and e.item or nil
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", p, "TOP", -w / 2, -(i - 1) * h)
        b:SetSize(w, h)
        b.iconF:ClearAllPoints(); b.iconF:SetPoint("TOPLEFT"); b.iconF:SetSize(h, h)
        b.bar:ClearAllPoints(); b.bar:SetPoint("TOPLEFT", h, 0); b.bar:SetSize(w - h, h)
        BarFonts(b.bar, h)
        local tex = e.spellID and Ask((C_Spell and C_Spell.GetSpellTexture) or _G.GetSpellTexture, e.spellID)
        pcall(b.icon.SetTexture, b.icon, tex or "Interface\\Icons\\INV_Misc_QuestionMark")
        b.icon:SetDesaturated(e.inactive == true)
        b:SetAlpha(e.inactive and 0.6 or 1)
        if e.item then MirrorBar(e.item, b)
        else b.name:SetText(e.name or ""); b.time:SetText(""); b.bar:SetMinMaxValues(0, 1); b.bar:SetValue(e.inactive and 0 or 0.6) end
        if e.inactive and e.item then b.bar:SetValue(0); b.time:SetText("") end
        b:Show()
        if i > 1 then local px = Px(p); Seam(p, -w / 2, (i - 1) * h - px / 2, w, px) end
    end
    for i = #list + 1, #p.bars do p.bars[i]:Hide() end
    -- the last bar a pixel shorter: the frame's bottom line lands on a grid line
    local total = #list * h - trim
    if trim > 0 and p.bars[#list] then p.bars[#list]:SetHeight(h - trim); p.bars[#list].bar:SetHeight(h - trim) end
    Place(p, s, w, total, "top")
    Ring(p, -w / 2, 0, w, total, total)
    p:Show()
    state.panes.bars = #list .. " bars"
end

-- Blizzard's personal resource display: off while our block shows health and power
local prdOff = false
local function PRD()
    local want = PaneOn("block") and db.replacePRD
    if InCombat() then return end
    if want and not prdOff then
        if pcall(SetCVar, "nameplateShowSelf", "0") then prdOff = true end
    elseif not want and prdOff then
        if pcall(SetCVar, "nameplateShowSelf", "1") then prdOff = false end
    end
end

-- Blizzard's player cast bar: off while ours shows. It is told it has no unit to follow (so it hears
-- no casts and stays hidden) and given the player back when ours goes; changed out of combat only
local castHidden = false
local function CastBar()
    local f = _G.PlayerCastingBarFrame
    if type(f) ~= "table" or not f.SetUnit or InCombat() then return end
    local want = PaneOn("block") and db.hideCastBar ~= false
    if want and not castHidden then
        if pcall(f.SetUnit, f, nil) then castHidden = true; pcall(f.Hide, f) end
    elseif not want and castHidden then
        if pcall(f.SetUnit, f, "player", true, false) then castHidden = false end
    end
end

local function Update()
    if not db then return end
    local bw = ns.Buffs and ns.Buffs.Settings and ns.Buffs.Settings()
    ShowGrid(On() and (db.unlocked == true or (bw and bw.unlocked == true)) or false)
    HideBlizzard(On() and db.hideBlizzard)
    state.blizzard = _G.EssentialCooldownViewer and (db.hideBlizzard and "made invisible" or "left showing") or "no Cooldown Manager found"
    DrawBlock()
    DrawIconPane("essential", "Cooldowns: essential")
    DrawIconPane("buffs", "Cooldowns: tracked buffs")
    DrawIconPane("utility", "Cooldowns: utility")
    DrawIconPane("items", "Cooldowns: items")
    DrawBars()
    PRD()
    CastBar()
end

----------------------------------------------------------------------
-- Driving
----------------------------------------------------------------------

local driver = CreateFrame("Frame")
local acc = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.1 then return end
    acc = 0
    Update()
end)
driver:Hide()
driver:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_HEAL_PREDICTION" }) do
    pcall(driver.RegisterUnitEvent or driver.RegisterEvent, driver, e, "player")
end
pcall(driver.RegisterEvent, driver, "PLAYER_REGEN_ENABLED")
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitDB().range
        root.cooldowns = root.cooldowns or {}
        local old = root.cooldowns.block
        if type(old) == "table" and old.size and not root.cooldowns.essential then
            -- 2.24: the Essential icons were part of the block; they are a pane of their own now
            root.cooldowns.essential = { size = old.size, cap = old.cap }
            old.size, old.cap = nil, nil
        end
        DeepFill(root.cooldowns, ns.CDM_DEFAULTS)
        db = root.cooldowns
        driver:Show()
    end
    Update()
end)

ns.Cooldowns = {
    Settings = function() return db end,
    Refresh = function() Update() end,
    On = function() return On() end,
    ResColor = ResColor,
    GRADIENT_MAX = GRADIENT_MAX, CYLINDER_MAX = CYLINDER_MAX,
    GRADIENT_TEXTURE = GRADIENT_TEXTURE, CYLINDER_TEXTURE = CYLINDER_TEXTURE,
    -- the resource display's settings back to how they came
    ResetResources = function()
        if not db then return end
        db.res = {}
        DeepFill(db.res, ns.CDM_DEFAULTS.res)
        Update()
    end,
    Panes = function() return panes end,
    Rows = Rows,
    ResetPositions = function()
        if not db then return end
        for k, d in pairs(ns.CDM_DEFAULTS) do
            if type(d) == "table" and db[k] then db[k].x, db[k].y = d.x, d.y end
        end
        Update()
    end,
    Debug = function(print)
        print(("cooldown panes: %s; Blizzard's Cooldown Manager %s"):format((On() and "on" or "off") .. (ns.BerryMode() and " (Berry Mode)" or ""), state.blizzard))
        for _, k in ipairs({ "block", "essential", "buffs", "utility", "items", "bars" }) do
            print(("  %s: %s"):format(k, state.panes[k] or "-"))
        end
        local main, extra = Powers()
        print(("  powers: %s%s; casting: %s"):format(POWER_KEY[main] or tostring(main), extra and (" + " .. (POWER_KEY[extra] or tostring(extra))) or "", tostring(cast.active)))
        -- what Blizzard's Cooldown Manager is tracking, one line a spell
        local function Show(v)
            if v == nil then return "-" end
            local pv = Plain(v)
            if pv == nil then return "hidden" end
            if type(pv) == "number" then return ("%.1f"):format(pv) end
            return tostring(pv)
        end
        for key, name in pairs(VIEWERS) do
            for _, it in ipairs(Items(name) or {}) do
                local id = ItemSpell(it)
                local nm = id and Ask((C_Spell and C_Spell.GetSpellName) or _G.GetSpellInfo, id)
                print(("  [%s] %s (%s): active %s, cd start %s for %s, ours %s%s"):format(key, tostring(Plain(nm) or "?"), tostring(id),
                    tostring(ItemActive(it)), Show(it.cooldownStartTime), Show(it.cooldownDuration),
                    itemIcon[it] and (itemIcon[it]:IsShown() and "shown" or "hidden") or "none",
                    alertOn[it] and ", alert on" or ""))
            end
        end
    end,
}
