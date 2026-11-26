-- SKTools - Profession DB window (/skt map, the button on the world map, or a
-- right-click on the minimap button). Built from plain frames and colour
-- textures so it doesn't depend on Blizzard templates that move around.
--
-- It is the world map's companion: opened while the map is up it sits beside
-- the map in a narrow layout (list, then details in the same column) and
-- closes and re-opens with the map. Opened on its own it is the full
-- two-column window. The ">>" / "<<" button switches layout either way.
-- Its settings are on the Profession DB tab of the SKTools window.

local ADDON, ns = ...
local DB = SKToolsProfessionDB

local UI = {}
DB.UI = UI

local TW = ns.W               -- shared classic-style widgets and window chrome
local PAD = 14                -- clear of the stone border
local LIST_W = 330
local W, H = LIST_W + 480 + 2 * PAD, 528
local CW = LIST_W + 2 * PAD   -- width of the narrow layout
local ROW_H = 18
-- detail columns, as offsets from the row icon: wide and narrow layout
local COLS = {
    wide    = { w1 = 150, x2 = 158, w2 = 52, x3 = 212, w3 = 54, x4 = 266, w4 = 40, x5 = 312 },
    compact = { w1 = 128, x2 = 136, w2 = 48, x3 = 186, w3 = 50, x4 = 238, w4 = 40 },
}
local GOLD = { 1, 0.82, 0 }
local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"


----------------------------------------------------------------------
-- Small widgets
----------------------------------------------------------------------

local function Fill(frame, r, g, b, a, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(r, g, b, a)
    return t
end

local function Border(frame, r, g, b, a)
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(r, g, b, a)
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT"); t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side); t:SetWidth(1)
        end
    end
end

local function Text(parent, font, justify)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- red panel button; :SetActive(true) marks the chosen one of a group
local function Button(parent, label, w, h, onClick)
    return TW.Button(parent, label, w, onClick, h)
end

-- horizontal slider with label and value read-out
local function Slider(parent, label, min, max, step, width, get, set, fmt)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(width, 28)
    local title = Text(c, "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT"); title:SetText(label)
    local value = Text(c, "GameFontNormalSmall", "RIGHT")
    value:SetPoint("TOPRIGHT")
    local s = CreateFrame("Slider", nil, c)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("BOTTOMLEFT", 0, 0); s:SetPoint("BOTTOMRIGHT", 0, 0)
    s:SetHeight(15)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:EnableMouseWheel(true)
    TW.SkinSlider(s)
    local function show(v) value:SetText(string.format(fmt or "%d", math.floor(v + 0.5))) end
    s:SetScript("OnValueChanged", function(_, v, user)
        v = math.floor(v / step + 0.5) * step
        show(v)
        if user then set(v) end
    end)
    s:SetScript("OnMouseWheel", function(self, d)
        local v = math.max(min, math.min(max, self:GetValue() + d * step))
        self:SetValue(v); set(v)
    end)
    function c:Update() s:SetValue(get()); show(get()) end
    c.slider = s
    c:Update()
    return c
end

-- virtual scrolling list: only as many row frames as fit, re-used on scroll
local function List(parent, width, height, rowH, makeRow, setRow)
    local l = CreateFrame("Frame", nil, parent)
    l:SetSize(width, height)
    TW.Skin(l, "inset")
    l.data, l.offset, l.rows = {}, 0, {}
    l.visible = math.floor((height - 10) / rowH)
    for i = 1, l.visible do
        local r = makeRow(l, width - 20, rowH)
        r:SetPoint("TOPLEFT", 5, -5 - (i - 1) * rowH)
        l.rows[i] = r
    end
    local bar = CreateFrame("Slider", nil, l)
    bar:SetOrientation("VERTICAL")
    bar:SetPoint("TOPRIGHT", -5, -5); bar:SetPoint("BOTTOMRIGHT", -5, 5)
    bar:SetWidth(8)
    bar:SetValueStep(1); bar:SetObeyStepOnDrag(true)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(); track:SetColorTexture(0.008, 0.016, 0.05, 0.8)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(0.75, 0.62, 0.38, 1); thumb:SetSize(8, 30)
    bar:SetThumbTexture(thumb)
    bar:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
        if v ~= l.offset then l.offset = v; l:Draw() end
    end)
    l.bar = bar
    l:EnableMouseWheel(true)
    l:SetScript("OnMouseWheel", function(_, d)
        local maxOff = math.max(0, #l.data - l.visible)
        local v = math.max(0, math.min(maxOff, l.offset - d * 3))
        bar:SetValue(v)
    end)
    function l:Draw()
        for i = 1, self.visible do
            local d = self.data[i + self.offset]
            local r = self.rows[i]
            if d then setRow(r, d); r:Show() else r:Hide() end
        end
    end
    function l:SetData(data, keepOffset)
        self.data = data
        local maxOff = math.max(0, #data - self.visible)
        if not keepOffset then self.offset = 0 end
        self.offset = math.min(self.offset, maxOff)
        bar:SetMinMaxValues(0, maxOff)
        bar:SetValue(self.offset)
        bar:SetShown(maxOff > 0)
        self:Draw()
    end
    return l
end

----------------------------------------------------------------------
-- Left list rows (headers, items, mobs)
----------------------------------------------------------------------

local function MakeMainRow(list, w, h)
    local r = CreateFrame("Button", nil, list)
    r:SetSize(w, h)
    r.sel = Fill(r, GOLD[1], GOLD[2], GOLD[3], 0.18)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.07)

    r.track = CreateFrame("Button", nil, r)
    r.track:SetSize(12, 12)
    r.track:SetPoint("LEFT", 3, 0)
    Fill(r.track, 0.008, 0.016, 0.05, 1)
    Border(r.track, 0.45, 0.45, 0.5, 1)
    r.track.check = r.track:CreateTexture(nil, "OVERLAY")
    r.track.check:SetTexture(CHECK); r.track.check:SetPoint("CENTER"); r.track.check:SetSize(16, 16)
    r.track:SetScript("OnClick", function(self) UI:ToggleTrack(self:GetParent().data) end)
    r.track:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("Show on map"); GameTooltip:Show()
    end)
    r.track:SetScript("OnLeave", function() GameTooltip:Hide() end)

    r.expand = Text(r, "GameFontNormal")
    r.expand:SetPoint("LEFT", 4, 0); r.expand:SetWidth(12)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(h - 2, h - 2)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = Text(r, "GameFontHighlightSmall")
    r.right = Text(r, "GameFontDisableSmall", "RIGHT")
    r.right:SetPoint("RIGHT", -4, 0)
    r.name:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
    r:SetScript("OnClick", function(self) UI:ClickRow(self.data) end)
    return r
end

local function SetMainRow(r, d)
    r.data = d
    local module = DB:CurrentModule()
    r.sel:SetShown(UI.selected and d.kind == UI.selected.kind and d.id == UI.selected.id)
    r.icon:ClearAllPoints()
    if d.kind == "header" then
        r.track:Hide(); r.expand:Show()
        r.expand:SetText(d.collapsed and "+" or "-")
        r.icon:SetPoint("LEFT", 18, 0)
        r.icon:SetTexture(d.icon or 134400); r.icon:SetShown(d.icon ~= nil)
        r.name:SetPoint("LEFT", d.icon and 38 or 18, 0)
        r.name:SetFontObject("GameFontNormalSmall")
        r.name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        r.name:SetText(d.label)
        r.right:SetText(d.count)
        return
    end
    r.track:Show(); r.expand:Hide(); r.icon:Show()
    r.icon:SetPoint("LEFT", 20, 0)
    r.name:SetPoint("LEFT", 40, 0)
    r.name:SetFontObject("GameFontHighlightSmall")
    if d.kind == "item" then
        local item = module.items[d.id]
        local q = DB.QUALITY[item.q or 1] or DB.QUALITY[1]
        r.icon:SetTexture(DB:ItemIcon(d.id))
        r.name:SetText(item.n)
        r.name:SetTextColor(q[1], q[2], q[3])
        r.track.check:SetShown(DB:IsItemTracked(module, d.id))
        if item.w then
            r.right:SetText("world drop")
        else
            local n = 0
            for _, s in ipairs(item.src) do if DB:SourceVisible(s[2], s[3]) then n = n + 1 end end
            r.right:SetText(n .. (n == 1 and " source" or " sources"))
        end
    else
        local mob = DB.mobs[d.id]
        local items = DB:GetMobItems(module, d.id)
        local best = items[1]
        r.icon:SetTexture(best and best[2] ~= "V" and DB:ItemIcon(best[1]) or "Interface\\GossipFrame\\VendorGossipIcon")
        r.name:SetText(mob.n)
        local dim = best and best[2] ~= "V" and best[3] < DB.db.minChance
        if dim then r.name:SetTextColor(0.5, 0.5, 0.5)
        elseif mob.r and mob.r > 0 then r.name:SetTextColor(1, 0.82, 0)
        else r.name:SetTextColor(1, 1, 1) end
        r.track.check:SetShown(DB:IsMobTracked(d.id))
        r.right:SetText(mob.t and "vendor" or ("lvl " .. DB:FormatLevel(mob)))
    end
end

----------------------------------------------------------------------
-- Detail rows (sources of an item, or items of a mob)
----------------------------------------------------------------------

local function MakeDetailRow(list, w, h, cols)
    cols = cols or COLS.wide
    local r = CreateFrame("Button", nil, list)
    r:SetSize(w, h)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.07)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(h - 2, h - 2); r.icon:SetPoint("LEFT", 2, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.c1 = Text(r); r.c1:SetPoint("LEFT", h + 4, 0); r.c1:SetWidth(cols.w1)
    r.c2 = Text(r); r.c2:SetPoint("LEFT", h + cols.x2, 0); r.c2:SetWidth(cols.w2)
    r.c3 = Text(r); r.c3:SetPoint("LEFT", h + cols.x3, 0); r.c3:SetWidth(cols.w3)
    r.c4 = Text(r, nil, "RIGHT"); r.c4:SetPoint("LEFT", h + cols.x4, 0); r.c4:SetWidth(cols.w4)
    if cols.x5 then       -- the narrow layout has no room for the "where" column
        r.c5 = Text(r, "GameFontDisableSmall"); r.c5:SetPoint("LEFT", h + cols.x5, 0); r.c5:SetPoint("RIGHT", -2, 0)
    end
    r:SetScript("OnClick", function(self)
        if self.data.npc then UI:ShowMob(self.data.npc, true) else UI:ShowItem(self.data.item, true) end
    end)
    r:SetScript("OnEnter", function(self)
        local d = self.data
        if d.npc then
            local mob = DB.mobs[d.npc]
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(mob.n)
            GameTooltip:AddLine(DB:MobZones(mob), 1, 1, 1, true)
            if mob.dg then GameTooltip:AddLine("Inside " .. mob.dg, 1, 0.5, 0.25) end
            GameTooltip:AddLine("Click for details", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        elseif d.item then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(d.item)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function SetDetailRow(r, d)
    r.data = d
    local module = DB:CurrentModule()
    local k = DB.KIND[d.src]
    local visible = DB:SourceVisible(d.src, d.chance)
    local a = visible and 1 or 0.45
    if d.npc then
        local mob = DB.mobs[d.npc]
        r.icon:SetTexture(d.src == "V" and "Interface\\GossipFrame\\VendorGossipIcon" or DB:ItemIcon(UI.selected.id))
        r.c1:SetText(mob.n)
        if mob.r and mob.r > 0 then r.c1:SetTextColor(1, 0.82, 0, a) else r.c1:SetTextColor(1, 1, 1, a) end
        r.c2:SetText(DB:FormatLevel(mob))
        if r.c5 then r.c5:SetText(mob.dg and (mob.dg .. " (dungeon)") or DB:MobZones(mob)) end
    else
        local item = module.items[d.item]
        local q = DB.QUALITY[item.q or 1] or DB.QUALITY[1]
        r.icon:SetTexture(DB:ItemIcon(d.item))
        r.c1:SetText(item.n)
        r.c1:SetTextColor(q[1], q[2], q[3], a)
        r.c2:SetText("")
        if r.c5 then r.c5:SetText(item.c) end
    end
    r.c2:SetTextColor(0.8, 0.8, 0.8, a)
    r.c3:SetText(k.label)
    r.c3:SetTextColor(k.color[1], k.color[2], k.color[3], a)
    r.c4:SetText(DB:FormatChance(d.src, d.chance))
    r.c4:SetTextColor(1, 1, 1, a)
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------

function UI:Build()
    if self.frame then return end
    local f = CreateFrame("Frame", "SKToolsDBFrame", UIParent)
    self.frame = f
    f:SetSize(W, H)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        -- beside the map and on its own are remembered separately
        if UI.onMap then DB.db.mapPoint = { p, rp, x, y } else DB.db.point = { p, rp, x, y } end
    end)
    TW.Skin(f, "dialog")
    tinsert(UISpecialFrames, "SKToolsDBFrame")

    -- the SKTools bee, then the title
    local logo = TW.Logo(f, 26, true)
    logo:SetPoint("TOPLEFT", PAD - 2, -8)
    local title = Text(f, "GameFontNormal")
    title:SetPoint("LEFT", logo, "RIGHT", 4, -1)
    title:SetText("Profession DB")
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    self.title = title

    local close = TW.CloseButton(f, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -5, -5)

    -- switch between the narrow layout and the full two-column one
    self.layoutBtn = Button(f, ">>", 24, 20, function()
        local key = UI.onMap and "compactMap" or "compactAlone"
        DB.db[key] = not DB.db[key]
        UI:ApplyLayout()
        UI:Place()
        UI:Refresh(true)
    end)
    self.layoutBtn:SetPoint("RIGHT", close, "LEFT", 0, 0)
    self.layoutBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(UI:IsCompact() and "Wide view: list and details side by side"
            or "Narrow view: details replace the list", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.layoutBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- module tabs (one per data module)
    self.moduleTabs = {}

    -- mode buttons
    self.modeItems = Button(f, "Materials", 80, 20, function() UI:SetMode("items") end)
    self.modeItems:SetPoint("TOPLEFT", PAD, -38)
    self.modeMobs = Button(f, "Mobs", 80, 20, function() UI:SetMode("mobs") end)
    self.modeMobs:SetPoint("LEFT", self.modeItems, "RIGHT", 4, 0)

    -- search box
    local sb = CreateFrame("EditBox", nil, f)
    sb:SetSize(LIST_W - 172, 20)
    sb:SetPoint("LEFT", self.modeMobs, "RIGHT", 8, 0)
    sb:SetAutoFocus(false)
    sb:SetFontObject("ChatFontSmall")
    sb:SetTextInsets(6, 18, 0, 0)
    TW.Skin(sb, "inset")
    sb.hint = Text(sb, "GameFontDisableSmall")
    sb.hint:SetPoint("LEFT", 6, 0)
    sb:SetScript("OnEscapePressed", sb.ClearFocus)
    sb:SetScript("OnEnterPressed", sb.ClearFocus)
    sb:SetScript("OnTextChanged", function(self, userInput)
        self.hint:SetShown(self:GetText() == "")
        -- narrow layout: typing a search goes back from the details to the list
        if userInput and UI:IsCompact() and UI.selected then
            UI.selected = nil
            wipe(UI.history)
            UI:Refresh(true)
        else
            UI:BuildList()
        end
    end)
    local clr = CreateFrame("Button", nil, sb)
    clr:SetSize(16, 16); clr:SetPoint("RIGHT", -2, 0)
    clr.t = Text(clr, "GameFontDisableSmall", "CENTER"); clr.t:SetPoint("CENTER"); clr.t:SetText("x")
    clr:SetScript("OnClick", function() sb:SetText(""); sb:ClearFocus() end)
    self.search = sb

    -- left list
    self.list = List(f, LIST_W, H - 112, ROW_H, MakeMainRow, SetMainRow)
    self.list:SetPoint("TOPLEFT", PAD, -64)

    -- detail panel (beside the list when wide, in place of it when narrow)
    local d = CreateFrame("Frame", nil, f)
    self.detail = d

    d.empty = Text(d, "GameFontDisable", "CENTER")
    d.empty:SetPoint("CENTER", 0, 20)
    d.empty:SetWidth(360)
    d.empty:SetWordWrap(true)
    d.empty:SetText("Pick a material or mob on the left.\n\nTick the box beside it (or use Show on map) to put its locations on your world map and minimap.")

    d.back = Button(d, "< Back", 56, 18, function() UI:Back() end)
    d.back:SetPoint("TOPLEFT", 0, 0)

    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(36, 36)
    d.icon:SetPoint("TOPLEFT", 0, -24)
    d.name = Text(d, "GameFontNormalLarge")
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 8, -1)
    d.name:SetPoint("RIGHT", d, "RIGHT", -120, 0)
    d.sub = Text(d, "GameFontHighlightSmall")
    d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)
    d.sub:SetPoint("RIGHT", d, "RIGHT", -4, 0)
    d.sub2 = Text(d, "GameFontDisableSmall")
    d.sub2:SetPoint("TOPLEFT", d.icon, "BOTTOMLEFT", 0, -6)
    d.sub2:SetPoint("RIGHT", d, "RIGHT", -4, 0)

    d.track = Button(d, "Show on map", 110, 22, function() UI:ToggleTrack(UI.selected) end)
    d.track:SetPoint("TOPRIGHT", 0, -24)

    -- column headers and the source list, once per layout
    local function DetailTable(cols, width)
        local t = {}
        local hdr = CreateFrame("Frame", nil, d)
        hdr:SetSize(10, 14)
        hdr:SetPoint("TOPLEFT", 0, -96)
        hdr:SetPoint("RIGHT", d, "RIGHT")
        local function col(x, label, w, j)
            local fs = Text(hdr, "GameFontNormalSmall", j)
            fs:SetPoint("LEFT", x, 0); fs:SetWidth(w); fs:SetText(label)
            return fs
        end
        local h = 16
        t.h1 = col(h + 6, "Mob", cols.w1)
        t.h2 = col(h + cols.x2 + 2, "Level", cols.w2)
        t.h3 = col(h + cols.x3 + 2, "Source", cols.w3)
        t.h4 = col(h + cols.x4 + 2, "Chance", cols.w4, "RIGHT")
        if cols.x5 then t.h5 = col(h + cols.x5 + 2, "Where", 100) end
        t.hdr = hdr
        t.list = List(d, width, H - 112 - 112, 16,
            function(l, w, rh) return MakeDetailRow(l, w, rh, cols) end, SetDetailRow)
        t.list:SetPoint("TOPLEFT", 0, -112)
        return t
    end
    d.wide = DetailTable(COLS.wide, W - LIST_W - 10 - 2 * PAD)
    d.compact = DetailTable(COLS.compact, LIST_W)

    -- bottom bar
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("BOTTOMLEFT", PAD, 14)
    bar:SetPoint("BOTTOMRIGHT", -PAD, 14)
    bar:SetHeight(30)
    self.bar = bar

    self.chance = Slider(bar, "Min. chance on map", 0, 50, 1, 150,
        function() return DB.db.minChance end,
        function(v) DB.db.minChance = v; DB:RefreshPins(); ns.RefreshSettings() end, "%d%%")
    self.chance:SetPoint("LEFT", 0, 0)

    -- pin and window settings live on the Profession DB tab of the settings window
    local settings = Button(bar, "Settings", 64, 20, function() ns.OpenSettings("db") end)
    settings:SetPoint("LEFT", self.chance, "RIGHT", 10, -2)

    local clear = Button(bar, "Clear map", 80, 20, function() DB:ClearTracked() end)
    clear:SetPoint("RIGHT", 0, -2)
    self.status = Text(bar, "GameFontDisableSmall", "RIGHT")
    self.status:SetPoint("RIGHT", clear, "LEFT", -8, 0)

    self.history = {}
    f:Hide()
    f:SetScript("OnShow", function() UI:Refresh(true); UI:UpdateMapButton() end)
    f:SetScript("OnHide", function() UI.wasAlone = nil; UI:UpdateMapButton() end)
    self:ApplyLayout()
    self:Place()
end

----------------------------------------------------------------------
-- Layout (wide / narrow) and position (on its own / beside the world map)
----------------------------------------------------------------------

function UI:MapShown()
    return WorldMapFrame and WorldMapFrame:IsShown() or false
end

function UI:IsCompact()
    if self.onMap then return DB.db.compactMap and true or false end
    return DB.db.compactAlone and true or false
end

function UI:ApplyLayout()
    local f, d = self.frame, self.detail
    if not f then return end
    local compact = self:IsCompact()
    f:SetWidth(compact and CW or W)
    d:ClearAllPoints()
    if compact then
        d:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, 0)
        d:SetPoint("BOTTOMRIGHT", self.list, "BOTTOMRIGHT", 0, 0)
    else
        d:SetPoint("TOPLEFT", self.list, "TOPRIGHT", 10, 0)
        d:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 48)
    end
    self.title:SetText(compact and "DB" or "Profession DB")
    self.layoutBtn.text:SetText(compact and ">>" or "<<")
    self.status:SetShown(not compact)
end

-- the strata one step above another frame's, so we draw over it
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }
local function StrataAbove(frame, atLeast)
    local cur = frame and frame.GetFrameStrata and frame:GetFrameStrata()
    local want = 1
    for i, name in ipairs(STRATA) do
        if name == cur then want = math.min(i + 1, #STRATA) end
    end
    for i, name in ipairs(STRATA) do
        if name == atLeast and i > want then want = i end
    end
    return STRATA[want]
end
UI.StrataAbove = StrataAbove

function UI:Place()
    local f = self.frame
    if not f then return end
    f:ClearAllPoints()
    if self.onMap then
        f:SetFrameStrata(StrataAbove(WorldMapFrame, "HIGH"))
        local p = DB.db.mapPoint
        if p then
            f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        else
            -- docked to the map's right edge; if there's no room there the
            -- screen clamp slides it back over the map's right side
            f:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", 4, 0)
        end
    else
        f:SetFrameStrata("HIGH")
        local p = DB.db.point
        if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("CENTER") end
    end
end

-- switch between "beside the map" and "on its own" when the map state changed
function UI:SyncMapMode()
    local onMap = self:MapShown()
    if onMap == self.onMap and self.placed then return end
    self.onMap, self.placed = onMap, true
    self:ApplyLayout()
    self:Place()
end

-- called by Pins.lua when the world map opens / closes
function UI:OnMapShown()
    self:UpdateMapButton()
    if self.frame and self.frame:IsShown() then
        -- already open on its own: move beside the map for now
        self.wasAlone = true
        self:SyncMapMode()
        self:Refresh(true)
    elseif DB.db.openWithMap or self.reopenWithMap then
        self:Show()
    end
    self.reopenWithMap = nil
end

function UI:OnMapHidden()
    local f = self.frame
    if not (f and f:IsShown() and self.onMap) then return end
    if self.wasAlone then
        -- it was open before the map was: put it back where it was
        self.wasAlone = nil
        self:SyncMapMode()
        self:Refresh(true)
    else
        -- it was opened beside the map: leave with it, come back with it
        self.reopenWithMap = true
        f:Hide()
    end
end

----------------------------------------------------------------------
-- Button on the world map
----------------------------------------------------------------------

local MAP_ICONS = {
    "Interface\\Icons\\INV_Misc_Book_09",
    "Interface\\Icons\\INV_Misc_Book_11",
    "Interface\\Icons\\Trade_LeatherWorking",
}
local CORNERS = {
    TOPLEFT = { 10, -10 }, TOPRIGHT = { -10, -10 },
    BOTTOMLEFT = { 10, 10 }, BOTTOMRIGHT = { -10, 10 },
}

function UI:CreateMapButton()
    if self.mapButton or not WorldMapFrame then return end
    local b = CreateFrame("Button", "SKToolsMapButton", WorldMapFrame)
    self.mapButton = b
    b:SetSize(30, 30)
    Fill(b, 0.012, 0.024, 0.07, 0.95)
    b.rim = b:CreateTexture(nil, "BORDER")
    b.rim:SetAllPoints()
    b.rim:SetColorTexture(0.4, 0.35, 0.2, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    for _, path in ipairs(MAP_ICONS) do
        b.icon:SetTexture(path)
        if b.icon:GetTexture() then break end
    end
    -- open state: a tick in the corner as well as the gold rim
    b.tick = b:CreateTexture(nil, "OVERLAY")
    b.tick:SetTexture(CHECK)
    b.tick:SetSize(20, 20)
    b.tick:SetPoint("BOTTOMRIGHT", 5, -5)
    b.tick:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then ns.OpenSettings("db") else UI:Toggle() end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Profession DB")
        GameTooltip:AddLine("Left-click: open or close the database", 1, 1, 1)
        GameTooltip:AddLine("Right-click: its settings", 1, 1, 1)
        local n = DB:CountTracked()
        GameTooltip:AddLine(n == 0 and "Nothing on the map" or (n .. " tracked on the map"), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self:UpdateMapButton()
end

function UI:UpdateMapButton()
    local b = self.mapButton
    if not b then return end
    b:SetShown(DB.db.mapButton and true or false)
    -- over the map and its pins, whatever strata the map uses on this client
    b:SetFrameStrata(StrataAbove(WorldMapFrame, "HIGH"))
    local host = WorldMapFrame.ScrollContainer or WorldMapFrame
    local corner = DB.db.mapButtonCorner
    local off = CORNERS[corner]
    if not off then corner, off = "BOTTOMLEFT", CORNERS.BOTTOMLEFT end
    b:ClearAllPoints()
    b:SetPoint(corner, host, corner, off[1], off[2])
    local open = self.frame and self.frame:IsShown() or false
    b.tick:SetShown(open)
    if open then b.rim:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    else b.rim:SetColorTexture(0.4, 0.35, 0.2, 1) end
end

function UI:BuildModuleTabs()
    local prev
    for i, key in ipairs(DB.moduleOrder) do
        local tab = self.moduleTabs[i]
        local module = DB.modules[key]
        if not tab then
            tab = Button(self.frame, module.name, 100, 20, function(b)
                DB.char.module = b.key; UI.selected = nil; wipe(UI.history); UI:Refresh(true)
            end)
            self.moduleTabs[i] = tab
        end
        tab.key = key
        tab.text:SetText(module.name)
        tab:SetWidth(tab.text:GetStringWidth() + 20)
        tab:ClearAllPoints()
        if prev then tab:SetPoint("RIGHT", prev, "LEFT", -2, 0) else tab:SetPoint("TOPRIGHT", -62, -10) end
        tab:SetActive(key == (DB:CurrentModule() or {}).key)
        prev = tab
    end
end

----------------------------------------------------------------------
-- Behaviour
----------------------------------------------------------------------

function UI:Show()
    self:Build()
    self:SyncMapMode()
    self.frame:Show()
    self.frame:Raise()
end

function UI:Toggle()
    self:Build()
    if self.frame:IsShown() then
        self.reopenWithMap, self.wasAlone = nil, nil
        self.frame:Hide()
    else
        self:Show()
    end
end

function UI:SetSearch(text)
    self:Build()
    if self:IsCompact() and self.selected then      -- back to the list, where the results are
        self.selected = nil
        wipe(self.history)
    end
    self.search:SetText(text or "")
    self:Refresh(true)
end

function UI:SetMode(mode)
    DB.char.mode = mode
    -- narrow layout: switching mode goes back from the details to the list
    if self:IsCompact() and self.selected then
        self.selected = nil
        wipe(self.history)
    end
    self:Refresh(true)
end

local function collapsedKey(header) return DB.char.mode .. ":" .. header end

function UI:IsCollapsed(header, searching)
    if searching then return false end
    local v = DB.db.collapsed[collapsedKey(header)]
    if v == nil then return DB.char.mode == "mobs" end   -- zones start collapsed, categories open
    return v
end

function UI:BuildList(keepOffset)
    local module = DB:CurrentModule()
    if not module or not self.frame then return end
    local text = self.search:GetText()
    local searching = DB.Normalize(text) ~= ""
    local rows = {}
    if DB.char.mode == "items" then
        local byCat = {}
        for _, id in ipairs(DB:SearchItems(module, text)) do
            local c = module.items[id].c
            byCat[c] = byCat[c] or {}
            table.insert(byCat[c], id)
        end
        for _, cat in ipairs(module.categories) do
            local ids = byCat[cat]
            if ids then
                -- header icon: the first item of the category (sorted the same way every time)
                table.sort(ids, function(a, b)
                    local ia, ib = module.items[a], module.items[b]
                    if (ia.sk or 0) ~= (ib.sk or 0) then return (ia.sk or 0) < (ib.sk or 0) end
                    return ia.n < ib.n
                end)
                local col = self:IsCollapsed(cat, searching)
                rows[#rows + 1] = { kind = "header", id = cat, label = cat, count = #ids, collapsed = col, icon = DB:ItemIcon(ids[1]) }
                if not col then
                    for _, id in ipairs(ids) do rows[#rows + 1] = { kind = "item", id = id } end
                end
            end
        end
    else
        local byZone = {}
        for _, npc in ipairs(DB:SearchMobs(module, text)) do
            for mapID in pairs(DB.mobs[npc].sp) do
                local z = DB.zones[mapID] or ("Map " .. mapID)
                byZone[z] = byZone[z] or {}
                table.insert(byZone[z], npc)
            end
        end
        local zones = {}
        for z in pairs(byZone) do zones[#zones + 1] = z end
        table.sort(zones)
        for _, z in ipairs(zones) do
            local npcs = byZone[z]
            table.sort(npcs, function(a, b)
                local ma, mb = DB.mobs[a], DB.mobs[b]
                if ma.l[1] ~= mb.l[1] then return ma.l[1] < mb.l[1] end
                return ma.n < mb.n
            end)
            local col = self:IsCollapsed(z, searching)
            rows[#rows + 1] = { kind = "header", id = z, label = z, count = #npcs, collapsed = col }
            if not col then
                for _, npc in ipairs(npcs) do rows[#rows + 1] = { kind = "mob", id = npc } end
            end
        end
    end
    self.list:SetData(rows, keepOffset)
end

function UI:ClickRow(d)
    if d.kind == "header" then
        local searching = DB.Normalize(self.search:GetText()) ~= ""
        if searching then return end
        DB.db.collapsed[collapsedKey(d.id)] = not d.collapsed
        self:BuildList(true)
    elseif d.kind == "item" then
        self:ShowItem(d.id)
    else
        self:ShowMob(d.id)
    end
end

function UI:ToggleTrack(d)
    if not d then return end
    local module = DB:CurrentModule()
    if d.kind == "item" then
        DB:SetItemTracked(module, d.id, not DB:IsItemTracked(module, d.id))
    elseif d.kind == "mob" then
        DB:SetMobTracked(d.id, not DB:IsMobTracked(d.id))
    end
end

local function pushHistory(self, push)
    if push and self.selected then
        table.insert(self.history, self.selected)
    elseif not push then
        wipe(self.history)
    end
end

function UI:ShowItem(itemID, push)
    self:Build()
    pushHistory(self, push)
    self.selected = { kind = "item", id = itemID }
    self:Refresh()
end

function UI:ShowMob(npc, push)
    self:Build()
    if not DB.mobs[npc] then return end
    pushHistory(self, push)
    self.selected = { kind = "mob", id = npc }
    self:Refresh()
end

function UI:Back()
    self.selected = table.remove(self.history)
    self:Refresh()
end

function UI:DrawDetail()
    local d, sel, module = self.detail, self.selected, DB:CurrentModule()
    local has = sel and module and ((sel.kind == "item" and module.items[sel.id]) or (sel.kind == "mob" and DB.mobs[sel.id]))
    has = has and true or false
    local compact = self:IsCompact()
    local tbl, other = compact and d.compact or d.wide, compact and d.wide or d.compact
    other.hdr:Hide(); other.list:Hide()
    for _, w in ipairs({ d.icon, d.name, d.sub, d.sub2, d.track, tbl.hdr, tbl.list }) do w:SetShown(has) end
    -- narrow layout: the details take the list's place, and Back always leads out
    d:SetShown(has or not compact)
    self.list:SetShown(not (compact and has))
    d.empty:SetShown(not has and not compact)
    d.back:SetShown(has and (compact or #self.history > 0))
    if not has then return end

    local rows = {}
    if sel.kind == "item" then
        local item = module.items[sel.id]
        local q = DB.QUALITY[item.q or 1] or DB.QUALITY[1]
        d.icon:SetTexture(DB:ItemIcon(sel.id))
        d.name:SetText(item.n)
        d.name:SetTextColor(q[1], q[2], q[3])
        local sub = item.c
        if item.sk then sub = sub .. "  ·  requires " .. module.name .. " " .. item.sk end
        d.sub:SetText(sub)
        local nVis = 0
        for _, s in ipairs(item.src) do
            rows[#rows + 1] = { npc = s[1], src = s[2], chance = s[3] }
            if DB:SourceVisible(s[2], s[3]) then nVis = nVis + 1 end
        end
        if item.w then
            d.sub2:SetText(compact and "Random world drop, quest reward or other source."
                or "No specific mob drops it often enough to list: it's a random world drop, quest reward or other source.")
        else
            d.sub2:SetText(string.format(compact and "%d sources, %d on the map (min. %d%%)"
                or "%d sources, %d shown on the map at %d%% minimum chance. Click a mob for details.",
                #item.src, nVis, DB.db.minChance))
        end
        tbl.h1:SetText("Mob")
        tbl.h2:SetText("Level")
        if tbl.h5 then tbl.h5:SetText("Where") end
        local on = DB:IsItemTracked(module, sel.id)
        d.track.text:SetText(on and "On map  |TInterface\\Buttons\\UI-CheckBox-Check:14|t" or "Show on map")
        d.track:SetActive(on)
        d.track:SetShown(not item.w)
    else
        local mob = DB.mobs[sel.id]
        local items = DB:GetMobItems(module, sel.id)
        d.icon:SetTexture(items[1] and items[1][2] ~= "V" and DB:ItemIcon(items[1][1]) or "Interface\\GossipFrame\\VendorGossipIcon")
        d.name:SetText(mob.n)
        if mob.r and mob.r > 0 then d.name:SetTextColor(1, 0.82, 0) else d.name:SetTextColor(1, 1, 1) end
        local sub = "Level " .. DB:FormatLevel(mob)
        if mob.t then sub = sub .. "  ·  <" .. mob.t .. ">" end
        if mob.f then
            sub = sub .. "  ·  " .. (mob.f == "AH" and "friendly to both factions" or mob.f == "A" and "Alliance" or "Horde")
        end
        d.sub:SetText(sub)
        local where = DB:MobZones(mob)
        if mob.dg then where = "Inside " .. mob.dg .. " (entrance in " .. where .. ")" end
        d.sub2:SetText(where)
        for _, it in ipairs(items) do
            rows[#rows + 1] = { item = it[1], src = it[2], chance = it[3] }
        end
        tbl.h1:SetText("Item")
        tbl.h2:SetText("")
        if tbl.h5 then tbl.h5:SetText("Type") end
        local on = DB:IsMobTracked(sel.id)
        d.track.text:SetText(on and "On map  |TInterface\\Buttons\\UI-CheckBox-Check:14|t" or "Show on map")
        d.track:SetActive(on)
        d.track:Show()
    end
    tbl.list:SetData(rows, self.lastDetail == sel and self.lastTable == tbl)
    self.lastDetail, self.lastTable = sel, tbl
end

function UI:Refresh(rebuild)
    if not self.frame or not self.frame:IsShown() then return end
    local module = DB:CurrentModule()
    self:BuildModuleTabs()
    self.modeItems:SetActive(DB.char.mode == "items")
    self.modeMobs:SetActive(DB.char.mode == "mobs")
    self.search.hint:SetText(DB.char.mode == "items" and "Search materials..." or "Search mobs or zones...")
    self.search.hint:SetShown(self.search:GetText() == "")
    self.chance:Update()
    if not module then
        self.list:SetData({})
        self:DrawDetail()
        self.status:SetText("No data modules loaded")
        return
    end
    if rebuild then self:BuildList() else self:BuildList(true) end
    self:DrawDetail()
    local n = DB:CountTracked()
    self.status:SetText(n == 0 and "Nothing on the map" or
        string.format("%d tracked · %d pins", n, DB.Pins and DB.Pins.count or 0))
end

function DB:OnModulesChanged()
    if UI.frame then UI:Refresh(true) end
end
