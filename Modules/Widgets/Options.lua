-- SKTools settings tab: Widgets.
--
-- Three sections of the same shape - a tick box before the title turns the widget on or off, a line
-- about it, its options with its icon size on the right:
--   Personal buffs       a designer row of five slots: your class buff locked in the middle, two
--                        either side (click one to pick a helpful spell, Rebirth, or empty)
--   Missing class buffs
--   PvP flag
-- and one row along the bottom for all of them: unlock (move and resize), reset positions, debug.

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
    local L, R, CW = 24, 400, 330
    local BF = ns.Buffs

    ------------------------------------------------------------------
    -- a section's title with its on / off tick box before it (as the cooldown panes' titles)
    local function Section(title, y, get, set, tip)
        local c = panel:Add(W.Check(panel, "", get, set, 22), L, y + 3)
        c.tooltip = tip
        W.Header(panel, title, L + 24, y, 680 - 24)
        return c
    end

    Section("Personal buffs", -8,
        function() return ns.FeatureOn(BF.Settings()) end,
        function(v) ns.SetFeatureOn(BF.Settings(), v); BF.Refresh() end,
        "Show the personal buffs pane: your class buff in the middle, your chosen buffs either side. Each lights "
        .. "up when you are missing it, or (for a buff you can put on others, like Thorns) when your tank is, with a "
        .. "small shield on the icon. Rebirth lights up when someone in your group is dead and you have its seed. "
        .. "Berry Mode keeps its own on / off for this (off until you turn it on).")

    -- the designer row
    local box = CreateFrame("Frame", nil, panel)
    box:SetSize(5 * SLOT + 4 * GAP + 40, SLOT + 46)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", L + (700 - (5 * SLOT + 4 * GAP + 40)) / 2, -34)
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
    ns.WidgetsPanel = panel             -- (reached by the tests)

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

    local how = W.Note(panel, "Click a side slot to choose a buff. On screen only the missing ones show, from the centre line out.",
        L, -130, 700)
    if how and how.SetJustifyH then how:SetJustifyH("CENTER") end

    -- the class buff in the middle can be left out (Lightning Shield, say, which runs out by its
    -- charges rather than by time)
    local classCheck = panel:Add(W.Check(panel, "Show your class buff in the middle",
        function() return BF.ClassShown() end,
        function(v) BF.SetClassShown(v); Redraw() end, CW), L, -160)
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

    panel:Add(W.Slider(panel, "Icon size", 16, 64, 1,
        function() return B().personal.size or 36 end,
        function(v) B().personal.size = v; BF.Refresh() end, W.px, CW), R, -152)

    ------------------------------------------------------------------
    Section("Missing class buffs", -200,
        function() return ns.FeatureOn(B().missing) end,
        function(v) ns.SetFeatureOn(B().missing, v); BF.Refresh() end,
        "Show the missing class buffs pane. Hover one in the game to see who can cast it. "
        .. "Berry Mode keeps its own on / off for this (off until you turn it on).")
    W.Note(panel, "The class buffs your group could give you that you do not have - only from players who can "
        .. "cast them (old enough, and for a talent buff, seen giving it).", L, -232, CW)
    panel:Add(W.Slider(panel, "Icon size", 16, 64, 1,
        function() return B().missing.size or 30 end,
        function(v) B().missing.size = v; BF.Refresh() end, W.px, CW), R, -224)

    ------------------------------------------------------------------
    local P = function() return ns.PvPIcon.Settings() or {} end
    Section("PvP flag", -272,
        function() return ns.FeatureOn(P()) end,
        function(v) ns.SetFeatureOn(P(), v); ns.PvPIcon.Refresh() end,
        "The game's own PvP icon - your faction's, or the free-for-all one - while you are flagged, hidden otherwise. "
        .. "Berry Mode keeps its own on / off for this (off until you turn it on).")
    local pvpTimer = panel:Add(W.Check(panel, "Countdown while the flag wears off",
        function() return P().timer ~= false end,
        function(v) P().timer = v and true or false; ns.PvPIcon.Refresh() end, CW), L, -304)
    pvpTimer.tooltip = "Minutes and seconds under the icon until your PvP flag drops (when the game is counting down)."
    panel:Add(W.Slider(panel, "Icon size", 16, 96, 1,
        function() return P().size or 36 end,
        function(v) P().size = v; ns.PvPIcon.Refresh() end, W.px, CW), R, -296)

    ------------------------------------------------------------------
    local Z = function() return ns.ZoneText.Settings() or {} end
    Section("Zone text", -334,
        function() return ns.FeatureOn(Z()) end,
        function(v) ns.SetFeatureOn(Z(), v); ns.ZoneText.Refresh() end,
        "Move the game's zone text: the area name you see entering a zone, with the sub-zone and PvP lines under it. "
        .. "Only where it shows changes. Off, the game's frames are left alone. "
        .. "Berry Mode keeps its own on / off for this (off until you turn it on).")
    W.Note(panel, "The area name you see entering a zone. Drag it with Unlock widgets below.", L, -362, 420)
    panel:Add(W.Button(panel, "Reset position", 130, function()
        ns.ZoneText.ResetPosition()
    end), L + 440, -358)

    ------------------------------------------------------------------ all of them
    local rule = panel:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(0.82, 0.68, 0.30, 0.35)
    rule:SetSize(700, 1)
    rule:SetPoint("TOPLEFT", panel, "TOPLEFT", L, -392)
    local unlock = panel:Add(W.Check(panel, "Unlock widgets (drag to move, corner to resize)",
        function() return B().unlocked == true end,
        function(v)
            B().unlocked = v and true or false; BF.Refresh()
            if ns.PvPIcon then ns.PvPIcon.Refresh() end
            if ns.ZoneText then ns.ZoneText.Refresh() end
        end, 360), L, -404)
    unlock.tooltip = "Shows the widgets with examples. Drag one to move it; drag its white corner to resize it. "
        .. "Untick when you are done."
    panel:Add(W.Button(panel, "Reset positions", 130, function()
        BF.ResetPositions()
        if ns.PvPIcon then ns.PvPIcon.ResetPosition() end
        if ns.ZoneText then ns.ZoneText.ResetPosition() end
        ns.Print("widget positions reset.")
    end), L + 440, -400)
    panel:Add(W.Button(panel, "Debug to log", 120, function()
        ns.Report("widgets", function(out)
            BF.Debug(out)
            if ns.PvPIcon then ns.PvPIcon.Debug(out) end
        end, true)
    end), L + 580, -400)

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
