-- SKTools settings tab: Nameplates (the designer).
--
-- One tab for everything on the nameplates. A sample plate shows every part; click a part
-- to select it and the column on the right shows only that part's settings. Parts that can
-- move are dragged; the small white square on the selected part's corner resizes it.
--
-- The parts that depend on your class (combo points, Claw/Shred/Bite icons, range crescent)
-- come in class sets. The drop-down by the top strip picks the class; the one in the corner of the
-- sample picks the subclass (a Druid's Cat Form or Bear Form). To add one later, register a set
-- with ns.ClassSets.Register and give each of its parts an entry in PARTS.

local ADDON, ns = ...

local W = ns.W
local M = ns.Marks
local MEDIA = ns.MEDIA
local SOLID = "Interface\\Buttons\\WHITE8X8"
local FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

----------------------------------------------------------------------
-- Class sets
----------------------------------------------------------------------

-- A set is a class, or a class in a role. The role is read from the talent trees (the tree with
-- the most points) plus a few telling talents; a set with a "role" only matches that role, a set
-- without one is the class's fallback. Add a role by registering a set with the role's name.
ns.ClassSets = {
    list = {
        { key = "cat",    title = "Cat Form",  class = "DRUID",  role = "feral", parts = { "combo", "feral", "finisher", "feralR", "finisherR", "finisherC" } },
        { key = "bear",   title = "Bear Form", class = "DRUID",  role = "feral", parts = { "combo", "feral", "finisher", "feralR", "finisherR", "finisherC" } },
        -- tank ("feral-tank"), healer ("restoration") and Balance ("balance") sets go here later
        { key = "rogue",  title = "Rogue",     class = "ROGUE",  parts = { "combo" } },
        { key = "hunter", title = "Hunter",    class = "HUNTER", parts = { "crescent", "feral", "finisher", "feralR", "finisherR", "finisherC" } },
        { key = "enhancement", title = "Enhancement", class = "SHAMAN", role = "enhancement", parts = { "totems", "feral", "finisher", "feralR", "finisherR", "finisherC" } },
        { key = "elemental",   title = "Elemental",   class = "SHAMAN", role = "elemental",   parts = { "totems", "feral", "finisher", "feralR", "finisherR", "finisherC" } },
        { key = "restoration", title = "Restoration", class = "SHAMAN", role = "restoration", parts = { "totems", "feral", "finisher", "feralR", "finisherR", "finisherC" } },
    },
    -- the classes the first drop-down offers, in order
    classes = {
        { value = "DRUID", text = "Druid" }, { value = "ROGUE", text = "Rogue" }, { value = "HUNTER", text = "Hunter" },
        { value = "SHAMAN", text = "Shaman" },
    },
}
function ns.ClassSets.Register(set) table.insert(ns.ClassSets.list, set) end
function ns.ClassSets.Get(key)
    if key == "feral" then key = "cat" end          -- the name this set had before Bear Form got its own
    for _, s in ipairs(ns.ClassSets.list) do if s.key == key then return s end end
end
-- the sets of one class, in order
function ns.ClassSets.OfClass(class)
    local out = {}
    for _, s in ipairs(ns.ClassSets.list) do if s.class == class then out[#out + 1] = s end end
    return out
end

-- points spent per talent tree, in tree order (Druid: Balance, Feral Combat, Restoration)
local function TreePoints()
    local out = {}
    local okN, n = pcall(function() return GetNumTalentTabs() end)
    n = okN and tonumber(n) or 0
    for i = 1, n do
        local ok, a, b, c, d = pcall(GetTalentTabInfo, i)
        local pts = 0
        if ok then
            if type(c) == "number" then pts = c            -- classic: name, icon, pointsSpent
            elseif type(d) == "number" then pts = d end    -- other layouts
        end
        out[i] = pts
    end
    return out
end
-- points in one talent, by name, anywhere in the trees
local function TalentPoints(name)
    if not (_G.GetNumTalentTabs and _G.GetNumTalents and _G.GetTalentInfo) then return 0 end
    local okN, n = pcall(GetNumTalentTabs)
    for tab = 1, (okN and tonumber(n)) or 0 do
        local okT, m = pcall(GetNumTalents, tab)
        for i = 1, (okT and tonumber(m)) or 0 do
            local ok, tname, _, _, _, rank = pcall(GetTalentInfo, tab, i)
            if ok and tname == name then return tonumber(rank) or 0 end
        end
    end
    return 0
end
-- the role this character plays, as far as talents can tell (asked several times a second by the
-- plates, so the answer is kept for a second)
local roleCache, roleAge = nil, -100
function ns.ClassSets.Role()
    local now = GetTime()
    if now - roleAge < 1 then return roleCache end
    roleCache, roleAge = ns.ClassSets.ReadRole(), now
    return roleCache
end
-- talents changed: ask again next time
function ns.ClassSets.ForgetRole() roleAge = -100 end
do
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED" }) do pcall(f.RegisterEvent, f, e) end
    f:SetScript("OnEvent", function() roleAge = -100 end)
end
function ns.ClassSets.ReadRole()
    local _, class = UnitClass("player")
    if class == "DRUID" then
        local p = TreePoints()
        local bal, fer, res = p[1] or 0, p[2] or 0, p[3] or 0
        if res > bal and res > fer then return "restoration" end
        if bal > fer and bal > res then return "balance" end
        if TalentPoints("Thick Hide") > 0 then return "feral-tank" end
        return "feral"
    end
    if class == "SHAMAN" then
        -- Elemental, Enhancement, Restoration: the tree with the most points (Enhancement until
        -- there are any)
        local p = TreePoints()
        local ele, enh, res = p[1] or 0, p[2] or 0, p[3] or 0
        if res > ele and res > enh then return "restoration" end
        if ele > enh and ele > res then return "elemental" end
        return "enhancement"
    end
    return nil
end
function ns.ClassSets.ForPlayer()
    local _, class = UnitClass("player")
    local role = ns.ClassSets.Role()
    local fallback
    for _, s in ipairs(ns.ClassSets.list) do
        if s.class == class then
            if s.role == role then return s end
            if not s.role or (class == "DRUID" and s.role == "feral") then fallback = fallback or s end   -- feral stands in until the other Druid sets exist
        end
    end
    return fallback
end

----------------------------------------------------------------------
-- Settings of each module
----------------------------------------------------------------------

local function P() return ns.Plates.Settings() or {} end
local function K() return ns.Combo.Settings() or {} end
local function F() return ns.Feral.Settings() or {} end
local function Z() return ns.Crescent.Settings() or {} end
local function mdb() return M.db end
local function PlatesChanged() ns.Plates.Refresh() end

-- the class the sample shows: "auto" is this character's own. An older save may hold a set's key
-- (the drop-down used to list sets), which stands for that set's class.
local function SampleClass()
    local v = P().classSet or "auto"
    if v == "auto" then
        local _, class = UnitClass("player")
        return class
    end
    local set = ns.ClassSets.Get(v)
    if set then return set.class end
    return v
end
-- the set on the sample: the chosen subclass of the class, else this character's own set, else the first
local function CurrentSet()
    local class = SampleClass()
    local own = ns.ClassSets.ForPlayer()
    local sets = ns.ClassSets.OfClass(class)
    local sub = P().subSet
    if sub then
        local set = ns.ClassSets.Get(sub)
        if set and set.class == class then return set end
    end
    if own and own.class == class then return own end
    return sets[1]
end
local function Clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function Round(v) return math.floor(v + 0.5) end

-- title, and for the parts you can drag or resize: where the numbers live
local PARTS = {
    bar      = { title = "Health bar",
                 resize = function(s, dx, dy) P().width = Clamp(Round(s.w + 2 * dx), 100, 400); P().height = Clamp(Round(s.h - 2 * dy), 14, 60); PlatesChanged() end,
                 start = function() return { w = P().width, h = P().height } end },
    level    = { title = "Level box" },
    cast     = { title = "Cast bar" },
    debuffs  = { title = "Your debuffs",
                 resize = function(s, dx) P().auraSize = Clamp(Round(s.v + dx), 12, 40); PlatesChanged() end,
                 start = function() return { v = P().auraSize } end },
    quest    = { title = "Quest marks" },
    swing    = { title = "Swing timer" },
    combo    = { title = "Combo points", set = true,
                 get = function() return K().x or 0, K().y or 0 end,
                 put = function(x, y) K().x = Clamp(x, -60, 60); K().y = Clamp(y, -40, 40); ns.Combo.Refresh() end,
                 resize = function(s, dx) K().size = Clamp(Round(s.v - dx), 6, 20); ns.Combo.Refresh() end,
                 start = function() return { v = K().size or 10 } end },
    feral    = { title = "Left icons", set = true, slots = { "l1", "l2", "l3" },
                 get = function() return F().x or 0, F().y or 0 end,
                 put = function(x, y) F().x = Clamp(x, -80, 80); F().y = Clamp(y, -60, 60); ns.Feral.Refresh() end,
                 resize = function(s, dx) F().size = Clamp(Round(s.v - dx), 14, 48); ns.Feral.Refresh() end,
                 start = function() return { v = F().size or 26 } end },
    finisher = { title = "Left big icon", set = true, slots = { "lb" },
                 get = function() return F().fx or 0, F().fy or 0 end,
                 put = function(x, y) F().fx = Clamp(x, -80, 80); F().fy = Clamp(y, -60, 60); ns.Feral.Refresh() end },
    feralR   = { title = "Right icons", set = true, slots = { "r1", "r2", "r3" }, rightSide = true,
                 get = function() return F().rx or 0, F().ry or 0 end,
                 put = function(x, y) F().rx = Clamp(x, -80, 80); F().ry = Clamp(y, -60, 60); ns.Feral.Refresh() end,
                 -- its own size (until changed, the same as the left side's)
                 resize = function(s, dx) F().rsize = Clamp(Round(s.v + dx), 14, 48); ns.Feral.Refresh() end,
                 start = function() return { v = F().rsize or F().size or 26 } end },
    finisherR = { title = "Right big icon", set = true, slots = { "rb" },
                 get = function() return F().rfx or 0, F().rfy or 0 end,
                 put = function(x, y) F().rfx = Clamp(x, -80, 80); F().rfy = Clamp(y, -60, 60); ns.Feral.Refresh() end },
    -- placed by its own sliders: in the editor it is drawn under the sample, out of the way
    finisherC = { title = "Centre big icon", set = true, slots = { "cb" } },
    totems   = { title = "Totem timers", set = true,
                 get = function() local t = ns.Totems.Settings() or {}; return t.x or 0, t.y or 0 end,
                 put = function(x, y) local t = ns.Totems.Settings(); if not t then return end
                     t.x = Clamp(x, -60, 60); t.y = Clamp(y, -40, 40); ns.Totems.Refresh() end,
                 resize = function(s, dx) local t = ns.Totems.Settings(); if not t then return end
                     t.size = Clamp(Round(s.v - dx), 10, 28); ns.Totems.Refresh() end,
                 start = function() return { v = (ns.Totems.Settings() or {}).size or 16 } end },
    crescent = { title = "Range crescent", set = true,
                 get = function() return Z().x or 0, Z().y or 0 end,
                 put = function(x, y) Z().x = Clamp(x, -60, 60); Z().y = Clamp(y, -40, 40); ns.Crescent.Refresh() end,
                 resize = function(s, dx) Z().size = Clamp(Round(s.v - dx), 20, 90); ns.Crescent.Refresh() end,
                 start = function() return { v = Z().size or 46 } end },
}
ns.DesignerParts = PARTS
local SlotAt

-- a part's name on the sample, which a set may word its own way
local function PartTitle(key)
    local set = CurrentSet()
    return (set and set.titles and set.titles[key]) or PARTS[key].title
end

----------------------------------------------------------------------
-- Small drawing helpers
----------------------------------------------------------------------

local function Tex(parent, layer, path)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(path or SOLID)
    return t
end
local function Paint(t, c, a)
    t:SetVertexColor(c[1], c[2], c[3], a or 1)
    if t.SetGradient and _G.CreateColor then
        pcall(t.SetGradient, t, "VERTICAL", CreateColor(c[1] * 0.55, c[2] * 0.55, c[3] * 0.55, a or 1),
            CreateColor(math.min(1, c[1] * 1.15 + 0.12), math.min(1, c[2] * 1.15 + 0.12), math.min(1, c[3] * 1.15 + 0.12), a or 1))
    end
end
local function Label(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size, "OUTLINE")
    fs:SetTextColor(1, 1, 1, 1)
    fs:SetJustifyH(justify or "LEFT")
    return fs
end
local function Cursor(frame)
    local cx, cy = GetCursorPosition()
    local es = frame:GetEffectiveScale()
    if type(es) ~= "number" or es <= 0 then es = 1 end
    return cx / es, cy / es
end
-- which of a column's slots is under the cursor: bottom, middle or top third
SlotAt = function(frame, slots)
    if #slots == 1 then return slots[1] end
    local ok, i = pcall(function()
        local _, cy = Cursor(frame)
        local rel = (cy - frame:GetBottom()) / frame:GetHeight()
        return math.floor(rel * #slots) + 1
    end)
    i = ok and type(i) == "number" and i or 1
    return slots[math.max(1, math.min(#slots, i))]
end
local function MouseHeld()
    return not _G.IsMouseButtonDown or IsMouseButtonDown("LeftButton")
end

----------------------------------------------------------------------
-- The tab
----------------------------------------------------------------------


local function Build(panel)
    local C1, C2, C3, CW = 24, 278, 532, 220
    ns.Designer = panel
    local el = {}                 -- part key -> its stand-in on the sample
    local selected = "bar"
    local Select, Redraw

    -- top strip: the whole-plate switches and the class set ------------
    local function PCheck(x, label, key, y, tip, width)
        local c = panel:Add(W.Check(panel, label,
            function() return P()[key] ~= false and P()[key] ~= nil end,
            function(v) P()[key] = v; PlatesChanged() end, width or CW), x, y)
        if tip then c.tooltip = tip end
        return c
    end
    PCheck(C1, "Use SKTools plates", "enabled", -8,
        "Enemy nameplates are drawn by SKTools. Friendly players and NPCs keep Blizzard's.", 130)
    -- Berry Mode: the switch by the berry at the bottom of the settings window. Here instead: the GCD
    -- meter, with its own on / off in Berry Mode
    local gcdTop = panel:Add(W.Check(panel, "GCD meter", function() return ns.Plates.GcdOn() end,
        function(v) ns.Plates.SetGcdOn(v); PlatesChanged() end, 100), 160, -8)
    gcdTop.tooltip = "A white line rises across your target's health bar while your global cooldown runs, with steam "
        .. "trailing under it. Berry Mode keeps its own on / off for this (off until you turn it on)."

    local options = { { value = "auto", text = "My class" } }
    for _, c in ipairs(ns.ClassSets.classes) do options[#options + 1] = c end
    local setDrop = panel:Add(W.Dropdown(panel, "Class:", options,
        function()
            local v = P().classSet or "auto"
            if v == "auto" then return v end
            return SampleClass()                       -- an older save may hold a set's key
        end,
        function(v)
            P().classSet = v
            P().subSet = nil                           -- a new class starts on its own default set
            if panel.SyncSubDrop then panel.SyncSubDrop() end
            Redraw()
            if PARTS[selected].set and not el[selected]:IsShown() then Select("bar") end
            Select(selected)
        end, 140), 272, -8)
    setDrop.tooltip = "Which class's extras are on the sample plate. In the game each character shows its own class's set."
    panel.setDrop = setDrop

    -- the sample plate ----------------------------------------------------
    local box = CreateFrame("Frame", nil, panel)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", C1, -38)
    box:SetSize(486, 214)
    box:SetFrameLevel(panel:GetFrameLevel() + 20)
    W.Fill(box, 0.06, 0.07, 0.09, 1)
    W.Skin(box, "inset")
    panel.sample = box

    -- subclass, in the corner of the sample: a Druid's Cat Form or Bear Form (a class with one set shows just that)
    local subDrop = W.Dropdown(box, "", {},
        function() local set = CurrentSet(); return set and set.key end,
        function(v)
            P().subSet = v
            Redraw()
            if PARTS[selected].set and not el[selected]:IsShown() then Select("bar") end
            Select(selected)
        end, 110)
    subDrop:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -6)
    subDrop:SetFrameLevel(box:GetFrameLevel() + 10)
    subDrop.tooltip = "Which subclass the sample shows: for a Druid, the Cat Form or Bear Form icons."
    panel.subDrop = subDrop
    local subFor
    function panel.SyncSubDrop()
        subFor = SampleClass()
        local opts = {}
        for _, set in ipairs(ns.ClassSets.OfClass(SampleClass())) do opts[#opts + 1] = { value = set.key, text = set.title } end
        subDrop:SetOptions(opts)
        subDrop:SetShown(#opts > 1)
    end
    panel.SyncSubDrop()

    local stage = CreateFrame("Frame", nil, box)        -- plate units; scaled to fit the box
    stage:SetSize(1, 1)
    stage:SetPoint("CENTER", box, "CENTER", 0, 4)

    local function Part(key)
        local b = CreateFrame("Button", nil, stage)
        b.part = key
        b:SetFrameLevel(box:GetFrameLevel() + 2)
        b:EnableMouse(true)
        local p = PARTS[key]
        b:SetScript("OnMouseDown", function(self)
            Select(key)
            self.pressed, self.moved = true, false
            if p.get then
                local cx, cy = Cursor(self)
                local x, y = p.get()
                self.drag = { cx, cy, x, y }
            end
        end)
        b:SetScript("OnMouseUp", function(self)
            if self.drag then self.drag = nil; if panel.subs[key] then panel.subs[key]:SyncAll() end end
            -- a click that did not move it: an icon part opens the skill list for the icon clicked
            if self.pressed and not self.moved and p.slots and panel.OpenPicker then
                panel.OpenPicker(key, SlotAt(self, p.slots))
            end
            self.pressed = false
        end)
        b:SetScript("OnUpdate", function(self)
            local d = self.drag
            if not d then return end
            if not MouseHeld() then self.drag = nil; return end
            local cx, cy = Cursor(self)
            -- a hand twitching during a click is not a drag: it takes 3 px of movement to start one
            if not self.moved and math.abs(cx - d[1]) < 3 and math.abs(cy - d[2]) < 3 then return end
            self.moved = true
            p.put(Round(d[3] + cx - d[1]), Round(d[4] + cy - d[2]))
            Redraw()
        end)
        b:SetScript("OnEnter", function(self)
            if _G.GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(PartTitle(key) .. (p.slots and "\nClick an icon to choose its skill." or "")
                    .. (p.get and "\nDrag to move." or ""), 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
        el[key] = b
        return b
    end

    -- health bar
    local bar = Part("bar")
    bar.bg = Tex(bar, "BACKGROUND"); bar.bg:SetAllPoints()
    bar.fill = Tex(bar, "BORDER"); bar.fill:SetPoint("TOPLEFT"); bar.fill:SetPoint("BOTTOMLEFT")
    bar.edge = W.Border(bar, 1, 1, 1, 1, 1.5)
    bar.name = Label(bar, 11); bar.name:SetPoint("LEFT", 7, 0); bar.name:SetText("Zhevra Runner")
    bar.pct = Label(bar, 10, "RIGHT"); bar.pct:SetPoint("RIGHT", -6, 0); bar.pct:SetText("77%")
    -- level box
    local lv = Part("level")
    lv:SetFrameLevel(box:GetFrameLevel() + 1)
    lv.bg = Tex(lv, "BACKGROUND"); lv.bg:SetAllPoints(); Paint(lv.bg, { 0.25, 0.25, 0.25 })
    W.Border(lv, 0.75, 0.77, 0.80, 1, 1)
    -- a still of the GCD meter: the line partway up, steam under it
    lv.steam = Tex(bar, "OVERLAY", MEDIA .. "GcdSteam1"); lv.steam:SetDrawLayer("OVERLAY", -2)    -- on the bar, under the line
    lv.gline = Tex(lv, "OVERLAY"); lv.gline:SetVertexColor(1, 1, 1, 1)
    bar.gline = Tex(bar, "OVERLAY"); bar.gline:SetDrawLayer("OVERLAY", -1); bar.gline:SetVertexColor(1, 1, 1, 1)  -- the line runs the whole plate
    lv.top = CreateFrame("Frame", nil, lv); lv.top:SetAllPoints(); lv.top:SetFrameLevel(lv:GetFrameLevel() + 2)
    lv.text = Label(lv.top, 10, "CENTER"); lv.text:SetText("13")
    -- cast bar, with Blizzard's crowd-control icon on its right end
    local cast = Part("cast")
    cast.bg = Tex(cast, "BACKGROUND"); cast.bg:SetAllPoints(); cast.bg:SetVertexColor(0.05, 0.05, 0.06, 1)
    cast.fill = Tex(cast, "BORDER"); cast.fill:SetPoint("TOPLEFT"); cast.fill:SetPoint("BOTTOMLEFT")
    cast.icon = Tex(cast, "ARTWORK", "Interface\\Icons\\Spell_Nature_Lightning")
    cast.icon:SetPoint("TOPLEFT"); cast.icon:SetPoint("BOTTOMLEFT"); cast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    cast.name = Label(cast, 10); cast.name:SetText("Lightning Bolt")
    cast.cc = Tex(cast, "OVERLAY", "Interface\\Icons\\Spell_Nature_Polymorph")
    cast.cc:SetPoint("RIGHT", -2, 0); cast.cc:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- swing timer strip
    local swing = Part("swing")
    swing.bg = Tex(swing, "BACKGROUND"); swing.bg:SetAllPoints()
    swing.red = Tex(swing, "BORDER"); swing.red:SetPoint("TOPLEFT"); swing.red:SetPoint("BOTTOMLEFT")
    swing.edge = Tex(swing, "ARTWORK"); swing.edge:SetVertexColor(0, 0, 0, 1)
    swing.pip = Tex(swing, "OVERLAY")
    -- debuffs
    local deb = Part("debuffs")
    deb.icons = {}
    for i, icon in ipairs({ "Ability_Druid_Disembowel", "Ability_GhoulFrenzy", "Spell_Nature_FaerieFire" }) do
        deb.icons[i] = Tex(deb, "ARTWORK", "Interface\\Icons\\" .. icon)
        deb.icons[i]:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    -- quest marks: kill count over the level box, loot count under it, quest-starter icon beside it
    local quest = Part("quest")
    quest.starter = Tex(quest, "ARTWORK", MEDIA .. "Starter"); quest.starter:SetAllPoints()
    quest.kill = Label(quest, 10, "CENTER"); quest.kill:SetText("4")
    quest.loot = Label(quest, 10, "CENTER"); quest.loot:SetText("3-2")
    -- combo points
    local combo = Part("combo")
    combo.dots = {}
    for i = 1, 5 do
        combo.dots[i] = { edge = Tex(combo, "BACKGROUND", MEDIA .. "ComboBG"), bg = Tex(combo, "BORDER", MEDIA .. "ComboBG"), fill = Tex(combo, "ARTWORK", MEDIA .. "ComboFill"),
                          ring = Tex(combo, "OVERLAY", MEDIA .. "ComboRing") }
    end
    -- the skill icons: three stacked and a big one on each side. In the editor every slot is drawn,
    -- an empty one as a dark square with a "+", so it can be clicked; the big icons stand beside
    -- their stacks instead of over them, so all three small ones can be seen
    local function SlotTex(part)
        local t = {}
        t.back = Tex(part, "BACKGROUND"); t.back:SetVertexColor(0, 0, 0, 0.55)
        t.icon = Tex(part, "ARTWORK"); t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t.plus = Label(part, 14, "CENTER"); t.plus:SetText("+")
        return t
    end
    local feral = Part("feral")
    feral.slots = { SlotTex(feral), SlotTex(feral), SlotTex(feral) }
    local fin = Part("finisher")
    fin:SetFrameLevel(box:GetFrameLevel() + 3)
    fin.slot = SlotTex(fin)
    fin.icon = fin.slot.icon
    local feralR = Part("feralR")
    feralR.slots = { SlotTex(feralR), SlotTex(feralR), SlotTex(feralR) }
    local finR = Part("finisherR")
    finR:SetFrameLevel(box:GetFrameLevel() + 3)
    finR.slot = SlotTex(finR)
    finR.icon = finR.slot.icon
    local finC = Part("finisherC")
    finC:SetFrameLevel(box:GetFrameLevel() + 3)
    finC.slot = SlotTex(finC)
    finC.icon = finC.slot.icon
    -- shaman totem timers: Earth, Fire, Water, Air (all four down), a sweep part-way round each
    local tot = Part("totems")
    tot.boxes = {}
    for i, e in ipairs(ns.TOTEM_ORDER or {}) do
        local b = { edge = Tex(tot, "BACKGROUND"), icon = Tex(tot, "ARTWORK", e.sample), dark = Tex(tot, "OVERLAY") }
        b.edge:SetVertexColor(0, 0, 0, 1)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.dark:SetVertexColor(0, 0, 0, 0.6)
        b.empty = false
        b.used = ({ 0.25, 0.7, 0.1, 0.45 })[i]
        tot.boxes[i] = b
    end
    -- the Lightning Shield segments: two charges left in the sample
    tot.segs = {}
    for i = 1, 3 do tot.segs[i] = Tex(tot, "ARTWORK", ns.MEDIA .. (i == 1 and "ShieldSegOff" or "ShieldSeg")) end
    -- hunter range crescent
    local cres = Part("crescent")
    cres.fill = Tex(cres, "ARTWORK", MEDIA .. "ArcCrescent"); cres.fill:SetAllPoints()
    cres.rim = Tex(cres, "OVERLAY", MEDIA .. "ArcCrescentRim"); cres.rim:SetAllPoints()

    -- selection: a white frame round the part, and a square handle on its corner when it can be resized
    local sel = CreateFrame("Frame", nil, stage)
    sel:SetFrameLevel(box:GetFrameLevel() + 6)
    W.Border(sel, 1, 1, 1, 0.9, 1)
    local grip = CreateFrame("Button", nil, stage)
    grip:SetFrameLevel(box:GetFrameLevel() + 7)
    grip:SetSize(8, 8)
    grip:EnableMouse(true)
    W.Fill(grip, 1, 1, 1, 1)
    W.Border(grip, 0, 0, 0, 1, 1)
    grip:SetScript("OnMouseDown", function(self)
        local p = PARTS[selected]
        if not p.resize then return end
        local cx, cy = Cursor(self)
        self.drag = { cx, cy, p.start() }
    end)
    grip:SetScript("OnMouseUp", function(self)
        if self.drag then self.drag = nil; if panel.subs[selected] then panel.subs[selected]:SyncAll() end end
    end)
    grip:SetScript("OnUpdate", function(self)
        local d = self.drag
        if not d then return end
        if not MouseHeld() then self.drag = nil; return end
        local cx, cy = Cursor(self)
        PARTS[selected].resize(d[3], cx - d[1], cy - d[2])
        Redraw()
    end)
    grip:SetScript("OnEnter", function(self)
        if _G.GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Drag to resize.", 1, 1, 1); GameTooltip:Show() end
    end)
    grip:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    panel.el, panel.grip = el, grip

    -- the skill list: opens over the sample when an icon is clicked ---------------------------
    local picker = CreateFrame("Frame", nil, panel)
    -- above the settings window and everything on the sample, like the drop-down lists
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    picker:SetFrameLevel(50)
    picker:EnableMouse(true)
    picker:SetPoint("TOPRIGHT", box, "TOPRIGHT", -4, -4)
    W.Fill(picker, 0.05, 0.05, 0.06, 0.97)
    W.Border(picker, 0.82, 0.68, 0.30, 1, 1)
    picker:Hide()
    picker.title = Label(picker, 11)
    picker.title:SetPoint("TOPLEFT", 8, -8)
    local close = CreateFrame("Button", nil, picker)
    close:SetSize(18, 18); close:SetPoint("TOPRIGHT", -3, -3)
    close.text = Label(close, 12, "CENTER"); close.text:SetPoint("CENTER"); close.text:SetText("x")
    close:SetScript("OnClick", function() picker:Hide() end)
    picker.empty = W.Button(picker, "Empty", 70, function() picker.Choose(ns.Feral.Slots.NONE) end)
    picker.empty:SetPoint("TOPLEFT", 8, -26)
    picker.special = W.Button(picker, "", 170, function() picker.Choose(ns.Feral.Slots.FINISHER) end)
    picker.special:SetPoint("LEFT", picker.empty, "RIGHT", 6, 0)
    picker.none = Label(picker, 10); picker.none:SetPoint("TOPLEFT", 8, -56)
    picker.none:SetText("No spells found in your spell book.")
    picker.cells = {}
    local PER_ROW, CELL = 10, 24
    function picker.Choose(value)
        if not (picker.set and picker.slot) then picker:Hide(); return end
        ns.Feral.Slots.Set(picker.set, picker.slot, value)
        picker:Hide()
        Redraw()
    end
    local function Cell(i)
        local c = picker.cells[i]
        if c then return c end
        c = CreateFrame("Button", nil, picker)
        c:SetSize(CELL - 2, CELL - 2)
        c.icon = Tex(c, "ARTWORK"); c.icon:SetAllPoints(); c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        c.mark = CreateFrame("Frame", nil, c)              -- gold frame round the skill in the slot now
        c.mark:SetAllPoints()
        W.Border(c.mark, 1, 0.82, 0.25, 1, 2)
        c:SetScript("OnClick", function(self) picker.Choose(self.name) end)
        c:SetScript("OnEnter", function(self)
            if _G.GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(self.name, 1, 1, 1); GameTooltip:Show() end
        end)
        c:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
        picker.cells[i] = c
        return c
    end
    local SLOT_WORDS = { l1 = "left, bottom", l2 = "left, middle", l3 = "left, top", lb = "left, big icon",
                         r1 = "right, bottom", r2 = "right, middle", r3 = "right, top", rb = "right, big icon",
                         cb = "centre, big icon" }
    function panel.OpenPicker(partKey, slot)
        local set = CurrentSet()
        if not (set and slot) then return end
        local SL = ns.Feral.Slots
        picker.set, picker.slot = set.key, slot
        local now = SL.Get(set.key, slot)
        picker.title:SetText(("%s: %s"):format(set.title, SLOT_WORDS[slot] or slot))
        -- the set's own big-icon rule (Bite or Shifting Power; Primal Bite) is offered for the left big icon
        local st = SL.Stack(set.key)
        local special = (slot == "lb" or slot == "cb") and st and st.finisher
        picker.special:SetShown(special and true or false)
        if special then
            local t = SL.Name(set.key, SL.FINISHER)
            if picker.special.classic then picker.special:SetText(t) end
            if picker.special.label then picker.special.label:SetText(t) end
        end
        local list = SL.SpellList()
        picker.none:SetShown(#list == 0)
        for i, sp in ipairs(list) do
            local c = Cell(i)
            c.name = sp.name
            c.icon:SetTexture(sp.icon or SL.Icon(set.key, sp.name))
            c.mark:SetShown(sp.name == now)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", picker, "TOPLEFT", 8 + ((i - 1) % PER_ROW) * CELL, -56 - math.floor((i - 1) / PER_ROW) * CELL)
            c:Show()
        end
        for i = #list + 1, #picker.cells do picker.cells[i]:Hide() end
        local rows = math.max(1, math.ceil(#list / PER_ROW))
        picker:SetSize(16 + PER_ROW * CELL, 64 + rows * CELL)
        picker:Show()
    end
    panel.picker = picker

    -- draws the sample from the settings as they are now
    function Redraw()
        if subFor ~= SampleClass() then panel.SyncSubDrop() end      -- the class changed: its subclasses
        subDrop:Sync()
        local p, k, f, z = P(), K(), F(), Z()
        local w, h, lw = p.width or 220, p.height or 28, p.levelWidth or 34
        -- fit: bar, level box and the icons on both sides (big icons beside their stacks), centred
        local fsz = F().size or 26
        local bz = math.floor((2 * fsz + 2) * 0.7 + 0.5)
        local outer = 4 + bz / 2 + fsz / 2 + 6 + bz
        local rsz = F().rsize or fsz
        local rbz = math.floor((2 * rsz + 2) * 0.7 + 0.5)
        local leftExt = ((ns.Combo.LeftReach and ns.Combo.LeftReach()) or 18) + outer
        local rightExt = (p.levelGap or 0) + lw + 4 + rbz / 2 + rsz / 2 + 6 + rbz
        local sc = Clamp(466 / (w + leftExt + rightExt), 0.5, 1.6)
        -- and the centre big icon drawn under the sample (below the cast bar) must fit the height
        local setNowC = CurrentSet()
        local hasC = false
        if setNowC then for _, key in ipairs(setNowC.parts) do if key == "finisherC" then hasC = true end end end
        if hasC then
            local below = h / 2 + ((p.cast ~= false) and ((p.castGap or 2) + (p.castHeight or 18)) or 0) + 8 + h * 1.5
            sc = math.min(sc, math.max(0.5, 100 / below))
        end
        stage:SetScale(sc)
        stage:ClearAllPoints(); stage:SetPoint("CENTER", box, "CENTER", (leftExt - rightExt) / 2, 4 / sc)

        bar:ClearAllPoints(); bar:SetPoint("CENTER", stage, "CENTER", 0, 0); bar:SetSize(w, h)
        Paint(bar.bg, { 0.25, 0.25, 0.25 })
        bar.fill:SetWidth(w * 0.77)
        Paint(bar.fill, ns.BerryMode() and (p.berryColor or { 0.8, 0.1, 0.12 }) or (p.colors and p.colors.melee) or { 0.25, 0.62, 0.30 })
        bar.name:SetFont(FONT, p.fontSize or 11, "OUTLINE")
        -- the health percentage as on the plates: on the centre line at the right end
        bar.pct:SetFont(FONT, ns.Plates.ReadoutSize(h, p.fontSize or 11), "OUTLINE")
        bar.pct:ClearAllPoints(); bar.pct:SetPoint("RIGHT", bar, "RIGHT", -6, 0)

        lv:ClearAllPoints(); lv:SetPoint("LEFT", bar, "RIGHT", (p.levelGap or 0) - 8, 0); lv:SetSize(lw + 8, h)
        lv.text:ClearAllPoints(); lv.text:SetPoint("CENTER", lv, "RIGHT", -lw / 2, 0)
        -- the level in its difficulty colour (13 against your own level) and the meter, when they are on
        lv.text:SetTextColor(ns.Plates.LevelColor(13))
        local on = ns.Plates.GcdOn()
        lv.gline:SetShown(false); lv.steam:SetShown(on); bar.gline:SetShown(on)   -- line and steam: on the health bar
        if on then
            local y = math.floor((h - 2) * 0.55)
            lv.gline:ClearAllPoints(); lv.gline:SetPoint("BOTTOMLEFT", lv, "BOTTOMRIGHT", -lw + 3, y); lv.gline:SetSize(lw - 6, 1.5)
            bar.gline:ClearAllPoints()
            bar.gline:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 2, y + 1)
            bar.gline:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -2, y + 1)
            bar.gline:SetHeight(1.5)
            lv.steam:ClearAllPoints(); lv.steam:SetPoint("TOPLEFT", bar.gline, "BOTTOMLEFT", 0, 0); lv.steam:SetPoint("TOPRIGHT", bar.gline, "BOTTOMRIGHT", 0, 0)
            lv.steam:SetHeight((h - 2) * 0.45)
            lv.steam:SetAlpha(0.8)
        end

        local ch = p.castHeight or 18
        cast:SetShown(p.cast ~= false)
        cast:ClearAllPoints(); cast:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -(p.castGap or 2)); cast:SetSize(w, ch)
        cast.icon:SetWidth(ch)
        cast.fill:ClearAllPoints(); cast.fill:SetPoint("TOPLEFT", ch, 0); cast.fill:SetPoint("BOTTOMLEFT", ch, 0); cast.fill:SetWidth((w - ch) * 0.6)
        Paint(cast.fill, p.castColor or { 0.95, 0.78, 0.25 })
        cast.name:ClearAllPoints(); cast.name:SetPoint("LEFT", ch + 4, 0)
        cast.cc:SetSize(ch + 2, ch + 2)

        local as, ag = p.auraSize or 20, p.auraGap or 2
        deb:SetShown(p.auras ~= false)
        -- swing strip: ranged look (right to left, red at the left end) for a set with a ranged part
        local sh, on = p.swingHeight or 4, p.swing ~= false
        local setNow = CurrentSet()
        local ranged = setNow and setNow.key == "hunter"
        swing:SetShown(on)
        swing:ClearAllPoints(); swing:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 3); swing:SetSize(w, sh)
        local sc, sr = p.swingColor or { 0.78, 0.80, 0.83 }, p.swingRed or { 0.88, 0.15, 0.12 }
        swing.bg:SetVertexColor(sc[1], sc[2], sc[3], p.swingAlpha or 0.35)
        swing.red:SetVertexColor(sr[1], sr[2], sr[3], 0.85); swing.red:SetWidth(w * (p.swingWindow or 0.5) / 2.8); swing.red:SetShown(ranged and true or false)
        local at = ranged and 0.4 or 0.6
        swing.pip:ClearAllPoints(); swing.pip:SetSize(3, sh + 4); swing.pip:SetPoint("CENTER", swing, "LEFT", w * at, 0)
        swing.edge:ClearAllPoints(); swing.edge:SetSize(5, sh + 6); swing.edge:SetPoint("CENTER", swing, "LEFT", w * at, 0)
        deb:ClearAllPoints(); deb:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, on and (sh + 5) or 2); deb:SetSize(3 * as + 2 * ag, as)
        for i, t in ipairs(deb.icons) do
            t:ClearAllPoints(); t:SetSize(as, as); t:SetPoint("LEFT", deb, "LEFT", (i - 1) * (as + ag), 0)
        end

        quest:ClearAllPoints(); quest:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, on and (sh + 5) or 2); quest:SetSize(18, 18)
        local m = mdb() or {}
        quest.starter:SetAlpha((m.show and m.show.starter) and 1 or 0.25)
        quest.kill:ClearAllPoints(); quest.kill:SetPoint("BOTTOM", lv, "TOPRIGHT", -lw / 2, 3)
        quest.loot:ClearAllPoints(); quest.loot:SetPoint("TOP", lv, "BOTTOMRIGHT", -lw / 2, -3)
        quest.kill:SetAlpha(m.counters and 1 or 0.25); quest.loot:SetAlpha(m.counters and 1 or 0.25)

        -- the class set
        local set, has = CurrentSet(), {}
        if set then for _, key in ipairs(set.parts) do has[key] = true end end
        for key, part in pairs(PARTS) do
            if part.set then el[key]:SetShown(has[key] and true or false) end
        end
        local reach = (ns.Combo.LeftReach and ns.Combo.LeftReach()) or 18
        if has.combo then
            local s = k.size or 10
            local step = 2 * math.asin(math.min((s + 2) / 96, 1))
            combo:ClearAllPoints(); combo:SetSize(reach, 4 * (s + 2) + s)
            combo:SetPoint("RIGHT", bar, "LEFT", k.x or 0, k.y or 0)
            local c = k.color or { 1, 0.16, 0.13 }
            for i, d in ipairs(combo.dots) do
                local phi = (i - 3) * step
                local x = -(2 + s / 2 + 48 * (math.cos(phi) - math.cos(2 * step)))
                local y = 48 * math.sin(phi)
                for name, t in pairs(d) do
                    t:ClearAllPoints(); t:SetSize(s, s); t:SetPoint("CENTER", combo, "RIGHT", x, y)
                    if name == "fill" then t:SetVertexColor(c[1], c[2], c[3], 1); t:SetShown(i <= 3) end
                    if name == "edge" then t:SetSize(s + 4, s + 4); t:SetVertexColor(0, 0, 0, k.edge or 0.9); t:SetShown((k.edge or 0) > 0) end
                    if name == "bg" then t:SetVertexColor(0, 0, 0, k.bgAlpha or 0.75) end
                end
            end
        end
        local fs = f.size or 26
        local bite = math.floor((2 * fs + 2) * 0.7 + 0.5)
        if setNow and setNow.key == "hunter" then reach = 32 * ((z.size or 46) / 46) + 2 end
        if has.totems and ns.Totems then reach = ns.Totems.LeftReach() + 2 end
        local fx = -(reach + 4 + bite / 2)
        local rxs = (p.levelGap or 0) + lw + 4 + bite / 2
        local beside = fs / 2 + 6 + bite / 2          -- the big icons stand this far out from their stacks
        local SL = ns.Feral.Slots
        local setKey = setNow and setNow.key or "cat"
        -- one slot drawn: its skill's icon, or an empty square with a "+"
        local function DrawSlot(t, part, slot, size, x, y)
            local v = SL.Get(setKey, slot)
            local icon = SL.Icon(setKey, v)
            for _, r in ipairs({ t.back, t.icon, t.plus }) do r:ClearAllPoints() end
            t.back:SetSize(size, size); t.back:SetPoint("CENTER", part, "CENTER", x, y)
            t.icon:SetSize(size - 2, size - 2); t.icon:SetPoint("CENTER", part, "CENTER", x, y)
            t.plus:SetPoint("CENTER", part, "CENTER", x, y)
            t.icon:SetShown(icon ~= nil)
            if icon then t.icon:SetTexture(icon) end
            t.plus:SetShown(icon == nil)
            t.value = v
        end
        local function Column(part, slots, cx, ox, oy)
            part:ClearAllPoints(); part:SetSize(fs, 3 * fs + 4)
            part:SetPoint("CENTER", bar, cx < 0 and "LEFT" or "RIGHT", cx + ox, oy)
            for i, t in ipairs(part.slots) do DrawSlot(t, part, slots[i], fs, 0, (i - 2) * (fs + 2)) end
        end
        local function Big(part, slot, cx, ox, oy)
            part:ClearAllPoints(); part:SetSize(bite, bite)
            part:SetPoint("CENTER", bar, cx < 0 and "LEFT" or "RIGHT", cx + ox, oy)
            DrawSlot(part.slot, part, slot, bite, 0, 0)
        end
        if has.feral then Column(feral, { "l1", "l2", "l3" }, fx, f.x or 0, f.y or 0) end
        if has.finisher then
            Big(fin, "lb", fx - beside, f.fx or 0, f.fy or 0)
            -- the set's own big icon switched off in its settings: dimmed
            local off = fin.slot.value == SL.FINISHER and ((setKey == "bear" and f.primalbite == false) or (setKey ~= "bear" and f.finisher == false))
            fin:SetAlpha(off and 0.3 or 1)
        end
        -- the right side, at its own size
        local rs = f.rsize or fs
        local rbite = math.floor((2 * rs + 2) * 0.7 + 0.5)
        local rx2 = (p.levelGap or 0) + lw + 4 + rbite / 2
        local rbeside = rs / 2 + 6 + rbite / 2
        local fsKeep, biteKeep = fs, bite
        fs, bite = rs, rbite
        if has.feralR then Column(feralR, { "r1", "r2", "r3" }, rx2, f.rx or 0, f.ry or 0) end
        if has.finisherR then Big(finR, "rb", rx2 + rbeside, f.rfx or 0, f.rfy or 0) end
        fs, bite = fsKeep, biteKeep
        if has.finisherC then
            -- in the game it stands over the middle of the bar; here, under the sample (below the
            -- cast bar), so it covers nothing and is easy to click
            local cs = math.floor(h * 1.5 + 0.5)
            local below = (p.cast ~= false) and ((p.castGap or 2) + (p.castHeight or 18)) or 0
            finC:ClearAllPoints(); finC:SetSize(cs, cs)
            finC:SetPoint("TOP", bar, "BOTTOM", f.cx or 0, -(below + 8))
            DrawSlot(finC.slot, finC, "cb", cs, 0, 0)
        end
        if has.totems and ns.Totems then
            local t = ns.Totems.Settings() or ns.TOTEM_DEFAULTS
            local s, gap = t.size or 16, t.gap or 2
            tot:ClearAllPoints(); tot:SetSize(1.5 * s, 4 * s + 3 * gap)
            tot:SetPoint("RIGHT", bar, "LEFT", t.x or 0, t.y or 0)
            for i, o in ipairs(ns.Totems.Offsets(s, gap, 4)) do
                local b = tot.boxes[i]
                b.edge:ClearAllPoints(); b.edge:SetSize(s + 2, s + 2); b.edge:SetPoint("CENTER", tot, "RIGHT", o.x, o.y)
                b.icon:ClearAllPoints(); b.icon:SetSize(s, s); b.icon:SetPoint("CENTER", tot, "RIGHT", o.x, o.y)
                b.icon:SetShown(not b.empty)
                if b.empty then b.edge:SetVertexColor(0.07, 0.07, 0.08, 0.9) end
                -- the sample's countdown: the used share darkened, from the top down (the game sweeps it round)
                b.dark:ClearAllPoints(); b.dark:SetSize(s, math.max(0.01, s * b.used))
                b.dark:SetPoint("TOP", tot, "RIGHT", o.x, o.y + s / 2)
                b.dark:SetShown(not b.empty and b.used > 0)
            end
            local on = t.shield ~= false
            local total = 2 * s + 3 * gap - 4
            local sg = math.max(1, s * 1.5 / 16)
            local sh = (total - 2 * sg) / 3
            for i, seg in ipairs(tot.segs) do
                seg:ClearAllPoints(); seg:SetSize(math.max(3, s * 6 / 16), sh)
                seg:SetPoint("TOP", tot, "RIGHT", -s / 4, total / 2 - (i - 1) * (sh + sg))
                seg:SetShown(on)
            end
        end
        if has.crescent then
            local kk = (z.size or 46) / 46
            cres:ClearAllPoints(); cres:SetSize(32 * kk, 64 * kk)
            cres:SetPoint("RIGHT", bar, "LEFT", z.x or 0, z.y or 0)
            local c = z.colors and z.colors.shoot or { 0.2, 0.85, 0.3 }
            cres.fill:SetVertexColor(c[1], c[2], c[3], 1)
        end

        -- selection frame and grip follow the selected part
        local s = el[selected]
        if not s or not s:IsShown() then sel:Hide(); grip:Hide(); return end
        sel:ClearAllPoints(); sel:SetPoint("TOPLEFT", s, "TOPLEFT", -3, 3); sel:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 3, -3); sel:Show()
        grip:SetShown(PARTS[selected].resize ~= nil)
        grip:ClearAllPoints()
        -- parts left of the bar grow leftward, so their grip is on the left corner
        -- the outer corner: the left side's icons grow leftward, the right side's rightward
        if PARTS[selected].set and not PARTS[selected].rightSide then grip:SetPoint("CENTER", sel, "BOTTOMLEFT", 0, 0)
        else grip:SetPoint("CENTER", sel, "BOTTOMRIGHT", 0, 0) end
    end
    panel.Redraw = Redraw

    -- the other controls change settings without telling the sample: it keeps itself current
    local acc = 0
    box:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + (elapsed or 0)
        if acc >= 0.1 then acc = 0; Redraw() end
    end)

    W.Note(panel, "Click a part to see its settings; click a skill icon to choose its skill. Drag a part to move it; "
        .. "drag the white square to resize.", C1, -258, 486)

    -- whole-plate numbers, under the sample --------------------------------
    local function PSlider(parent, x, label, key, lo, hi, step, fmt, y)
        return parent:Add(W.Slider(parent, label, lo, hi, step,
            function() return P()[key] end,
            function(v) P()[key] = v; PlatesChanged() end, fmt, CW), x, y)
    end
    PSlider(panel, C1, "Overall size", "scale", 0.5, 1.5, 0.05, W.percent, -284)
    PSlider(panel, C2, "Target size", "targetScale", 1, 2, 0.05, W.percent, -284)
    PSlider(panel, C1, "Other plates opacity", "dimAlpha", 0.3, 1, 0.05, W.percent, -328)
    PSlider(panel, C2, "Plate position, left/right", "x", -100, 100, 1, W.signed, -328)
    PSlider(panel, C2, "Plate position, up/down", "y", -60, 60, 1, W.signed, -372)
    panel:Add(W.Button(panel, "Reset plates", 108, function()
        ns.Plates.Reset()
        panel:SyncAll()
    end), C1, -384)
    panel:Add(W.Button(panel, "Debug to chat", 108, function()
        ns.Plates.Debug(function(m) print(m) end)
    end), C1 + 112, -384).tooltip = "Prints what the game gave us for the plates in view: useful if something looks wrong."

    -- right column: the selected part ---------------------------------------
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", C3, -12)
    panel.partTitle = title

    -- the class parts come from Options.lua, unchanged
    local ShowSub = ns.NameplateOptions.BuildSubs(panel, C3, CW)

    local function Sub(key)
        local f = CreateFrame("Frame", nil, panel)
        f:SetAllPoints(panel)
        panel.subs[key] = W.Panel(f)
        return panel.subs[key]
    end
    local function Check(sub, label, key, y, tip)
        local c = sub:Add(W.Check(sub, label,
            function() return P()[key] ~= false and P()[key] ~= nil end,
            function(v) P()[key] = v; PlatesChanged() end, CW), C3, y)
        if tip then c.tooltip = tip end
        return c
    end
    local function Swatch(sub, label, get, set, y)
        return sub:Add(W.Swatch(sub, label, get, function(r, g, b) set(r, g, b); PlatesChanged() end), C3, y)
    end
    local function ColorKey(sub, label, key, y)
        return Swatch(sub, label,
            function() local c = P()[key] or { 1, 1, 1 }; return c[1], c[2], c[3] end,
            function(r, g, b) P()[key] = { r, g, b } end, y)
    end

    local s = Sub("bar")
    PSlider(s, C3, "Width", "width", 100, 400, 1, W.px, -38)
    PSlider(s, C3, "Height", "height", 14, 60, 1, W.px, -82)
    PSlider(s, C3, "Text size", "fontSize", 8, 16, 1, W.px, -126)
    for i, entry in ipairs({ { "melee", "Melee" }, { "caster", "Casters" }, { "boss", "Bosses" }, { "neutral", "Neutral" } }) do
        local key = entry[1]
        Swatch(s, entry[2],
            function() local c = P().colors and P().colors[key] or { 1, 1, 1 }; return c[1], c[2], c[3] end,
            function(r, g, b) P().colors = P().colors or {}; P().colors[key] = { r, g, b } end, -174 - (i - 1) * 26)
    end
    Check(s, "Class colours for enemy players", "classColors", -280)
    Check(s, "Red when the mob is on you", "aggro", -304,
        "Red while the mob has you as its target. If you tank, that is every mob you hold.")
    Check(s, "Flash three times when it gets on you", "aggroFlash", -328)
    ColorKey(s, "Aggro colour", "aggroColor", -354)

    s = Sub("level")
    PSlider(s, C3, "Width", "levelWidth", 20, 60, 1, W.px, -38)
    PSlider(s, C3, "Gap to the bar", "levelGap", 0, 20, 1, W.px, -82)
    W.Note(s, "At 0 the box reaches back under the bar, so the bar sits on top of it.", C3, -130, CW)
    Check(s, "Colour the level by difficulty", "levelColors", -164,
        "Red: 5 or more levels above you (and ??). Orange: 3-4 above. Yellow: within 2. Green: lower, still "
        .. "gives experience. White: gives no experience.")
    do -- the same switch as at the top (Berry Mode keeps its own)
        local c = s:Add(W.Check(s, "GCD meter on your target", function() return ns.Plates.GcdOn() end,
            function(v) ns.Plates.SetGcdOn(v); PlatesChanged() end, CW), C3, -188)
        c.tooltip = "A white line rises across your target's health bar while your global cooldown runs, with steam "
            .. "trailing under it. Hidden between GCDs. Berry Mode keeps its own on / off for this."
    end
    Check(s, "Elite dragon by the name", "eliteIcon", -212,
        "The game's elite dragon left of the mob's name, which moves right to make room: gold for elites "
        .. "and bosses, silver for rares and rare elites.")

    s = Sub("cast")
    Check(s, "Show cast bars", "cast", -38)
    PSlider(s, C3, "Height", "castHeight", 10, 40, 1, W.px, -66)
    PSlider(s, C3, "Gap under the bar", "castGap", 0, 12, 1, W.px, -110)
    ColorKey(s, "Cast colour", "castColor", -158)
    ColorKey(s, "Cast aimed at you", "castMeColor", -184)
    W.Note(s, "Blizzard's crowd-control icon sits on the right end of the cast bar, cast or no cast. "
        .. "It is Blizzard's own, so its size cannot be changed here.", C3, -216, CW)

    s = Sub("debuffs")
    Check(s, "Show them above the bar", "auras", -38, "Your own debuffs on the unit, left-aligned above the health bar.")
    PSlider(s, C3, "Icon size", "auraSize", 12, 40, 1, W.px, -66)
    PSlider(s, C3, "Most shown", "auraMax", 1, 12, 1, function(v) return ("%d"):format(v) end, -110)
    Check(s, "Blink for the last seconds", "blink", -156)
    PSlider(s, C3, "Blink during the last", "blinkSeconds", 1, 8, 1, function(v) return ("%d s"):format(v) end, -180)
    Check(s, "Hide Blizzard's own aura rows", "hideBlizzAuras", -226)
    PSlider(s, C3, "Blizzard's row, left/right", "debuffX", -150, 150, 1, W.signed, -254)
    W.Note(s, "While the game keeps debuffs secret from addons (in combat), Blizzard's own debuff row "
        .. "stands in at the same place. Size, count and blinking only apply when SKTools can draw them.", C3, -302, CW)

    s = Sub("swing")
    Check(s, "Show on your target", "swing", -38,
        "A pip travels along the strip with each swing. Melee runs left to right; ranged runs right to left.")
    PSlider(s, C3, "Thickness", "swingHeight", 2, 10, 1, W.px, -66)
    ColorKey(s, "Strip colour", "swingColor", -114)
    PSlider(s, C3, "Strip opacity", "swingAlpha", 0.1, 1, 0.05, W.percent, -142)
    ColorKey(s, "Ranged: stand-still zone", "swingRed", -190)
    PSlider(s, C3, "Stand-still time", "swingWindow", 0.2, 1, 0.05, function(v) return ("%.2f s"):format(v) end, -218)
    W.Note(s, "Shown while you fight your target. A Hunter's strip switches between bow and main hand "
        .. "as the target moves between shooting range and melee range. Off-hand swings are not shown.", C3, -266, CW)

    -- the right-hand icons: position, and resetting the icon choices
    local function FSlider(sub, label, key, lo, hi, y)
        return sub:Add(W.Slider(sub, label, lo, hi, 1,
            function() return F()[key] or 0 end,
            function(v) F()[key] = v; ns.Feral.Refresh() end, W.signed, CW), C3, y)
    end
    local function IconNote(sub, y)
        W.Note(sub, "Click an icon on the sample to choose its skill from your spell book, or empty it. "
            .. "Each set (Cat Form, Bear Form, Hunter) keeps its own choices. On the plates, two filled "
            .. "slots sit where the two-icon stack always did and one sits on the centre line; in this "
            .. "editor every slot is shown, and the big icons stand beside their stacks so all three "
            .. "small ones can be seen.", C3, y, CW)
    end
    local function ResetIcons(sub, y)
        sub:Add(W.Button(sub, "Reset this set's icons", 160, function()
            local set = CurrentSet()
            if set then ns.Feral.Slots.Reset(set.key) end
            Redraw()
        end), C3, y).tooltip = "Empties every icon slot of the set shown."
    end
    -- the totem timers
    local function TotemsDB() return ns.Totems.Settings() or {} end
    s = Sub("totems")
    s:Add(W.Check(s, "Show on your target",
        function() return TotemsDB().enabled ~= false end,
        function(v) TotemsDB().enabled = v; ns.Totems.Refresh() end, CW), C3, -38)
    local function TSlider(label, key, lo, hi, fmt, y)
        return s:Add(W.Slider(s, label, lo, hi, 1,
            function() return TotemsDB()[key] or ns.TOTEM_DEFAULTS[key] end,
            function(v) TotemsDB()[key] = v; ns.Totems.Refresh(); ns.Feral.Refresh() end, fmt, CW), C3, y)
    end
    s:Add(W.Check(s, "Lightning Shield charges",
        function() return TotemsDB().shield ~= false end,
        function(v) TotemsDB().shield = v; ns.Totems.Refresh(); Redraw() end, CW), C3, -60)
    local hc = s:Add(W.Check(s, "Hide its Cooldown Manager icon",
        function() return TotemsDB().hideCdm ~= false end,
        function(v) TotemsDB().hideCdm = v; ns.Totems.Refresh() end, CW), C3, -82)
    hc.tooltip = "With Lightning Shield among the Cooldown Manager's Tracked Buffs, its charges are read from "
        .. "there (they stay readable in combat). This makes Blizzard's own icon for it invisible."
    TSlider("Box size", "size", 10, 28, W.px, -110)
    TSlider("Horizontal", "x", -60, 60, W.signed, -154)
    TSlider("Vertical", "y", -40, 40, W.signed, -198)
    W.Note(s, "Earth, Fire, Water and Air from top to bottom, each the totem you have down, with a dark "
        .. "sweep eating it clockwise as it runs out. Only the totems down show: one sits on the bar's "
        .. "centre line, two either side of it, three as one on it with one above and below, four as "
        .. "shown here. The blue bars by the health bar are your Lightning Shield's charges, going dark "
        .. "from the top as they are used. Add Lightning Shield to the Cooldown Manager's Tracked Buffs "
        .. "for an exact count in combat.", C3, -242, CW)
    s:Add(W.Button(s, "Reset totem timers", 150, function()
        ns.Totems.Reset(); panel.subs.totems:SyncAll(); Redraw()
    end), C3, -370)

    s = Sub("feralR")
    FSlider(s, "Horizontal", "rx", -80, 80, -38)
    FSlider(s, "Vertical", "ry", -60, 60, -82)
    s:Add(W.Slider(s, "Icon size", 14, 48, 1,
        function() return F().rsize or F().size or 19 end,
        function(v) F().rsize = v; ns.Feral.Refresh() end, W.px, CW), C3, -126).tooltip =
        "The right side's icons (and its big icon with them). Until you change it, the same as the left side's."
    IconNote(s, -174)
    ResetIcons(s, -280)
    s = Sub("finisherR")
    FSlider(s, "Horizontal", "rfx", -80, 80, -38)
    FSlider(s, "Vertical", "rfy", -60, 60, -82)
    W.Note(s, "Shown while its skill is usable, your target is in range and it is off cooldown. "
        .. "Click it on the sample to choose the skill.", C3, -130, CW)
    ResetIcons(s, -180)

    s = Sub("finisherC")
    FSlider(s, "Horizontal", "cx", -80, 80, -38)
    FSlider(s, "Vertical", "cy", -40, 40, -82)
    W.Note(s, "In the game it stands over the middle of the health bar: square, one and a half times the bar's "
        .. "height, centred on the bar so it overhangs equally above and below. Here it is drawn under the sample, out of the way. "
        .. "It can hold a skill, or the set's own big-icon rule (Ferocious Bite / Shifting Power; Primal Bite). "
        .. "Shown while its skill is usable, your target is in range and it is off cooldown; click it on the "
        .. "sample to choose the skill.", C3, -130, CW)
    ResetIcons(s, -230)

    s = Sub("quest")
    local MC = ns.NameplateOptions.MarkCheck
    local MS = ns.NameplateOptions.MarkSlider
    s:Add(MC(s, "Kill and loot counters",
        function() return mdb().counters end, function(v) mdb().counters = v end), C3, -38)
    s:Add(MC(s, "Quest-starter icon",
        function() return mdb().show.starter end, function(v) mdb().show.starter = v end), C3, -62)
    s:Add(MC(s, "...include rare world drops",
        function() return mdb().starterWide end, function(v) mdb().starterWide = v end), C3 + 14, -86)
    s:Add(MC(s, "Glow on rare mobs",
        function() return mdb().glow end, function(v) mdb().glow = v end), C3, -112)
    s:Add(MC(s, "Pulse",
        function() return mdb().glowPulse end, function(v) mdb().glowPulse = v end), C3 + 14, -136)
    W.Header(s, "On Blizzard's plates (friendly NPCs)", C3, -168, CW)
    s:Add(MS(s, "Quest icon size",
        function() return mdb().iconSize end, function(v) mdb().iconSize = v end, 10, 48, 1, W.px), C3, -194)
    s:Add(MS(s, "Quest icon, left/right",
        function() return mdb().iconX end, function(v) mdb().iconX = v end, -150, 150, 1, W.signed), C3, -238)
    s:Add(MS(s, "Quest icon, up/down",
        function() return mdb().iconY end, function(v) mdb().iconY = v end, -60, 60, 1, W.signed), C3, -282)
    local test = s:Add(W.Check(s, "Test mode: mark every nameplate",
        function() return M.manualTest end,
        function(v) M.manualTest = v and true or false; M.RefreshAll() end, CW), C3, -330)
    test.tooltip = "Shows every icon, the counters and the glow on all nameplates until you turn it off."
    s:Add(W.Button(s, "Reset quest marks", 140, function()
        M.ResetSettings()
        panel.subs.quest:SyncAll()
        M.RefreshAll()
    end), C3, -358)

    function Select(key)
        if not PARTS[key] or not panel.subs[key] then return end
        selected = key
        panel.selected = key
        title:SetText(PartTitle(key))
        ShowSub(key)
        Redraw()
    end
    panel.Select = Select

    function panel:OnSync()
        -- a class part of a set that is not on the sample falls back to the bar
        if self.SyncSubDrop then self.SyncSubDrop() end
        Redraw()
        local key = self.selected or "bar"
        if PARTS[key].set and not el[key]:IsShown() then key = "bar" end
        Select(key)
    end
end

ns.RegisterTab({
    key = "nameplate", title = "Nameplates", order = 2, Build = Build,
    OnShow = function(panel)
        M.previewing = true
        M.RefreshAll()
        if panel.Select then panel.Select(panel.selected or "bar") end
    end,
    OnHide = function()
        M.previewing = false
        M.RefreshAll()
        ns.Combo.Preview(false)
        ns.Crescent.Preview(false)
        if ns.Totems then ns.Totems.Preview(false) end
        ns.Feral.Preview(false)
    end,
})
