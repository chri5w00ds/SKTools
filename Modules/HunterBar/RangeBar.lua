--[[-------------------------------------------------------------------------
  SKTools - Hunter range detection, for WoW Forever, by Scotskoogen-Chris

  Works out which range zone your target is in - melee, the Hunter dead zone,
  shooting range, too far - for the crescent on its nameplate
  (Modules/Nameplate/Crescent.lua). The vertical bar this started as is gone.

  Based on RangeBar (Hunter) by AlwaysFourth
  (https://github.com/AlwaysFourth/RangeBarHunter), MIT license, see LICENSE.

  Forever port changes:
    * secret-value safe: any API answer the client hides from addons
      (issecretvalue) is treated as "no answer" instead of erroring
    * events that may not exist on this client are registered safely
    * frame / global / saved-variable names changed so it can sit next to
      the original without clashing

  The zones:

      melee range          (0 - 5 yd)
      dead zone            (5 - 8 yd)   <- can't shoot, can't melee
      ranged weapon range  (8 - 35/41 yd)
      out of range         (> max range)

  The zones are driven by the real range APIs (Auto Shot / Raptor
  Strike range checks), not by guessed numbers, so they stay correct for
  large mobs, Hawk Eye, etc. The distance bracket is an estimate, because the
  client never gives addons an exact distance.
---------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

local TAG = "|cffffd200SKTools|r |cffaaaaaa(Range)|r"
local db          -- this module's settings (SKToolsDB.range), set on load

----------------------------------------------------------------------
-- Secret values (Forever runs on the modern client, which can hide some
-- API answers from addons). A secret can't be compared or used, so every
-- answer goes through Plain() and a secret simply counts as "no answer".
----------------------------------------------------------------------

local issecret = _G.issecretvalue or function() return false end
local secretHits = 0

local function Plain(v)
    if v ~= nil and issecret(v) then
        secretHits = secretHits + 1
        return nil
    end
    return v
end

-- call an API safely and return its first result, secret-checked
local function Ask(fn, ...)
    if not fn then return nil end
    local ok, res = pcall(fn, ...)
    if not ok then return nil end
    return Plain(res)
end

-- On the Forever client CheckInteractDistance and IsItemInRange are reserved
-- for Blizzard's own UI whenever the unit isn't friendly, in or out of combat.
-- Calling them pops the "blocked from an action" warning, which pcall can't
-- stop, so they are only ever asked about friendly units.
-- 1.1.3: limiting them to friendly units still triggered the warning, so on
-- Forever they are not called at all.
local function Restricted(unit)
    return true
end

local function SafeRegister(frame, event)
    return pcall(frame.RegisterEvent, frame, event)
end

----------------------------------------------------------------------
-- Defaults / constants
----------------------------------------------------------------------

local DEFAULTS = {
    meleeRange  = 5,      -- top of melee band
    minRange    = 8,      -- ranged minimum range (top of the dead zone)
    maxOverride = 0,      -- 0 = auto detect (35 + Hawk Eye)
}
-- the old vertical bar's settings (the bar is gone: the nameplate crescent replaced it)
local OLD_BAR_KEYS = { "point", "relPoint", "x", "y", "width", "height", "locked", "alpha", "showText",
    "showTicks", "hideNoTarget", "legacyBar", "tickSize", "tickColor", "showBar", "showMinimap", "mmAngle" }

local function IsHunter()
    local _, class = UnitClass("player")
    return Plain(class) == "HUNTER"
end

-- The dead zone only matters for a Hunter holding a bow, gun or crossbow.
local RANGED_SUBCLASS = { [2] = true, [3] = true, [18] = true }   -- bow, gun, crossbow
local function HasRangedWeapon()
    local slot = _G.INVSLOT_RANGED or 18
    local id = Ask(GetInventoryItemID, "player", slot)
    if id then return true end                     -- Classic-style ranged slot
    -- modern layout: bows and guns sit in the main hand
    id = Ask(GetInventoryItemID, "player", _G.INVSLOT_MAINHAND or 16)
    if id and C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, _, _, classID, subID = pcall(C_Item.GetItemInfoInstant, id)
        if ok and Plain(classID) == 2 and RANGED_SUBCLASS[Plain(subID) or -1] then return true end
    end
    return false
end

-- The crescent is only for a bow: look at the ranged slot and the main hand
-- and ask the item itself (class 2 = weapon, subclass 2 = bow).
local function HasBow()
    if not (C_Item and C_Item.GetItemInfoInstant) then return false end
    for _, slot in ipairs({ _G.INVSLOT_RANGED or 18, _G.INVSLOT_MAINHAND or 16 }) do
        local id = Ask(GetInventoryItemID, "player", slot)
        if id then
            local ok, _, _, _, _, _, classID, subID = pcall(C_Item.GetItemInfoInstant, id)
            if ok and Plain(classID) == 2 and Plain(subID) == 2 then return true end
        end
    end
    return false
end

local function CopyDefault(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = x end
    return t
end

-- Spell IDs are resolved to (localized) names once at login.
-- NOTE: in Classic Era auto attack ("Attack", 6603) and wand "Shoot" (5019)
-- report "in range" at any distance. Forever reworked auto attack to pick
-- melee or Auto Shot by itself, so Attack is tried as a last-resort melee
-- check: if it still lies, the self-check below catches it and ignores it.
local MELEE_SPELLS = {
    2974, 1495, 19306,        -- Hunter:  Wing Clip, Mongoose Bite, Counterattack
                              -- (Raptor Strike is an "on next swing" attack, so
                              -- Forever reports it in range at any distance)
    1752, 2098,               -- Rogue:   Sinister Strike, Eviscerate
    772, 1715, 7386,          -- Warrior: Rend, Hamstring, Sunder Armor
    1082, 5211, 1822,         -- Druid:   Claw, Bash, Rake
    6603,                     -- Attack (Forever's smart auto attack), last resort
}
local SHOT_SPELLS  = { 75, 3044, 1978, 5116, 20736, 2643, 19434 } -- Auto Shot, Arcane, Serpent Sting, Concussive, Distracting, Multi, Aimed
local LONG_SPELLS  = { 1130 }                            -- Hunter's Mark (100 yd, no minimum)

-- Generic "distance <= range" probes: any spell you actually know contributes
-- a bracket. Only spells with no minimum range are listed, and next-melee
-- attacks (Heroic Strike etc.) are deliberately left out because they report
-- "in range" regardless of distance.
-- Optional third field: the target must be of that creature type for the check
-- to mean anything (otherwise the client refuses the spell for reasons that
-- have nothing to do with distance).
local RANGE_SPELLS = {
    { 19503, 15 },            -- Scatter Shot - Hunter, 15 yd with NO minimum,
                              -- so it can prove the dead zone outright
    { 1513,  10, "Beast" },   -- Scare Beast - 10 yd, no minimum, beasts only
    { 20271, 10 },  -- Judgement
    { 853,   10 },  -- Hammer of Justice
    { 2136,  20 },  -- Fire Blast
    { 8042,  20 },  -- Earth Shock
    { 355,   30 },  -- Taunt
    { 116,   30 },  -- Frostbolt
    { 686,   30 },  -- Shadow Bolt
    { 172,   30 },  -- Corruption
    { 585,   30 },  -- Smite
    { 589,   30 },  -- Shadow Word: Pain
    { 8092,  30 },  -- Mind Blast
    { 403,   30 },  -- Lightning Bolt
    { 5176,  30 },  -- Wrath
    { 5185,  40 },  -- Healing Touch (friendly)
    { 770,   30 },  -- Faerie Fire
    { 133,   35 },  -- Fireball
    { 348,   30 },  -- Immolate
    { 5782,  20 },  -- Fear
}

local HAWK_EYE = {
    ["Hawk Eye"] = true, ["Adlerauge"] = true, ["Oeil de l'aigle"] = true,
    ["\197\146il de l'aigle"] = true, ["Ojo de halc\195\179n"] = true,
    ["Occhio di falco"] = true, ["Olho de \195\129guia"] = true,
    ["\208\161\208\190\208\186\208\190\208\187\208\184\208\189\209\139\208\185 \208\179\208\187\208\176\208\183"] = true,
    ["\235\167\164\236\157\152 \235\136\136"] = true,
    ["\233\185\176\231\156\188"] = true, ["\233\183\185\231\156\188"] = true,
}

-- CheckInteractDistance indices -> yards (Classic values).
-- These test whether the *interaction* is legal, not just the distance, so
-- they are only meaningful on friendly players. Against a hostile NPC you can
-- never trade / duel / follow, so they return false at any distance and would
-- poison the estimate.
local INTERACT = {
    { index = 3,  range = 9.9  },  -- duel
    { index = 2,  range = 11.11 }, -- trade
    { index = 4,  range = 28   },  -- follow
}

-- Items with a known "use on a hostile target" range. IsItemInRange is the
-- only way to probe the 8 - 35 yd gap on a mob, which is exactly the range
-- the dead zone lives in. Unknown / uncached items just return nil and are
-- skipped, so listing them costs nothing.
local RANGE_ITEMS = {
    { 8149,   5 },  -- Voodoo Charm
    { 13289, 10 },  -- Egan's Blaster
    { 10645, 20 },  -- Gnomish Death Ray
    { 835,   30 },  -- Large Rope Net
    { 18904, 35 },  -- Zorbin's Ultra-Shrinker
}

local BASE_RANGED_RANGE = 35
local UNKNOWN_MAX = 999

-- the four static bands, bottom to top, and how they are drawn
local BAND_ZONES = { "MELEE", "DEAD", "SHOOT", "FAR" }
local LIT_ALPHA  = 0.90   -- band you are in
local LIT_BOOST  = 1.35   -- brighten the lit band's colour a little

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------

local maxRange   = BASE_RANGED_RANGE
local scaleTop   = 42     -- fixed: fits 35 yd, or 41 with 3/3 Hawk Eye
local meleeNames, shotNames, longNames = {}, {}, {}

-- Melee spells caught answering "in range" when they can't be (at the same
-- time as Auto Shot, which needs 8+ yd, or Hunter's Mark saying 100+ yd).
-- Forever can report some melee abilities as in range at any distance, so
-- each one has to prove itself; one caught lying is never asked again.
local meleeBad = {}      -- replaced by the saved table (db.meleeBad) on load
local meleeWarned = false
local rangeChecks = {}    -- { { name = <localized>, range = <yd> }, ... }

-- The client tells us exactly why a shot failed when we actually try one.
-- "Target too close" proves the dead zone, "Out of range" proves too far.
-- Those are the only certain signals available against a hostile NPC, so we
-- latch them for a moment and use them to break the tie.
local closeUntil, farUntil = 0, 0
-- Set when your target lands (or tries) a physical hit on you. With no
-- working melee spell (Wing Clip comes at level 12), that is the only sign
-- left that you're in melee range rather than just in the dead zone.
local meleeUntil = 0
local MELEE_LATCH = 2.5
local ERROR_LATCH = 2.0

-- A nameplate only exists for a unit inside nameplateMaxDistance yards, which
-- is the one passive distance probe that works on a hostile NPC. It is only
-- ever used as proof that you are CLOSE - a missing plate proves nothing,
-- because plates can be hidden by the user's settings.
local nameplateOK  = false   -- proven usable by seeing a plate on a melee-range target
local nameplateMax = 20
-- How far past max shot range the nameplate distance may sit and still be
-- taken as dead-zone evidence. Covers the common "plates at 40, shots to 35"
-- setup: the only thing it can get wrong is the 5 yd sliver just out of range.
local NAMEPLATE_SLACK = 10   -- Forever shows plates out to 45 yd; 35 + 10 covers it

-- Which side of shooting range you were last seen on. "Can't shoot, plate
-- visible" is either the dead zone or just past max range; coming in from
-- beyond max range it can only be the latter, and dropping out of shooting
-- range from inside it is far more often the dead zone (a mob running at you).
local cameFromFar = false
local cameFromNear = false   -- last seen in shooting range or closer
-- A missing plate only means "far" if THIS target had one before: critters
-- and some other units never get a nameplate at all.
local plateSeenOnTarget = false
local interactOK = true
-- nil = not proven yet, true/false = whether CheckInteractDistance actually
-- answers for hostile NPCs on this client. Proven at runtime by testing it
-- while the melee check says the target is a few yards away.
local interactNPC = nil


----------------------------------------------------------------------
-- API wrappers (Era exposes both the old globals and C_Spell)
----------------------------------------------------------------------

local C_Spell_IsSpellInRange = C_Spell and C_Spell.IsSpellInRange
local IsSpellInRange_ = _G.IsSpellInRange

local function GetSpellName(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and info and info.name then return info.name end
    end
    if _G.GetSpellInfo then
        local ok, name = pcall(_G.GetSpellInfo, id)
        if ok and name then return name end
    end
end

local function SpellKnown(id)
    if _G.IsSpellKnown then
        local ok, res = pcall(_G.IsSpellKnown, id)
        if ok then return res and true or false end
    end
    if _G.IsPlayerSpell then
        local ok, res = pcall(_G.IsPlayerSpell, id)
        if ok then return res and true or false end
    end
    return true   -- can't tell: keep it, the range check just returns nil
end

-- returns true / false / nil (nil = spell not usable as a range check)
local function SpellInRange(name, unit)
    if not name then return nil end
    local ok, res
    if C_Spell_IsSpellInRange then
        ok, res = pcall(C_Spell_IsSpellInRange, name, unit)
    elseif IsSpellInRange_ then
        ok, res = pcall(IsSpellInRange_, name, unit)
    else
        return nil
    end
    if not ok then return nil end
    res = Plain(res)
    if res == nil then return nil end
    return (res == true or res == 1)
end

local function FirstSpellResult(names, unit)
    for i = 1, #names do
        local r = SpellInRange(names[i], unit)
        if r ~= nil then return r end
    end
    return nil
end

local function RawInteract(index, unit)
    if not interactOK then return nil end
    if Restricted(unit) then return nil end
    local res = Ask(CheckInteractDistance, unit, index)
    if res == nil then return nil end
    return (res == true or res == 1)
end

-- On a player these are always meaningful. On an NPC they may or may not
-- answer, depending on how restricted the client build is, so we prove it at
-- runtime instead of guessing:
--   * ANY index returning true is proof the call answers for NPCs - nothing
--     but real distance can make it succeed.
--   * index 3 (9.9 yd) returning false while the melee check says we are
--     within ~5 yd is proof it does NOT answer, and it gets switched off.
-- Until it is proven either way the results are collected but not used.
local function InteractInRange(index, unit)
    local r = RawInteract(index, unit)
    if r == nil then return nil end
    if Ask(UnitIsPlayer, unit) then return r end
    if r == true then interactNPC = true end
    return interactNPC and r or nil
end

local function CalibrateInteract(unit)
    if Ask(UnitIsPlayer, unit) then return end
    local r = RawInteract(3, unit)
    if r == false then interactNPC = false end
end

local function RefreshNameplateRange()
    local v = GetCVar and tonumber(GetCVar("nameplateMaxDistance"))
    nameplateMax = (v and v > 0) and v or 20
end

-- true / false / nil (nil = the nameplate API is not available at all)
local function NameplateVisible(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok then return nil end
    if plate ~= nil and issecret(plate) then return nil end
    return plate and true or false
end

local function ItemInRange(id, unit)
    if Restricted(unit) then return nil end
    local ok, res
    if C_Item and C_Item.IsItemInRange then
        ok, res = pcall(C_Item.IsItemInRange, id, unit)
    elseif _G.IsItemInRange then
        ok, res = pcall(_G.IsItemInRange, id, unit)
    else
        return nil
    end
    if not ok then return nil end
    res = Plain(res)
    if res == nil then return nil end
    return (res == true or res == 1)
end

----------------------------------------------------------------------
-- Talents / max range
----------------------------------------------------------------------

local function ScanHawkEye()
    if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return 0 end
    local tabs = GetNumTalentTabs() or 0
    for tab = 1, tabs do
        local n = GetNumTalents(tab) or 0
        for i = 1, n do
            local name, _, _, _, rank = GetTalentInfo(tab, i)
            name, rank = Plain(name), Plain(rank)
            if name and HAWK_EYE[name] then
                return (tonumber(rank) or 0) * 2
            end
        end
    end
    return 0
end

local function HawkEyeBonus()
    local ok, bonus = pcall(ScanHawkEye)
    if ok and bonus then return bonus end
    return 0
end

local function RefreshRanges()
    if db.maxOverride and db.maxOverride > 0 then
        maxRange = db.maxOverride
    else
        maxRange = BASE_RANGED_RANGE + HawkEyeBonus()
    end
end

----------------------------------------------------------------------
-- Range estimation
----------------------------------------------------------------------

-- Pick a zone purely from an estimated distance bracket. Used whenever the
-- class has no shot ability to ask, so a band always lights up.
local function ZoneFromBracket(minD, maxD)
    local d
    if maxD >= UNKNOWN_MAX then
        d = math.max(minD, maxRange + 1)
    else
        d = (minD + maxD) * 0.5
    end
    if d <= db.meleeRange then return "MELEE"
    elseif d < db.minRange then return "DEAD"
    elseif d <= maxRange  then return "SHOOT"
    else return "FAR" end
end

-- Returns zone, minDist, maxDist
-- What Forever's smart auto attack is doing right now.
-- Returns meleeOn, shotOn (true / false / nil = can't tell).
local function AutoAttackState()
    local CS = C_Spell or {}
    local isCurrent = CS.IsCurrentSpell or _G.IsCurrentSpell
    local isRepeat  = CS.IsAutoRepeatSpell or _G.IsAutoRepeatSpell
    local meleeOn = Ask(isCurrent, 6603)
    if meleeOn == nil then meleeOn = Ask(isCurrent, GetSpellName(6603)) end
    local shotOn = Ask(isRepeat, 75)
    if shotOn == nil then shotOn = Ask(isRepeat, GetSpellName(75)) end
    return meleeOn, shotOn
end

local function MeleeResult(unit)
    for i = 1, #meleeNames do
        local name = meleeNames[i]
        if not meleeBad[name] then
            local r = SpellInRange(name, unit)
            if r ~= nil then return r, name end
        end
    end
    return nil
end

local function GetRangeInfo(unit)
    local melee, meleeName = MeleeResult(unit)
    local shootable = FirstSpellResult(shotNames, unit)
    local longCheck = FirstSpellResult(longNames, unit)

    -- a melee "yes" that contradicts a shot, a 100 yd check, or a missing
    -- nameplate (plates proven to work, so the target is beyond plate range)
    -- is a lie
    local plateNow = NameplateVisible(unit)
    local function Contradicted()
        return shootable == true or longCheck == false
            or (nameplateOK and plateSeenOnTarget and plateNow == false)
    end
    if melee == true and Contradicted() then
        meleeBad[meleeName] = true
        if not meleeWarned then
            meleeWarned = true
            DEFAULT_CHAT_FRAME:AddMessage(TAG .. ": " .. meleeName
                .. " reports melee range at any distance on this client - ignoring it.")
        end
        melee, meleeName = MeleeResult(unit)
        if melee == true and Contradicted() then
            meleeBad[meleeName] = true
            melee = nil
        end
    end

    -- collect pure "distance <= X" checks
    local results, n = {}, 0
    if melee ~= nil then
        n = n + 1; results[n] = { range = db.meleeRange, ok = melee }
    end
    if melee == true then CalibrateInteract(unit) end
    for i = 1, #INTERACT do
        local c = INTERACT[i]
        local r = InteractInRange(c.index, unit)
        if r ~= nil then n = n + 1; results[n] = { range = c.range, ok = r } end
    end
    for i = 1, #rangeChecks do
        local c = rangeChecks[i]
        if (not c.ctype) or Ask(UnitCreatureType, unit) == c.ctype then
            local r = SpellInRange(c.name, unit)
            if r ~= nil then n = n + 1; results[n] = { range = c.range, ok = r } end
        end
    end
    for i = 1, #RANGE_ITEMS do
        local r = ItemInRange(RANGE_ITEMS[i][1], unit)
        if r ~= nil then n = n + 1; results[n] = { range = RANGE_ITEMS[i][2], ok = r } end
    end

    -- Nameplate probe. Whenever the melee check proves the target is a few
    -- yards away, a visible plate proves plates are working for us; that is
    -- how the probe calibrates itself without ever asking the user. Only a
    -- VISIBLE plate is fed in - "no plate" can mean the plate is switched off,
    -- so it is never treated as evidence of distance.
    local plate = NameplateVisible(unit)
    if plate then
        plateSeenOnTarget = true
        nameplateOK = true
        n = n + 1; results[n] = { range = nameplateMax, ok = true }
    elseif plate == false and melee == true then
        -- close enough that a plate must exist, and there is none: the user
        -- has nameplates switched off, so the probe is unavailable
        nameplateOK = false
    end
    local far = longCheck
    if far ~= nil then n = n + 1; results[n] = { range = 100, ok = far } end

    -- upper bound: the smallest check that succeeded
    local maxD = UNKNOWN_MAX
    for i = 1, n do
        if results[i].ok and results[i].range < maxD then maxD = results[i].range end
    end
    -- lower bound: the largest failed check that does not contradict the upper bound
    local minD = 0
    for i = 1, n do
        local r = results[i]
        if (not r.ok) and r.range < maxD and r.range > minD then minD = r.range end
    end

    -- decide the zone from what we can actually do, not from the numbers
    local zone
    if shootable == true then
        zone = "SHOOT"
    elseif melee == true then
        zone = "MELEE"
    elseif shootable == false then
        -- Can't shoot and can't melee: either inside the minimum range or past
        -- the max range. Decide on positive evidence only - a check that
        -- SUCCEEDED at or below max range proves we are close (dead zone), a
        -- check that FAILED at or above max range proves we are far away.
        local now = GetTime()
        local autoMelee = (AutoAttackState() == true)
        if maxD <= maxRange then
            zone = "DEAD"
        elseif minD >= db.minRange then
            -- Something failed at or beyond the minimum shooting range, so we
            -- are past the dead zone entirely. Not being able to shoot from
            -- there can only mean too far.
            zone = "FAR"
        elseif autoMelee then
            zone = "DEAD"          -- auto attack swings melee only when you're
                                   -- too close to shoot, never when too far
        elseif now < closeUntil then
            zone = "DEAD"          -- the client told us "target too close",
                                   -- or the mob is landing melee swings on us
        elseif now < farUntil then
            zone = "FAR"           -- ...or "out of range"
        elseif plate == false and nameplateOK and plateSeenOnTarget then
            zone = "FAR"           -- this target had a plate, and it's gone
        elseif cameFromFar then
            zone = "FAR"           -- walking in from beyond max range: still out
        elseif cameFromNear and not plate then
            -- no plate to go by (critters never get one): you were in
            -- shooting range a moment ago and now can't shoot - most likely
            -- the dead zone
            zone = "DEAD"
        elseif plate and nameplateMax <= maxRange + NAMEPLATE_SLACK then
            -- The plate proves you are within nameplateMax. That is a little
            -- past max shot range, so strictly you are either in the dead zone
            -- or in the thin sliver just past your range - and the dead zone is
            -- far and away the likelier of the two.
            zone = "DEAD"
        else
            zone = ZoneFromBracket(minD, maxD)
        end
    elseif n > 0 then
        -- no shot ability to ask (not a Hunter): go by the distance bracket
        zone = ZoneFromBracket(minD, maxD)
    else
        zone = "UNKNOWN"
    end

    -- no melee spell to ask: the mob hitting you puts you in melee range
    if zone == "DEAD" and melee == nil and GetTime() < meleeUntil then
        zone = "MELEE"
    end

    if zone == "FAR" then cameFromFar = true; cameFromNear = false
    elseif zone == "SHOOT" or zone == "MELEE" then cameFromFar = false; cameFromNear = true end

    -- tighten the bracket with what the zone tells us
    if zone == "SHOOT" then
        if minD < db.minRange then minD = db.minRange end
        if maxD > maxRange then maxD = maxRange end
    elseif zone == "MELEE" then
        if maxD > db.meleeRange then maxD = db.meleeRange end
        minD = 0
    elseif zone == "DEAD" then
        -- without a working melee check, melee range can't be told apart
        if melee == nil then minD = 0
        elseif minD < db.meleeRange then minD = db.meleeRange end
        if maxD > db.minRange then maxD = db.minRange end
    elseif zone == "FAR" then
        if minD < maxRange then minD = maxRange end
    end
    if maxD < minD then maxD = minD end

    return zone, minD, maxD
end

-- the ranges: worked out again whenever talents or settings change
local function Layout() RefreshRanges() end

local function FormatRange(minD, maxD)
    if maxD >= UNKNOWN_MAX then return string.format("%d+ yd", minD) end
    if minD <= 0 then return string.format("0 - %.0f yd", maxD) end
    return string.format("%.0f - %.0f yd", minD, maxD)
end

----------------------------------------------------------------------
-- Update loop
----------------------------------------------------------------------

-- The bar is only meaningful on something you can actually shoot, so it shows
-- for attackable units only - enemy or neutral, player or NPC. Friendly
-- targets of any kind never show it.
local function ShouldShowFor(unit)
    return (Ask(UnitExists, unit) and Ask(UnitCanAttack, "player", unit)
            and not Ask(UnitIsDead, unit)) and true or false
end

-- /skt range watch: print a line whenever the zone or auto attack mode changes
local watching = false
local lastWatch
local function Watch(zone, minD, maxD)
    if not watching then return end
    local m, sh = AutoAttackState()
    local key = ("%s|%s|%s"):format(tostring(zone), tostring(m), tostring(sh))
    if key == lastWatch then return end
    lastWatch = key
    DEFAULT_CHAT_FRAME:AddMessage((TAG .. " |cffaaaaaa%.1f|r  zone = |cffffd100%s|r (%s)  melee swinging = %s  auto shot = %s  combat = %s")
        :format(GetTime() % 1000, tostring(zone), FormatRange(minD, maxD), tostring(m), tostring(sh),
                tostring(InCombatLockdown and InCombatLockdown())))
end

-- only for /skt range watch
local function Update()
    if not (db and watching) then return end
    if not ShouldShowFor("target") then return end
    Watch(GetRangeInfo("target"))
end

----------------------------------------------------------------------
-- Events / driver
----------------------------------------------------------------------

local driver = CreateFrame("Frame")
local acc = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    if not watching then return end
    acc = acc + elapsed
    if acc < 0.05 then return end
    acc = 0
    Update()
end)

local function ResolveSpellNames()
    wipe(meleeNames); wipe(shotNames); wipe(longNames); wipe(rangeChecks)
    -- only spells you actually know: on Forever an unknown spell can still
    -- give a range answer, and it means nothing
    local function Fill(list, ids)
        for i = 1, #ids do
            local name = SpellKnown(ids[i]) and GetSpellName(ids[i]) or nil
            if name then list[#list + 1] = name end
        end
    end
    Fill(meleeNames, MELEE_SPELLS)
    -- Attack isn't always listed as a "known" spell, but every character has it
    local attack = GetSpellName(6603)
    if attack then
        local have = false
        for i = 1, #meleeNames do if meleeNames[i] == attack then have = true end end
        if not have then meleeNames[#meleeNames + 1] = attack end
    end
    Fill(shotNames, SHOT_SPELLS)
    Fill(longNames, LONG_SPELLS)
    -- Auto Shot can be missing from the known-spell lists on some clients;
    -- it is the main ranged check, so keep it regardless
    if #shotNames == 0 then
        local n = GetSpellName(75); if n then shotNames[1] = n end
    end
    for i = 1, #RANGE_SPELLS do
        local id = RANGE_SPELLS[i][1]
        local name = SpellKnown(id) and GetSpellName(id) or nil
        if name then
            rangeChecks[#rangeChecks + 1] = {
                name = name, range = RANGE_SPELLS[i][2], ctype = RANGE_SPELLS[i][3],
            }
        end
    end
end

-- UI_ERROR_MESSAGE passes (errorType, message) on modern clients and just
-- (message) on older ones, so accept whichever argument is the string.
local TOO_CLOSE = { [SPELL_FAILED_TOO_CLOSE or "Target too close"] = true }
local TOO_FAR   = {
    [SPELL_FAILED_OUT_OF_RANGE or "Out of range"] = true,
    [ERR_SPELL_OUT_OF_RANGE    or "Out of range"] = true,
    [ERR_OUT_OF_RANGE          or "Out of range"] = true,
}

-- Some of these may not exist (or may be blocked for addons) on the Forever
-- client; registering an unknown event errors, so each one is tried safely.
for _, ev in ipairs({
    "ADDON_LOADED", "UI_ERROR_MESSAGE", "CVAR_UPDATE", "PLAYER_LOGIN",
    "PLAYER_TARGET_CHANGED", "SPELLS_CHANGED", "CHARACTER_POINTS_CHANGED",
    "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED",
}) do SafeRegister(driver, ev) end
-- (The combat log is reserved for Blizzard's UI on Forever - registering for it
-- triggers the "blocked from an action" warning - so it is not used.)
SafeRegister(driver, "UNIT_COMBAT")
local HIT_EVENTS = {
    WOUND = true, MISS = true, DODGE = true, PARRY = true, BLOCK = true,
    DEFLECT = true, ABSORB = true, RESIST = false,
}
driver:SetScript("OnEvent", function(_, event, arg1, arg2, _, _, school)
    if event == "UNIT_COMBAT" then
        -- UNIT_COMBAT(unit, action, flagText, amount, schoolMask)
        if Plain(arg1) ~= "player" then return end
        local action, mask = Plain(arg2), Plain(school)
        if not (action and HIT_EVENTS[action]) then return end
        if mask and mask ~= 1 then return end            -- physical only
        -- and it has to be your target that's attacking you
        if not Ask(UnitIsUnit, "targettarget", "player") then return end
        local now = GetTime()
        meleeUntil = now + MELEE_LATCH
        closeUntil = now + ERROR_LATCH
        farUntil   = 0
        return
    elseif event == "CVAR_UPDATE" then
        RefreshNameplateRange()
    elseif event == "UI_ERROR_MESSAGE" then
        arg1, arg2 = Plain(arg1), Plain(arg2)
        local msg = (type(arg1) == "string") and arg1 or arg2
        if type(msg) == "string" then
            if TOO_CLOSE[msg] then
                closeUntil = GetTime() + ERROR_LATCH
                farUntil   = 0
            elseif TOO_FAR[msg] then
                farUntil   = GetTime() + ERROR_LATCH
                closeUntil = 0
            end
        end
    elseif event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        db = ns.InitDB().range
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = CopyDefault(v) end
        end
        for _, k in ipairs(OLD_BAR_KEYS) do db[k] = nil end
        db.meleeBad = db.meleeBad or {}   -- learned once, remembered after
        meleeBad = db.meleeBad
        Layout()
    elseif event == "PLAYER_LOGIN" then
        ResolveSpellNames()
        RefreshNameplateRange()
        -- sanity check: distance to yourself is 0, so this must succeed.
        -- if it doesn't, the API is restricted on this client and we ignore it.
        interactOK = false   -- reserved for Blizzard's UI on Forever, never called
        Layout()
    elseif event == "SPELLS_CHANGED" then
        ResolveSpellNames()
    elseif event == "CHARACTER_POINTS_CHANGED" or event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_CONFIG_UPDATED" then
        Layout()
    elseif event == "PLAYER_TARGET_CHANGED" then
        cameFromFar = false
        cameFromNear = false
        plateSeenOnTarget = false
        meleeUntil = 0
    end
end)

----------------------------------------------------------------------
-- Shared helpers
----------------------------------------------------------------------

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(TAG .. ": " .. msg)
end

----------------------------------------------------------------------
-- For the settings tab (Options.lua)
----------------------------------------------------------------------

local function ResetSettings()
    for k, v in pairs(DEFAULTS) do db[k] = CopyDefault(v) end
    Layout()
end

ns.RangeBar = {
    Settings = function() return db end,
    DEFAULTS = DEFAULTS,
    Layout = Layout,
    Reset = ResetSettings,
    Print = Print,
    -- for the nameplate crescent: the zone ("MELEE", "DEAD", "SHOOT", "FAR",
    -- "UNKNOWN") plus the distance bracket, who it applies to, and whether
    -- the unit is something you could shoot at all
    Zone = function(unit) return GetRangeInfo(unit) end,
    Eligible = function() return IsHunter() and HasRangedWeapon() end,
    HasBow = function() return IsHunter() and HasBow() end,
    ShouldShow = function(unit) return ShouldShowFor(unit) end,
    NameplateMax = function() return nameplateMax end,
    MaxRange = function() return maxRange end,
    SetNameplateMax = function(v)
        if InCombatLockdown and InCombatLockdown() then
            Print("can't change the nameplate distance in combat.")
            return
        end
        pcall(SetCVar, "nameplateMaxDistance", v)
        RefreshNameplateRange()
    end,
}

----------------------------------------------------------------------
-- /skt range ... (the range checks' own commands)
----------------------------------------------------------------------

function ns.RangeBar.Command(msg)
    if not db then
        DEFAULT_CHAT_FRAME:AddMessage(TAG .. ": still loading, try again in a moment.")
        return
    end
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    local num = tonumber(rest)

    if cmd == "crescent" and rest:lower() == "debug" then
        if ns.Crescent then ns.Crescent.Debug(Print) end
    elseif cmd == "combo" and rest:lower() == "debug" then
        if ns.Combo then ns.Combo.Debug(Print) end
    elseif cmd == "watch" then
        watching = not watching
        lastWatch = nil
        Print("watch " .. (watching and "|cff55ff55ON|r - a line prints whenever the zone or auto attack changes. |cffffff00/skt range watch|r again to stop."
                                     or "off."))
    elseif cmd == "debug" then
        local unit = "target"
        if not Ask(UnitExists, unit) then
            Print("no target - target something first.")
        else
            local zone, minD, maxD = GetRangeInfo(unit)
            Print(("zone = %s , bracket = %s"):format(tostring(zone), FormatRange(minD, maxD)))
            local mp = {}
            for i = 1, #meleeNames do
                mp[#mp + 1] = ("%s=%s%s"):format(meleeNames[i],
                    tostring(SpellInRange(meleeNames[i], unit)),
                    meleeBad[meleeNames[i]] and "(ignored)" or "")
            end
            Print("melee spells: " .. (#mp > 0 and table.concat(mp, " ") or "none known"))
            Print(("shot spells: %s"):format(table.concat(shotNames, ", ")))
            local attackName = GetSpellName(6603)
            local meleeOn, shotOn = AutoAttackState()
            Print(("auto attack: in range = %s%s , melee swinging = %s , auto shot on = %s , in combat = %s")
                :format(tostring(SpellInRange(attackName, unit)),
                        (attackName and meleeBad[attackName]) and "(ignored)" or "",
                        tostring(meleeOn), tostring(shotOn),
                        tostring(InCombatLockdown and InCombatLockdown())))
            Print(("melee = %s , shot = %s , long = %s")
                :format(tostring((MeleeResult(unit))),
                        tostring(FirstSpellResult(shotNames, unit)),
                        tostring(FirstSpellResult(longNames, unit))))
            local parts = {}
            for i = 1, #rangeChecks do
                parts[#parts + 1] = ("%dyd=%s"):format(rangeChecks[i].range,
                    tostring(SpellInRange(rangeChecks[i].name, unit)))
            end
            Print("spells: " .. (#parts > 0 and table.concat(parts, " ") or "none known"))
            Print(("nameplate: visible = %s , usable = %s , range = %s yd%s")
                :format(tostring(NameplateVisible(unit)), tostring(nameplateOK),
                        tostring(nameplateMax),
                        nameplateMax > maxRange + NAMEPLATE_SLACK
                            and " |cffff5555(too far to prove the dead zone - use /skt range plates)|r" or ""))
            Print(("client: secret answers so far = %d"):format(secretHits))
        end
    elseif cmd == "plates" and InCombatLockdown and InCombatLockdown() then
        Print("can't change the nameplate distance in combat - try again after the fight.")
    elseif cmd == "plates" then
        local want = num and math.min(41, math.max(10, num)) or 20
        local ok = pcall(SetCVar, "nameplateMaxDistance", want)
        pcall(SetCVar, "nameplateShowEnemies", 1)
        RefreshNameplateRange()
        Print(ok and ("nameplate distance set to %d yd - used to spot the dead zone."):format(want)
            or "could not change the nameplate distance on this client.")
    elseif cmd == "max" and num then
        db.maxOverride = num; Layout(); Print("max ranged range = " .. maxRange .. (num > 0 and " (manual)" or " (auto)"))
    elseif cmd == "min" and num then
        db.minRange = num; Layout(); Print("minimum ranged range = " .. db.minRange)
    elseif cmd == "reset" then
        for k, v in pairs(DEFAULTS) do db[k] = CopyDefault(v) end
        wipe(db.meleeBad); meleeWarned = false   -- wiped in place: the table is shared by every profile
        Layout(); Print("range settings reset.")
    else
        Print("range commands:")
        Print("  |cffffff00/skt range debug|r - what the range checks report on your target")
        Print("  |cffffff00/skt range watch|r - print zone and auto attack changes to chat")
        Print("  |cffffff00/skt range crescent debug|r , |cffffff00combo debug|r - the crescent / combo points on your target")
        Print("  |cffffff00/skt range plates|r N - nameplate distance used to spot the dead zone (now " .. nameplateMax .. ")")
        Print("  |cffffff00/skt range max|r N - max ranged range (0 = auto, now " .. maxRange .. ") , |cffffff00min|r N - dead zone top (now " .. db.minRange .. ")")
        Print("  |cffffff00/skt range reset|r")
    end

    ns.RefreshSettings()   -- keep an open settings window in step with chat commands
end

-- timed by /skt cpu
ns.Profile("Hunter range bar", driver)
