--[[-------------------------------------------------------------------------
  SKTools - Shaman totem timers on the target's nameplate

  Four small icons at the left end of the health bar, in the spot the combo
  points (Rogue, Druid) and the range crescent (Hunter) use: Earth, Fire,
  Water, Air from top to bottom, each the totem you have down. A dark radial
  sweep eats each icon clockwise as its totem runs out.

  They sit in a chevron: the top and bottom boxes' right edges line up with
  the bar's left end (so they never overlap the debuffs above the bar), and
  the middle two sit half a box further out, their right edges on the top
  and bottom boxes' centre line.

  Lightning Shield: three short blue bars in the gap between the boxes and
  the health bar, one per charge, going dark from the top as charges are
  used; all three dark while the shield is down.

  Only the totems you have down show, keeping that order: one sits on the
  bar's centre line, two either side of it, three as one on the line with
  one above and one below, four as the chevron. Part of the Shaman class sets (Enhancement, Elemental,
  Restoration).
---------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

ns.TOTEM_DEFAULTS = {
    enabled = true,
    size    = 16,        -- each box, in pixels
    gap     = 2,         -- between the boxes, top to bottom
    x       = 0,         -- offset from the bar's left end
    y       = 0,
    shield  = true,      -- the Lightning Shield charges in the gap by the bar
    shieldCd = 3,        -- seconds between two balls firing (learned after each fight)
    hideCdm  = true,     -- hide Lightning Shield's own icon in Blizzard's Cooldown Manager
}

-- top to bottom: the game's totem slots are 1 Fire, 2 Earth, 3 Water, 4 Air
local ORDER = {
    { slot = 2, name = "Earth", sample = "Interface\\Icons\\Spell_Nature_EarthBindTotem" },
    { slot = 1, name = "Fire",  sample = "Interface\\Icons\\Spell_Fire_SearingTotem" },
    { slot = 3, name = "Water", sample = "Interface\\Icons\\INV_Spear_04" },
    { slot = 4, name = "Air",   sample = "Interface\\Icons\\Spell_Nature_Windfury" },
}
ns.TOTEM_ORDER = ORDER

local SHIELD_ID, SHIELD_MAX = 324, 3      -- Lightning Shield, and its charges

local db, holder
local boxes = {}
local previewing = false
local state = "not started"
local cachePlate, cacheAnchor, cacheHow, cacheAge = nil, nil, nil, -100

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

-- box centres in the holder, whose right edge is the bar's left end, for n totems down. Four: the
-- outer two flush with the bar's end, the middle two half a box further out. Three: one on the centre
-- line, one above and one below it (flush). Two: either side of the centre line. One: on it. The
-- boxes on or beside the centre line always sit half a box out, leaving the gap by the bar.
local function Offsets(s, gap, n)
    n = n or 4
    local step = s + gap
    local IN, OUT = -s, -s / 2
    if n <= 1 then return { { x = IN, y = 0 } } end
    if n == 2 then return { { x = IN, y = step / 2 }, { x = IN, y = -step / 2 } } end
    if n == 3 then return { { x = OUT, y = step }, { x = IN, y = 0 }, { x = OUT, y = -step } } end
    return { { x = OUT, y = 1.5 * step }, { x = IN, y = 0.5 * step }, { x = IN, y = -0.5 * step }, { x = OUT, y = -1.5 * step } }
end
-- how far the chevron reaches left of the bar (for what sits further out, like the icon column)
local function LeftReach()
    local s = (db and db.size) or ns.TOTEM_DEFAULTS.size
    return 1.5 * s - ((db and db.x) or 0)
end

local function Build()
    holder = CreateFrame("Frame", "SKToolsTotems", UIParent)
    holder:SetSize(1, 1)
    holder:EnableMouse(false)
    holder:Hide()
    for i = 1, 4 do
        local b = CreateFrame("Frame", nil, holder)
        b:SetFrameLevel(holder:GetFrameLevel() + 2)
        b.edge = b:CreateTexture(nil, "BACKGROUND")
        b.edge:SetPoint("TOPLEFT", -1, 1); b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
        b.edge:SetColorTexture(0, 0, 0, 1)
        b.empty = b:CreateTexture(nil, "BORDER")
        b.empty:SetAllPoints()
        b.empty:SetColorTexture(0.07, 0.07, 0.08, 0.8)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- the radial countdown: reversed, so the dark part is the time used and grows clockwise
        local ok, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
        if ok and cd then
            cd:SetAllPoints()
            if cd.SetReverse then cd:SetReverse(true) end
            if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
            if cd.SetDrawEdge then cd:SetDrawEdge(false) end
            if cd.SetDrawBling then cd:SetDrawBling(false) end
            if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.7) end
            b.cd = cd
        end
        boxes[i] = b
    end
    -- the shield's three segments, top to bottom. Each is a tiny bar that is either full or empty:
    -- the k-th from the bottom runs from k-1 to k, so given the charge count it is lit when there are
    -- k or more. Bars take the count even when the game hides it from addons.
    holder.segs = {}
    for i = 1, SHIELD_MAX do
        local k = SHIELD_MAX + 1 - i
        local b = CreateFrame("StatusBar", nil, holder)
        b:SetStatusBarTexture(ns.MEDIA .. "ShieldSeg")
        if b.SetOrientation then b:SetOrientation("VERTICAL") end
        b:SetMinMaxValues(k - 1, k)
        b:SetValue(0)
        b.off = b:CreateTexture(nil, "BACKGROUND")
        b.off:SetAllPoints()
        b.off:SetTexture(ns.MEDIA .. "ShieldSegOff")
        b.k = k
        holder.segs[i] = b
    end
end

----------------------------------------------------------------------
-- Lightning Shield: its charges (0 = down). In combat the game may hide your auras; then the last
-- count stands, and casting the shield counts as three.
----------------------------------------------------------------------
local shieldCharges = 0
local function ShieldName()
    local shieldName
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, SHIELD_ID)
        shieldName = ok and type(info) == "table" and Plain(info.name) or nil
    elseif _G.GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, SHIELD_ID)
        shieldName = ok and Plain(n) or nil
    end
    shieldName = shieldName or "Lightning Shield"
    return shieldName
end
local function ShieldKnown()
    local name = ShieldName()
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        return ok and type(info) == "table" and Plain(info.spellID) ~= nil
    end
    if _G.GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, name)
        return ok and Plain(n) ~= nil
    end
    return false
end
-- the Lightning Shield ranks (looked up by id: in combat the names can be hidden too)
local SHIELD_RANKS = { 324, 325, 905, 945, 8134, 10431, 10432 }
local RANK = {}
for _, id in ipairs(SHIELD_RANKS) do RANK[id] = true end
local lastRead = "not read yet"
local countsKnown = false      -- has this client ever shown a real charge count on the shield?
local shieldInstance           -- the shield aura's id, to follow its changes in combat
local idLookupWorks = false    -- has asking for it by that id answered in combat?

local function InCombat()
    if _G.InCombatLockdown then
        local ok, r = pcall(InCombatLockdown)
        if ok and Plain(r) == true then return true end
    end
    local ok, r = pcall(UnitAffectingCombat, "player")
    return ok and Plain(r) == true
end

-- what the game says about the shield on you:
--   { present = true / false / nil (hidden), count = a number or nil, raw = a hidden count or nil }
local function Look(a)
    local app, ch = a.applications, a.charges
    local pa, pc = Plain(app), Plain(ch)
    local inst = Plain(a.auraInstanceID)
    if inst then shieldInstance = inst end
    lastRead = ("applications=%s charges=%s id=%s"):format(pa == nil and (app == nil and "nil" or "hidden") or tostring(pa),
        pc == nil and (ch == nil and "nil" or "hidden") or tostring(pc), tostring(inst or "hidden"))
    local r = { present = true }
    if type(pa) == "number" and pa > 0 then r.count = math.min(SHIELD_MAX, pa); countsKnown = true
    elseif type(pc) == "number" and pc > 0 then r.count = math.min(SHIELD_MAX, pc); countsKnown = true
    elseif pa == nil and app ~= nil then r.raw = app
    elseif pc == nil and ch ~= nil then r.raw = ch end
    return r
end
----------------------------------------------------------------------
-- Blizzard's Cooldown Manager: with Lightning Shield among its Tracked Buffs, its icon keeps a copy
-- of the shield's aura that the game refreshes in combat too. Whether that copy is there says
-- whether the shield is up; its count is hidden in combat, but the pips can show a hidden number.
-- The icon itself is made invisible (not hidden: hidden, it would stop updating).
----------------------------------------------------------------------
local CDM_VIEWERS = { "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local cdmItem, cdmViewer, cdmAge = nil, nil, -100
local cdmState = "not looked for yet"

local function ItemSpell(item)
    local info = item.cooldownInfo
    if type(info) ~= "table" and item.GetCooldownInfo then
        local ok, r = pcall(item.GetCooldownInfo, item); info = ok and r or nil
    end
    if type(info) ~= "table" then return nil end
    for _, k in ipairs({ "spellID", "overrideSpellID", "overrideTooltipSpellID", "linkedSpellID" }) do
        local id = Plain(info[k])
        if id and RANK[id] then return id end
    end
    for _, id in ipairs(type(info.linkedSpellIDs) == "table" and info.linkedSpellIDs or {}) do
        if RANK[Plain(id) or 0] then return Plain(id) end
    end
    return nil
end
local function FindCdm()
    local now = GetTime()
    if cdmItem and now - cdmAge < 1 then return cdmItem end
    cdmAge = now
    cdmItem, cdmViewer = nil, nil
    for _, name in ipairs(CDM_VIEWERS) do
        local v = _G[name]
        if type(v) == "table" and v.GetItemFrames then
            local ok, items = pcall(v.GetItemFrames, v)
            if ok and type(items) == "table" then
                for _, item in ipairs(items) do
                    if type(item) == "table" and ItemSpell(item) then
                        cdmItem, cdmViewer = item, name
                        cdmState = "found in " .. name
                        return item
                    end
                end
            end
        end
    end
    cdmState = (_G.BuffIconCooldownViewer and "Lightning Shield is not among its Tracked Buffs") or "no Cooldown Manager"
    return nil
end
-- keep Lightning Shield's own icon invisible while we show it (and give it back when we stop)
local cdmHidden = nil
local function HideCdmIcon(item)
    local want = item and db and db.hideCdm ~= false and db.shield ~= false
    if cdmHidden and cdmHidden ~= item then pcall(cdmHidden.SetAlpha, cdmHidden, 1); cdmHidden = nil end
    if want then
        if item:GetAlpha() ~= 0 then pcall(item.SetAlpha, item, 0) end
        cdmHidden = item
    elseif cdmHidden then
        pcall(cdmHidden.SetAlpha, cdmHidden, 1); cdmHidden = nil
    end
end

local function ReadShield()
    -- from the Cooldown Manager first
    local item = FindCdm()
    HideCdmIcon(item)
    if item then
        local a = item.auraDataCached
        if a == nil and item.GetAuraDataCached then
            local ok, r = pcall(item.GetAuraDataCached, item); a = ok and r or nil
        end
        if type(a) ~= "table" then lastRead = "Cooldown Manager: not up"; return { present = false, cdm = true } end
        local r = Look(a)
        lastRead = "Cooldown Manager: " .. lastRead
        r.cdm = true
        return r
    end
    -- else by spell id
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local failed = false
        for _, id in ipairs(SHIELD_RANKS) do
            local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
            if not ok then failed = true
            elseif type(a) == "table" then return Look(a) end
        end
        -- in combat the game answers "not on you" even while it is up: only trust that out of combat.
        -- There, ask for the shield's own aura by the id we know it by: its count may be hidden, but
        -- the pips can still show a hidden count.
        if not failed then
            if InCombat() then
                if shieldInstance and C_UnitAuras.GetAuraDataByAuraInstanceID then
                    local ok, a = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", shieldInstance)
                    if ok and type(a) == "table" then
                        idLookupWorks = true
                        local r = Look(a)
                        lastRead = "by its aura id: " .. lastRead
                        return r
                    end
                    -- nothing for it: gone, once the lookup has been seen to work in combat
                    if ok and idLookupWorks then lastRead = "by its aura id: gone"; return { present = false } end
                    lastRead = "hidden in combat (by aura id: " .. (ok and "nothing" or "refused") .. ")"
                    return {}
                end
                lastRead = "hidden in combat"; return {}
            end
            lastRead = "not on you"; return { present = false }
        end
    end
    -- else by name, aura by aura
    local name = ShieldName()
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local secret = false
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok then lastRead = "auras hidden"; return {} end
            if type(a) ~= "table" then break end
            local n = Plain(a.name)
            if n == nil then secret = true elseif n == name then return Look(a) end
        end
        if secret then lastRead = "auras hidden"; return {} end
        lastRead = "not on you"
        return { present = false }
    end
    if _G.UnitBuff then
        for i = 1, 40 do
            local ok, n, _, count = pcall(UnitBuff, "player", i)
            if not ok then return {} end
            n = Plain(n)
            if not n then break end
            if n == name then return Look({ applications = count }) end
        end
        return { present = false }
    end
    return {}
end

local function Hide(why)
    state = why
    if holder and holder:IsShown() then holder:Hide() end
end

-- is a totem set on for this character: a Shaman whose class set has the totem timers
local function Wanted()
    local _, class = UnitClass("player")
    if class ~= "SHAMAN" then return false, "not a Shaman" end
    local set = ns.ClassSets and ns.ClassSets.ForPlayer and ns.ClassSets.ForPlayer()
    if not set then return false, "no Shaman class set" end
    for _, p in ipairs(set.parts or {}) do if p == "totems" then return true end end
    return false, "the " .. tostring(set.title) .. " set has no totem timers"
end

-- one element: shown (icon, start, duration) or empty. The numbers may be hidden from addons;
-- they go straight to the game's own countdown, which can draw them anyway.
local function Read(slot)
    if not _G.GetTotemInfo then return nil end
    local ok, have, _, start, dur, icon = pcall(GetTotemInfo, slot)
    if not ok then return nil end
    local h = Plain(have)
    if h == false then return nil end
    local d = Plain(dur)
    if d ~= nil and d <= 0 then return nil end
    if h == nil and Plain(icon) == nil and icon == nil then return nil end
    return { icon = icon, start = start, dur = dur }
end

local function Update()
    if not holder or not db then return end
    if not db.enabled then return Hide("turned off in settings") end
    local ok, why = Wanted()
    if not ok and not previewing then return Hide(why) end

    -- the totems down, top to bottom in element order
    local list = {}
    for i, e in ipairs(ORDER) do
        local t
        if previewing then t = { icon = e.sample, start = GetTime() - 30 * i, dur = 120 } else t = Read(e.slot) end
        if t then list[#list + 1] = t end
    end
    -- the shield: only in combat, and only while it is up
    local shieldOn = db.shield ~= false and (previewing or ShieldKnown())
    local charges = 0
    if shieldOn and not previewing then
        local r = ReadShield()
        if r.present == false then shieldCharges = 0
        elseif r.count then shieldCharges = r.count; charges = r.count
        elseif r.present and shieldCharges == 0 then shieldCharges = SHIELD_MAX   -- up, but no count shown
        end
        charges = shieldCharges
        -- a client that shows real counts: in combat the hidden count goes straight to the bars
        if r.raw ~= nil and (countsKnown or r.cdm) then charges = r.raw end
        if r.cdm and r.present and shieldCharges < 1 then shieldCharges = 1 end     -- up: at least one left
        shieldOn = InCombat() and shieldCharges > 0
        if r.raw == nil or not (countsKnown or r.cdm) then charges = shieldCharges end
    elseif previewing then
        charges = 2
    end
    if #list == 0 and not shieldOn then return Hide("no totems down" .. (shieldCharges > 0 and ", out of combat" or "")) end

    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
        and select(2, pcall(C_NamePlate.GetNamePlateForUnit, "target"))
    if type(plate) ~= "table" or (plate.IsForbidden and plate:IsForbidden()) then
        return Hide("totems down, but the target has no nameplate")
    end
    if plate ~= cachePlate or GetTime() - cacheAge > 1 or (cacheHow == "sktools") ~= (ns.Plates and ns.Plates.Frame(plate) ~= nil) then
        cacheAnchor, cacheHow = ns.Combo.Anchor(plate, "target")
        cachePlate, cacheAge = plate, GetTime()
    end
    local ours = cacheHow == "sktools"
    local s, gap = db.size, db.gap or 2
    holder:SetParent(ours and cacheAnchor or plate)
    holder:SetFrameStrata(plate:GetFrameStrata() or "MEDIUM")
    holder:SetFrameLevel((plate:GetFrameLevel() or 1) + 20)
    holder:SetSize(1.5 * s, 4 * s + 3 * gap)
    holder:ClearAllPoints()
    if ours then
        holder:SetPoint("RIGHT", cacheAnchor, "LEFT", db.x - ((ns.Plates and ns.Plates.LeftEdge and ns.Plates.LeftEdge()) or 0), db.y)      -- past the level box
    elseif cacheHow == "health bar" then
        holder:SetPoint("LEFT", cacheAnchor, "RIGHT", 4 + db.x, db.y)
    else
        holder:SetPoint("CENTER", cacheAnchor, "CENTER", db.x, db.y)
    end
    local off = Offsets(s, gap, #list)
    for i, b in ipairs(boxes) do
        local t = list[i]
        if t then
            b:SetSize(s, s)
            b:ClearAllPoints()
            b:SetPoint("CENTER", holder, "RIGHT", off[i].x, off[i].y)
            b.empty:Hide()
            b.icon:Show()
            pcall(b.icon.SetTexture, b.icon, t.icon)
            if b.cd then
                b.cd:Show()
                pcall(b.cd.SetCooldown, b.cd, t.start, t.dur)
            end
            b:Show()
        else
            b:Hide()
        end
    end
    -- the shield's segments in the gap: from the boxes on the centre line (half a box out) to the bar,
    -- between the boxes above and below (with three totems those sit flush, so the gap is shorter)
    for i, t in ipairs(holder.segs) do t:SetShown(shieldOn) end
    if shieldOn then
        local span = (#list == 3) and (s + 2 * gap) or (2 * s + 3 * gap)
        local total = span - 4
        local sg = math.max(1, s * 1.5 / 16)
        local sh = (total - 2 * sg) / 3
        local w = math.max(3, s * 6 / 16)
        for i, t in ipairs(holder.segs) do
            t:ClearAllPoints()
            t:SetSize(w, sh)
            t:SetPoint("TOP", holder, "RIGHT", -s / 4, total / 2 - (i - 1) * (sh + sg))
            -- used charges go dark from the top
            if not pcall(t.SetValue, t, charges) then t:SetValue(shieldCharges) end
        end
    end
    holder:Show()
    state = "showing " .. #list .. " totems" .. (shieldOn and (", shield " .. (Plain(charges) and tostring(charges) or "hidden") .. "/3") or "")
        .. ", anchored to " .. tostring(cacheHow)
end

local driver = CreateFrame("Frame")
local acc = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.2 then return end
    acc = 0
    Update()
end)
driver:Hide()
driver:RegisterEvent("PLAYER_LOGIN")
pcall(driver.RegisterEvent, driver, "PLAYER_TARGET_CHANGED")
pcall(driver.RegisterEvent, driver, "PLAYER_TOTEM_UPDATE")
pcall(driver.RegisterUnitEvent or driver.RegisterEvent, driver, "UNIT_SPELLCAST_SUCCEEDED", "player")
pcall(driver.RegisterUnitEvent or driver.RegisterEvent, driver, "UNIT_AURA", "player")
pcall(driver.RegisterUnitEvent or driver.RegisterEvent, driver, "UNIT_COMBAT", "player")
pcall(driver.RegisterEvent, driver, "PLAYER_REGEN_DISABLED")
pcall(driver.RegisterEvent, driver, "PLAYER_REGEN_ENABLED")

-- the shield's aura changing in combat: a charge used (an update to it), or gone (removed). The
-- game says which auras changed even while it hides what they are.
local function Has(list, id)
    if type(list) ~= "table" or id == nil then return false end
    for _, v in ipairs(list) do if Plain(v) == id then return true end end
    return false
end
-- casting the shield in combat: its new aura's details are hidden, so the aura added within a moment
-- of the cast is taken to be it
local castAt, addedAt, addedId = -100, -100, nil
local function Adopt(id)
    shieldInstance = id
    shieldCharges = SHIELD_MAX
end
-- the last few aura changes, for /skt totemdebug: what the game tells us in combat
local auraLog = {}
local function LogAura(info)
    local function ids(list)
        if type(list) ~= "table" then return "0" end
        local out = {}
        for _, v in ipairs(list) do
            local p = Plain(v)
            out[#out + 1] = p == nil and "hidden" or tostring(p)
            if #out >= 4 then out[#out + 1] = "..."; break end
        end
        return #out == 0 and "0" or table.concat(out, ",")
    end
    local line
    if type(info) ~= "table" then line = "no details"
    elseif info.isFullUpdate then line = "full update"
    else
        local added = {}
        for _, a in ipairs(info.addedAuras or {}) do
            if type(a) == "table" then
                local id, sp = Plain(a.auraInstanceID), Plain(a.spellId)
                added[#added + 1] = (id and tostring(id) or "hidden") .. "/" .. (sp and tostring(sp) or "hidden")
            end
        end
        line = ("added %s; changed %s; removed %s"):format(#added == 0 and "0" or table.concat(added, ","),
            ids(info.updatedAuraInstanceIDs), ids(info.removedAuraInstanceIDs))
    end
    table.insert(auraLog, 1, (InCombat() and "[combat] " or "") .. line)
    auraLog[7] = nil
end

local function OnAura(info)
    LogAura(info)
    if type(info) ~= "table" or info.isFullUpdate then return end
    local now = GetTime()
    for _, a in ipairs(info.addedAuras or {}) do
        if type(a) == "table" then
            local id = Plain(a.auraInstanceID)
            if RANK[Plain(a.spellId) or 0] then Adopt(id or shieldInstance)
            elseif id then
                if now - castAt < 1 then Adopt(id) else addedAt, addedId = now, id end
            end
        end
    end
    if Has(info.removedAuraInstanceIDs, shieldInstance) then
        shieldCharges = 0; shieldInstance = nil
    elseif Has(info.updatedAuraInstanceIDs, shieldInstance) and shieldCharges > 0 then
        -- a charge used (a real count, when the game shows one, puts it right on the next read)
        shieldCharges = shieldCharges - 1
    end
end

-- hits you take: Lightning Shield spends a charge on each melee or ranged hit (a physical hit:
-- wounded, blocked or absorbed). In combat the game sends no aura changes to addons, but it does
-- say when you are hit.
-- A ball fires at most once every few seconds, so a hit inside that spends nothing. The wait is
-- learned: after a fight the real count can be read, and the wait that explains the hits is kept.
local HITS = { WOUND = true, BLOCK = true, ABSORB = true }
local lastBall = -100
local fight = nil              -- { start = charges at the start, hits = { times } } since the last real count
local function Wait() return (db and db.shieldCd) or ns.TOTEM_DEFAULTS.shieldCd end

-- with this wait, how many charges would these hits have spent?
local function Spent(hits, wait)
    local n, last = 0, -100
    for _, t in ipairs(hits) do
        if t - last >= wait - 0.05 then n = n + 1; last = t end
    end
    return n
end
-- after a fight: the real count against the hits taken; keep the wait (1 to 6 s) that explains it,
-- nearest to the one in use
local function Learn(realCount)
    if not fight or not db or #fight.hits == 0 then fight = nil; return end
    local used = fight.start - realCount
    local fits = {}
    for w = 1, 6, 0.25 do
        local n = Spent(fight.hits, w)
        if math.min(n, fight.start) == used then fits[#fits + 1] = w end
    end
    if #fits > 0 and used < fight.start then
        -- an all-spent shield only says the wait was short enough: learn only from a part-used one
        local best, now = fits[1], Wait()
        for _, w in ipairs(fits) do if math.abs(w - now) < math.abs(best - now) then best = w end end
        db.shieldCd = best
    end
    fight = nil
end

local function OnHit(action, school)
    local a, sc = Plain(action), Plain(school)
    local now = GetTime()
    local spend = a and HITS[a] and (sc == nil or sc == 1) and shieldCharges > 0 and not FindCdm()
    if spend then
        fight = fight or { start = shieldCharges, hits = {} }
        fight.hits[#fight.hits + 1] = now
        if now - lastBall >= Wait() - 0.05 then
            lastBall = now
            shieldCharges = shieldCharges - 1
        else
            spend = false
        end
    end
    table.insert(auraLog, 1, ("%shit: %s, school %s%s"):format(InCombat() and "[combat] " or "",
        a == nil and (action == nil and "nil" or "hidden") or tostring(a), sc == nil and (school == nil and "nil" or "hidden") or tostring(sc),
        spend and " (a charge spent)" or ""))
    auraLog[7] = nil
    return spend
end

driver:SetScript("OnEvent", function(_, event, unit, a2, spellID, a4, a5)
    if event == "UNIT_COMBAT" then
        -- unit, action, flags, amount, school
        if unit == "player" and OnHit(a2, a5) then Update() end
        return
    end
    if event == "UNIT_AURA" then
        if unit == "player" then OnAura(a2); Update() end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        -- out of combat the real count can be read again: learn the wait from this fight
        local r = ReadShield()
        if r.count then Learn(r.count) elseif r.present == false then Learn(0) else fight = nil end
        Update(); return
    end
    if event == "PLAYER_REGEN_DISABLED" then fight = nil; Update(); return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- casting the shield: three charges, even while the game hides your auras
        if unit ~= "player" or Plain(spellID) == nil then return end
        local name
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
            name = ok and type(info) == "table" and Plain(info.name) or nil
        end
        if name and name == ShieldName() then
            shieldCharges = SHIELD_MAX
            fight = nil                       -- a fresh shield: start counting again
            castAt = GetTime()
            if GetTime() - addedAt < 1 and addedId then Adopt(addedId) end
            -- the new aura's id, while it can still be read
            ReadShield()
            Update()
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitDB().range
        root.totems = root.totems or {}
        DeepFill(root.totems, ns.TOTEM_DEFAULTS)
        db = root.totems
        Build()
        driver:Show()
    end
    cachePlate = nil
    Update()
end)

ns.Totems = {
    Settings = function() return db end,
    -- is this spell Lightning Shield, shown on the nameplate (so other displays leave it out)?
    ShowsShield = function(spellID)
        local _, class = UnitClass("player")
        return class == "SHAMAN" and db ~= nil and db.shield ~= false and db.hideCdm ~= false and RANK[spellID or 0] == true
    end,
    Refresh = Update,
    Offsets = Offsets,
    LeftReach = LeftReach,
    Order = ORDER,
    Boxes = function() return boxes end,
    Reset = function()
        local root = ns.InitDB().range
        root.totems = {}
        DeepFill(root.totems, ns.TOTEM_DEFAULTS)
        db = root.totems
        Update()
    end,
    -- shown on the target with sample totems while the settings are open, on any class
    Preview = function(on) previewing = on and true or false; Update() end,
    Debug = function(print)
        print(("totems: enabled=%s, %s"):format(tostring(db and db.enabled), state))
        local r = ReadShield()
        print(("  Lightning Shield: %s; on you: %s (%s); charges counted %d; client shows counts: %s; in combat: %s"):format(
            ShieldKnown() and "learned" or "not learned", r.present == nil and "hidden" or tostring(r.present),
            lastRead, shieldCharges, tostring(countsKnown), tostring(InCombat())))
        print(("  Cooldown Manager: %s%s"):format(cdmState, cdmHidden and " (its icon made invisible)" or ""))
        print(("  a ball fires at most every %.2f s (learned after each fight; only used without the Cooldown Manager)"):format(Wait()))
        print(("  shield aura id: %s; last aura changes and hits taken (newest first):"):format(tostring(shieldInstance or "unknown")))
        for _, l in ipairs(auraLog) do print("    " .. l) end
        for _, e in ipairs(ORDER) do
            local t = Read(e.slot)
            print(("  %s: %s"):format(e.name, t and "down" or "none"))
        end
    end,
}
