--[[-------------------------------------------------------------------------
  SKTools - Feral cat: Claw and Shred "ready" icons on the target's nameplate

  Two small icons sit by the target's level box while a Druid is in
  Cat Form: Shred directly above it and Claw directly below it, as wide as
  the box and the same distance from it on both sides (or, with
  "Beside the level badge" off, side by side under the health bar). Each one
  is lit only when that skill could be used right now:

      * enough energy       asked of the game itself (spell usability), so
                            talents, procs and anything else that makes the
                            skill cheaper are already counted
      * in melee range      the skill's own range check on the target
      * not on cooldown     the global cooldown does not count against it

  Lit means full colour, a soft glow and a gentle pulse; not ready means a
  grey, dimmed icon, so the two states differ by more than colour. "Hide
  when not ready" in the settings removes the dimmed ones.

  Secret-value safe: an answer the client hides is "no answer", and a skill
  with no answer is shown as not ready rather than guessed.
---------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

local issecret = _G.issecretvalue or function() return false end
local function Plain(v)
    if v ~= nil and issecret(v) then return nil end
    return v
end

ns.FERAL_DEFAULTS = {
    behind      = true,      -- Shred, Backstab and the like: not while your target faces you
    enabled     = true,
    size        = 19,        -- pixels per icon (when "Match level box width" is off)
    match       = false,     -- icons as wide as the level box
    x           = 12,        -- offset from the bottom of the health bar
    y           = 1,
    gap         = 2,
    claw        = true,
    shred       = true,
    raptor      = true,
    mongoose    = true,
    maul        = true,
    primalbite  = true,
    swipe       = true,
    glow        = true,
    pulse       = true,
    hideNotReady = true,     -- an icon only shows while its skill can be used right now
    combatOnly  = true,      -- nothing outside combat
    moveCC      = true,      -- push Blizzard's shared crowd-control icon out beside the stack
    badge       = true,      -- beside the level badge: Shred above the combo points, Claw below
    -- the finisher icon, to the left of the health bar: Ferocious Bite at full energy, or Shifting Power
    -- when casting it would get you to a full-energy Bite
    finisher    = true,
    finBite     = true,
    finShift    = true,
    finisherPoints = 5,
    fx          = 0,         -- fine position of the finisher icon
    fy          = 0,
    fgap        = 4,         -- distance from the left end of the health bar
    shiftEnergy = 0,         -- energy Shifting Power gives; 0 = read it from the spell's description
    -- the column and big icon to the right of the level box (on SKTools plates): fine position
    rx = 0, ry = 0, rfx = 0, rfy = 0,
    -- rsize: the right side's icon size; unset = the same as the left side's
    -- slots = { [set] = { l1 = "Claw", ... } }: which skill sits where; empty = the set's defaults
}

-- the two icons, per class: [1] sits at the bottom, [2] at the top. "ready" means the game says
-- the skill is usable (power, any proc it needs), the target is in its range and it is off cooldown.
-- A class can have several stacks, one per form; a stack with no "forms" fits any form.
local STACKS = {
    DRUID = {
        {   -- Cat Form: Claw below, Shred above, the Bite / Shifting Power finisher over them
            key = "cat",
            forms = { [1] = true },
            skills = {
                { key = "claw",  id = 1082, name = "Claw",  fallbackIcon = "Interface\\Icons\\Ability_Druid_Rake" },
                { key = "shred", id = 5221, name = "Shred", fallbackIcon = "Interface\\Icons\\Spell_Shadow_VampiricAura" },
            },
            finisher = true,
        },
        {   -- Bear Form (and Dire Bear): Maul below, Swipe above; Primal Bite is the big icon laid
            -- over both, like Bite in Cat Form, shown when it is usable, in range and off cooldown
            key = "bear",
            forms = { [5] = true, [8] = true },
            skills = {
                { key = "maul",  id = 6807, name = "Maul",  fallbackIcon = "Interface\\Icons\\Ability_Druid_Maul" },
                { key = "swipe", id = 779,  name = "Swipe", fallbackIcon = "Interface\\Icons\\INV_Misc_MonsterClaw_03" },
            },
            finisher = "ready",
            finisherSkill = { key = "primalbite", id = nil, iconSpell = 407995, name = "Primal Bite", fallbackIcon = "Interface\\Icons\\Ability_Racial_Cannibalize", cooldown = true },
        },
    },
    -- Shaman: one set per role (from the talents), every slot chosen in the editor; the totem
    -- timers sit where the combo points would be
    SHAMAN = {
        { key = "enhancement", role = "enhancement", skills = {}, finisher = false, totems = true },
        { key = "elemental",   role = "elemental",   skills = {}, finisher = false, totems = true },
        { key = "restoration", role = "restoration", skills = {}, finisher = false, totems = true },
    },
    HUNTER = {
        {
            key = "hunter",
            skills = {
                { key = "raptor",   id = 2973, name = "Raptor Strike", fallbackIcon = "Interface\\Icons\\Ability_MeleeDamage", cooldown = true },
                { key = "mongoose", id = 1495, name = "Mongoose Bite", fallbackIcon = "Interface\\Icons\\Ability_Hunter_SwiftStrike" },
            },
            finisher = false,
            crescent = true,     -- the range crescent sits where the combo points would be
        },
    },
}
ns.FERAL_STACKS = STACKS
local MAX_ICONS = 3
local function PlayerClass()
    local ok, _, class = pcall(UnitClass, "player")
    return ok and class or nil
end
local function CurrentForm()
    if not _G.GetShapeshiftFormID then return nil end
    local ok, id = pcall(_G.GetShapeshiftFormID)
    return ok and Plain(id) or nil
end
-- the stack for this class in its current form, or nil
local function Stack()
    local list = STACKS[PlayerClass() or ""]
    if not list then return nil end
    -- sets by role (Shaman): the one for the role your talents point to, else the first
    if list[1] and list[1].role then
        local role = ns.ClassSets and ns.ClassSets.Role and ns.ClassSets.Role()
        for _, st in ipairs(list) do if st.role == role then return st end end
        return list[1]
    end
    local form = CurrentForm()
    for _, st in ipairs(list) do
        if not st.forms or (form ~= nil and st.forms[form]) then return st end
    end
    return nil
end
-- every stack of this class (for the settings: one checkbox per skill)
local function AllStacks() return STACKS[PlayerClass() or ""] or {} end
local SKILLS = STACKS.DRUID[1].skills          -- replaced at login by the player's class stack
local BITE  = { key = "bite",  id = 22568, name = "Ferocious Bite", fallbackIcon = "Interface\\Icons\\Ability_Druid_FerociousBite" }
local SHIFT = { key = "shift", id = nil,   name = "Shifting Power",  fallbackIcon = "Interface\\Icons\\Spell_Nature_WispSplode" }
local STACK_GAP, OWN_GAP = 2, 4          -- Shred to Claw, and the icons to the combo points
local ownX, ownBite = -40, 38          -- column and Bite size on our own plates
local ownRBite = 38                       -- the right side's big icon size

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

local db, holder, icons = nil, nil, {}
-- the mirrored set to the right of the level box (on our own plates only)
local rholder, ricons = nil, {}
local rfinHolder, rfin
-- the centre big icon: square, over the middle of the health bar, overhanging it equally above and below
local cfinHolder, cfin
local RightX

----------------------------------------------------------------------
-- Slots: which skill sits where. Each set (Cat Form, Bear Form, Hunter) has three stacked icons and
-- a big one on each side: l1 (bottom), l2 (middle), l3 (top), lb (big); r1, r2, r3, rb on the right.
-- A slot holds a spell name, NONE (empty) or FINISHER (the set's own big-icon rule: Bite / Shifting
-- Power in Cat Form, Primal Bite in Bear Form). Saved per set in db.slots[set][slot]; nothing saved
-- means the set's default, which is how the icons were before slots existed.
----------------------------------------------------------------------

local SLOTS = { "l1", "l2", "l3", "lb", "r1", "r2", "r3", "rb", "cb" }
local NONE, FINISHER = "none", "finisher"

local function StackByKey(key)
    for _, list in pairs(STACKS) do
        for _, st in ipairs(list) do if st.key == key then return st end end
    end
end

-- every slot starts empty: you choose the skills in the Nameplates editor
local function SlotDefault(st, slot) return NONE end
-- what the slots held before they started empty (2.17.0): kept for settings saved before then
local function OldSlotDefault(st, slot)
    if slot == "l1" and st.skills[1] then return st.skills[1].name end
    if slot == "l3" and st.skills[2] then return st.skills[2].name end
    if slot == "lb" and st.finisher then return FINISHER end
    return NONE
end

local function SlotValue(st, slot)
    if not st then return NONE end
    local saved = db and db.slots and db.slots[st.key]
    local v = saved and saved[slot]
    if v == nil then v = SlotDefault(st, slot) end
    if v == "Rebirth" then return NONE end        -- moved to the buff widgets
    return v
end

local function SetSlot(setKey, slot, value)
    if not (db and setKey and slot) then return end
    db.slots = db.slots or {}
    db.slots[setKey] = db.slots[setKey] or {}
    local st = StackByKey(setKey)
    -- the default is not stored: a later change of defaults still reaches this slot
    if st and value == SlotDefault(st, slot) then value = nil end
    db.slots[setKey][slot] = value
end

-- the skill table for a spell name: one of the sets' own (they carry the right icons and cooldown
-- handling), else a plain one made for it, hidden while on cooldown like the rest
local generic = {}
local function SkillByName(name)
    if type(name) ~= "string" or name == NONE or name == FINISHER then return nil end
    for _, list in pairs(STACKS) do
        for _, st in ipairs(list) do
            for _, sk in ipairs(st.skills) do if sk.name == name then return sk end end
            if st.finisherSkill and st.finisherSkill.name == name then return st.finisherSkill end
        end
    end
    local g = generic[name]
    if not g then
        g = { key = "spell:" .. name, name = name, cooldown = true, fallbackIcon = "Interface\\Icons\\INV_Misc_QuestionMark" }
        generic[name] = g
    end
    return g
end

local finHolder, fin            -- the finisher icon, to the left of the health bar

-- A gate for a big icon: shows it only once a hidden number reaches a threshold. A status bar the
-- size of the icon runs from threshold - 1 to threshold; the icon sits in a frame clipped to the
-- bar's fill, so it is all there when the fill is full and none of it otherwise. The game fills the
-- bar from the hidden value; the addon never reads it.
local function Gate(icon, holder, value, at)
    if value == nil then
        -- open: the icon back on its holder, as always
        if icon.gateClip and icon:GetParent() == icon.gateClip then
            icon:SetParent(holder); icon:SetAllPoints(holder)
        end
        icon.gated = false
        return
    end
    if not icon.gateBar then
        local bar = CreateFrame("StatusBar", nil, holder)
        bar:SetAllPoints(holder)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetStatusBarColor(0, 0, 0, 0)
        local clip = CreateFrame("Frame", nil, holder)
        clip:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        clip:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        pcall(clip.SetClipsChildren, clip, true)
        icon.gateBar, icon.gateClip = bar, clip
    end
    icon.gateClip:SetFrameLevel(holder:GetFrameLevel() + 1)
    if icon:GetParent() ~= icon.gateClip then icon:SetParent(icon.gateClip); icon:SetAllPoints(holder) end
    icon.gateBar:SetMinMaxValues((at or 1) - 1, at or 1)
    if not pcall(icon.gateBar.SetValue, icon.gateBar, value) then icon.gateBar:SetValue(at or 1) end
    icon.gated = true
end
local finInfo = {}              -- what the last finisher check saw (for the debug print)
-- Blizzard's crowd-control icon (plate.UnitFrame.AurasFrame.CrowdControlListFrame) sits right
-- under the level badge, where Claw goes. Same handling as the hunter crescent: moved beside the
-- icons while they show, re-applied every tick because Blizzard re-anchors it, and handed back
-- to Blizzard's own position when they hide.
local CC_GAP = 4
local ccSaved = setmetatable({}, { __mode = "k" })
local ccHeld, ccKey
local ccSpot                -- where it goes: x, y from the holder centre (the badge)

local function ReleaseCC()
    local cc = ccHeld
    ccHeld, ccKey = nil, nil
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
    if not cc or not ccSpot then return end
    pcall(function()
        local key = ccSpot[1] .. ":" .. ccSpot[2]
        local _, rel = cc:GetPoint(1)
        if rel == holder then
            if ccHeld == cc and ccKey == key then return end        -- already placed
        else
            local pts = {}                                           -- Blizzard (re)anchored it: keep those
            for i = 1, cc:GetNumPoints() do
                local a, b, c, x, y = cc:GetPoint(i)
                pts[i] = { a, b, c, x, y }
            end
            ccSaved[cc] = pts
        end
        ccHeld, ccKey = cc, key
        cc:ClearAllPoints()
        cc:SetPoint("TOP", holder, "CENTER", ccSpot[1], ccSpot[2])
    end)
end

local previewing, state = false, "starting"
local cachePlate, cacheAnchor, cacheHow, cacheAge = nil, nil, nil, 0

----------------------------------------------------------------------
-- What the game says about a skill
----------------------------------------------------------------------

-- a skill's spell id; Shifting Power's is found by name
-- the spell's id: the rank you actually know (looked up by name, cached for a while), else the
-- fixed rank-1 id. Cooldowns and usability belong to the known rank, not to rank 1.
local idCache = {}
local function Id(s)
    local c = idCache[s]
    if c and GetTime() - c.at < 5 then return c.id end
    local id
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, s.name)
        local got = ok and type(info) == "table" and Plain(info.spellID) or nil
        if type(got) == "number" then id = got end
    end
    id = id or s.id
    -- an unknown spell (not learned yet, or a name the client has not got) is asked about again next time
    if id then idCache[s] = { id = id, at = GetTime() } else idCache[s] = nil end
    return id
end

local function Known(s)
    local id = Id(s)
    if not id then return false end
    if _G.IsSpellKnown then
        local ok, r = pcall(_G.IsSpellKnown, id)
        if ok and r then return true end
    end
    if _G.IsPlayerSpell then
        local ok, r = pcall(_G.IsPlayerSpell, id)
        if ok and r then return true end
    end
    if C_Spell and C_Spell.GetSpellInfo and s.id then
        local ok, info = pcall(C_Spell.GetSpellInfo, s.name)
        if ok and type(info) == "table" and info.spellID then return true end
    end
    return false
end

local function SpellName(s)
    local id = Id(s)
    if id and C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" and info.name then return info.name end
    end
    return s.name
end

local function SpellIcon(s)
    local id = Id(s) or s.iconSpell          -- iconSpell: an id used only to look the icon up before the spell is learned
    if id and C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" and Plain(info.iconID) then return info.iconID end
    end
    if id and _G.GetSpellTexture then
        local ok, t = pcall(_G.GetSpellTexture, id)
        if ok and Plain(t) then return t end
    end
    return s.fallbackIcon
end

-- the spells in your spell book that can be cast (no passives), one per name, sorted by name:
-- what the editor offers for a slot. The first tab (General: Auto Attack, professions...) is skipped.
local function SpellList()
    local out, seen = {}, {}
    local function add(name, icon, id)
        name = Plain(name)
        if type(name) ~= "string" or name == "" or seen[name] or name == "Rebirth" then return end
        seen[name] = true
        out[#out + 1] = { name = name, icon = Plain(icon), id = Plain(id) }
    end
    local SB = _G.C_SpellBook
    if SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo then
        local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
        local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
        local ok, lines = pcall(SB.GetNumSpellBookSkillLines)
        for line = 2, (ok and Plain(lines) or 0) do
            local okl, info = pcall(SB.GetSpellBookSkillLineInfo, line)
            if okl and type(info) == "table" and not info.offSpecID then
                local first, n = info.itemIndexOffset or 0, info.numSpellBookItems or 0
                for i = first + 1, first + n do
                    local oki, it = pcall(SB.GetSpellBookItemInfo, i, bank)
                    if oki and type(it) == "table" and not it.isPassive and not it.isOffSpec
                        and (spellType == nil or it.itemType == spellType) then
                        add(it.name, it.iconID, it.spellID or it.actionID)
                    end
                end
            end
        end
    elseif _G.GetNumSpellTabs and _G.GetSpellTabInfo and _G.GetSpellBookItemName then
        local book = _G.BOOKTYPE_SPELL or "spell"
        for tab = 2, GetNumSpellTabs() do
            local ok, _, _, offset, n = pcall(GetSpellTabInfo, tab)
            if ok then
                for i = (offset or 0) + 1, (offset or 0) + (n or 0) do
                    local passive = _G.IsPassiveSpell and select(2, pcall(IsPassiveSpell, i, book))
                    if not passive then
                        local okn, name = pcall(GetSpellBookItemName, i, book)
                        local icon = _G.GetSpellBookItemTexture and select(2, pcall(GetSpellBookItemTexture, i, book))
                        local id = _G.GetSpellBookItemInfo and select(3, pcall(GetSpellBookItemInfo, i, book))
                        if okn then add(name, icon, id) end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- usable (enough energy and everything else) -> true / false / nil (no answer)
local function Usable(s)
    local usable, noPower
    local id = Id(s)
    if not id then return nil, false end
    if C_Spell and C_Spell.IsSpellUsable then
        local ok, a, b = pcall(C_Spell.IsSpellUsable, id)
        if ok then usable, noPower = Plain(a), Plain(b) end
    elseif _G.IsUsableSpell then
        local ok, a, b = pcall(_G.IsUsableSpell, id)
        if ok then usable, noPower = Plain(a), Plain(b) end
    end
    if usable == nil then return nil, false end
    return (usable == true or usable == 1), (noPower == true or noPower == 1)
end

local function InRange(s)
    local r
    if C_Spell and C_Spell.IsSpellInRange then
        local ok, v = pcall(C_Spell.IsSpellInRange, SpellName(s), "target")
        if ok then r = Plain(v) end
    elseif _G.IsSpellInRange then
        local ok, v = pcall(_G.IsSpellInRange, SpellName(s), "target")
        if ok then r = Plain(v) end
    end
    if r == nil then return nil end
    return (r == true or r == 1)
end

-- the global cooldown (1.5 s and under) is not a cooldown of the skill
local function OnCooldown(s)
    local dur, gcd
    local id = Id(s)
    if not id then return false end
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, id)
        if ok and type(info) == "table" then dur, gcd = Plain(info.duration), Plain(info.isOnGCD) end
    elseif _G.GetSpellCooldown then
        local ok, _, d = pcall(_G.GetSpellCooldown, id)
        if ok then dur = Plain(d) end
    end
    if dur == nil and id and C_Spell and C_Spell.GetSpellCooldown then
        -- the game answered but kept the number to itself (in combat): "don't know"
        local ok, info = pcall(C_Spell.GetSpellCooldown, id)
        if ok and type(info) == "table" and info.duration ~= nil then return nil end
    end
    if type(dur) ~= "number" or dur <= 0 then return false end
    if gcd == true or dur <= 1.5 then return false end
    return true
end

-- While the game hides cooldowns, a skill with a real cooldown (Raptor Strike) is still shown
-- or hidden correctly: the game evaluates its own cooldown timer against a step curve (1 when
-- nothing is left, 0 while any time is left) and the result goes straight into the icon's alpha.
local cdCurve
local function CooldownCurve()
    if cdCurve ~= nil then return cdCurve or nil end
    cdCurve = false
    if C_CurveUtil and C_CurveUtil.CreateCurve then
        local ok, c = pcall(C_CurveUtil.CreateCurve)
        if ok and c then
            local E = _G.Enum
            if E and E.LuaCurveType and E.LuaCurveType.Step and c.SetType then pcall(c.SetType, c, E.LuaCurveType.Step) end
            pcall(c.AddPoint, c, 0, 1)
            pcall(c.AddPoint, c, 0.05, 0)
            pcall(c.AddPoint, c, 3600, 0)
            cdCurve = c
        end
    end
    return cdCurve or nil
end
-- true when the icon's alpha has been handed to the game's timer
local function AlphaFromCooldown(f)
    local s = f.skill
    if not (s and s.cooldown) then return false end
    local id = Id(s)
    if not (id and C_Spell and C_Spell.GetSpellCooldownDuration) then return false end
    local ok, dur = pcall(C_Spell.GetSpellCooldownDuration, id)
    if not ok or dur == nil or not dur.EvaluateRemainingDuration then return false end
    local curve = CooldownCurve()
    if not curve then return false end
    -- the pulse animates the frame's alpha and would fight the value set here
    if f.pulse:IsPlaying() then f.pulse:Stop() end
    -- 1. the whole frame's alpha
    local ok = pcall(function() f:SetAlpha(dur:EvaluateRemainingDuration(curve)) end)
    if ok then f.fadePath = "frame alpha"; return true end
    -- 2. each piece of the icon on its own (some regions take hidden values where frames do not)
    local pieces = { f.tex, f.back, f.glow, f.rim[1], f.rim[2], f.rim[3], f.rim[4] }
    ok = pcall(function()
        local a = dur:EvaluateRemainingDuration(curve)
        for _, t in ipairs(pieces) do t:SetAlpha(a) end
    end)
    if ok then f.fadePath = "texture alpha"; return true end
    -- 3. a cooldown swipe laid over the icon: the game draws a dark cover while any time is left
    if not f.cd then
        local okc, cd = pcall(CreateFrame, "Cooldown", nil, f, "CooldownFrameTemplate")
        if okc and cd then
            cd:SetAllPoints(f)
            pcall(cd.SetDrawEdge, cd, false)
            pcall(cd.SetDrawBling, cd, false)
            pcall(cd.SetSwipeTexture, cd, "Interface\\Buttons\\WHITE8X8")
            pcall(cd.SetSwipeColor, cd, 0, 0, 0, 0.9)
            pcall(cd.SetHideCountdownNumbers, cd, false)
            f.cd = cd
        else
            f.cd = false
        end
    end
    if f.cd then
        ok = pcall(f.cd.SetCooldownFromDurationObject, f.cd, dur)
        if ok then f.fadePath = "cooldown swipe"; return true end
    end
    f.fadePath = "none worked"
    return false
end

-- Rebirth used to be a slot here; it now lives in the buff widgets (Modules/Widgets/Buffs.lua).
local MOVED = { Rebirth = true }

-- Skills that only work from behind the target. Addons can't see where you stand, so two signs
-- stand in for it: a mob faces whoever it is attacking (targeting you: you are in front of it),
-- and the game's "You must be behind your target" when one of these fails (then: not behind, for a
-- moment, or until the target changes).
-- Known ones are listed; any other skill the game turns down with that message is learned and
-- treated the same from then on (db.behindLearned), so a server's own rules are picked up too.
local BEHIND = { Shred = true, Ravage = true, Pounce = true, Backstab = true, Ambush = true, Garrote = true }
local notBehindUntil = 0
local lastTry = { name = nil, t = 0 }        -- the skill you last tried, to pin a "behind" error on
local function NeedsBehind(name)
    return name and (BEHIND[name] or (db and db.behindLearned and db.behindLearned[name])) or false
end
local function FacingYou()
    if not (UnitExists and UnitExists("target")) then return false end
    local ok, v = pcall(UnitIsUnit, "targettarget", "player")
    v = ok and Plain(v) or nil
    return v == true
end
local function BehindBlocked(s)
    if not (db and db.behind ~= false and NeedsBehind(s.name)) then return nil end
    if GetTime() < notBehindUntil then return "not behind the target (the game said so)" end
    if FacingYou() then return "your target is facing you" end
    return nil
end

-- ready?, and why not
local function Ready(s)
    if MOVED[s.name] then return false, "moved to the buff widgets" end
    local extraWhy
    local usable, noPower = Usable(s)
    if usable == nil then return false, "no answer from the game" end
    if not usable then return false, noPower and "not enough energy" or "not usable" end
    if InRange(s) == false then return false, "out of range" end
    local behind = BehindBlocked(s)
    if behind then return false, behind end
    local cd = OnCooldown(s)
    if cd then return false, "on cooldown" end
    local tail = extraWhy and (" - " .. extraWhy) or ""
    if cd == nil then return true, "ready (cooldown hidden by the game)" .. tail end
    return true, "ready" .. tail
end

----------------------------------------------------------------------
-- The finisher icon: Ferocious Bite, or Shifting Power on the way to one
----------------------------------------------------------------------

local function Num(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    v = Plain(v)
    if type(v) == "number" then return v end
end

local function EnergyType()
    return (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3
end

local function ComboPoints()
    local v
    if _G.GetComboPoints then v = Num(_G.GetComboPoints, "player", "target") end
    if v == nil then v = Num(UnitPower, "player", (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4) end
    return v
end

-- energy per second right now, as the game reports it (haste is included in that)
local function EnergyRegen()
    local v
    if _G.GetPowerRegenForPowerType then
        local ok, a = pcall(_G.GetPowerRegenForPowerType, EnergyType())
        a = ok and Plain(a) or nil
        if type(a) == "number" and a > 0 then v = a end
    end
    if not v and _G.GetPowerRegen then
        local ok, a = pcall(_G.GetPowerRegen)
        a = ok and Plain(a) or nil
        if type(a) == "number" and a > 0 then v = a end
    end
    return v or 10
end

-- length of the global cooldown after casting s, in seconds: the spell's own base GCD
-- shortened by spell haste, never below 0.75 s (or below the base itself, if that is shorter)
local function GcdSeconds(s)
    local base = 1.0
    local id = Id(s)
    if id and _G.GetSpellBaseCooldown then
        local ok, _, g = pcall(_G.GetSpellBaseCooldown, id)
        g = ok and Plain(g) or nil
        if type(g) == "number" and g > 0 then base = g / 1000 end
    end
    local haste = 0
    if _G.UnitSpellHaste then
        local h = Num(_G.UnitSpellHaste, "player")
        if h then haste = h end
    end
    return math.max(math.min(base, 0.75), base / (1 + haste / 100)), base, haste
end

-- energy Shifting Power gives: your own number if you set one, else read from the spell's text
local function ShiftGain()
    if (db.shiftEnergy or 0) > 0 then return db.shiftEnergy, "set by you" end
    local id = Id(SHIFT)
    local text
    if id then
        if C_Spell and C_Spell.GetSpellDescription then
            local ok, t = pcall(C_Spell.GetSpellDescription, id)
            if ok then text = Plain(t) end
        elseif _G.GetSpellDescription then
            local ok, t = pcall(_G.GetSpellDescription, id)
            if ok then text = Plain(t) end
        end
    end
    if type(text) == "string" then
        local n = text:match("(%d+)%s+[Ee]nergy") or text:match("[Ee]nergy[^%d]-(%d+)")
        if n then return tonumber(n), "read from the spell" end
    end
    return nil, "not found in the spell text"
end

-- "bite", "shift" or nil, and why
local function Finisher()
    wipe(finInfo)
    local combo, energy, maxE = ComboPoints(), Num(UnitPower, "player", EnergyType()), Num(UnitPowerMax, "player", EnergyType())
    finInfo.combo, finInfo.energy, finInfo.maxEnergy = combo, energy, maxE
    local need = db.finisherPoints or 5
    -- energy hidden (in combat) but combo points and the maximum readable: Bite is shown through a
    -- gate the game opens at full energy (see Gate), without the addon reading the number
    if combo and maxE and energy == nil then
        if combo < need then return nil, combo .. " of " .. need .. " combo points" end
        if db.finBite == false then return nil, "energy hidden, and Bite is switched off" end
        if not Known(BITE) then return nil, "Ferocious Bite is not learned" end
        local ok, raw = pcall(UnitPower, "player", EnergyType())
        if not ok or raw == nil then return nil, "energy unknown" end
        finInfo.gate, finInfo.gateAt = raw, maxE
        return "bite", combo .. " combo points; shown at full energy (energy hidden: the game decides)"
    end
    if not (combo and energy and maxE) then return nil, "combo points or energy are hidden by the game" end
    if combo < need then return nil, combo .. " of " .. need .. " combo points" end
    if energy >= maxE then
        if db.finBite == false then return nil, "full energy, but Bite is switched off" end
        if not Known(BITE) then return nil, "Ferocious Bite is not learned" end
        return "bite", "full energy and " .. combo .. " combo points"
    end
    if db.finShift == false then return nil, "not full energy" end
    if not Known(SHIFT) then return nil, "Shifting Power is not learned" end
    local usable, noPower = Usable(SHIFT)
    finInfo.usable = usable
    if usable == nil then return nil, "no answer about Shifting Power" end
    if not usable then return nil, noPower and "not enough mana for Shifting Power" or "Shifting Power is not usable" end
    if OnCooldown(SHIFT) then return nil, "Shifting Power is on cooldown" end
    local gain, src = ShiftGain()
    finInfo.gain, finInfo.gainSource = gain, src
    if not gain then return nil, "energy from Shifting Power unknown: set it in the Bite panel" end
    local gcd, base, haste = GcdSeconds(SHIFT)
    local regen = EnergyRegen()
    local after = energy + gain + regen * gcd
    finInfo.gcd, finInfo.baseGcd, finInfo.haste, finInfo.regen, finInfo.after = gcd, base, haste, regen, after
    if after >= maxE then return "shift", ("%d energy + %d from Shifting Power + %.1f regen over a %.2fs GCD = %.0f"):format(energy, gain, regen * gcd, gcd, after) end
    return nil, ("would reach only %.0f of %d"):format(after, maxE)
end

-- in combat? A hidden answer counts as yes, so the icons are never lost to it
local function InCombat()
    if not _G.UnitAffectingCombat then return true end
    local ok, v = pcall(_G.UnitAffectingCombat, "player")
    if not ok then return true end
    v = Plain(v)
    if v == nil then return true end
    return v == true or v == 1
end

-- Stack() already answers for the form: nil when this form has no icons
local function InForm() return Stack() ~= nil end

local function HasStack() return #AllStacks() > 0 end

----------------------------------------------------------------------
-- The two icons
----------------------------------------------------------------------

local function MakeIcon(s, parent)
    local f = CreateFrame("Frame", nil, parent or holder)
    f:EnableMouse(false)
    f.skill = s

    f.glow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.glow:SetBlendMode("ADD")
    f.glow:SetPoint("CENTER")

    f.back = f:CreateTexture(nil, "BACKGROUND")
    f.back:SetColorTexture(0, 0, 0, 0.85)
    f.back:SetAllPoints()

    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", 1, -1)
    f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- bright rim, only while ready: a shape cue as well as a colour one
    f.rim = {}
    for i = 1, 4 do f.rim[i] = f:CreateTexture(nil, "OVERLAY") end
    f.rim[1]:SetPoint("TOPLEFT");     f.rim[1]:SetPoint("TOPRIGHT");     f.rim[1]:SetHeight(2)
    f.rim[2]:SetPoint("BOTTOMLEFT");  f.rim[2]:SetPoint("BOTTOMRIGHT");  f.rim[2]:SetHeight(2)
    f.rim[3]:SetPoint("TOPLEFT");     f.rim[3]:SetPoint("BOTTOMLEFT");   f.rim[3]:SetWidth(2)
    f.rim[4]:SetPoint("TOPRIGHT");    f.rim[4]:SetPoint("BOTTOMRIGHT");  f.rim[4]:SetWidth(2)
    for i = 1, 4 do f.rim[i]:SetColorTexture(1, 0.88, 0.35, 1) end

    f.pulse = f:CreateAnimationGroup()
    f.pulse:SetLooping("BOUNCE")
    local a = f.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.72); a:SetDuration(0.45)
    return f
end

local function Build()
    holder = CreateFrame("Frame", "SKToolsFeralFrame", UIParent)
    holder:SetSize(1, 1)
    holder:EnableMouse(false)
    holder:Hide()
    local st = Stack() or AllStacks()[1]
    if st then SKILLS = st.skills end
    for i = 1, MAX_ICONS do icons[i] = MakeIcon(SKILLS[i] or SKILLS[1]); icons[i].skill = SKILLS[i] end
    finHolder = CreateFrame("Frame", "SKToolsFeralFinisher", UIParent)
    finHolder:SetSize(26, 26)
    finHolder:EnableMouse(false)
    finHolder:Hide()
    fin = MakeIcon(BITE, finHolder)
    fin:SetAllPoints(finHolder)
    fin.wanted = false
    -- the mirrored set right of the level box
    rholder = CreateFrame("Frame", "SKToolsFeralRight", UIParent)
    rholder:SetSize(1, 1)
    rholder:EnableMouse(false)
    rholder:Hide()
    for i = 1, MAX_ICONS do ricons[i] = MakeIcon(nil, rholder) end
    rfinHolder = CreateFrame("Frame", "SKToolsFeralRightBig", UIParent)
    rfinHolder:SetSize(26, 26)
    rfinHolder:EnableMouse(false)
    rfinHolder:Hide()
    rfin = MakeIcon(nil, rfinHolder)
    rfin:SetAllPoints(rfinHolder)
    rfin.wanted = false
    cfinHolder = CreateFrame("Frame", "SKToolsFeralCentreBig", UIParent)
    cfinHolder:SetSize(30, 30)
    cfinHolder:EnableMouse(false)
    cfinHolder:Hide()
    cfin = MakeIcon(nil, cfinHolder)
    cfin:SetAllPoints(cfinHolder)
    cfin.wanted = false
end

local function Layout()
    local size, gap = db.size, db.gap
    ccSpot = nil
    if cacheHow == "sktools" then
        -- left of the combo points / crescent: Shred over Claw almost touching; Bite is a bigger
        -- icon laid over the middle of the pair, leaving 30% of each showing at the ends
        local reach = (ns.Combo and ns.Combo.LeftReach and ns.Combo.LeftReach()) or 18
        -- a Hunter has the range crescent there instead of the combo points, and it is wider
        if PlayerClass() == "HUNTER" and ns.Crescent and ns.Crescent.Settings then
            local z = ns.Crescent.Settings()
            reach = 32 * ((z and z.size or 46) / 46) + 2
        end
        -- a Shaman has the totem timers there
        if PlayerClass() == "SHAMAN" and ns.Totems then reach = ns.Totems.LeftReach() + 2 end
        ownBite = math.floor((2 * size + STACK_GAP) * 0.7 + 0.5)
        -- past the level box, which stands left of the bar
        ownX = -(reach + OWN_GAP + ownBite / 2) - ((ns.Plates and ns.Plates.LeftEdge and ns.Plates.LeftEdge()) or 0)
        -- the column: icon 1 at the bottom, the last at the top, centred on the bar's middle.
        -- Only the skills you know take a slot, so one not learned yet (Primal Bite before its
        -- level) leaves no hole; a known skill keeps its slot whether or not it is ready
        -- three slots: all three filled stand at the bottom, middle and top; two stand where the
        -- two-icon stack always had them; one sits on the bar's centre line
        local function Column(list, h)
            local column = {}
            for _, f in ipairs(list) do
                if f.skill and f.known ~= false and db[f.skill.key] ~= false then column[#column + 1] = f end
            end
            local n = #column
            h:SetSize(1, 1)
            for _, f in ipairs(list) do
                f:ClearAllPoints()
                f:SetSize(size, size)
                f.glow:SetSize(size * 1.9, size * 1.9)
            end
            for j, f in ipairs(column) do
                f:SetPoint("CENTER", h, "CENTER", 0, (j - (n + 1) / 2) * (size + STACK_GAP))
            end
        end
        Column(icons, holder)
        -- the right side: its own size (until changed, the same as the left's)
        local rsize = db.rsize or size
        ownRBite = math.floor((2 * rsize + STACK_GAP) * 0.7 + 0.5)
        size = rsize
        Column(ricons, rholder)
        state = "left of the bar"
        return
    end
    if db.badge ~= false then
        -- Shred above the level box, Claw below it, as wide as the box and the same distance
        -- from it on both sides; each keeps its own slot
        local bw, bh = 26, 16
        if ns.Combo and ns.Combo.BoxSize then bw, bh = ns.Combo.BoxSize(cacheAnchor, cacheHow) end
        if db.match ~= false then size = math.max(12, math.min(bw, 64)) end
        local off = bh / 2 + gap + size / 2
        holder:SetSize(1, 1)
        -- the shared CC icon goes straight under Claw, in the same column
        ccSpot = { 0, -(off + size / 2 + CC_GAP) }
        -- the first filled slot under the box, the next above it, any third one above that
        local j = 0
        for _, f in ipairs(icons) do
            f:ClearAllPoints()
            f:SetSize(size, size)
            if f.skill then
                j = j + 1
                local y = (j == 1) and -off or (off + (j - 2) * (size + gap))
                f:SetPoint("CENTER", holder, "CENTER", 0, y)
            end
            f.glow:SetSize(size * 1.9, size * 1.9)
        end
        state = "box " .. math.floor(bw + 0.5) .. "x" .. math.floor(bh + 0.5)
        return
    end
    local shownList = {}
    for _, f in ipairs(icons) do
        if f.wanted then shownList[#shownList + 1] = f end
    end
    local total = #shownList * size + math.max(#shownList - 1, 0) * gap
    holder:SetSize(math.max(total, 1), size)
    for i, f in ipairs(shownList) do
        f:ClearAllPoints()
        f:SetSize(size, size)
        f:SetPoint("LEFT", holder, "LEFT", (i - 1) * (size + gap), 0)
        f.glow:SetSize(size * 1.9, size * 1.9)
    end
end

local function Paint(f, ready)
    f.tex:SetTexture(SpellIcon(f.skill))
    if f.tex.SetDesaturated then f.tex:SetDesaturated(not ready) end
    f.tex:SetVertexColor(ready and 1 or 0.55, ready and 1 or 0.55, ready and 1 or 0.55, 1)
    f:SetAlpha(ready and 1 or 0.45)
    for i = 1, 4 do f.rim[i]:SetShown(ready) end
    f.glow:SetShown(ready and db.glow ~= false)
    f.glow:SetVertexColor(1, 0.85, 0.3, 0.55)
    if ready and db.pulse ~= false then
        if not f.pulse:IsPlaying() then f.pulse:Play() end
    else
        f.pulse:Stop()
        f:SetAlpha(ready and 1 or 0.45)
    end
end

----------------------------------------------------------------------
-- Placement and the update tick
----------------------------------------------------------------------

local function HideRight()
    if rholder and rholder:IsShown() then
        for _, f in ipairs(ricons) do f.pulse:Stop() end
        rholder:Hide()
    end
    if rfin then rfin.wanted = false end
    if rfinHolder and rfinHolder:IsShown() then
        rfin.pulse:Stop()
        rfinHolder:Hide()
    end
    if cfin then cfin.wanted = false end
    if cfinHolder and cfinHolder:IsShown() then
        cfin.pulse:Stop()
        cfinHolder:Hide()
    end
end

local function HideStack()
    ReleaseCC()
    if holder and holder:IsShown() then
        for _, f in ipairs(icons) do f.pulse:Stop() end
        holder:Hide()
    end
end

local function HideFinisher()
    if fin then fin.wanted = false; fin.kind = nil end
    if finHolder and finHolder:IsShown() then
        fin.pulse:Stop()
        finHolder:Hide()
    end
end

local function Hide(why)
    state = why
    HideStack()
    HideFinisher()
    HideRight()
end

local function RefreshAnchor(plate)
    local ours = ns.Plates and ns.Plates.Frame and ns.Plates.Frame(plate)
    if ours then cacheAnchor, cacheHow, cachePlate, cacheAge = ours, "sktools", plate, GetTime(); return end
    if cacheHow == "sktools" then cachePlate = nil end        -- we stopped drawing this plate
    if db.badge == false and db.match == false then return end
    if not (ns.Combo and ns.Combo.Anchor) then return end
    if plate ~= cachePlate or GetTime() - cacheAge > 1 then
        cacheAnchor, cacheHow = ns.Combo.Anchor(plate, "target")
        cachePlate, cacheAge = plate, GetTime()
    end
end

-- centre of the right-hand column, from our bar's right end: the level box moved to the left, so
-- the column stands right by the bar, the same distance the left column keeps from the combo points
RightX = function()
    return OWN_GAP + ownRBite / 2
end

-- icon size for the finisher: as wide as the level box, like Claw and Shred
local function IconSize()
    if cacheHow == "sktools" then return ownBite end
    if db.badge ~= false and db.match ~= false and ns.Combo and ns.Combo.BoxSize then
        local bw = ns.Combo.BoxSize(cacheAnchor, cacheHow)
        return math.max(12, math.min(bw, 64))
    end
    return db.size
end

local function Update()
    if not holder or not db then return end
    if not db.enabled then return Hide("turned off in settings") end

    if not previewing then
        if not HasStack() then return Hide("no icons for this class") end
        if not InForm() then return Hide("not in the right form") end
        if db.combatOnly ~= false and not InCombat() then return Hide("out of combat") end
        if not (UnitCanAttack and UnitCanAttack("player", "target")) or (UnitIsDead and UnitIsDead("target")) then
            return Hide("no attackable target")
        end
    end

    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
        and select(2, pcall(C_NamePlate.GetNamePlateForUnit, "target"))
    if type(plate) ~= "table" or (plate.IsForbidden and plate:IsForbidden()) then
        return Hide("the target has no nameplate")
    end

    RefreshAnchor(plate)
    local sktools = cacheHow == "sktools"

    -- the slots of the set for this form (Stack() picks it; with no form match, the first set)
    local st = Stack() or AllStacks()[1] or (previewing and STACKS.DRUID[1]) or nil
    SKILLS = st and st.skills or SKILLS
    for i = 1, MAX_ICONS do
        icons[i].skill = SkillByName(SlotValue(st, "l" .. i))
        ricons[i].skill = sktools and SkillByName(SlotValue(st, "r" .. i)) or nil
    end

    -- one small icon: is it learned, ready, wanted?
    local function Eval(f)
        local s = f.skill
        local ready, why
        if not s then
            f.wanted = false; f:Hide(); f.pulse:Stop()
            f.ready, f.why, f.known = false, "empty slot", false
            return false
        elseif previewing then
            ready, why = true, "preview"
        elseif Known(s) then
            ready, why = Ready(s)
        else
            ready, why = false, "skill not learned"
        end
        f.ready, f.why = ready, why
        f.known = previewing or Known(s)
        f.wanted = db[s.key] ~= false and f.known and (ready or not db.hideNotReady)
        f:SetShown(f.wanted)
        if f.wanted then
            Paint(f, ready)
            -- cooldown kept secret: the game itself fades the icon out while any is left
            if ready and not previewing and why:find("hidden") and AlphaFromCooldown(f) then
                f.pulse:Stop()
                f.why = "ready unless on cooldown (the game decides)"
            end
        end
        return f.wanted
    end
    local anyWanted, anyRight = false, false
    for _, f in ipairs(icons) do if Eval(f) then anyWanted = true end end
    for _, f in ipairs(ricons) do if Eval(f) then anyRight = true end end

    -- a big icon that holds a plain skill: shown while that skill is ready
    local function BigSkill(sk)
        if db[sk.key] == false then return nil, sk.name .. " is switched off" end
        if previewing then return "skill", "preview" end
        if not Known(sk) then return nil, sk.name .. " is not learned" end
        local r, why = Ready(sk)
        return r and "skill" or nil, sk.name .. ": " .. why
    end

    -- a big icon's slot: a skill, or the set's own rule (Ferocious Bite / Shifting Power; Primal Bite)
    local function BigKind(v)
        local bigSkill
        if v == NONE then return nil, "no skill chosen for the big icon" end
        if v ~= FINISHER then
            bigSkill = SkillByName(v)
            local k, w = BigSkill(bigSkill)
            return k, w, bigSkill
        end
        if not (st and st.finisher) then return nil, "this class has no finisher icon" end
        if st.finisher == "ready" then
            -- a plain "ready" skill as the big icon (Bear Form: Primal Bite)
            bigSkill = st.finisherSkill
            local k, w = BigSkill(bigSkill)
            return k, w, bigSkill
        end
        if previewing then return "bite", "preview" end
        local k, w = Finisher()
        return k, w
    end

    -- the left big icon
    local kind, fwhy, bigSkill
    if db.finisher == false then
        kind, fwhy = nil, "big icon switched off"
    else
        kind, fwhy, bigSkill = BigKind(SlotValue(st, "lb"))
    end
    local gateL, gateAtL = finInfo.gate, finInfo.gateAt      -- set by Finisher() when energy is hidden
    fin.kind, fin.why = kind, fwhy
    fin.wanted = kind ~= nil
    Gate(fin, finHolder, (kind == "bite") and gateL or nil, gateAtL)
    if fin.wanted then
        fin.skill = (kind == "shift") and SHIFT or (kind == "skill") and bigSkill or BITE
        Paint(fin, true)
        -- a cooldown hidden in combat: the game's timer fades the icon then
        if kind == "skill" and not previewing and fin.why:find("hidden") then AlphaFromCooldown(fin) end
    end

    -- the right big icon (our own plates only)
    local rb = sktools and SlotValue(st, "rb") or NONE
    rfin.wanted, rfin.why = false, sktools and "no skill chosen" or "only on SKTools plates"
    if rb ~= NONE and rb ~= FINISHER then
        local sk = SkillByName(rb)
        local rk, rwhy = BigSkill(sk)
        rfin.why = rwhy
        if rk then
            rfin.wanted, rfin.skill = true, sk
            Paint(rfin, true)
            if not previewing and rwhy:find("hidden") then AlphaFromCooldown(rfin) end
        end
    end

    -- the centre big icon (our own plates only): a skill, or the set's own rule like the left one
    local cb = sktools and SlotValue(st, "cb") or NONE
    cfin.wanted, cfin.why, cfin.kind = false, sktools and "no skill chosen" or "only on SKTools plates", nil
    Gate(cfin, cfinHolder, nil)
    if cb ~= NONE then
        local ck, cwhy, csk = BigKind(cb)
        cfin.why, cfin.kind = cwhy, ck
        Gate(cfin, cfinHolder, (ck == "bite") and finInfo.gate or nil, finInfo.gateAt)
        if ck then
            cfin.wanted = true
            cfin.skill = (ck == "shift") and SHIFT or (ck == "skill") and csk or BITE
            Paint(cfin, true)
            if ck == "skill" and not previewing and cwhy:find("hidden") then AlphaFromCooldown(cfin) end
        end
    end

    if not anyWanted and not fin.wanted and not anyRight and not rfin.wanted and not cfin.wanted then return Hide("nothing to show") end
    local hb = ns.Combo and ns.Combo.HealthBar and ns.Combo.HealthBar(plate)
    local level, strata = (plate:GetFrameLevel() or 1) + 20, plate:GetFrameStrata() or "MEDIUM"
    if anyWanted or anyRight or fin.wanted then Layout() end

    if anyWanted then
        holder:SetParent(plate)
        holder:SetFrameStrata(strata)
        holder:SetFrameLevel(level)
        holder:ClearAllPoints()
        if sktools then
            holder:SetParent(cacheAnchor)
            holder:SetPoint("CENTER", cacheAnchor, "LEFT", ownX + db.x, db.y)
        elseif db.badge ~= false and ns.Combo and ns.Combo.Anchor then
            -- the level badge, where the combo points sit
            if cacheHow == "health bar" then
                holder:SetPoint("CENTER", cacheAnchor, "RIGHT", 16 + db.x, db.y)
            else
                holder:SetPoint("CENTER", cacheAnchor, "CENTER", db.x, db.y)
            end
        elseif type(hb) == "table" then
            holder:SetPoint("TOP", hb, "BOTTOM", db.x, db.y)
        else
            holder:SetPoint("TOP", plate, "CENTER", db.x, -14 + db.y)
        end
        -- the range crescent, when this class has one, is the one that moves the CC icon
        if db.moveCC ~= false and ccSpot and not (st and st.crescent) then PushCC(plate) else ReleaseCC() end
        holder:Show()
    else
        HideStack()
    end

    -- right of the level box: the stack's mirror image
    local rx = RightX()
    if anyRight then
        rholder:SetParent(cacheAnchor)
        rholder:SetFrameStrata(strata)
        rholder:SetFrameLevel(level)
        rholder:ClearAllPoints()
        rholder:SetPoint("CENTER", cacheAnchor, "RIGHT", rx + (db.rx or 0), db.ry or 0)
        rholder:Show()
    elseif rholder:IsShown() then
        for _, f in ipairs(ricons) do f.pulse:Stop() end
        rholder:Hide()
    end
    if rfin.wanted then
        rfinHolder:SetParent(cacheAnchor)
        rfinHolder:SetFrameStrata(strata)
        rfinHolder:SetFrameLevel(level + 5)
        rfinHolder:SetSize(ownRBite, ownRBite)
        rfin.glow:SetSize(ownRBite * 1.9, ownRBite * 1.9)
        rfinHolder:ClearAllPoints()
        rfinHolder:SetPoint("CENTER", cacheAnchor, "RIGHT", rx + (db.rfx or 0), db.rfy or 0)
        rfin:Show()
        rfinHolder:Show()
    elseif rfinHolder:IsShown() then
        rfin.pulse:Stop()
        rfinHolder:Hide()
    end
    if cfin.wanted then
        -- square, 1.5 times the bar's height, centred on the bar: a quarter of the bar's height
        -- shows above it and a quarter below
        local bh = (cacheAnchor.GetHeight and cacheAnchor:GetHeight()) or 0
        if not (type(bh) == "number" and bh > 0) then bh = ((ns.Plates and ns.Plates.Settings() or {}).height) or 20 end
        local cs = math.floor(bh * 1.5 + 0.5)
        cfinHolder:SetParent(cacheAnchor)
        cfinHolder:SetFrameStrata(strata)
        cfinHolder:SetFrameLevel(level + 6)
        cfinHolder:SetSize(cs, cs)
        cfin.glow:SetSize(cs * 1.9, cs * 1.9)
        cfinHolder:ClearAllPoints()
        cfinHolder:SetPoint("CENTER", cacheAnchor, "CENTER", db.cx or 0, db.cy or 0)
        cfin:Show()
        cfinHolder:Show()
    elseif cfinHolder:IsShown() then
        cfin.pulse:Stop()
        cfinHolder:Hide()
    end

    if fin.wanted then
        local size = IconSize()
        finHolder:SetSize(size, size)
        fin.glow:SetSize(size * 1.9, size * 1.9)
        finHolder:SetParent(plate)
        finHolder:SetFrameStrata(strata)
        finHolder:SetFrameLevel(level)
        finHolder:ClearAllPoints()
        if sktools then
            finHolder:SetParent(cacheAnchor)
            finHolder:SetFrameLevel(level + 5)
            finHolder:SetSize(ownBite, ownBite)
            fin.glow:SetSize(ownBite * 1.9, ownBite * 1.9)
            finHolder:SetPoint("CENTER", cacheAnchor, "LEFT", ownX + (db.fx or 0), (db.fy or 0))
        elseif type(hb) == "table" then
            finHolder:SetPoint("RIGHT", hb, "LEFT", -(db.fgap or 4) + (db.fx or 0), db.fy or 0)
        else
            finHolder:SetPoint("RIGHT", plate, "CENTER", -70 + (db.fx or 0), db.fy or 0)
        end
        fin:Show()
        finHolder:Show()
    else
        HideFinisher()
    end
    state = "showing" .. (anyWanted and " stack" or "") .. (fin.wanted and (" + " .. kind) or "")
        .. ((anyRight or rfin.wanted) and " + right side" or "") .. (cfin.wanted and " + centre" or "")
end

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
pcall(driver.RegisterEvent, driver, "PLAYER_TARGET_CHANGED")
pcall(driver.RegisterEvent, driver, "UPDATE_SHAPESHIFT_FORM")
pcall(driver.RegisterEvent, driver, "SPELLS_CHANGED")
pcall(driver.RegisterEvent, driver, "PLAYER_REGEN_DISABLED")
pcall(driver.RegisterEvent, driver, "PLAYER_REGEN_ENABLED")
pcall(driver.RegisterEvent, driver, "UI_ERROR_MESSAGE")
pcall(driver.RegisterEvent, driver, "UNIT_TARGET")
pcall(driver.RegisterUnitEvent or driver.RegisterEvent, driver, "UNIT_SPELLCAST_SENT", "player")
pcall(driver.RegisterUnitEvent or driver.RegisterEvent, driver, "UNIT_SPELLCAST_FAILED", "player")
driver:SetScript("OnEvent", function(_, event, a, b, ...)
    if event == "UI_ERROR_MESSAGE" then
        -- (error type, message) in newer clients; (message) in older ones
        local msg = type(b) == "string" and b or (type(a) == "string" and a) or nil
        local want = _G.SPELL_FAILED_NOT_BEHIND or "You must be behind your target"
        if msg and (msg == want or msg:find("behind", 1, true)) then
            notBehindUntil = GetTime() + 1.5
            -- the skill just tried needs it: remember that, for next time
            if db and lastTry.name and GetTime() - lastTry.t < 1 and not BEHIND[lastTry.name] then
                db.behindLearned = db.behindLearned or {}
                db.behindLearned[lastTry.name] = true
            end
        end
        return
    elseif event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_FAILED" then
        if a ~= "player" then return end
        -- SENT: unit, target name, cast id, spell id; FAILED: unit, cast id, spell id
        local id = (event == "UNIT_SPELLCAST_SENT") and select(4, a, b, ...) or select(3, a, b, ...)
        id = Plain(id)
        local nm
        if id and C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, id)
            if ok and type(info) == "table" then nm = Plain(info.name) end
        elseif id and _G.GetSpellInfo then
            local ok, n = pcall(_G.GetSpellInfo, id)
            if ok then nm = Plain(n) end
        end
        if nm then lastTry.name, lastTry.t = nm, GetTime() end
        return
    elseif event == "UNIT_TARGET" then
        if a ~= "target" then return end
    elseif event == "PLAYER_TARGET_CHANGED" then
        notBehindUntil = 0
    end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitDB().range
        local had = root.feral ~= nil
        root.feral = root.feral or {}
        DeepFill(root.feral, ns.FERAL_DEFAULTS)
        -- 2.17.0: slots start empty. Settings from before keep the icons they showed: any slot
        -- left at the old default is written down as that skill, once
        if not root.feral.slotsStartEmpty then
            root.feral.slotsStartEmpty = true
            if had then
                root.feral.slots = root.feral.slots or {}
                for _, list in pairs(STACKS) do
                    for _, st in ipairs(list) do
                        local saved = root.feral.slots[st.key] or {}
                        for _, slot in ipairs(SLOTS) do
                            if saved[slot] == nil and OldSlotDefault(st, slot) ~= NONE then saved[slot] = OldSlotDefault(st, slot) end
                        end
                        root.feral.slots[st.key] = saved
                    end
                end
            end
        end
        -- 1.7.1: icons now hide when not castable and out of combat. Settings saved by
        -- earlier versions still hold the old defaults, so move them over once
        if not root.feral.hideUpgrade then
            root.feral.hideUpgrade = true
            root.feral.hideNotReady = true
            root.feral.combatOnly = true
        end
        db = root.feral
        Build()
        driver:Show()
    end
    Update()
end)

ns.Feral = {
    ReleaseCC = ReleaseCC,     -- hand Blizzard's CC icon back (our plates take it over)
    Settings = function() return db end,
    Refresh = Update,
    Reset = function()
        local root = ns.InitDB().range
        root.feral = {}
        DeepFill(root.feral, ns.FERAL_DEFAULTS)
        db = root.feral
        Update()
    end,
    -- show both lit on the target while the settings are open, on any class
    Preview = function(on) previewing = on and true or false; Update() end,
    Ready = Ready,
    Icon = SpellIcon,          -- a skill's real icon from the game, else its stand-in (the designer's sample uses it)
    Skills = function() return SKILLS end,
    AllStacks = AllStacks,
    Stacks = STACKS,
    -- the slots, for the editor: names, what a slot holds, changing it, and what can go in one
    Slots = {
        list = SLOTS, NONE = NONE, FINISHER = FINISHER,
        Get = function(setKey, slot) return SlotValue(StackByKey(setKey), slot) end,
        Set = function(setKey, slot, value) SetSlot(setKey, slot, value); Update() end,
        Reset = function(setKey) if db and db.slots then db.slots[setKey] = nil end; Update() end,
        Stack = StackByKey,
        -- the icon a slot's value shows: nil for an empty slot
        Icon = function(setKey, value)
            if value == nil or value == NONE then return nil end
            if value == FINISHER then
                local st = StackByKey(setKey)
                if st and st.finisher == "ready" and st.finisherSkill then return SpellIcon(st.finisherSkill) end
                return SpellIcon(BITE)
            end
            return SpellIcon(SkillByName(value))
        end,
        -- a slot's value in words, for tooltips
        Name = function(setKey, value)
            if value == nil or value == NONE then return "Empty" end
            if value == FINISHER then
                local st = StackByKey(setKey)
                if st and st.finisher == "ready" and st.finisherSkill then return st.finisherSkill.name end
                return "Ferocious Bite / Shifting Power"
            end
            return value
        end,
        SpellList = SpellList,
    },
    Debug = function(print)
        print(("feral: enabled=%s, class=%s (icons: %s), in form=%s, %s"):format(
            tostring(db and db.enabled), tostring(PlayerClass()), HasStack() and "yes" or "none", tostring(InForm()), state))
        local st = Stack() or AllStacks()[1]
        if st then
            local t = {}
            for _, slot in ipairs(SLOTS) do t[#t + 1] = slot .. "=" .. tostring(SlotValue(st, slot)) end
            print(("  slots (%s): %s"):format(tostring(st.key), table.concat(t, ", ")))
        end
        local list = {}
        for _, slot in ipairs({ "l1", "l2", "l3", "r1", "r2", "r3" }) do
            local sk = SkillByName(SlotValue(st, slot))
            if sk then list[#list + 1] = sk end
        end
        for _, s in ipairs(list) do
            local r, why = false, "skill not learned"
            if Known(s) then r, why = Ready(s) end
            print(("  %s: %s (%s), id %s"):format(s.name, r and "READY" or "not ready", why, tostring(Id(s))))
            local id = Id(s)
            if id and C_Spell and C_Spell.GetSpellCooldown then
                local ok, info = pcall(C_Spell.GetSpellCooldown, id)
                local function S(v) if v == nil then return "nil" elseif issecret(v) then return "secret" else return tostring(v) end end
                if ok and type(info) == "table" then
                    print(("    cooldown: start %s, duration %s, onGCD %s, enabled %s"):format(S(info.startTime), S(info.duration), S(info.isOnGCD), S(info.isEnabled)))
                else
                    print("    cooldown: " .. tostring(info))
                end
                local ok2, d = pcall(C_Spell.GetSpellCooldownDuration, id)
                print(("    duration object: %s; curve: %s; fade path: %s"):format(ok2 and (d and "yes" or "nil") or ("error " .. tostring(d)), CooldownCurve() and "yes" or "none",
                    (function() for _, f in ipairs(icons) do if f.skill == s then return tostring(f.fadePath) end end
                        for _, f in ipairs(ricons) do if f.skill == s then return tostring(f.fadePath) end end return "?" end)()))
                if ok2 and d then
                    local okE, v = pcall(function() return d:EvaluateRemainingDuration(CooldownCurve()) end)
                    local vs = okE and (v == nil and "nil" or (issecret(v) and "secret" or tostring(v))) or ("error " .. tostring(v))
                    print("    curve value now: " .. vs)
                end
                local ok3, u, np = pcall(C_Spell.IsSpellUsable, id)
                print(("    usable %s, no power %s; in range %s"):format(ok3 and S(u) or "?", ok3 and S(np) or "?", tostring(InRange(s))))
            end
        end
        local kind, why = "", ""
        if db then kind, why = Finisher() end
        print(("  finisher: %s (%s)"):format(kind or "nothing", tostring(why)))
        print(("  big icons now: left %s (%s); right %s (%s)"):format(tostring(fin and fin.kind or "nothing"), tostring(fin and fin.why),
            tostring(rfin and rfin.wanted and rfin.skill and rfin.skill.name or "nothing"), tostring(rfin and rfin.why)))
        local function N(v) if v == nil then return "hidden/unknown" end return tostring(v) end
        print(("    combo %s, energy %s of %s, Shifting Power %s (id %s), Bite %s"):format(
            N(finInfo.combo), N(finInfo.energy), N(finInfo.maxEnergy),
            Known(SHIFT) and "learned" or "not learned", tostring(Id(SHIFT) or "none"), Known(BITE) and "learned" or "not learned"))
        if finInfo.gain then
            print(("    gain %s (%s), regen %s/s, GCD %.2fs (base %.2fs, haste %s%%), after the cast %.0f"):format(
                tostring(finInfo.gain), tostring(finInfo.gainSource), N(finInfo.regen), finInfo.gcd or 0,
                finInfo.baseGcd or 0, N(finInfo.haste), finInfo.after or 0))
        end
    end,
}
