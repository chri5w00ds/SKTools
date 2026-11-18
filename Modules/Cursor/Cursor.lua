-- SKTools - the cursor: a soft glow that follows it in combat (the cursor's own picture can't be
-- changed by an addon, so the glow is drawn under it), and tooltips that move to the cursor while
-- Alt is held.
--
-- New features: off in Berry Mode until turned on there (ns.FeatureOn).

local ADDON, ns = ...

ns.CURSOR_DEFAULTS = {
    glow = {
        enabled = true, berryEnabled = false,
        combatOnly = true,        -- or always
        size = 72,                -- across, in UI units
        alpha = 0.8,
        color = { r = 1, g = 0.55, b = 0.18 },     -- warm orange
        shadow = 0.7,             -- the dark halo under it, so it shows on bright ground too
        pulse = false,            -- a slow brighten-and-dim
    },
    altTip = { enabled = true, berryEnabled = false },
}

local db
local function DeepFill(t, d)
    for k, v in pairs(d) do
        if type(v) == "table" then
            if type(t[k]) ~= "table" then t[k] = {} end
            DeepFill(t[k], v)
        elseif t[k] == nil then
            t[k] = v
        end
    end
end

local function InCombat()
    local ok, v = pcall(UnitAffectingCombat, "player")
    return (ok and v == true) or (InCombatLockdown and InCombatLockdown()) or false
end

----------------------------------------------------------------------
-- the glow
----------------------------------------------------------------------

local glow
local previewing = false           -- the Cursor settings tab is open: show it to see the changes
local shownAlpha = 0               -- fades in and out

-- the game hides the cursor while you turn the camera or steer with the mouse (right button, or
-- the left one dragged on the world): the glow goes with it
local function CursorHidden()
    if IsMouselooking and IsMouselooking() then return true end
    if not IsMouseButtonDown then return false end
    if not (IsMouseButtonDown("RightButton") or IsMouseButtonDown("LeftButton")) then return false end
    local focus
    if GetMouseFoci then local t = GetMouseFoci(); focus = t and t[1]
    elseif GetMouseFocus then focus = GetMouseFocus() end
    return focus == nil or focus == WorldFrame
end

local function GlowWanted()
    if CursorHidden() then return false end
    if not db or not ns.FeatureOn(db.glow) then return previewing and db ~= nil end
    if previewing then return true end
    return not db.glow.combatOnly or InCombat()
end

-- two layers: a dark halo a little wider than the glow (it carries it on snow, sand and bright
-- spells), and the coloured glow over it, drawn as colour rather than as added light (added light
-- washes out to white on bright ground)
local function Style()
    if not glow then return end
    local g = db.glow
    local s = g.size or 72
    glow:SetSize(s * 1.3, s * 1.3)
    glow.tex:SetSize(s, s)
    local c = g.color or {}
    glow.tex:SetVertexColor(c.r or 1, c.g or 0.55, c.b or 0.18, 1)
    glow.shadow:SetVertexColor(0, 0, 0, math.max(0, math.min(1, g.shadow or 0.7)))
    glow.shadow:SetShown((g.shadow or 0.7) > 0)
end

local function MakeGlow()
    glow = CreateFrame("Frame", "SKToolsCursorGlow", UIParent)
    glow:SetFrameStrata("TOOLTIP")
    glow:SetFrameLevel(1)
    glow:EnableMouse(false)
    glow.shadow = glow:CreateTexture(nil, "BACKGROUND")
    glow.shadow:SetAllPoints()
    glow.shadow:SetTexture(ns.MEDIA .. "CursorShadow")
    glow.shadow:SetBlendMode("BLEND")
    glow.tex = glow:CreateTexture(nil, "ARTWORK")
    glow.tex:SetPoint("CENTER")
    glow.tex:SetTexture(ns.MEDIA .. "CursorGlow")
    glow.tex:SetBlendMode("BLEND")
    glow.t = 0
    glow:SetAlpha(0)
    glow:Hide()
    glow:SetScript("OnUpdate", function(self, elapsed)
        -- follow the cursor: centred a little down and right of its tip, behind the gauntlet
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s + 7, y / s - 9)
        -- the cursor hidden (camera turning): gone at once, no fade
        if CursorHidden() then
            shownAlpha = 0; self:SetAlpha(0)
            return
        end
        -- fade towards wanted
        local want = GlowWanted() and (db.glow.alpha or 0.8) or 0
        if shownAlpha ~= want then
            local step = (elapsed or 0.016) * 4
            if shownAlpha < want then shownAlpha = math.min(want, shownAlpha + step)
            else shownAlpha = math.max(want, shownAlpha - step) end
            self:SetAlpha(shownAlpha)
        end
        if shownAlpha <= 0 and want <= 0 then self:Hide() end
        -- the pulse: the glow (not the halo) brightens and dims every 1.4 seconds
        if db.glow.pulse then
            self.t = (self.t + (elapsed or 0.016)) % 1.4
            self.tex:SetAlpha(0.7 + 0.3 * math.cos(self.t / 1.4 * 2 * math.pi))
        elseif self.tex:GetAlpha() ~= 1 then
            self.tex:SetAlpha(1)
        end
    end)
    Style()
end

local function UpdateGlow()
    if not db then return end
    if not glow then MakeGlow() end
    Style()
    if GlowWanted() then glow:Show() end            -- it hides itself once faded out
end

----------------------------------------------------------------------
-- Alt: tooltips at the cursor
----------------------------------------------------------------------

local function AltTipOn()
    return db and ns.FeatureOn(db.altTip) and IsAltKeyDown and IsAltKeyDown() or false
end

local hooked = false
local function HookTooltips()
    if hooked or not _G.GameTooltip_SetDefaultAnchor then return end
    hooked = true
    -- a tooltip placed in its usual corner goes to the cursor instead while Alt is held
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        if AltTipOn() and tooltip and tooltip.SetOwner then
            pcall(tooltip.SetOwner, tooltip, parent or UIParent, "ANCHOR_CURSOR_RIGHT", 24, 4)
        end
    end)
end

-- Alt pressed or let go while pointing at someone in the world: their tooltip moves straight away
local function Remake()
    local tt = _G.GameTooltip
    if not (tt and tt:IsShown() and UnitExists and UnitExists("mouseover")) then return end
    local owner = tt.GetOwner and tt:GetOwner()
    if owner ~= UIParent and owner ~= _G.WorldFrame then return end
    if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(tt, UIParent) end
    pcall(tt.SetUnit, tt, "mouseover")
end

----------------------------------------------------------------------

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterEvent("MODIFIER_STATE_CHANGED")
driver:SetScript("OnEvent", function(_, event, key)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitDB().range
        root.cursor = root.cursor or {}
        DeepFill(root.cursor, ns.CURSOR_DEFAULTS)
        db = root.cursor
        HookTooltips()
        UpdateGlow()
    elseif event == "MODIFIER_STATE_CHANGED" then
        if (key == "LALT" or key == "RALT") and db and ns.FeatureOn(db.altTip) then Remake() end
    else
        UpdateGlow()
    end
end)

ns.Cursor = {
    Settings = function() return db end,
    Refresh = function() UpdateGlow() end,
    Preview = function(on) previewing = on and true or false; UpdateGlow() end,
    GlowFrame = function() return glow end,
    Wanted = function() return GlowWanted() end,
}
