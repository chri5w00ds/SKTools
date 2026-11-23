--[[-------------------------------------------------------------------------
  SKTools - buff widgets

  Two small panes, information only (nothing on them can be clicked):

  Personal buffs
    Your class buff in the middle (Mark of the Wild, Power Word: Fortitude,
    Arcane Intellect...), lit while you or anyone in your group who is in
    range is missing it. Up to two chosen buffs either side of it (Thorns,
    Omen of Clarity...), lit while you are missing them, or, for a buff that
    can go on others, while your group's tank is: then the icon carries a
    small tank shield. Rebirth can take a side slot too: lit while someone
    in the group lies dead and you carry its seed.

  Missing class buffs
    The class buffs your group members could give you that you do not have
    (a Priest's Fortitude, a Mage's Intellect...). Hover one to see who can
    cast it.

  Both show only what is missing, centred: one icon in the middle, two either
  side of the centre line, three with one in the middle. Your class buff stays
  in the middle (centre-left when the count is even). Both panes can be moved
  and resized from the Widgets tab.

  In combat the game may keep auras from addons: the panes then keep what they
  last knew until it can read them again.
---------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

----------------------------------------------------------------------
-- The class buffs: the spell (its id gives the name and icon in your language), and any other
-- spells whose aura counts as having it (the group version of it, the other paladin blessings).
-- group = false: one only the caster gets, so it never shows as "missing" from someone else.
----------------------------------------------------------------------

local CLASS_BUFFS = {
    -- level: the lowest level it is learned at; talent: a talent, so only someone seen giving it counts
    DRUID   = { id = 1126,  name = "Mark of the Wild",       level = 1, also = { { 21849, "Gift of the Wild" } } },
    PRIEST  = { id = 1243,  name = "Power Word: Fortitude",  level = 1, also = { { 21562, "Prayer of Fortitude" } } },
    MAGE    = { id = 1459,  name = "Arcane Intellect",       level = 1, also = { { 23028, "Arcane Brilliance" } } },
    PALADIN = { id = 19740, name = "Blessing of Might",      level = 4, also = {
                    { 20217, "Blessing of Kings" }, { 19742, "Blessing of Wisdom" }, { 1038, "Blessing of Salvation" },
                    { 19977, "Blessing of Light" }, { 20911, "Blessing of Sanctuary" },
                    { 25782, "Greater Blessing of Might" }, { 25898, "Greater Blessing of Kings" },
                    { 25894, "Greater Blessing of Wisdom" }, { 25895, "Greater Blessing of Salvation" },
                    { 25890, "Greater Blessing of Light" }, { 25899, "Greater Blessing of Sanctuary" } } },
    WARRIOR = { id = 6673,  name = "Battle Shout",           level = 1 },
    HUNTER  = { id = 19506, name = "Trueshot Aura",          level = 40, talent = true },
    WARLOCK = { id = 706,   name = "Demon Armor", group = false, also = { { 687, "Demon Skin" } } },
    SHAMAN  = { id = 324,   name = "Lightning Shield", group = false },
}
ns.CLASS_BUFFS = CLASS_BUFFS

local REBIRTH = "Rebirth"
local NONE = "none"
local SIDE = { "s1", "s2", "s3", "s4" }       -- s1, s2 left of the class buff; s3, s4 right of it

ns.BUFF_DEFAULTS = {
    personal = { size = 36, point = "CENTER", x = 0, y = -180 },
    -- the missing class buffs pane has its own on / off (the one below is the personal pane's)
    missing  = { size = 30, point = "CENTER", x = 0, y = -230, enabled = true, berryEnabled = false },
    slots    = {},                             -- [class] = { s1 = "Thorns", ... }
    unlocked = false,                          -- the panes show their frames and can be moved / resized
    enabled  = true,
    berryEnabled = false,                      -- Berry Mode keeps its own switch, off until turned on
}

local db

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

local function MyClass()
    local _, c = UnitClass("player")
    return c
end

-- a spell's name in your language (from its id), else the English one we know
local nameCache = {}
local function SpellName(id, fallback)
    if nameCache[id] then return nameCache[id] end
    local n
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        n = ok and type(info) == "table" and Plain(info.name) or nil
    elseif _G.GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, id)
        n = ok and Plain(name) or nil
    end
    n = n or fallback
    nameCache[id] = n
    return n
end
local function SpellIcon(idOrName)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, idOrName)
        if ok and Plain(t) then return Plain(t) end
    end
    if _G.GetSpellTexture then
        local ok, t = pcall(GetSpellTexture, idOrName)
        if ok and Plain(t) then return Plain(t) end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- do you know this spell (by name)?
local function Known(name)
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

-- the names that count as having a class buff
local function BuffNames(cb)
    local t = { [SpellName(cb.id, cb.name)] = true }
    for _, a in ipairs(cb.also or {}) do t[SpellName(a[1], a[2])] = true end
    return t
end

----------------------------------------------------------------------
-- Auras: has a unit got any of these? true / false / nil (the game will not say)
----------------------------------------------------------------------

local function HasAura(unit, names)
    local secret = false
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok then return nil end
            if type(a) ~= "table" then break end
            local n = Plain(a.name)
            if n == nil then secret = true elseif names[n] then return true end
        end
        if secret then return nil end
        return false
    end
    if _G.UnitBuff then
        for i = 1, 40 do
            local ok, n = pcall(UnitBuff, unit, i)
            if not ok then return nil end
            n = Plain(n)
            if not n then break end
            if names[n] then return true end
        end
        return false
    end
    return nil
end

----------------------------------------------------------------------
-- The group
----------------------------------------------------------------------

local function Units()
    local list = { "player" }
    local okR, raid = pcall(_G.IsInRaid or function() return false end)
    local okN, n = pcall(_G.GetNumGroupMembers or function() return 0 end)
    n = okN and Plain(n) or 0
    if okR and raid == true then
        list = {}
        for i = 1, n do list[#list + 1] = "raid" .. i end
    else
        for i = 1, 4 do
            local ok, e = pcall(UnitExists, "party" .. i)
            if ok and Plain(e) then list[#list + 1] = "party" .. i end
        end
    end
    return list
end
local function IsMe(unit)
    if unit == "player" then return true end
    local ok, r = pcall(UnitIsUnit, unit, "player")
    return ok and Plain(r) == true
end
local function Usable(unit)
    local function q(fn, ...) if not fn then return nil end local ok, r = pcall(fn, ...) return ok and Plain(r) or nil end
    if unit ~= "player" and q(UnitExists, unit) ~= true then return false end
    if q(_G.UnitIsDeadOrGhost, unit) == true then return false end
    if q(_G.UnitIsConnected, unit) == false then return false end
    return true
end
local function InRange(spell, unit)
    if IsMe(unit) then return true end
    local fn = (C_Spell and C_Spell.IsSpellInRange) or _G.IsSpellInRange
    if not fn then return true end
    local ok, r = pcall(fn, spell, unit)
    r = ok and Plain(r)
    return r == true or r == 1
end
-- can this spell go on someone else at all? (Omen of Clarity cannot: the game gives no range answer)
local function OnOthers(spell, unit)
    local fn = (C_Spell and C_Spell.IsSpellInRange) or _G.IsSpellInRange
    if not fn then return false end
    local ok, r = pcall(fn, spell, unit)
    r = ok and Plain(r)
    return r ~= nil
end
local function IsTank(unit)
    if _G.UnitGroupRolesAssigned then
        local ok, r = pcall(UnitGroupRolesAssigned, unit)
        if ok and Plain(r) == "TANK" then return true end
    end
    if _G.GetPartyAssignment then
        local ok, r = pcall(GetPartyAssignment, "MAINTANK", unit)
        if ok and Plain(r) == true then return true end
    end
    return false
end

----------------------------------------------------------------------
-- What we last knew, per person and buff. In combat the game hides auras from addons, so a read
-- gives nothing; then what we last knew stands, and your own casts update it: cast Mark of the
-- Wild on someone and they count as marked until the auras can be read again.
----------------------------------------------------------------------

local known = {}               -- [person][buff key] = true / false
local function Person(unit)
    local ok, n = pcall(UnitName, unit)
    n = ok and Plain(n)
    if IsMe(unit) then return "player" end
    return n or unit
end
-- the aura read, else what we last knew (nil: never known)
local function Has(unit, names, key)
    local r = HasAura(unit, names)
    local p = Person(unit)
    known[p] = known[p] or {}
    if r ~= nil then known[p][key] = r; return r end
    return known[p][key]
end
local function Mark(unit, key)
    local p = Person(unit)
    known[p] = known[p] or {}
    known[p][key] = true
end

-- Rebirth: someone in the group lying dead (not a released ghost), and its seed in your bags
local REBIRTH_SEEDS = {
    [20484] = { 17034, "Maple Seed" }, [20739] = { 17035, "Stranglethorn Seed" }, [20742] = { 17036, "Ashwood Seed" },
    [20747] = { 17037, "Hornbeam Seed" }, [20748] = { 17038, "Ironwood Seed" },
}
local function DeadMember()
    for _, u in ipairs(Units()) do
        if not IsMe(u) then
            local function q(fn) if not fn then return nil end local ok, r = pcall(fn, u) return ok and Plain(r) or nil end
            if q(UnitExists) and q(_G.UnitIsDead) == true and q(_G.UnitIsGhost) ~= true and q(_G.UnitIsConnected) ~= false then
                return true, q(UnitName) or u
            end
        end
    end
    return false
end
local function RebirthState()
    if not Known(REBIRTH) then return false, "Rebirth not learned" end
    local dead, who = DeadMember()
    if not dead then return false, "no one in your group is dead" end
    local id
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, REBIRTH)
        id = ok and type(info) == "table" and Plain(info.spellID) or nil
    end
    local seed = REBIRTH_SEEDS[id or 0]
    if seed then
        local fn = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
        if fn then
            local ok, n = pcall(fn, seed[1])
            n = ok and Plain(n)
            if type(n) == "number" and n < 1 then return false, "no " .. seed[2] end
        end
    end
    -- off cooldown
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, cd = pcall(C_Spell.GetSpellCooldown, REBIRTH)
        if ok and type(cd) == "table" then
            local s, d = Plain(cd.startTime), Plain(cd.duration)
            if type(s) == "number" and type(d) == "number" and d > 1.6 and GetTime() < s + d then return false, "on cooldown" end
        end
    end
    return true, tostring(who) .. " is dead"
end

----------------------------------------------------------------------
-- What each pane should show
----------------------------------------------------------------------

local function Slots()
    local c = MyClass()
    db.slots[c] = db.slots[c] or {}
    return db.slots[c]
end
local function SlotValue(slot) return Slots()[slot] or NONE end

-- the class buff: missing on you or anyone in range in your group?
local function ClassShown()
    return not (db and db.noClass and db.noClass[MyClass() or ""])
end
local function ClassBuffNeeded()
    local cb = CLASS_BUFFS[MyClass() or ""]
    if not cb or not ClassShown() then return nil end
    local name = SpellName(cb.id, cb.name)
    if not Known(name) then return nil end
    local names = BuffNames(cb)
    local unknown, who = false, nil
    for _, u in ipairs(Units()) do
        if Usable(u) and (cb.group ~= false or IsMe(u)) and InRange(name, u) then
            local has = Has(u, names, "class")
            if has == nil then unknown = true
            elseif has == false then who = who or u end
        end
    end
    if who then return { key = "class", name = name, icon = SpellIcon(cb.id), who = who } end
    if unknown then return "unknown" end
    return false
end

-- a side slot: missing on you, or (for a buff that can go on others) on your group's tank
local function SideNeeded(value)
    if value == NONE then return false end
    if value == REBIRTH then
        local ok, why = RebirthState()
        if ok then return { key = REBIRTH, name = REBIRTH, icon = SpellIcon(REBIRTH), why = why } end
        return false
    end
    if not Known(value) then return false end
    local names = { [value] = true }
    local mine = Has("player", names, value)
    if mine == nil then return "unknown" end
    if mine == false then return { key = value, name = value, icon = SpellIcon(value), who = "player" } end
    for _, u in ipairs(Units()) do
        if not IsMe(u) and Usable(u) and IsTank(u) and OnOthers(value, u) and InRange(value, u) then
            local has = Has(u, names, value)
            if has == nil then return "unknown" end
            if has == false then return { key = value, name = value, icon = SpellIcon(value), who = u, tank = true } end
        end
    end
    return false
end

-- Can this group member give their class buff? The game does not say what spells someone else knows,
-- so: old enough to have learned it, and, for a buff that comes from a talent, seen giving it - their
-- buff on anyone in the group, or a cast of it (remembered by name from then on).
local function Seen() db.seen = db.seen or {}; return db.seen end
local function NameOf(u) local ok, n = pcall(UnitName, u); return ok and Plain(n) or nil end
local function CanGive(u, c)
    local cb = CLASS_BUFFS[c]
    local okL, lv = pcall(UnitLevel, u)
    lv = okL and Plain(lv)
    if type(lv) == "number" and lv > 0 and cb.level and lv < cb.level then return false end
    if cb.talent then
        local n = NameOf(u)
        return n ~= nil and Seen()[n] ~= nil and Seen()[n][c] == true
    end
    return true
end
local function MarkSeen(giverName, c)
    if not (db and giverName and c) then return end
    local s2 = Seen()
    s2[giverName] = s2[giverName] or {}
    if not s2[giverName][c] then s2[giverName][c] = true; return true end
end
-- which class buff a spell or aura name is (any of its versions)
local function ClassOfBuff(name)
    if not name then return nil end
    for c, cb in pairs(CLASS_BUFFS) do
        if cb.talent and BuffNames(cb)[name] then return c end
    end
end
-- look for talent buffs on the group (who put them there), while someone's is still unknown
local function LookForGivers()
    if not db then return end
    local wanted = false
    for _, u in ipairs(Units()) do
        if not IsMe(u) then
            local okC, _, c = pcall(UnitClass, u)
            c = okC and Plain(c)
            local cb = c and CLASS_BUFFS[c]
            if cb and cb.talent and not CanGive(u, c) then wanted = true end
        end
    end
    if not (wanted and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    for _, u in ipairs(Units()) do
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, u, i, "HELPFUL")
            if not ok or type(a) ~= "table" then break end
            local c = ClassOfBuff(Plain(a.name))
            local src = c and Plain(a.sourceUnit)
            if src then MarkSeen(NameOf(src), c) end
        end
    end
end

-- the class buffs your group members could give you that you are missing
local function MissingFromGroup()
    local mine = MyClass()
    local byClass = {}
    for _, u in ipairs(Units()) do
        if not IsMe(u) then
            local ok, _, c = pcall(UnitClass, u)
            c = ok and Plain(c)
            local cb = c and CLASS_BUFFS[c]
            if cb and c ~= mine and cb.group ~= false and CanGive(u, c) then
                byClass[c] = byClass[c] or {}
                local okN, n = pcall(UnitName, u)
                byClass[c][#byClass[c] + 1] = okN and Plain(n) or u
            end
        end
    end
    local out, unknown = {}, false
    local order = { "PRIEST", "MAGE", "DRUID", "PALADIN", "WARRIOR", "HUNTER" }
    for _, c in ipairs(order) do
        if byClass[c] then
            local cb = CLASS_BUFFS[c]
            local has = Has("player", BuffNames(cb), "class:" .. c)
            if has == nil then unknown = true
            elseif has == false then
                out[#out + 1] = { key = c, name = SpellName(cb.id, cb.name), icon = SpellIcon(cb.id), casters = byClass[c], class = c }
            end
        end
    end
    if unknown and #out == 0 then return "unknown" end
    return out
end

----------------------------------------------------------------------
-- The panes
----------------------------------------------------------------------

-- each icon sits in its own silver frame (Media\BuffFrame.tga, 128 px with the icon from 9 to 119):
-- the frame reaches PAD of the icon's size past each edge, and icons are spaced so frames never touch
local FRAME_TEX = ns.MEDIA .. "BuffFrame"
local PAD = 9 / 110
local function Gap(size) return math.ceil(2 * PAD * size) + 4 end
local Update                                   -- defined further down
local TANK_ATLAS = "roleicon-tiny-tank"
local panes = {}

local function HasAtlas(name)
    if C_Texture and C_Texture.GetAtlasInfo then
        local ok, info = pcall(C_Texture.GetAtlasInfo, name)
        return ok and info ~= nil
    end
    return false
end

local function Settings(kind) return db[kind] end

local function MakeIcon(pane)
    local f = CreateFrame("Frame", nil, pane)
    f:EnableMouse(true)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- the silver frame: over the icon's edge, which hides its square corners under the rounded ones
    f.frame = f:CreateTexture(nil, "OVERLAY", nil, 1)
    f.frame:SetTexture(FRAME_TEX)
    f.frame:SetPoint("CENTER")
    -- the tank shield, when it is your tank who needs the buff (above the frame)
    f.tank = f:CreateTexture(nil, "OVERLAY", nil, 2)
    f.tank:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
    if HasAtlas(TANK_ATLAS) then
        f.tank:SetAtlas(TANK_ATLAS)
    else
        f.tank:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
        f.tank:SetTexCoord(0, 19 / 64, 22 / 64, 41 / 64)
    end
    f.tank:Hide()
    f:SetScript("OnEnter", function(self)
        if not _G.GameTooltip or not self.entry then return end
        local e = self.entry
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(e.name or "?", 1, 1, 1)
        if e.casters then
            GameTooltip:AddLine("Can be cast by: " .. table.concat(e.casters, ", "), 0.8, 0.8, 0.8, true)
        elseif e.tank then
            local ok, n = pcall(UnitName, e.who)
            GameTooltip:AddLine("Your tank " .. tostring(ok and Plain(n) or "") .. " is missing it.", 0.8, 0.8, 0.8, true)
        elseif e.why then
            GameTooltip:AddLine(e.why, 0.8, 0.8, 0.8, true)
        elseif e.key == "class" and e.who and e.who ~= "player" then
            local ok, n = pcall(UnitName, e.who)
            GameTooltip:AddLine(tostring(ok and Plain(n) or "Someone") .. " is missing it.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    return f
end

local function MakePane(kind, label)
    local p = CreateFrame("Frame", "SKToolsBuffs" .. kind:gsub("^%l", string.upper), UIParent)
    p:SetFrameStrata("MEDIUM")
    p:SetClampedToScreen(true)
    p:SetMovable(true)
    p.kind = kind
    p.icons = {}
    -- the frame, shown only while unlocked: drag to move, drag the corner to resize
    p.frame = CreateFrame("Frame", nil, p)
    p.frame:SetAllPoints()
    p.frame:SetFrameLevel(p:GetFrameLevel() + 10)
    ns.W.Fill(p.frame, 0.1, 0.4, 0.6, 0.25)
    ns.W.Border(p.frame, 0.4, 0.8, 1, 0.9, 1)
    p.frame.text = p.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.frame.text:SetPoint("BOTTOM", p.frame, "TOP", 0, 2)
    p.frame.text:SetText(label)
    p.frame:EnableMouse(true)
    p.frame:RegisterForDrag("LeftButton")
    -- while dragging, the twice-a-second refresh leaves the position alone (it used to put the pane
    -- back where it was saved, so it jumped back mid-drag). On release the place is saved as the
    -- pane's centre against the screen's centre, so a pane that grows or shrinks stays centred there.
    p.frame:SetScript("OnDragStart", function() p.moving = true; p:StartMoving() end)
    p.frame:SetScript("OnDragStop", function()
        p:StopMovingOrSizing()
        p.moving = nil
        local s = Settings(kind)
        local px, py = p:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if px and ux then
            local k = (p:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
            s.point, s.x, s.y = "CENTER", math.floor(px * k - ux + 0.5), math.floor(py * k - uy + 0.5)
            if ns.Snap then s.x, s.y = ns.Snap(s.x, s.y) end
        end
        Update()
    end)
    p.frame:SetScript("OnHide", function()       -- locked again mid-drag: stop moving
        if p.moving then p:StopMovingOrSizing(); p.moving = nil end
    end)
    p.grip = CreateFrame("Button", nil, p.frame)
    p.grip:SetSize(10, 10)
    p.grip:SetPoint("BOTTOMRIGHT", 0, 0)
    ns.W.Fill(p.grip, 1, 1, 1, 1)
    p.grip:SetScript("OnMouseDown", function(self)
        local cx = GetCursorPosition()
        self.drag = { cx = cx, size = Settings(kind).size }
    end)
    p.grip:SetScript("OnMouseUp", function(self) self.drag = nil end)
    p.grip:SetScript("OnUpdate", function(self)
        if not self.drag then return end
        if _G.IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then self.drag = nil; return end
        local cx = GetCursorPosition()
        local scale = p:GetEffectiveScale() or 1
        -- five icons wide: dragging the corner by one icon's width grows each icon by a fifth of it
        local s = math.floor(self.drag.size + (cx - self.drag.cx) / scale / 5 + 0.5)
        Settings(kind).size = math.max(16, math.min(64, s))
        ns.Buffs.Refresh()
    end)
    p.frame:Hide()
    panes[kind] = p
    return p
end

-- lay a pane's icons out from the centre: one in the middle, two either side of the centre line;
-- 'first' (your class buff) stays at the middle, or just left of it when the count is even
local function Draw(p, list)
    local s = Settings(p.kind)
    local size = s.size or 32
    local slots = 5
    local gap = Gap(size)
    local fs = math.floor(size * (1 + 2 * PAD) + 0.5)
    p:SetSize(slots * (size + gap) - gap + 2 * math.ceil(PAD * size), fs)
    if not p.moving then
        p:ClearAllPoints()
        p:SetPoint(s.point or "CENTER", UIParent, s.point or "CENTER", s.x or 0, s.y or 0)
    end
    local n = #list
    for i = 1, math.max(n, #p.icons) do
        local f = p.icons[i]
        if i <= n then
            if not f then f = MakeIcon(p); p.icons[i] = f end
            local e = list[i]
            f.entry = e
            f:SetSize(size, size)
            f:ClearAllPoints()
            f:SetPoint("CENTER", p, "CENTER", (i - (n + 1) / 2) * (size + gap), 0)
            f.frame:SetSize(fs, fs)
            f.tex:SetTexture(e.icon)
            f.tank:SetSize(math.floor(size * 0.45), math.floor(size * 0.45))
            f.tank:SetShown(e.tank == true)
            f:Show()
        elseif f then
            f:Hide()
        end
    end
    p:Show()
end

-- the personal pane's order: left slots, the class buff, right slots; the class buff then sits
-- at the middle (or just left of it), the others filling round it in their order
local function Arrange(class, left, right)
    if not class then
        local all = {}
        for _, e in ipairs(left) do all[#all + 1] = e end
        for _, e in ipairs(right) do all[#all + 1] = e end
        return all
    end
    local others = {}
    for _, e in ipairs(left) do others[#others + 1] = e end
    for _, e in ipairs(right) do others[#others + 1] = e end
    local n = #others + 1
    local m = math.floor((n + 1) / 2)          -- middle, or centre-left when even
    local out = {}
    local j = 1
    for i = 1, n do
        if i == m then out[i] = class else out[i] = others[j]; j = j + 1 end
    end
    return out
end

local last = { personal = {}, missing = {} }
local state = { personal = "-", missing = "-" }

local function Sample(kind)
    -- while unlocked, a full row of examples so the pane can be placed and sized
    local list = {}
    local cb = CLASS_BUFFS[MyClass() or ""]
    for i = 1, (kind == "personal" and 3 or 2) do
        list[i] = { key = "sample" .. i, name = "Example", icon = cb and SpellIcon(cb.id) or "Interface\\Icons\\INV_Misc_QuestionMark" }
    end
    return list
end

function Update()
    if not db then return end
    if not panes.personal then
        MakePane("personal", "Personal buffs")
        MakePane("missing", "Missing class buffs")
    end
    -- each pane switched on or off on its own (in Berry Mode they start off, until turned on there)
    local on = { personal = ns.FeatureOn(db), missing = ns.FeatureOn(db.missing) }
    local why = ns.BerryMode() and "off (Berry Mode)" or "off"
    local function Off(kind)
        local p = panes[kind]
        Draw(p, {}); p:Hide(); p.frame:Hide()
        state[kind] = why
    end
    for kind, p in pairs(panes) do p.frame:SetShown(on[kind] and db.unlocked == true) end
    if db.unlocked then
        for _, kind in ipairs({ "personal", "missing" }) do
            if on[kind] then Draw(panes[kind], Sample(kind)); state[kind] = "unlocked" else Off(kind) end
        end
        return
    end
    if not on.personal then Off("personal") end
    if not on.missing then Off("missing") end
    if not (on.personal or on.missing) then return end

    -- personal: the class buff and the side slots; a "can't tell" keeps what was shown last
    local class = ClassBuffNeeded()
    local left, right = {}, {}
    local unknown = class == "unknown"
    for _, slot in ipairs(SIDE) do
        local need = SideNeeded(SlotValue(slot))
        if need == "unknown" then unknown = true
        elseif need then
            if slot == "s1" or slot == "s2" then left[#left + 1] = need else right[#right + 1] = need end
        end
    end
    if on.personal then
        if unknown then
            state.personal = "kept (the game is keeping auras hidden)"
        else
            last.personal = Arrange(class or nil, left, right)
            state.personal = #last.personal .. " shown"
        end
        Draw(panes.personal, last.personal)
    end

    if on.missing then
        local miss = MissingFromGroup()
        if miss == "unknown" then
            state.missing = "kept (the game is keeping auras hidden)"
        else
            last.missing = miss
            state.missing = #miss .. " shown"
        end
        Draw(panes.missing, last.missing)
    end
end

----------------------------------------------------------------------
-- Driving
----------------------------------------------------------------------

local driver = CreateFrame("Frame")
local acc = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.5 then return end                -- auras, range and the group, twice a second
    acc = 0
    LookForGivers()
    Update()
end)
-- a group member casting a talent buff: they can give it
local giverWatch = CreateFrame("Frame")
pcall(giverWatch.RegisterEvent, giverWatch, "UNIT_SPELLCAST_SUCCEEDED")
giverWatch:SetScript("OnEvent", function(_, _, unit, _, spellID)
    if type(unit) ~= "string" or not (unit:match("^party%d") or unit:match("^raid%d")) then return end
    local c = ClassOfBuff(Plain(spellID) and SpellName(spellID, nil))
    if c and MarkSeen(NameOf(unit), c) then Update() end
end)
-- your casts: which buff, and on whom
local GROUP_IDS = { 21849, 21562, 23028, 25782, 25898, 25894, 25895, 25890, 25899 }   -- the group versions
local pendingTarget = {}       -- [castGUID] = the target's name, from UNIT_SPELLCAST_SENT

local function UnitByName(name)
    if not name then return nil end
    for _, u in ipairs(Units()) do
        local ok, n = pcall(UnitName, u)
        if ok and Plain(n) == name then return u end
    end
    return nil
end
-- the single person a buff cast landed on: the name the cast was sent at, else your target if it is
-- in your group, else you (a buff cast with nothing targeted goes on you)
local function CastTarget(targetName)
    local u = UnitByName(targetName)
    if u then return u end
    for _, g in ipairs(Units()) do
        local ok, r = pcall(UnitIsUnit, g, "target")
        if ok and Plain(r) == true then return g end
    end
    return "player"
end

local function OnCast(spellID, targetName)
    local name = Plain(spellID) and SpellName(spellID, nil)
    if not name then return end
    local changed = false
    local cb = CLASS_BUFFS[MyClass() or ""]
    if cb and BuffNames(cb)[name] then
        local group = false
        for _, id in ipairs(GROUP_IDS) do if SpellName(id, nil) == name then group = true end end
        if group then
            for _, u in ipairs(Units()) do Mark(u, "class") end
        else
            Mark(CastTarget(targetName), "class")
        end
        changed = true
    end
    for _, slot in ipairs(SIDE) do
        local v = db and SlotValue(slot)
        if v and v ~= NONE and v ~= REBIRTH and v == name then
            Mark(CastTarget(targetName), v)
            changed = true
        end
    end
    if changed then Update() end
end

driver:RegisterEvent("PLAYER_LOGIN")
pcall(driver.RegisterUnitEvent or driver.RegisterEvent, driver, "UNIT_SPELLCAST_SENT", "player")
pcall(driver.RegisterUnitEvent or driver.RegisterEvent, driver, "UNIT_SPELLCAST_SUCCEEDED", "player")
pcall(driver.RegisterEvent, driver, "GROUP_ROSTER_UPDATE")
driver:SetScript("OnEvent", function(_, event, unit, a, b, c)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitDB().range
        root.buffs = root.buffs or {}
        DeepFill(root.buffs, ns.BUFF_DEFAULTS)
        db = root.buffs
        Update()
    elseif event == "UNIT_SPELLCAST_SENT" then
        -- unit, target name, cast id, spell id
        if unit ~= "player" then return end
        local guid = Plain(b)
        if guid then pendingTarget[guid] = Plain(a) or false end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- unit, cast id, spell id
        if unit ~= "player" or not db then return end
        local guid = Plain(a)
        local target = guid and pendingTarget[guid] or nil
        if guid then pendingTarget[guid] = nil end
        OnCast(b, target or nil)
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- someone left or joined: forget whoever is no longer with us
        local here = { player = true }
        for _, u in ipairs(Units()) do here[Person(u)] = true end
        for p in pairs(known) do if not here[p] then known[p] = nil end end
        Update()
    end
end)

-- the buffs you could put in a side slot: the helpful spells in your spell book (not your class
-- buff, which has the middle), and Rebirth if you know it
local function Choices()
    local list = (ns.Feral and ns.Feral.Slots and ns.Feral.Slots.SpellList and ns.Feral.Slots.SpellList()) or {}
    local cb = CLASS_BUFFS[MyClass() or ""]
    local skip = cb and BuffNames(cb) or {}
    local out = {}
    for _, sp in ipairs(list) do
        local helpful = true
        if C_Spell and C_Spell.IsSpellHelpful then
            local ok, r = pcall(C_Spell.IsSpellHelpful, sp.id or sp.name)
            if ok and Plain(r) == false then helpful = false end
        elseif _G.IsHelpfulSpell then
            local ok, r = pcall(IsHelpfulSpell, sp.name)
            if ok and not Plain(r) then helpful = false end
        end
        if helpful and not skip[sp.name] then out[#out + 1] = sp end
    end
    return out
end

ns.Buffs = {
    Settings = function() return db end,
    Refresh = function() Update() end,
    ForgetNames = function() for k in pairs(nameCache) do nameCache[k] = nil end end,
    Panes = function() return panes end,
    ClassBuff = function(class) return CLASS_BUFFS[class or MyClass() or ""] end,
    -- the class buff in the middle, on or left out (kept per class)
    ClassShown = function() return ClassShown() end,
    SetClassShown = function(v)
        if not db then return end
        db.noClass = db.noClass or {}
        db.noClass[MyClass() or ""] = (not v) or nil
        Update()
    end,
    ClassBuffIcon = function()
        local cb = CLASS_BUFFS[MyClass() or ""]
        return cb and SpellIcon(cb.id), cb and SpellName(cb.id, cb.name)
    end,
    SlotValue = function(slot) return db and SlotValue(slot) or NONE end,
    SetSlot = function(slot, value)
        if not db then return end
        Slots()[slot] = (value ~= NONE) and value or nil
        Update()
    end,
    SlotIcon = function(value)
        if not value or value == NONE then return nil end
        return SpellIcon(value)
    end,
    Choices = Choices,
    REBIRTH = REBIRTH, NONE = NONE, SIDE = SIDE,
    ResetPositions = function()
        if not db then return end
        for _, k in ipairs({ "personal", "missing" }) do
            local d = ns.BUFF_DEFAULTS[k]
            db[k].point, db[k].x, db[k].y = d.point, d.x, d.y
        end
        Update()
    end,
    Arrange = Arrange,
    Debug = function(print)
        print(("buff widgets: personal %s; missing class buffs %s"):format(state.personal, state.missing))
        local class = db and ClassBuffNeeded()
        print(("  class buff: %s"):format(not ClassShown() and "left out in the settings" or class == nil and "none for your class (or not learned)"
            or class == false and "everyone has it" or class == "unknown" and "can't tell (auras hidden)"
            or ("missing on " .. tostring(class.who))))
        for _, slot in ipairs(SIDE) do
            local v = db and SlotValue(slot) or NONE
            if v ~= NONE then
                local need = SideNeeded(v)
                print(("  %s: %s, %s"):format(slot, v, need == false and "not needed" or need == "unknown" and "can't tell"
                    or (need.tank and "your tank needs it" or need.why or "you need it")))
            end
        end
    end,
}

-- timed by /skt cpu
ns.Profile("Buff widgets", driver)
