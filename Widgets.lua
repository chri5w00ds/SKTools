-- SKTools shared widgets and window theme.
--
-- The look is classic WoW with Forever's cleaner spacing: the stone dialog
-- border and title plate, red panel buttons, classic ticks, sliders and tabs,
-- gold headings. It uses the game's own templates and texture files, each
-- one checked first; anything this client doesn't have falls back to a flat
-- dark control, so a missing file can never leave a broken window.
--
-- Every control takes get/set functions and has a :Sync() that pushes the
-- saved value back into it. W.Panel collects controls so a whole settings
-- tab can be re-synced in one call.

local ADDON, ns = ...

local W = {}
ns.W = W

W.GOLD  = { 1, 0.82, 0 }
W.EDGE  = { 0.55, 0.45, 0.25 }      -- warm bronze, for thin borders
W.SOLID = "Interface\\Buttons\\WHITE8X8"
W.LOGO  = ns.MEDIA .. "Logo"
W.LOGO_SMALL = ns.MEDIA .. "LogoSmall"

local GOLD, EDGE = W.GOLD, W.EDGE

function W.Fill(frame, r, g, b, a, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(r, g, b, a)
    return t
end

-- 1px border; returns a table with :SetColor() so it can change on hover
function W.Border(frame, r, g, b, a, thickness)
    local sides = {}
    local px = thickness or 1
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(r, g, b, a)
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT"); t:SetHeight(px)
        else
            t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side); t:SetWidth(px)
        end
        sides[#sides + 1] = t
    end
    function sides:SetColor(nr, ng, nb, na)
        for i = 1, #self do self[i]:SetColorTexture(nr, ng, nb, na or 1) end
    end
    return sides
end

----------------------------------------------------------------------
-- Classic chrome
----------------------------------------------------------------------

-- does this client have a texture file?
local probe
local known = {}
function W.Exists(path)
    if known[path] ~= nil then return known[path] end
    probe = probe or UIParent:CreateTexture()
    probe:Hide()
    local ok = probe:SetTexture(path)
    local have = ok ~= false and probe:GetTexture() ~= nil
    probe:SetTexture(nil)
    known[path] = have
    return have
end

-- frame from a Blizzard template, or nil if this client doesn't have it
-- the window colours: deep navy panels, darker navy wells inside them
W.NAVY      = { 0.015, 0.03, 0.09 }          -- window body
W.NAVY_DEEP = { 0.008, 0.016, 0.05 }          -- lists, boxes and fields set into it
local SOLID = W.SOLID

local function FromTemplate(kind, parent, template)
    local ok, f = pcall(CreateFrame, kind, nil, parent, template)
    if ok and f then return f end
end

local BACKDROPS = {
    -- stone-bordered dialog, as on the classic options and pop-up windows
    dialog = {
        bgFile = SOLID,
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
        color = { 0.015, 0.03, 0.09, 1 },
    },
    -- thin bronze-edged box for lists and content areas
    inset = {
        bgFile = SOLID,
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
        color = { 0.008, 0.016, 0.05, 0.8 }, border = { 0.75, 0.62, 0.38, 1 },
    },
    slider = {
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    },
}

local function CanBackdrop(f)
    if f.SetBackdrop then return true end
    if BackdropTemplateMixin and Mixin then
        Mixin(f, BackdropTemplateMixin)
        if f.OnBackdropSizeChanged then f:HookScript("OnSizeChanged", f.OnBackdropSizeChanged) end
    end
    return f.SetBackdrop ~= nil
end

-- Give a frame one of the classic backdrops. Returns false (and draws the
-- flat fallback, unless noFallback) when the client can't do it.
function W.Skin(frame, style, noFallback)
    local bd = BACKDROPS[style]
    if bd and W.Exists(bd.bgFile) and W.Exists(bd.edgeFile) and CanBackdrop(frame) then
        local ok = pcall(frame.SetBackdrop, frame, bd)
        if ok then
            if bd.color then frame:SetBackdropColor(unpack(bd.color)) end
            if bd.border then frame:SetBackdropBorderColor(unpack(bd.border)) end
            return true
        end
    end
    if not noFallback then
        if style == "dialog" then
            W.Fill(frame, W.NAVY[1], W.NAVY[2], W.NAVY[3], 1)
        else
            W.Fill(frame, W.NAVY_DEEP[1], W.NAVY_DEEP[2], W.NAVY_DEEP[3], 0.75)
        end
        W.Border(frame, EDGE[1], EDGE[2], EDGE[3], 1)
    end
    return false
end

-- the gold-lettered plate that sits on a classic dialog's top edge
function W.TitlePlate(frame, text)
    local path = "Interface\\DialogFrame\\UI-DialogBox-Header"
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if W.Exists(path) then
        local plate = frame:CreateTexture(nil, "ARTWORK")
        plate:SetTexture(path)
        plate:SetSize(300, 64)
        plate:SetPoint("TOP", 0, 12)
        fs:SetPoint("TOP", plate, "TOP", 0, -14)
    else
        fs:SetPoint("TOP", 0, -12)
    end
    fs:SetText(text)
    return fs
end

-- the addon's bee
function W.Logo(parent, size, small)
    local t = parent:CreateTexture(nil, "OVERLAY", nil, 6)
    t:SetTexture(small and W.LOGO_SMALL or W.LOGO)
    t:SetSize(size, size)
    return t
end

function W.CloseButton(parent, onClick)
    local b = FromTemplate("Button", parent, "UIPanelCloseButton")
    if b then
        b:SetSize(30, 30)
    else
        b = CreateFrame("Button", nil, parent)
        b:SetSize(22, 22)
        W.Fill(b, 0.15, 0.15, 0.18, 1)
        W.Border(b, EDGE[1], EDGE[2], EDGE[3], 1)
        local x = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        x:SetPoint("CENTER")
        x:SetText("X")
    end
    b:SetScript("OnClick", onClick)
    return b
end

-- Classic tab (the kind on top of the old options windows). The open tab is
-- the raised one with white text and a gold bar under it.
local TAB_OFF = "Interface\\OptionsFrame\\UI-OptionsFrame-InActiveTab"
local TAB_ON  = "Interface\\OptionsFrame\\UI-OptionsFrame-ActiveTab"
function W.Tab(parent, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetText(text)
    b:SetSize(math.max(84, (b.label:GetStringWidth() or 70) + 34), 26)
    b.label:SetPoint("CENTER", 0, -3)

    local classic = W.Exists(TAB_OFF) and W.Exists(TAB_ON)
    local function Pieces(path)
        local set = {}
        local l = b:CreateTexture(nil, "BACKGROUND"); l:SetTexture(path)
        l:SetTexCoord(0, 0.15625, 0, 1); l:SetWidth(20)
        l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMLEFT")
        local r = b:CreateTexture(nil, "BACKGROUND"); r:SetTexture(path)
        r:SetTexCoord(0.84375, 1, 0, 1); r:SetWidth(20)
        r:SetPoint("TOPRIGHT"); r:SetPoint("BOTTOMRIGHT")
        local m = b:CreateTexture(nil, "BACKGROUND"); m:SetTexture(path)
        m:SetTexCoord(0.15625, 0.84375, 0, 1)
        m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
        set[1], set[2], set[3] = l, m, r
        return set
    end
    if classic then
        b.off, b.on = Pieces(TAB_OFF), Pieces(TAB_ON)
    else
        b.flat = W.Fill(b, 0.12, 0.12, 0.14, 1)
        W.Border(b, EDGE[1], EDGE[2], EDGE[3], 1)
    end

    b.bar = b:CreateTexture(nil, "OVERLAY")
    b.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    b.bar:SetHeight(2)
    b.bar:SetPoint("BOTTOMLEFT", 10, 2)
    b.bar:SetPoint("BOTTOMRIGHT", -10, 2)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 6, -8); hl:SetPoint("BOTTOMRIGHT", -6, 3)
    hl:SetColorTexture(1, 1, 1, 0.06)

    function b:SetActive(on)
        self.bar:SetShown(on)
        if self.on then
            for i = 1, 3 do self.on[i]:SetShown(on); self.off[i]:SetShown(not on) end
        else
            self.flat:SetColorTexture(on and 0.22 or 0.12, on and 0.20 or 0.12, on and 0.12 or 0.14, 1)
        end
        if on then self.label:SetTextColor(1, 1, 1)
        else self.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
    end
    b:SetScript("OnClick", onClick)
    b:SetActive(false)
    return b
end

function W.Header(parent, text, x, y, width)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.3)
    line:SetHeight(1)
    line:SetWidth(width or 220)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
    return fs
end

-- small grey explanatory text
function W.Note(parent, text, x, y, width)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetWidth(width or 220)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetText(text)
    return fs
end

-- Red panel button from the game's own template. :SetActive(true) marks it
-- as the chosen one of a group: held-down highlight, white text, gold bar.
function W.Button(parent, label, width, onClick, height)
    local b = FromTemplate("Button", parent, "UIPanelButtonTemplate")
    local classic = b ~= nil
    if classic then
        b:SetSize(width or 100, height or 22)
        if b.SetNormalFontObject then
            b:SetNormalFontObject("GameFontNormalSmall")
            b:SetHighlightFontObject("GameFontHighlightSmall")
            if b.SetDisabledFontObject then b:SetDisabledFontObject("GameFontDisableSmall") end
        end
        b:SetText(label)
        b.label = (b.GetFontString and b:GetFontString()) or b.Text
        if type(b.label) ~= "table" then b.label = nil end
    else
        b = CreateFrame("Button", nil, parent)
        b:SetSize(width or 100, height or 22)
        b.bg = W.Fill(b, 0.15, 0.15, 0.18, 1)
        b.border = W.Border(b, EDGE[1], EDGE[2], EDGE[3], 1)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
    end
    if not b.label then
        b.label = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        b.label:SetPoint("CENTER")
        b.label:SetText(label)
    end
    b.text = b.label
    b.classic = classic

    b.bar = b:CreateTexture(nil, "OVERLAY")
    b.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    b.bar:SetHeight(2)
    b.bar:SetPoint("BOTTOMLEFT", 5, 2)
    b.bar:SetPoint("BOTTOMRIGHT", -5, 2)
    b.bar:Hide()

    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function b:SetLabel(text)
        if self.classic then self:SetText(text) else self.label:SetText(text) end
    end
    function b:SetActive(on)
        self.bar:SetShown(on and true or false)
        if self.classic then
            if on then self:LockHighlight() else self:UnlockHighlight() end
        else
            self.bg:SetColorTexture(on and 0.30 or 0.15, on and 0.24 or 0.15, on and 0.06 or 0.18, 1)
        end
    end
    return b
end

-- Dress a Slider as the classic grooved bar with the round knob. Returns
-- false and draws the flat version when the client lacks the art.
function W.SkinSlider(s)
    local knob = "Interface\\Buttons\\UI-SliderBar-Button-Horizontal"
    if W.Exists(knob) and W.Skin(s, "slider", true) then
        s:SetThumbTexture(knob)
        local t = s.GetThumbTexture and s:GetThumbTexture()
        if t then t:SetSize(26, 26) end
        return true
    end
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0.25, 0.25, 0.28, 1)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    thumb:SetSize(8, 16)
    s:SetThumbTexture(thumb)
    return false
end

-- slider with label, value read-out, mouse-wheel stepping and - / + buttons
function W.Slider(parent, label, lo, hi, step, get, set, fmt, width)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(width or 200, 36)

    local title = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(label)
    c.title = title

    local value = c:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    value:SetPoint("TOPRIGHT", 0, 0)

    local s = CreateFrame("Slider", nil, c)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("TOPLEFT", 16, -15)
    s:SetPoint("TOPRIGHT", -16, -15)
    s:SetHeight(17)
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)
    c.slider = s

    local classic = W.SkinSlider(s)

    -- marker at zero for sliders that go negative
    if lo < 0 and hi > 0 then
        local zero = s:CreateTexture(nil, "BORDER")
        zero:SetColorTexture(0.6, 0.6, 0.6, 0.8)
        zero:SetSize(1, 10)
        -- HookScript: the classic bar's backdrop listens to this event too
        s:HookScript("OnSizeChanged", function(self, w)
            zero:ClearAllPoints()
            zero:SetPoint("CENTER", self, "LEFT", w * (-lo) / (hi - lo), 0)
        end)
    end

    local function Round(v)
        v = math.floor(v / step + 0.5) * step
        if step < 1 then v = tonumber(("%.2f"):format(v)) end
        return v
    end
    local function Show(v)
        value:SetText(fmt and fmt(v) or tostring(v))
    end

    s:SetScript("OnValueChanged", function(_, v)
        v = Round(v)
        Show(v)
        if c.syncing then return end
        if get() ~= v then set(v) end
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * step)
    end)

    local function Stepper(text, dir)
        local b = CreateFrame("Button", nil, c)
        b:SetSize(14, 16)
        b:SetPoint(dir < 0 and "RIGHT" or "LEFT", s, dir < 0 and "LEFT" or "RIGHT", dir < 0 and -2 or 2, 0)
        local t = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        t:SetAllPoints()
        t:SetText(text)
        b:SetScript("OnClick", function() s:SetValue(s:GetValue() + dir * step) end)
        b:SetScript("OnEnter", function() t:SetTextColor(1, 1, 1) end)
        b:SetScript("OnLeave", function() t:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end)
    end
    Stepper("-", -1)
    Stepper("+", 1)

    function c:Sync()
        local v = get()
        if v == nil then return end
        self.syncing = true
        s:SetValue(v)
        self.syncing = false
        Show(Round(v))
    end
    return c
end

-- Classic check box (the game's own template): empty box when off, a gold
-- tick when on. The label is part of the click area.
function W.Check(parent, label, get, set, width)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(width or 200, 18)

    local box = FromTemplate("CheckButton", c, "UICheckButtonTemplate")
    local tick
    if box then
        box:SetSize(24, 24)
        box:SetPoint("LEFT", -4, 0)
        -- the template brings its own label region on some clients; ours is used instead
        local own = box.Text or box.text
        if type(own) == "table" and own.SetText then own:SetText("") end
    else
        box = CreateFrame("Button", nil, c)
        box:SetSize(14, 14)
        box:SetPoint("LEFT", 0, 0)
        W.Fill(box, 0.25, 0.25, 0.28, 1)
        tick = box:CreateTexture(nil, "ARTWORK")
        tick:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        tick:SetSize(8, 8)
        tick:SetPoint("CENTER")
    end
    c.box = box

    local text = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("LEFT", c, "LEFT", 20, 0)
    text:SetText(label)
    c.text = text
    box:SetHitRectInsets(0, -((text:GetStringWidth() or 60) + 4), 0, 0)

    function c:Sync()
        local on = get() and true or false
        if tick then tick:SetShown(on) else box:SetChecked(on) end
    end
    box:SetScript("OnClick", function()
        set(not get())
        c:Sync()
    end)
    box:SetScript("OnEnter", function(self)
        if c.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(c.tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return c
end

-- Blizzard colour picker, new and old API.
-- onChange(r, g, b) is called live; cancelling calls onCancel(), or without
-- one puts the starting colour back through onChange.
function W.ColorPicker(r, g, b, onChange, onCancel)
    local cp = ColorPickerFrame
    if not cp then return end
    local function Read()
        onChange(cp:GetColorRGB())
    end
    local function Cancel()
        if onCancel then onCancel() else onChange(r, g, b) end
    end
    if cp.SetupColorPickerAndShow then
        cp:SetupColorPickerAndShow({
            r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = Read, cancelFunc = Cancel,
        })
    else
        cp:Hide()                       -- forces OnShow to run again
        cp.func, cp.opacityFunc, cp.cancelFunc = Read, nil, Cancel
        cp.hasOpacity = false
        cp.previousValues = { r = r, g = g, b = b }
        cp:SetColorRGB(r, g, b)
        cp:Show()
    end
    cp:SetFrameStrata("FULLSCREEN_DIALOG")
end

-- colour swatch: click to open the colour picker. get() returns r, g, b.
function W.Swatch(parent, label, get, set, width, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 18, height or 18)

    local edge = b:CreateTexture(nil, "BACKGROUND")
    edge:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
    edge:SetAllPoints()

    local fill = b:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    b.fill = fill

    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", b, "RIGHT", 6, 0)
    t:SetText(label or "")

    function b:Sync()
        local r, g, bl = get()
        fill:SetColorTexture(r, g, bl, 1)
    end
    b:SetScript("OnClick", function(self)
        local r, g, bl = get()
        W.ColorPicker(r, g, bl, function(nr, ng, nb)
            set(nr, ng, nb)
            self:Sync()
        end)
    end)
    b:SetScript("OnEnter", function() edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1) end)
    b:SetScript("OnLeave", function() edge:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1) end)
    return b
end

-- simple drop-down: a button showing the choice, a list that opens under it.
-- options = { { value = ..., text = ... }, ... }
function W.Dropdown(parent, label, options, get, set, width)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(220, 22)

    local title = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    title:SetPoint("LEFT", 0, 0)
    title:SetText(label)

    local w = width or 150
    local list = CreateFrame("Frame", nil, c)
    local box
    box = W.Button(c, "", w, function()
        -- opens downwards, or upwards when set to (a drop-down low in a panel)
        list:ClearAllPoints()
        local side = c.alignRight and "RIGHT" or "LEFT"
        if c.openUp then list:SetPoint("BOTTOM" .. side, box, "TOP" .. side, 0, 1)
        else list:SetPoint("TOP" .. side, box, "BOTTOM" .. side, 0, -1) end
        list:SetShown(not list:IsShown())
    end)
    box:SetPoint("LEFT", title, "RIGHT", 8, 0)
    local arrow = box:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", -8, 0)
    arrow:SetText("v")

    W.Fill(list, 0.012, 0.024, 0.07, 0.98)
    W.Skin(list, "inset")
    list:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -1)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:EnableMouse(true)
    list:Hide()

    function c:Sync()
        local v = get()
        for _, o in ipairs(options) do
            if o.value == v then box:SetLabel(o.text) end
        end
    end
    local rows = {}
    -- the entries can change later (a drop-down whose choices depend on another one)
    function c:SetOptions(new)
        options = new
        -- a long list goes in two columns
        local cols = (#options > 10) and 2 or 1
        local per = math.ceil(#options / cols)
        list:SetSize(w * cols, per * 20 + 8)
        for i, o in ipairs(options) do
            local b = rows[i]
            if not b then
                b = CreateFrame("Button", nil, list)
                b:SetSize(w - 8, 20)
                local hl = b:CreateTexture(nil, "BACKGROUND")
                hl:SetAllPoints()
                hl:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.18)
                hl:Hide()
                b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                b.text:SetPoint("LEFT", 6, 0)
                b:SetScript("OnEnter", function() hl:Show() end)
                b:SetScript("OnLeave", function() hl:Hide() end)
                b:SetScript("OnClick", function(self)
                    list:Hide()
                    set(self.value)
                    c:Sync()
                end)
                rows[i] = b
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 4 + math.floor((i - 1) / per) * w, -4 - ((i - 1) % per) * 20)
            b.value = o.value
            b.text:SetText(o.text)
            b:Show()
        end
        for i = #options + 1, #rows do rows[i]:Hide() end
        c:Sync()
    end
    c:SetOptions(options)
    c:SetScript("OnHide", function() list:Hide() end)
    c.list, c.box = list, box
    return c
end

-- Give a settings panel :Add(widget, x, y) and :SyncAll().
function W.Panel(panel)
    panel.widgets = {}
    function panel:Add(widget, x, y)
        widget:SetPoint("TOPLEFT", self, "TOPLEFT", x, y)
        if widget.Sync then self.widgets[#self.widgets + 1] = widget end
        return widget
    end
    function panel:SyncAll()
        for i = 1, #self.widgets do self.widgets[i]:Sync() end
        if self.OnSync then self:OnSync() end
    end
    return panel
end

-- value formatters shared by the tabs
function W.px(v) return ("%d px"):format(v) end
function W.signed(v) return (v > 0 and "+" or "") .. math.floor(v + 0.5) end
function W.percent(v) return ("%.0f%%"):format(v * 100) end
function W.percentInt(v) return ("%d%%"):format(v) end
