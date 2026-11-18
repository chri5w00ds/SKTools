--[[-------------------------------------------------------------------------
  SKTools - action bar tint

  Tints action bar icons so you can read them at a glance:
    * out of range              -> range colour (red by default)
    * not enough resource       -> that resource's colour (mana blue, energy
                                   yellow, ...)
    * both                      -> two layers: the resource colour on top,
                                   the range colour where it has receded

  With "partial tint" on, the resource tint only covers the share of the
  resource you are still missing. It recedes towards the top-right corner
  along a 45 degree edge as the resource fills, and the edge ripples gently.

  Works for every class. Default Blizzard bars, Bartender4 and Dominos.
---------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

local MEDIA = ns.MEDIA
local PHASES = 12
local MASK, MASK_INV, LINE = {}, {}, {}
for i = 1, PHASES do
    MASK[i]     = MEDIA .. "Mask" .. i
    MASK_INV[i] = MEDIA .. "MaskInv" .. i
    LINE[i]     = MEDIA .. "Line" .. i
end
-- the two extra lines ride the same edge a third of a cycle apart, so the
-- three waves weave around each other instead of stacking
local DARK_OFFSET, LIGHT_OFFSET = 4, 8
local LINE_ALPHA = 0.85
local function Phase(p, offset) return (p - 1 + offset) % PHASES + 1 end
local CLAMP = "CLAMPTOBLACKADDITIVE"
local SOLID = "Interface\\Buttons\\WHITE8X8"

ns.TINT_DEFAULTS = {
    enabled = true,
    range   = true,     -- tint skills you're out of range for
    resource= true,     -- tint skills you can't afford
    alpha   = 0.45,     -- tint opacity: low enough to still read the icon
    partial = true,     -- resource tint shrinks as the resource fills
    animate = true,     -- gentle ripple on the edge
    darkLine  = true,   -- extra wavy lines along the edge, for contrast
    lightLine = true,
    colors  = {
        range  = { 1.00, 0.10, 0.10 },
        mana   = { 0.15, 0.40, 1.00 },
        rage   = { 0.65, 0.00, 0.25 },
        energy = { 1.00, 0.90, 0.10 },
        focus  = { 1.00, 0.50, 0.20 },
        other  = { 0.80, 0.80, 0.80 },
        darkLine  = { 0.00, 0.00, 0.00 },
        lightLine = { 1.00, 1.00, 1.00 },
    },
}

-- Enum.PowerType -> colour key
local POWER_KEY = { [0] = "mana", [1] = "rage", [2] = "focus", [3] = "energy" }
ns.TINT_COLOR_KEYS = {
    { "range",  "Out of range" },
    { "mana",   "Mana" },
    { "rage",   "Rage" },
    { "energy", "Energy" },
    { "focus",  "Focus" },
}

----------------------------------------------------------------------
-- Helpers (secret-value safe, like the rest of the addon)
----------------------------------------------------------------------

local issecret = _G.issecretvalue or function() return false end
local function Plain(v)
    if v ~= nil and issecret(v) then return nil end
    return v
end
local function Ask(fn, ...)
    if not fn then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return nil end
    return Plain(a), Plain(b), Plain(c)
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

local CS, CAB = C_Spell or {}, C_ActionBar or {}
local GetActionInfo_    = CAB.GetActionInfo or _G.GetActionInfo
local HasAction_        = CAB.HasAction or _G.HasAction
local IsActionInRange_  = CAB.IsActionInRange or _G.IsActionInRange
local IsUsableAction_   = CAB.IsUsableAction or _G.IsUsableAction
local GetSpellPowerCost_ = CS.GetSpellPowerCost or _G.GetSpellPowerCost
local GetMacroSpell_    = _G.GetMacroSpell

----------------------------------------------------------------------
-- Finding the action buttons
----------------------------------------------------------------------

local BUTTON_SETS = {
    { "ActionButton", 12 },
    { "MultiBarBottomLeftButton", 12 },
    { "MultiBarBottomRightButton", 12 },
    { "MultiBarRightButton", 12 },
    { "MultiBarLeftButton", 12 },
    { "MultiBar5Button", 12 },
    { "MultiBar6Button", 12 },
    { "MultiBar7Button", 12 },
    { "BT4Button", 180 },              -- Bartender4
    { "DominosActionButton", 180 },    -- Dominos
}

local overlays = {}       -- button -> overlay
local list = {}           -- overlays in order, for the update loop
local db

local function IconOf(button)
    local name = button.GetName and button:GetName()
    local icon = button.icon or button.Icon or (name and _G[name .. "Icon"])
    if type(icon) == "table" and icon.GetObjectType then return icon end
end

local function SlotOf(button)
    local slot = Plain(rawget(button, "action")) or Plain(rawget(button, "_state_action"))
    if type(slot) ~= "number" and button.GetAttribute then
        local ok, v = pcall(button.GetAttribute, button, "action")
        if ok then slot = Plain(v) end
    end
    return type(slot) == "number" and slot or nil
end

local function MakeOverlay(button, icon)
    local o = CreateFrame("Frame", nil, button)
    o:SetAllPoints(icon)
    o:SetFrameLevel((button:GetFrameLevel() or 1) + 1)
    o:EnableMouse(false)

    -- "full" carries the range colour, "part" the resource (or mixed) colour.
    -- The two masks are exact opposites placed on the same line, so the two
    -- layers meet edge to edge without overlapping.
    o.full = o:CreateTexture(nil, "OVERLAY", nil, 1)
    o.full:SetAllPoints()
    o.part = o:CreateTexture(nil, "OVERLAY", nil, 2)
    o.part:SetAllPoints()

    o.mask = o:CreateMaskTexture()
    o.mask:SetTexture(MASK[1], CLAMP, CLAMP)
    o.inv = o:CreateMaskTexture()
    o.inv:SetTexture(MASK_INV[1], CLAMP, CLAMP)
    o.part:AddMaskTexture(o.mask)
    o.full:AddMaskTexture(o.inv)

    -- contrast lines along the edge; they are bigger than the icon, so they
    -- are clipped to it with a plain square mask (plus the icon shape below)
    o.dark = o:CreateTexture(nil, "OVERLAY", nil, 3)
    o.dark:SetTexture(LINE[Phase(1, DARK_OFFSET)])
    o.light = o:CreateTexture(nil, "OVERLAY", nil, 4)
    o.light:SetTexture(LINE[Phase(1, LIGHT_OFFSET)])
    local clip = o:CreateMaskTexture()
    clip:SetTexture(SOLID, CLAMP, CLAMP)
    clip:SetAllPoints(o)
    o.dark:AddMaskTexture(clip)
    o.light:AddMaskTexture(clip)
    o.dark:Hide(); o.light:Hide()

    -- Clip the tint to the same shape as the icon. Modern action buttons
    -- draw the icon a little larger than the frame and trim it with
    -- button.IconMask (rounded corners); without this the tint's square
    -- corners poke out past the button border.
    local im = rawget(button, "IconMask")
    if type(im) == "table" and im.GetObjectType then
        local shape = o:CreateMaskTexture()
        local atlas = im.GetAtlas and im:GetAtlas()
        if atlas then
            shape:SetAtlas(atlas, false)
        else
            local tex = im.GetTexture and im:GetTexture()
            if tex then shape:SetTexture(tex, CLAMP, CLAMP) end
        end
        shape:SetAllPoints(im)
        o.part:AddMaskTexture(shape)
        o.full:AddMaskTexture(shape)
        o.dark:AddMaskTexture(shape)
        o.light:AddMaskTexture(shape)
        o.shape = shape
    else
        -- no icon mask (older art, some bar addons): keep inside the border
        o:ClearAllPoints()
        o:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
        o:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    end

    -- Forever hides your current mana from addons, but a status bar can still
    -- be fed the hidden value and draws it correctly. This invisible bar spans
    -- the edge's travel; the tint edge is pinned to the end of its fill, so
    -- the game itself moves the edge with your mana.
    local meter = CreateFrame("StatusBar", nil, o)
    meter:SetStatusBarTexture(SOLID)
    meter:SetOrientation("HORIZONTAL")
    meter:SetAlpha(0)
    meter:EnableMouse(false)
    o.meter = meter

    o.button = button
    o:Hide()
    overlays[button] = o
    list[#list + 1] = o
end

local function Scan()
    if InCombatLockdown and InCombatLockdown() then return end   -- try again later
    for _, set in ipairs(BUTTON_SETS) do
        for i = 1, set[2] do
            local b = _G[set[1] .. i]
            if b and not overlays[b] then
                local icon = IconOf(b)
                if icon then pcall(MakeOverlay, b, icon) end
            end
        end
    end
end

----------------------------------------------------------------------
-- What's wrong with an action
----------------------------------------------------------------------

local function SpellOf(slot)
    local kind, id = Ask(GetActionInfo_, slot)
    if kind == "spell" then return id end
    if kind == "macro" and GetMacroSpell_ then
        local sid = Ask(GetMacroSpell_, id)
        return sid
    end
end

-- what the last check of each slot saw, for /skr tint debug
local seen = {}

-- returns outOfRange (bool), shortKey (colour key or nil), fraction available (0-1)
local function Check(slot)
    local info = { spell = "-", cost = "-", avail = "-", src = "none" }
    seen[slot] = info
    local outRange = false
    if db.range ~= false and UnitExists("target") then
        local r = Ask(IsActionInRange_, slot)
        outRange = (r == false or r == 0)
    end

    local key, have, meter
    local costKnown = false
    if db.resource == false then
        info.range = tostring(outRange)
        return outRange, nil, nil
    end
    local spell = SpellOf(slot)
    info.spell = tostring(spell)
    if spell and GetSpellPowerCost_ then
        local ok, costs = pcall(GetSpellPowerCost_, spell)
        info.cost = ok and ((costs ~= nil and issecret(costs)) and "secret" or type(costs)) or "error"
        costs = ok and Plain(costs) or nil
        if type(costs) == "table" then
            costKnown = true
            for _, c in ipairs(costs) do
                local cost = Plain(c.cost)
                local ptype = Plain(c.type)
                info.cost = ("%s (type %s)"):format(tostring(cost), tostring(ptype))
                if cost and cost > 0 and ptype then
                    local okP, raw = pcall(UnitPower, "player", ptype)
                    local avail = okP and Plain(raw) or nil
                    info.avail = (okP and raw ~= nil and issecret(raw)) and "hidden" or tostring(avail)
                    if avail then
                        info.src = "cost"
                        if avail < cost then
                            key = POWER_KEY[ptype] or "other"
                            have = math.max(avail, 0) / cost
                        end
                    elseif okP and raw ~= nil then
                        -- mana is hidden: the game's flag says whether you're
                        -- short, the status bar shows by how much
                        local _, noMana = Ask(IsUsableAction_, slot)
                        info.src = "meter (noMana=" .. tostring(noMana) .. ")"
                        if noMana then
                            key = POWER_KEY[ptype] or "other"
                            have = 0
                            meter = { cost = cost, raw = raw }
                        end
                    else
                        costKnown = false
                    end
                    break
                end
            end
        end
    end

    -- no cost data: fall back to the game's own "not enough mana" flag
    if not key and not costKnown then
        local _, noMana = Ask(IsUsableAction_, slot)
        info.src = "fallback (noMana=" .. tostring(noMana) .. ")"
        if noMana then
            local pt = Ask(UnitPowerType, "player")
            key = (pt and POWER_KEY[pt]) or "other"
            have = 0
        end
    end
    info.have = meter and "bar" or (have and ("%.0f%%"):format(have * 100) or "-")
    info.range = tostring(outRange)
    return outRange, key, have, meter
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

local phase = 1

-- Puts the edge where `have` (0 - 1) says: 0 = whole icon tinted, 1 = none.
-- Line runs x + y = k in icon coordinates, k from -size to +size.
-- The mask's 45 degree edge runs through its centre, so sliding the mask
-- sideways by k puts the edge on the line x + y = k.
local function PlaceEdge(o, have, meter)
    local size = o:GetWidth()
    if not size or size <= 0 then return end
    local m = 3 * size + 16                -- covers the icon at any edge position

    if meter and db.partial then
        local bar = o.meter
        bar:ClearAllPoints()
        bar:SetPoint("LEFT", o, "CENTER", -size, 0)
        bar:SetSize(2 * size, 2)
        bar:SetMinMaxValues(0, meter.cost)
        pcall(bar.SetValue, bar, meter.raw)   -- hidden value goes straight in
        local fill = bar:GetStatusBarTexture()
        for _, mk in ipairs({ o.mask, o.inv, o.dark, o.light }) do
            mk:SetSize(m, m)
            mk:ClearAllPoints()
            mk:SetPoint("CENTER", fill, "RIGHT", 0, 0)
        end
        return
    end

    local k
    if have == nil then
        k = size + 6                       -- edge past the top-right corner
    elseif not db.partial or have <= 0 then
        k = -size - 6                      -- past the bottom-left: all tinted
    else
        k = -size + 2 * size * have
    end
    for _, mk in ipairs({ o.mask, o.inv, o.dark, o.light }) do
        mk:SetSize(m, m)
        mk:ClearAllPoints()
        mk:SetPoint("CENTER", o, "CENTER", k, 0)
    end
end

local function Paint(o, outRange, key, have, meter)
    local a, C = db.alpha, db.colors
    if not outRange and not key then o:Hide(); return end

    local range = C.range
    if key then
        -- resource layer keeps its own colour; when you're also out of range
        -- the red layer shows in the part it has uncovered
        local res = C[key] or C.other
        o.part:SetColorTexture(res[1], res[2], res[3], a)
        o.part:Show()
    else
        o.part:Hide()
    end

    if outRange then
        o.full:SetColorTexture(range[1], range[2], range[3], a)
        o.full:Show()
    else
        o.full:Hide()
    end

    PlaceEdge(o, key and have or nil, key and meter or nil)

    -- lines only make sense when the edge actually crosses the icon
    local edgeOnIcon = key and db.partial and (meter or (have and have > 0))
    for _, l in ipairs({ { o.dark, "darkLine" }, { o.light, "lightLine" } }) do
        local tex, name = l[1], l[2]
        if edgeOnIcon and db[name] then
            local c = C[name] or { 1, 1, 1 }
            tex:SetVertexColor(c[1], c[2], c[3], LINE_ALPHA)
            tex:Show()
        else
            tex:Hide()
        end
    end
    o:Show()
end

local function UpdateAll()
    if not db then return end
    if not db.enabled then
        for i = 1, #list do list[i]:Hide() end
        return
    end
    for i = 1, #list do
        local o = list[i]
        local slot = o.button:IsVisible() and SlotOf(o.button)
        if slot and Ask(HasAction_, slot) then
            Paint(o, Check(slot))
        else
            o:Hide()
        end
    end
end

local function Animate()
    if not (db and db.enabled and db.animate and db.partial) then return end
    phase = phase % PHASES + 1
    for i = 1, #list do
        local o = list[i]
        if o:IsShown() then
            o.mask:SetTexture(MASK[phase], CLAMP, CLAMP)
            o.inv:SetTexture(MASK_INV[phase], CLAMP, CLAMP)
            o.dark:SetTexture(LINE[Phase(phase, DARK_OFFSET)])
            o.light:SetTexture(LINE[Phase(phase, LIGHT_OFFSET)])
        end
    end
end

----------------------------------------------------------------------
-- Driver
----------------------------------------------------------------------

local driver = CreateFrame("Frame")
local acc, animAcc, scanAcc = 0, 0, 0
driver:SetScript("OnUpdate", function(_, elapsed)
    acc, animAcc, scanAcc = acc + elapsed, animAcc + elapsed, scanAcc + elapsed
    if acc >= 0.1 then acc = 0; UpdateAll() end
    if animAcc >= 0.09 then animAcc = 0; Animate() end   -- 12 steps, ~1.1 s cycle
    if scanAcc >= 10 then scanAcc = 0; Scan() end   -- catches bars made later
end)
driver:Hide()

local function Init()
    -- kept inside the range settings
    local root = ns.InitDB().range
    root.tint = root.tint or {}
    DeepFill(root.tint, ns.TINT_DEFAULTS)
    db = root.tint
end

driver:RegisterEvent("PLAYER_LOGIN")
pcall(driver.RegisterEvent, driver, "PLAYER_ENTERING_WORLD")
pcall(driver.RegisterEvent, driver, "PLAYER_REGEN_ENABLED")
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        Init()
        Scan()
        driver:Show()
    else
        Scan()
    end
end)

----------------------------------------------------------------------
-- For the options window / slash commands
----------------------------------------------------------------------

ns.Tint = {
    Refresh = UpdateAll,
    Reset = function()
        ns.InitDB().range.tint = nil
        Init()
        UpdateAll()
    end,
    Settings = function() return db end,
    Count = function() return #list end,
    List = function() return list end,
    Debug = function(print)
        print(("tint: %d buttons, enabled=%s partial=%s animate=%s, in combat=%s")
            :format(#list, tostring(db and db.enabled), tostring(db and db.partial),
                    tostring(db and db.animate), tostring(InCombatLockdown and InCombatLockdown())))
        local n = 0
        for i = 1, #list do
            local o = list[i]
            local slot = SlotOf(o.button)
            local info = slot and seen[slot]
            if info and info.src ~= "none" and n < 8 then
                n = n + 1
                local _, _, _, mx = o.mask:GetPoint()
                print(("  %s (slot %d): spell %s | cost %s | mana %s | have %s | via %s | out of range %s | edge %s | icon shape %s")
                    :format(o.button:GetName() or "?", slot, info.spell, info.cost, info.avail,
                            info.have, info.src, info.range, mx and ("%.0f"):format(mx * 2) or "?",
                            o.shape and "yes" or "no"))
            end
        end
        if n == 0 then print("  no button with a cost right now") end
    end,
}
