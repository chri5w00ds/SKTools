-- SKTools settings tab: Widgets (the buff panes).
--
-- A designer row of five slots: your class buff locked in the middle, two slots either side.
-- Click a side slot to pick what goes there (a helpful spell from your spell book, Rebirth,
-- or empty). Below it: unlock the panes to move and resize them, and their sizes.

local ADDON, ns = ...

local W = ns.W
local FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local function B() return ns.Buffs.Settings() or { personal = {}, missing = {} } end

local function Label(parent, size, justify)
    local t = parent:CreateFontString(nil, "OVERLAY")
    t:SetFont(FONT, size or 11, "OUTLINE")
    t:SetJustifyH(justify or "LEFT")
    t:SetTextColor(0.9, 0.9, 0.9)
    return t
end

local SLOT_WORDS = { s1 = "left, outer", s2 = "left, inner", s3 = "right, inner", s4 = "right, outer" }
local ORDER = { "s1", "s2", "centre", "s3", "s4" }
local SLOT, GAP = 44, 14

local function Build(panel)
    local L, R = 24, 400
    local BF = ns.Buffs
    ns.WidgetsPanel = panel

    ------------------------------------------------------------------
    W.Header(panel, "Personal buffs", L, -8, 480)
    local on = panel:Add(W.Check(panel, "Show the buff widgets",
        function() return ns.FeatureOn(BF.Settings()) end,
        function(v) ns.SetFeatureOn(BF.Settings(), v); BF.Refresh() end, 190), L + 510, -10)
    on.tooltip = "Berry Mode keeps its own on / off for this (off until you turn it on)."
    W.Note(panel, "Your class buff sits in the middle. Click a slot either side to choose a buff for it: it lights up "
        .. "when you are missing it, or (for a buff you can put on others, like Thorns) when your tank is, with a "
        .. "small shield on the icon. Rebirth lights up when someone in your group is dead and you have its seed.",
        L, -32, 700)

    -- the designer row
    local box = CreateFrame("Frame", nil, panel)
    box:SetSize(5 * SLOT + 4 * GAP + 40, SLOT + 46)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", L + (700 - (5 * SLOT + 4 * GAP + 40)) / 2, -84)
    W.Fill(box, 0.06, 0.06, 0.07, 0.9)
    W.Border(box, 0.35, 0.35, 0.38, 1, 1)
    -- the centre line the panes grow out from
    local line = box:CreateTexture(nil, "BORDER")
    line:SetColorTexture(0.82, 0.68, 0.30, 0.35)
    line:SetSize(1, SLOT + 30)
    line:SetPoint("CENTER", box, "CENTER", 0, 4)

    local cells = {}
    for i, key in ipairs(ORDER) do
        local c = CreateFrame("Button", nil, box)
        c:SetSize(SLOT, SLOT)
        c:SetPoint("CENTER", box, "CENTER", (i - 3) * (SLOT + GAP), 6)
        c.key = key
        c.icon = c:CreateTexture(nil, "ARTWORK")
        c.icon:SetAllPoints()
        c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        c.plus = Label(c, 20, "CENTER"); c.plus:SetPoint("CENTER"); c.plus:SetText("+")
        c.edge = CreateFrame("Frame", nil, c); c.edge:SetAllPoints()
        if key == "centre" then
            W.Border(c.edge, 1, 0.82, 0.25, 1, 2)                       -- gold: locked, your class buff
            c.lock = c:CreateTexture(nil, "OVERLAY")
            c.lock:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
            c.lock:SetSize(14, 14); c.lock:SetPoint("TOPRIGHT", 4, 4)
        else
            W.Border(c.edge, 0.55, 0.55, 0.6, 1, 1)
        end
        c.caption = Label(box, 9, "CENTER")
        c.caption:SetPoint("TOP", c, "BOTTOM", 0, -4)
        c.caption:SetWidth(SLOT + GAP)
        c:SetScript("OnClick", function(self)
            if self.key ~= "centre" and panel.OpenPicker then panel.OpenPicker(self.key) end
        end)
        c:SetScript("OnEnter", function(self)
            if not _G.GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if self.key == "centre" then
                local _, name = BF.ClassBuffIcon()
                GameTooltip:SetText(name or "No class buff", 1, 1, 1)
                GameTooltip:AddLine(name and "Your class buff: always in the middle." or "Your class has no group buff.", 0.8, 0.8, 0.8, true)
            else
                local v = BF.SlotValue(self.key)
                GameTooltip:SetText(v == BF.NONE and "Empty" or v, 1, 1, 1)
                GameTooltip:AddLine("Click to choose (" .. SLOT_WORDS[self.key] .. ").", 0.8, 0.8, 0.8, true)
            end
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
        cells[key] = c
    end
    panel.cells = cells

    local function Redraw()
        for key, c in pairs(cells) do
            if key == "centre" then
                local icon, name = BF.ClassBuffIcon()
                local shown = BF.ClassShown()
                c.icon:SetTexture(icon or QUESTION)
                c.icon:SetDesaturated(icon == nil or not shown)
                c.icon:SetAlpha(shown and 1 or 0.35)
                c.plus:Hide()
                c.caption:SetText(not icon and "none" or shown and name or "left out")
            else
                local v = BF.SlotValue(key)
                local empty = v == BF.NONE
                c.icon:SetTexture(empty and nil or BF.SlotIcon(v))
                c.icon:SetShown(not empty)
                c.plus:SetShown(empty)
                c.caption:SetText(empty and "empty" or v)
            end
        end
    end
    panel.RedrawSlots = Redraw

    -- the picker: opens over the row when a side slot is clicked
    local picker = CreateFrame("Frame", nil, panel)
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    picker:SetFrameLevel(50)
    picker:EnableMouse(true)
    picker:SetPoint("TOP", box, "BOTTOM", 0, -4)
    W.Fill(picker, 0.05, 0.05, 0.06, 0.97)
    W.Border(picker, 0.82, 0.68, 0.30, 1, 1)
    picker:Hide()
    picker.title = Label(picker, 11)
    picker.title:SetPoint("TOPLEFT", 8, -8)
    local close = CreateFrame("Button", nil, picker)
    close:SetSize(18, 18); close:SetPoint("TOPRIGHT", -3, -3)
    close.text = Label(close, 12, "CENTER"); close.text:SetPoint("CENTER"); close.text:SetText("x")
    close:SetScript("OnClick", function() picker:Hide() end)
    picker.empty = W.Button(picker, "Empty", 70, function() picker.Choose(BF.NONE) end)
    picker.empty:SetPoint("TOPLEFT", 8, -26)
    picker.rebirth = W.Button(picker, "Rebirth", 90, function() picker.Choose(BF.REBIRTH) end)
    picker.rebirth:SetPoint("LEFT", picker.empty, "RIGHT", 6, 0)
    picker.none = Label(picker, 10); picker.none:SetPoint("TOPLEFT", 8, -56)
    picker.none:SetText("No helpful spells found in your spell book.")
    picker.cells = {}
    local PER_ROW, CELL = 12, 26
    function picker.Choose(value)
        if picker.slot then BF.SetSlot(picker.slot, value) end
        picker:Hide()
        Redraw()
    end
    local function Cell(i)
        local c = picker.cells[i]
        if c then return c end
        c = CreateFrame("Button", nil, picker)
        c:SetSize(CELL - 2, CELL - 2)
        c.icon = c:CreateTexture(nil, "ARTWORK"); c.icon:SetAllPoints(); c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        c.mark = CreateFrame("Frame", nil, c); c.mark:SetAllPoints()
        W.Border(c.mark, 1, 0.82, 0.25, 1, 2)
        c:SetScript("OnClick", function(self) picker.Choose(self.name) end)
        c:SetScript("OnEnter", function(self)
            if _G.GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(self.name, 1, 1, 1); GameTooltip:Show() end
        end)
        c:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
        picker.cells[i] = c
        return c
    end
    function panel.OpenPicker(slot)
        picker.slot = slot
        local now = BF.SlotValue(slot)
        picker.title:SetText("Personal buffs: " .. (SLOT_WORDS[slot] or slot))
        local list = BF.Choices()
        picker.none:SetShown(#list == 0)
        for i, sp in ipairs(list) do
            local c = Cell(i)
            c.name = sp.name
            c.icon:SetTexture(sp.icon or BF.SlotIcon(sp.name))
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

    W.Note(panel, "On screen only the missing ones show, grown out from the centre line: one sits on it, two sit "
        .. "either side of it. Your class buff stays in the middle (just left of it when the count is even).",
        L, -186, 700)

    -- the class buff in the middle can be left out (Lightning Shield, say, which runs out by its
    -- charges rather than by time)
    local classCheck = panel:Add(W.Check(panel, "Show your class buff in the middle",
        function() return BF.ClassShown() end,
        function(v) BF.SetClassShown(v); Redraw() end, 400), L, -222)
    local oldRedraw = Redraw
    Redraw = function()
        oldRedraw()
        local _, name = BF.ClassBuffIcon()
        if classCheck.text then
            classCheck.text:SetText("Show " .. (name or "your class buff") .. " in the middle")
            classCheck.box:SetHitRectInsets(0, -((classCheck.text:GetStringWidth() or 60) + 4), 0, 0)
        end
        classCheck:Sync()
    end
    panel.RedrawSlots = Redraw

    ------------------------------------------------------------------
    W.Header(panel, "Size", L, -262, 330)
    panel:Add(W.Slider(panel, "Personal buffs icon size", 16, 64, 1,
        function() return B().personal.size or 36 end,
        function(v) B().personal.size = v; BF.Refresh() end, W.px, 300), L, -288)
    panel:Add(W.Slider(panel, "Missing class buffs icon size", 16, 64, 1,
        function() return B().missing.size or 30 end,
        function(v) B().missing.size = v; BF.Refresh() end, W.px, 300), L, -342)

    W.Header(panel, "Position", R, -262, 330)
    local unlock = panel:Add(W.Check(panel, "Unlock the panes (move and resize)",
        function() return B().unlocked == true end,
        function(v) B().unlocked = v and true or false; BF.Refresh() end, 300), R, -288)
    unlock.tooltip = "Shows both panes with example icons. Drag a pane to move it; drag its white corner to resize it. "
        .. "Untick when you are done."
    W.Note(panel, "Missing class buffs: the class buffs your group members could give you that you do not have. "
        .. "Hover one in the game to see who can cast it.", R, -316, 330)
    panel:Add(W.Button(panel, "Reset positions", 130, function()
        BF.ResetPositions()
        ns.Print("buff widget positions reset.")
    end), R, -370)
    panel:Add(W.Button(panel, "Debug to chat", 120, function()
        BF.Debug(ns.Printer and ns.Printer("Buffs") or print)
    end), R + 140, -370)

    local oldSync = panel.OnSync
    function panel:OnSync()
        if oldSync then oldSync(self) end
        Redraw()
    end
    panel:HookScript("OnShow", Redraw)
    panel:HookScript("OnHide", function() picker:Hide() end)
    Redraw()
end

ns.RegisterTab({ key = "widgets", title = "Widgets", order = 2.7, Build = Build })
