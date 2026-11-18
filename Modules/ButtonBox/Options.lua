-- SKTools settings tab: Button Box (the minimap button box).

local ADDON, ns = ...

local W = ns.W
local B = ns.ButtonBox

local function db() return B.Settings() or {} end
local function Changed() B.Apply() end

local ROWS = 15            -- buttons listed per page

-- the bee's clicks: every mix of Shift, Ctrl and Alt with each button, and what it does
local function BuildClicks(page)
    local CL, CR = 24, 400
    for col, mouse in ipairs({ "LeftButton", "RightButton" }) do
        local x = (col == 1) and CL or CR
        W.Header(page, mouse == "LeftButton" and "Left-click" or "Right-click", x, -8, 330)
        for i, m in ipairs(ns.BEE_MODIFIERS) do
            local y = -36 - (i - 1) * 32
            local label = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            label:SetPoint("TOPLEFT", page, "TOPLEFT", x, y - 5)
            label:SetText(m.text)
            local key = m.key .. mouse
            local dd = page:Add(W.Dropdown(page, "", ns.BEE_ACTIONS,
                function() return (db().clicks or {})[key] or "none" end,
                function(v)
                    db().clicks = db().clicks or {}
                    db().clicks[key] = (v ~= "none") and v or nil
                end, 210), x + 100, y)
            dd.clickKey = key
            dd.openUp = i > 4                       -- the list opens upwards from the lower rows
            dd.alignRight = col == 2                -- and leftwards in the right-hand column
        end
    end
    page:Add(W.Button(page, "Default clicks", 120, function()
        db().clicks = ns.DeepCopy(ns.BOX_DEFAULTS.clicks)
        page:SyncAll()
    end), CL, -306)
    W.Note(page, "Hold Shift, Ctrl or Alt (or a mix) as you click the bee. Clicks set to Nothing are left out "
        .. "of the bee's tooltip. A released bee is dragged with the left button.", CL + 136, -306, 560)
end

local function Build(panel)
    local C1, C2, C3 = 24, 278, 532
    local CW = 220

    ------------------------------------------------------------------
    -- Column 1: the box
    W.Header(panel, "Minimap button box", C1, -8, CW)

    panel:Add(W.Check(panel, "Gather the minimap buttons",
        function() return db().enabled end,
        function(v) db().enabled = v; Changed() end, CW), C1, -34)

    local det = panel:Add(W.Check(panel, "Detach from the minimap",
        function() return db().detached end,
        function(v) db().detached = v; if v then B.Open() end; Changed() end, CW), C1, -58)
    det.tooltip = "Off: the box opens beside the bee button. "
        .. "On: the box opens free-standing, drag it by its top strip anywhere on the screen."

    panel:Add(W.Check(panel, "Lock the detached box in place",
        function() return db().locked end,
        function(v) db().locked = v end, CW), C1, -82)

    panel:Add(W.Check(panel, "Close when the mouse leaves",
        function() return db().autoClose end,
        function(v) db().autoClose = v end, CW), C1, -106)

    panel:Add(W.Button(panel, "Open / close box", 104, function()
        B.Toggle()
    end), C1, -164)
    panel:Add(W.Button(panel, "Reset position", 104, function()
        B.ResetPosition()
        panel:SyncAll()
    end), C1 + 112, -164)
    panel:Add(W.Button(panel, "Reset all", 104, function()
        B.Reset()
        panel:SyncAll()
    end), C1, -192)

    -- the bee's clicks, in a window of their own, framed like the settings window, closed with its X
    local win = CreateFrame("Frame", "SKToolsBeeClicks", UIParent)
    win:SetSize(760, 400)
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    W.Skin(win, "dialog")
    W.TitlePlate(win, "Bee button clicks")
    local close = W.CloseButton(win, function() win:Hide() end)
    close:SetPoint("TOPRIGHT", -5, -5)
    tinsert(UISpecialFrames, "SKToolsBeeClicks")       -- Esc closes it
    local clicks = CreateFrame("Frame", nil, win)
    clicks:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -36)
    clicks:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
    W.Panel(clicks)
    BuildClicks(clicks)
    win:Hide()
    -- it goes with the settings window
    local top = _G.SKToolsSettings
    if top and top.HookScript then top:HookScript("OnHide", function() win:Hide() end) end
    panel.clicksPage = win
    win.SyncAll = function() clicks:SyncAll() end
    win.page = clicks
    panel:Add(W.Button(panel, "Bee button clicks...", 216, function()
        if win:IsShown() then win:Hide(); return end
        win:ClearAllPoints()
        win:SetPoint("CENTER", top or UIParent, "CENTER", 0, 0)
        win:SetFrameLevel(((top and top:GetFrameLevel()) or 1) + 30)
        win:Show(); clicks:SyncAll()
    end), C1, -226)

    W.Note(panel, "Buttons are only moved, not changed: click, tooltip and menu work as before, "
        .. "and each goes back to the minimap if you turn the box off or untick it in the list.",
        C1, -260, CW)

    ------------------------------------------------------------------
    -- Column 2: how it looks
    W.Header(panel, "Layout", C2, -8, CW)

    panel:Add(W.Slider(panel, "Icon size", 20, 64, 1,
        function() return db().size end,
        function(v) db().size = v; Changed() end, W.px, CW), C2, -34)

    panel:Add(W.Dropdown(panel, "Order",
        { { value = "alpha", text = "Alphabetical" }, { value = "manual", text = "Manual (drag)" } },
        function() return db().sort end,
        function(v) db().sort = v; Changed(); panel:SyncAll() end, 118), C2, -84)

    panel:Add(W.Dropdown(panel, "Count",
        { { value = "wide", text = "Icons wide" }, { value = "tall", text = "Icons tall" } },
        function() return db().fill end,
        function(v) db().fill = v; Changed(); panel:SyncAll() end, 118), C2, -114)

    local count = panel:Add(W.Slider(panel, "Icons wide", 1, 12, 1,
        function() return db().count end,
        function(v) db().count = v; Changed() end, function(v) return tostring(v) end, CW), C2, -148)
    panel.countSlider = count

    panel.orderNote = W.Note(panel, "", C2, -200, CW)

    ------------------------------------------------------------------
    -- Column 3: which buttons
    W.Header(panel, "Buttons found", C3, -8, CW)
    panel.page = 0
    panel.rows = {}
    for i = 1, ROWS do
        local row = panel:Add(W.Check(panel, "",
            function()
                local k = panel.rows[i].key
                return k ~= nil and not db().skip[k]
            end,
            function(v)
                local k = panel.rows[i].key
                if not k then return end
                db().skip[k] = (not v) or nil
                Changed()
            end, CW), C3, -32 - (i - 1) * 21)
        panel.rows[i] = row
    end
    panel.prev = panel:Add(W.Button(panel, "<", 30, function()
        panel.page = math.max(0, panel.page - 1); panel:SyncAll()
    end, 20), C3, -352)
    panel.next = panel:Add(W.Button(panel, ">", 30, function()
        panel.page = panel.page + 1; panel:SyncAll()
    end, 20), C3 + 34, -352)
    panel.pageText = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    panel.pageText:SetPoint("LEFT", panel.next, "RIGHT", 8, 0)
    panel:Add(W.Button(panel, "Rescan", 70, function()
        B.Rescan(); panel:SyncAll()
    end, 20), C3 + 150, -352)
    panel.listNote = W.Note(panel, "", C3, -380, CW)

    function panel:OnSync()
        -- wording that follows the choices
        local tall = db().fill == "tall"
        self.countSlider.title:SetText(tall and "Icons tall" or "Icons wide")
        self.orderNote:SetText(db().sort == "manual"
            and "Drag the buttons inside the box to put them in order."
            or "Switch Order to Manual to drag the buttons into your own order.")

        -- the button list, a page at a time
        local found = B.Found()
        local pages = math.max(1, math.ceil(#found / ROWS))
        if self.page >= pages then self.page = pages - 1 end
        for i = 1, ROWS do
            local row = self.rows[i]
            local e = found[self.page * ROWS + i]
            row.key = e and e.key or nil
            row:SetShown(e ~= nil)
            if e then
                row.text:SetText(e.key)
                row.box:SetHitRectInsets(0, -((row.text:GetStringWidth() or 60) + 4), 0, 0)
            end
        end
        self.prev:SetShown(pages > 1)
        self.next:SetShown(pages > 1)
        self.pageText:SetText(pages > 1 and ("page " .. (self.page + 1) .. " of " .. pages) or "")
        self.listNote:SetText(#found == 0
            and "No minimap buttons found yet. Other addons add theirs a little after login: press Rescan."
            or "Ticked buttons are in the box. Untick one to leave it on the minimap.")
        -- the list rows keep their ticks right
        for i = 1, ROWS do if self.rows[i]:IsShown() then self.rows[i]:Sync() end end
    end
end

ns.RegisterTab({
    key = "buttons", title = "Button Box", order = 1, Build = Build,
    OnShow = function(panel)
        if panel.clicksPage then panel.clicksPage:Hide() end
        B.Rescan()
        if panel.SyncAll then panel:SyncAll() end
    end,
})
