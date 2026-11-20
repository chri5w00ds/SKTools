--[[-------------------------------------------------------------------------
  SKTools - Minimap button box

  Gathers the round buttons other addons put round the minimap into one tidy
  box. Two ways to have it:

    attached   a small bee button sits on the minimap; click it and the box
               opens beside it (click again to close)
    detached   the box is free-standing: drag it by its top strip to any
               point on the screen

  Settings (Button Box tab):
    icon size            how big the buttons are in the box
    order                alphabetical, or the order you drag them into
    layout               N icons wide (rows fill left to right) or
                         N icons tall (columns fill top to bottom)
    leave on minimap     any button can be left where it is

  Buttons are only moved (re-parented, scaled and re-anchored), never
  changed; each one is handed back exactly as it was when it leaves the box
  (box turned off, or "leave on minimap" ticked). Their own click, tooltip
  and menu code keeps working. Blizzard's own minimap buttons (tracking,
  mail, zoom, calendar and so on) are never touched.
---------------------------------------------------------------------------]]

local ADDON, ns = ...

local W = ns.W
local atan2 = math.atan2 or _G.atan2

ns.BOX_DEFAULTS = {
    enabled     = true,
    detached    = false,        -- true: free-standing box, anywhere on screen
    locked      = false,        -- detached: stop the box being dragged by mistake
    size        = 32,           -- button size in the box, px
    sort        = "alpha",      -- "alpha" or "manual"
    fill        = "wide",       -- "wide": count icons per row; "tall": count icons per column
    count       = 3,
    autoClose   = false,        -- attached: close when the mouse leaves
    free        = false,        -- the bee button has been released from the minimap and sits where you dragged it
    togglePoint = nil,          -- { point, relPoint, x, y } on UIParent, while released
    point       = { "CENTER", "CENTER", 0, 0 },     -- detached position on UIParent
    order       = {},           -- manual order: button names
    skip        = {},           -- button name -> true: stays on the minimap
    -- what each click on the bee does: [modifiers .. mouse button] = action (see CLICK_ACTIONS)
    clicks      = {
        ["LeftButton"]        = "box",
        ["RightButton"]       = "buttonsTab",
        ["SHIFT-LeftButton"]  = "release",
        ["SHIFT-RightButton"] = "reset",
    },
}

-- the clicks that can be bound: every mix of Shift, Ctrl and Alt with the left and the right button
ns.BEE_MODIFIERS = {
    { key = "",               text = "Click" },
    { key = "SHIFT-",         text = "Shift" },
    { key = "CTRL-",          text = "Ctrl" },
    { key = "ALT-",           text = "Alt" },
    { key = "CTRL-SHIFT-",    text = "Ctrl+Shift" },
    { key = "ALT-SHIFT-",     text = "Alt+Shift" },
    { key = "ALT-CTRL-",      text = "Ctrl+Alt" },
    { key = "ALT-CTRL-SHIFT-", text = "Ctrl+Alt+Shift" },
}

-- what a click can do
local function OpenTab(key) return function() ns.OpenSettings(key) end end
ns.BEE_ACTIONS = {
    { value = "none",       text = "Nothing" },
    { value = "box",        text = "Open / close the box" },
    { value = "release",    text = "Release it to drag anywhere" },
    { value = "reset",      text = "Put it back on the minimap" },
    { value = "settings",   text = "SKTools settings" },
    { value = "buttonsTab", text = "Button Box settings" },
    { value = "nameplate",  text = "Nameplate settings" },
    { value = "cooldowns",  text = "Cooldowns settings" },
    { value = "widgets",    text = "Widgets settings" },
    { value = "action",     text = "Mouseover settings" },
    { value = "dbTab",      text = "Profession DB settings" },
    { value = "profiles",   text = "Profiles" },
    { value = "dbWindow",   text = "Profession DB window" },
    { value = "bars",       text = "Hide / show action bars" },
    { value = "cdm",        text = "Blizzard's Cooldown Manager" },
    { value = "unlock",     text = "Unlock / lock the panes" },
    { value = "berry",      text = "Berry Mode on / off" },
    { value = "reload",     text = "Reload the UI" },
}

local GAP, PAD, HEADER = 4, 6, 16
local BEE = 31              -- the bee button's size: in the box that opens from it, every button is this size

-- Blizzard's own minimap furniture: never gathered
local BLIZZARD = {
    MinimapZoomIn = 1, MinimapZoomOut = 1, MiniMapWorldMapButton = 1, MiniMapTracking = 1,
    MiniMapTrackingButton = 1, MiniMapMailFrame = 1, MiniMapBattlefieldFrame = 1,
    MiniMapInstanceDifficulty = 1, GameTimeFrame = 1, MinimapBackdrop = 1,
    MiniMapRecordingButton = 1, GarrisonLandingPageMinimapButton = 1,
    ExpansionLandingPageMinimapButton = 1, QueueStatusButton = 1, QueueStatusMinimapButton = 1,
    MiniMapLFGFrame = 1, AddonCompartmentFrame = 1, TimeManagerClockButton = 1,
    MinimapToggleButton = 1, MinimapCluster = 1, Minimap = 1,
}

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

local db
local box, content, host, handle, toggle, driver
local held = {}             -- button -> record
local known = {}            -- key -> true, every button that could be gathered
local hooked = {}
local warned = {}
local boxOpen = false
local dirty = true
local placing = false
local dragging
local pending = false       -- a scan was skipped in combat
local idle = 0

----------------------------------------------------------------------
-- Which buttons
----------------------------------------------------------------------

local function KeyOf(btn)
    local n = btn:GetName() or ""
    return (n:gsub("^LibDBIcon10_", ""))
end

local function Eligible(btn)
    if btn.IsForbidden and btn:IsForbidden() then return false end
    local name = btn:GetName()
    if type(name) ~= "string" or BLIZZARD[name] then return false end
    if name == "SKToolsBoxToggle" or name == "SKToolsButtonBox" then return false end
    if name:find("^LibDBIcon10_") then return true end
    -- anything else must look like a minimap button: a named button of about
    -- icon size, not a Blizzard "MiniMap..." piece or a map pin
    if name:find("^MiniMap") or name:find("^Minimap") or name:find("^HBD")
        or name:find("^HereBeDragons") or name:find("^SKToolsProfessionDB") or name:find("Pin") then
        return false
    end
    if not (btn.IsObjectType and btn:IsObjectType("Button")) then return false end
    local w = btn:GetWidth()
    return type(w) == "number" and w >= 20 and w <= 50
end

local function Capture(btn)
    local rec = {
        btn = btn, key = KeyOf(btn),
        scale = btn:GetScale() or 1,
        parent = btn:GetParent(),
        strata = btn:GetFrameStrata(), level = btn:GetFrameLevel(),
        nat = math.max(btn:GetWidth() or 31, 1),
        points = {},
        onDragStart = btn:GetScript("OnDragStart"),
        onDragStop = btn:GetScript("OnDragStop"),
    }
    -- LibDBIcon (and others) pin their button to a fixed strata and level, which makes
    -- SetFrameStrata do nothing: remember that, unpin while the button is in the box
    if btn.HasFixedFrameStrata then rec.fixS = btn:HasFixedFrameStrata() end
    if btn.HasFixedFrameLevel then rec.fixL = btn:HasFixedFrameLevel() end
    for i = 1, (btn:GetNumPoints() or 0) do rec.points[i] = { btn:GetPoint(i) } end
    held[btn] = rec
    btn:SetScript("OnDragStart", function() ns.ButtonBox.DragStart(rec) end)
    btn:SetScript("OnDragStop", function() ns.ButtonBox.DragStop(rec) end)
    -- other addons re-anchor their button now and then: notice and put it back
    if hooksecurefunc and not hooked[btn] then
        hooked[btn] = true
        hooksecurefunc(btn, "SetPoint", function(self)
            if held[self] and not placing then dirty = true end
        end)
    end
end

local function Release(btn)
    local rec = held[btn]
    if not rec then return end
    held[btn] = nil
    placing = true
    pcall(function()
        btn:SetParent(rec.parent or Minimap)
        btn:SetScale(rec.scale)
        if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(false) end
        if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(false) end
        btn:SetFrameStrata(rec.strata)
        btn:SetFrameLevel(rec.level)
        if btn.SetFixedFrameStrata and rec.fixS then btn:SetFixedFrameStrata(true) end
        if btn.SetFixedFrameLevel and rec.fixL then btn:SetFixedFrameLevel(true) end
        btn:ClearAllPoints()
        for _, p in ipairs(rec.points) do btn:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
        btn:SetScript("OnDragStart", rec.onDragStart)
        btn:SetScript("OnDragStop", rec.onDragStop)
    end)
    placing = false
end

local function ReleaseAll()
    local list = {}
    for btn in pairs(held) do list[#list + 1] = btn end
    for _, btn in ipairs(list) do Release(btn) end
    dirty = true
end

local function Scan()
    if not (db and db.enabled) or not Minimap then return end
    if InCombatLockdown and InCombatLockdown() then pending = true return end
    pending = false
    local changed = false
    for _, child in ipairs({ Minimap:GetChildren() }) do
        if not held[child] then
            local ok, yes = pcall(Eligible, child)
            if ok and yes then
                local key = KeyOf(child)
                known[key] = true
                if not db.skip[key] then
                    local okc, err = pcall(Capture, child)
                    if okc then
                        changed = true
                    else
                        held[child] = nil
                        if not warned[key] then
                            warned[key] = true
                            ns.Print("button box: could not take " .. key .. " (" .. tostring(err) .. ")")
                        end
                    end
                end
            end
        end
    end
    -- ticked "leave on minimap": hand those back
    for btn, rec in pairs(held) do
        if db.skip[rec.key] then Release(btn); changed = true end
    end
    if changed then dirty = true end
end

----------------------------------------------------------------------
-- Order and layout
----------------------------------------------------------------------

-- the buttons in the box, in display order
local function Sorted()
    local arr = {}
    for btn, rec in pairs(held) do
        if btn:IsShown() then arr[#arr + 1] = rec end     -- the owner can hide its own button
    end
    local function alpha(a, b)
        local x, y = a.key:lower(), b.key:lower()
        if x ~= y then return x < y end
        return a.key < b.key
    end
    table.sort(arr, alpha)
    if db.sort == "manual" then
        local pos = {}
        for i, k in ipairs(db.order) do pos[k] = i end
        table.sort(arr, function(a, b)
            local pa, pb = pos[a.key], pos[b.key]
            if pa and pb then return pa < pb end
            if pa then return true end          -- ordered ones first, new ones after, A-Z
            if pb then return false end
            return alpha(a, b)
        end)
    end
    return arr
end

-- columns and rows for n buttons
local function Geometry(n)
    local cnt = math.max(1, math.floor(db.count or 1))
    n = math.max(n, 1)
    if db.fill == "tall" then
        local rows = math.min(cnt, n)
        return math.ceil(n / rows), rows
    end
    local cols = math.min(cnt, n)
    return cols, math.ceil(n / cols)
end

-- the box that opens from the bee holds the bee too: it takes the corner of the grid that faces
-- the middle of the screen's edge it sits by (top right when the minimap is top right), and the
-- gathered buttons fill the other cells. A free-standing (detached) box is just the buttons.
local PlaceAttached        -- set under "Where the box is"
local function WithBee() return db and not db.detached end
local function CellSize() return WithBee() and BEE or db.size end
local function BeeSide()
    if not toggle then return false, false end
    local tx, ty = toggle:GetCenter()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    return (tx and sw and tx > sw / 2) and true or false, (ty and sh and ty > sh / 2) and true or false
end
local grid = { cols = 1, rows = 1, beeCol = 0, beeRow = 0, slots = {} }
local function CellIndex(col, row, cols, rows)
    if db.fill == "tall" then return col * rows + row + 1 end
    return row * cols + col + 1
end
local Cell
-- the grid for n gathered buttons: its size, the bee's cell, and which cell each button takes
local function Grid(n)
    local total = n + (WithBee() and 1 or 0)
    local cols, rows = Geometry(total)
    grid.cols, grid.rows, grid.slots = cols, rows, {}
    local bee
    if WithBee() then
        local right, top = BeeSide()
        grid.beeCol, grid.beeRow = right and (cols - 1) or 0, top and 0 or (rows - 1)
        bee = CellIndex(grid.beeCol, grid.beeRow, cols, rows)
    end
    grid.bee = bee
    for c = 1, cols * rows do
        if c ~= bee and #grid.slots < n then grid.slots[#grid.slots + 1] = c end
    end
    return cols, rows
end

Cell = function(i, cols, rows)
    local i0 = i - 1
    if db.fill == "tall" then return math.floor(i0 / rows), i0 % rows end     -- col, row
    return i0 % cols, math.floor(i0 / cols)
end

local function Place(rec, i, cols, rows)
    local col, row = Cell(grid.slots[i] or i, cols, rows)
    local size = CellSize()
    local scale = size / rec.nat
    local x = col * (size + GAP) + size / 2
    local y = row * (size + GAP) + size / 2
    local btn = rec.btn
    pcall(function()
        if btn:GetParent() ~= content then btn:SetParent(content) end
        if btn:GetScale() ~= scale then btn:SetScale(scale) end
        local strata, level = host:GetFrameStrata(), host:GetFrameLevel() + 5
        if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(false) end
        if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(false) end
        if btn:GetFrameStrata() ~= strata then btn:SetFrameStrata(strata) end
        if btn:GetFrameLevel() ~= level then btn:SetFrameLevel(level) end
        if btn:GetFrameStrata() ~= strata then
            -- the game would not let us move the button up: drop the box (and its frame) below it instead
            local low = btn:GetFrameStrata()
            box:SetFrameStrata(low); host:SetFrameStrata(low)
            box:SetFrameLevel(1); host:SetFrameLevel(2)
            btn:SetFrameLevel(host:GetFrameLevel() + 5)
        end
        local px, py = x / scale, -y / scale
        local p, rel, rp, ox, oy = btn:GetPoint(1)
        if btn:GetNumPoints() == 1 and p == "CENTER" and rel == content and rp == "TOPLEFT"
            and ox and oy and math.abs(ox - px) < 0.01 and math.abs(oy - py) < 0.01 then
            return                  -- already there: re-placing a button mid-click would eat the click
        end
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", content, "TOPLEFT", px, py)
    end)
end

-- how many gathered buttons their owners currently show
local function ShownCount()
    local n = 0
    for btn in pairs(held) do if btn:IsShown() then n = n + 1 end end
    return n
end

local function Layout()
    if not box then return end
    placing = true
    local arr = Sorted()
    local cols, rows = Grid(#arr)
    for i, rec in ipairs(arr) do
        if rec ~= dragging then Place(rec, i, cols, rows) end
    end
    local size = CellSize()
    local w = cols * size + (cols - 1) * GAP
    local h = rows * size + (rows - 1) * GAP
    local head = db.detached and HEADER or 0
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", box, "TOPLEFT", PAD, -(PAD + head))
    content:SetSize(w, h)
    box:SetSize(w + 2 * PAD, h + 2 * PAD + head)
    box.empty:SetShown(#arr == 0 and not WithBee())
    placing = false
    dirty = false
    box.count = #arr
    -- the attached box follows the bee: its grid may have changed shape
    if WithBee() and toggle and PlaceAttached then PlaceAttached() end
end

----------------------------------------------------------------------
-- Where the box is
----------------------------------------------------------------------

-- the button never goes away: anchored to the left-most centre of the minimap,
-- or, once released with Shift+left-click, wherever it was dragged to
local function PlaceToggle()
    if not toggle then return end
    toggle:ClearAllPoints()
    local tp = db.free and db.togglePoint
    if tp then
        toggle:SetPoint(tp[1] or "CENTER", UIParent, tp[2] or "CENTER", tp[3] or 0, tp[4] or 0)
    else
        toggle:SetPoint("CENTER", Minimap or UIParent, Minimap and "LEFT" or "CENTER", 0, 0)
    end
end

local function ReleaseToggle()
    local cx, cy = toggle:GetCenter()
    local s = toggle:GetEffectiveScale() / UIParent:GetEffectiveScale()
    db.free = true
    if cx and cy then
        db.togglePoint = { "CENTER", "BOTTOMLEFT", math.floor(cx * s + 0.5), math.floor(cy * s + 0.5) }
    elseif not db.togglePoint then
        db.togglePoint = { "CENTER", "CENTER", 0, 0 }
    end
    PlaceToggle()
end

local function ResetToggle()
    db.free = false
    db.togglePoint = nil
    PlaceToggle()
end

PlaceAttached = function()
    -- the box sits so that the bee's own cell is right where the bee is
    local step = BEE + GAP
    local x = PAD + grid.beeCol * step + BEE / 2
    local y = PAD + grid.beeRow * step + BEE / 2
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", toggle, "CENTER", -x, y)
end

-- the bee faces left while its box is open, right when it is shut; and while the box is open it
-- sits with the buttons, above the box's backing
local function SetBee(open)
    if not toggle then return end
    if toggle.icon then
        if open then toggle.icon:SetTexCoord(1, 0, 0, 1) else toggle.icon:SetTexCoord(0, 1, 0, 1) end
    end
    if open and WithBee() and host then
        toggle:SetFrameStrata(host:GetFrameStrata())
        toggle:SetFrameLevel(host:GetFrameLevel() + 6)
    else
        toggle:SetFrameStrata("HIGH")
        toggle:SetFrameLevel(20)
    end
end

local function PlaceDetached()
    local pt = db.point
    box:ClearAllPoints()
    box:SetPoint(pt[1] or "CENTER", UIParent, pt[2] or "CENTER", pt[3] or 0, pt[4] or 0)
end

local function Apply()
    if not box or not db then return end
    if not db.enabled then
        ReleaseAll()
        box:Hide()
        toggle:Hide()
        return
    end
    Scan()
    PlaceToggle()
    toggle:Show()
    handle:SetShown(db.detached)
    Layout()
    if db.detached then
        box:SetClampedToScreen(true)
        PlaceDetached()
    else
        PlaceAttached()
    end
    box:SetShown(boxOpen)
    SetBee(boxOpen)
end

----------------------------------------------------------------------
-- Dragging buttons into a new order (manual order only)
----------------------------------------------------------------------

local function OrderKeys()
    local keys = {}
    for i, rec in ipairs(Sorted()) do keys[i] = rec.key end
    return keys
end

-- put the button called key at position index in the manual order
local function Reorder(key, index)
    local keys = OrderKeys()
    for i, k in ipairs(keys) do if k == key then table.remove(keys, i) break end end
    index = math.max(1, math.min(index, #keys + 1))
    table.insert(keys, index, key)
    db.order = keys
    dirty = true
end

local function SlotUnderCursor()
    local cx, cy = GetCursorPosition()
    local s = content:GetEffectiveScale() or 1
    local l, t = content:GetLeft(), content:GetTop()
    if not (cx and cy and l and t) then return end
    cx, cy = cx / s, cy / s
    local n = box.count or 0
    local cols, rows = grid.cols, grid.rows
    local step = CellSize() + GAP
    local col = math.max(0, math.min(cols - 1, math.floor((cx - l) / step)))
    local row = math.max(0, math.min(rows - 1, math.floor((t - cy) / step)))
    local c = CellIndex(col, row, cols, rows)
    for i, slot in ipairs(grid.slots) do if slot == c then return i end end
    -- the bee's cell (or an empty one): the nearest button position
    for i = #grid.slots, 1, -1 do if grid.slots[i] < c then return i end end
    return math.max(1, math.min(1, n))
end

local function DragStart(rec)
    if db.sort ~= "manual" or (InCombatLockdown and InCombatLockdown()) then return end
    dragging = rec
    pcall(function()
        rec.btn:SetMovable(true)
        rec.btn:StartMoving()
    end)
    if GameTooltip then GameTooltip:Hide() end
end

local function DragStop(rec)
    if dragging ~= rec then return end
    pcall(function() rec.btn:StopMovingOrSizing() end)
    dragging = nil
    dirty = true
    Layout()
end

local function DragUpdate()
    if not dragging then return end
    local i = SlotUnderCursor()
    if not i then return end
    local keys = OrderKeys()
    if keys[i] ~= dragging.key then
        Reorder(dragging.key, i)
        Layout()
    end
end

----------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------

local ACTION_TEXT = {}
for _, a in ipairs(ns.BEE_ACTIONS) do ACTION_TEXT[a.value] = a.text end

-- the click held now: "ALT-CTRL-SHIFT-" as held, then the mouse button
local function ClickKey(mouse)
    local m = ""
    if IsAltKeyDown and IsAltKeyDown() then m = m .. "ALT-" end
    if IsControlKeyDown and IsControlKeyDown() then m = m .. "CTRL-" end
    if IsShiftKeyDown and IsShiftKeyDown() then m = m .. "SHIFT-" end
    return m .. (mouse or "LeftButton")
end

local function ToggleTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Minimap buttons")
    GameTooltip:AddLine((box and box.count or 0) .. " in the box", 0.7, 0.7, 0.7)
    local clicks = db and db.clicks or {}
    for _, mouse in ipairs({ "LeftButton", "RightButton" }) do
        for _, m in ipairs(ns.BEE_MODIFIERS) do
            local a = clicks[m.key .. mouse]
            if a and a ~= "none" and ACTION_TEXT[a] then
                local name = (m.key == "" and "" or (m.text .. "+")) .. (mouse == "LeftButton" and "left-click" or "right-click")
                name = name:sub(1, 1):upper() .. name:sub(2)
                GameTooltip:AddLine("|cffffffff" .. name .. "|r  " .. ACTION_TEXT[a]:lower(), 1, 0.82, 0)
            end
        end
    end
    if db and db.free then GameTooltip:AddLine("|cffffffffDrag|r  move this button", 1, 0.82, 0) end
    GameTooltip:Show()
end

local function Build()
    -- the box
    box = CreateFrame("Frame", "SKToolsButtonBox", UIParent)
    box:SetFrameStrata("HIGH")
    box:SetClampedToScreen(true)
    box:SetMovable(true)
    box:EnableMouse(true)
    box:Hide()
    W.Skin(box, "inset")            -- the thin bronze-edged navy box: the dialog border is too thick for a small box
    -- the buttons live on their own frame, a whole strata above the box, so the box's
-- backdrop can never draw over them or catch their clicks
    host = CreateFrame("Frame", "SKToolsBoxButtons", UIParent)
    host:SetFrameStrata("DIALOG")
    host:SetFrameLevel(30)
    host:SetAllPoints(box)
    host:Hide()
    box:SetScript("OnShow", function() host:Show() end)
    box:SetScript("OnHide", function() host:Hide() end)
    content = CreateFrame("Frame", nil, host)
    content:SetSize(10, 10)
    box.empty = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    box.empty:SetPoint("CENTER", content, "CENTER")
    box.empty:SetText("No minimap\nbuttons found")
    box.empty:Hide()

    -- the strip you drag a detached box by, with the button that puts it back
    handle = CreateFrame("Frame", nil, box)
    handle:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
    handle:SetPoint("TOPRIGHT", box, "TOPRIGHT", -4, -4)
    handle:SetHeight(HEADER - 2)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    local hl = handle:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints()
    hl:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.12)
    local title = handle:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    title:SetPoint("LEFT", 4, 0)
    title:SetText("Buttons")
    local attach = CreateFrame("Button", nil, handle)
    attach:SetSize(40, HEADER - 2)
    attach:SetPoint("RIGHT", 0, 0)
    local at = attach:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    at:SetPoint("CENTER")
    at:SetText("Attach")
    attach:SetScript("OnClick", function()
        db.detached = false
        boxOpen = false
        Apply()
        if ns.RefreshSettings then ns.RefreshSettings() end
    end)
    attach:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Put the box back on the minimap", 1, 1, 1)
        GameTooltip:Show()
    end)
    attach:SetScript("OnLeave", function() GameTooltip:Hide() end)
    handle:SetScript("OnDragStart", function()
        if not db.locked then box:StartMoving() end
    end)
    handle:SetScript("OnDragStop", function()
        box:StopMovingOrSizing()
        local p, _, rp, x, y = box:GetPoint(1)
        if p then db.point = { p, rp, x, y } end
    end)
    handle:Hide()

    -- the bee button: always on screen while the box is on
    toggle = CreateFrame("Button", "SKToolsBoxToggle", UIParent)
    toggle:SetSize(31, 31)
    toggle:SetFrameStrata("HIGH")
    toggle:SetFrameLevel(20)
    toggle:SetMovable(true)
    toggle:SetClampedToScreen(true)
    toggle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    toggle:RegisterForDrag("LeftButton")
    toggle:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = toggle:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER")
    local icon = toggle:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.MEDIA .. "LogoSmall")      -- the bee
    toggle.icon = icon
    icon:SetSize(21, 21)
    icon:SetPoint("CENTER")
    local border = toggle:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    toggle:SetScript("OnClick", function(self, mouse)
        local action = (db.clicks or {})[ClickKey(mouse)] or "none"
        ns.ButtonBox.Do(action)
        if self.IsMouseOver and self:IsMouseOver() and GameTooltip.GetOwner and GameTooltip:GetOwner() == self then
            ToggleTooltip(self)                     -- the tooltip follows (a released bee says "Drag")
        end
    end)
    toggle:SetScript("OnDragStart", function(self)
        if not db.free then return end              -- anchored until released with Shift+left-click
        GameTooltip:Hide()
        self:StartMoving()
        self:SetScript("OnUpdate", function()
            if box:IsShown() and not db.detached then PlaceAttached() end
        end)
    end)
    toggle:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:StopMovingOrSizing()
        if not db.free then return end
        local p, _, rp, x, y = self:GetPoint(1)
        if p then db.togglePoint = { p, rp or p, x or 0, y or 0 } end
        PlaceToggle()
        if box:IsShown() and not db.detached then PlaceAttached() end
    end)
    toggle:SetScript("OnEnter", ToggleTooltip)
    toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    PlaceToggle()
    toggle:Hide()

    -- housekeeping: re-place buttons that moved, close on leave, drag order
    driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, elapsed)
        if dragging then DragUpdate() end
        idle = idle + elapsed
        if idle < 0.25 then return end
        idle = 0
        if pending then Scan() end
        if box.count ~= ShownCount() then dirty = true end      -- an addon hid or showed its button
        if dirty and not dragging then Layout() end
        if db.enabled and not db.detached and boxOpen and db.autoClose then
            local over = (box.IsMouseOver and box:IsMouseOver()) or (toggle.IsMouseOver and toggle:IsMouseOver())
            box.away = over and 0 or ((box.away or 0) + 0.25)
            if box.away >= 1.2 then
                boxOpen = false
                box:Hide()
                SetBee(false)
            end
        end
    end)
    ns.Profile("Button box", driver)
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------

local function Later(secs, fn)
    if C_Timer and C_Timer.After then C_Timer.After(secs, fn) else fn() end
end

local function Rescan()
    if not box then return end
    Scan()
    if dirty or box.count ~= ShownCount() then Layout() end
    if not db.detached and boxOpen then PlaceAttached() end
end

-- what each bindable action does
local DO = {
    none = function() end,
    box = function() ns.ButtonBox.Toggle() end,
    release = function() ReleaseToggle() end,
    reset = function()
        ResetToggle()
        if box and box:IsShown() and not db.detached then PlaceAttached() end
    end,
    settings = function() if ns.ToggleSettings then ns.ToggleSettings() end end,
    buttonsTab = OpenTab("buttons"),
    nameplate = OpenTab("nameplate"),
    cooldowns = OpenTab("cooldowns"),
    widgets = OpenTab("widgets"),
    action = OpenTab("action"),
    dbTab = OpenTab("db"),
    profiles = OpenTab("profiles"),
    dbWindow = function() if SKToolsProfessionDB and SKToolsProfessionDB.Toggle then SKToolsProfessionDB:Toggle() end end,
    cdm = function() if ns.OpenCooldownManager then ns.OpenCooldownManager() end end,
    -- the Action Bar tab's main switch: the bars ticked there hide until hovered, or all show
    bars = function()
        local h = ns.Hover and ns.Hover.Settings and ns.Hover.Settings()
        if not h then return end
        h.enabled = not h.enabled
        ns.Hover.Refresh()
        ns.Print(h.enabled and "action bars hide until hovered." or "action bars always show.")
    end,
    unlock = function()
        -- the cooldown panes and the widget panes together
        local cd = ns.Cooldowns and ns.Cooldowns.Settings()
        local bw = ns.Buffs and ns.Buffs.Settings()
        local on = not ((cd and cd.unlocked) or (bw and bw.unlocked))
        if cd then cd.unlocked = on; ns.Cooldowns.Refresh() end
        if bw then bw.unlocked = on; if ns.Buffs.Refresh then ns.Buffs.Refresh() end end
        ns.Print(on and "panes unlocked: drag them where you like." or "panes locked.")
    end,
    berry = function()
        ns.SetBerryMode(not ns.BerryMode())
        ns.Print("Berry Mode " .. (ns.BerryMode() and "on." or "off."))
    end,
    reload = function() if ReloadUI then ReloadUI() end end,
}

ns.ButtonBox = {
    Settings = function() return db end,
    Do = function(action) local f = DO[action]; if f then f() end end,
    ClickKey = ClickKey,
    Apply = function() Apply() end,
    Rescan = Rescan,
    DragStart = DragStart,
    DragStop = DragStop,
    DragTick = DragUpdate,
    Reorder = function(key, index) Reorder(key, index); if box then Layout() end end,
    OrderKeys = OrderKeys,
    Geometry = Geometry,
    Grid = function() return grid end,
    Count = function() return box and box.count or 0 end,
    IsOpen = function() return box and box:IsShown() or false end,
    Open = function()
        if not db.enabled then return end
        boxOpen = true
        Apply()
    end,
    Close = function()
        boxOpen = false
        if box then box:Hide() end
        SetBee(false)
    end,
    Toggle = function()
        if not db.enabled then return end
        boxOpen = not boxOpen
        Apply()
    end,
    ResetPosition = function()
        db.point = { "CENTER", "CENTER", 0, 0 }
        db.free, db.togglePoint = false, nil
        if box then PlaceToggle(); Apply() end
    end,
    Reset = function()
        local keep = { order = db.order, skip = db.skip }
        for k in pairs(db) do db[k] = nil end
        DeepFill(db, ns.BOX_DEFAULTS)
        db.order, db.skip = keep.order, keep.skip           -- what you arranged is not a setting
        if box then PlaceToggle(); Apply() end
    end,
    -- every button that could be in the box: { key, collected }, A-Z
    Found = function()
        local out = {}
        for key in pairs(known) do out[#out + 1] = { key = key, collected = not db.skip[key] and db.enabled } end
        table.sort(out, function(a, b) return a.key:lower() < b.key:lower() end)
        return out
    end,
    -- /skt boxdebug: what each gathered button looks like to the game, and what is under the mouse
    Probe = function(print)
        local function N(o) return o and ((o.GetName and o:GetName()) or (o.GetObjectType and o:GetObjectType()) or "?") or "nil" end
        local function Info(o)
            local function try(m, ...) if o[m] then local ok, v = pcall(o[m], o, ...) if ok then return tostring(v) end end return "?" end
            return ("%s parent=%s strata=%s level=%s alpha=%s eff=%s scale=%s mouse=%s enabled=%s shown=%s"):format(
                N(o), N(o:GetParent()), try("GetFrameStrata"), try("GetFrameLevel"), try("GetAlpha"),
                try("GetEffectiveAlpha"), try("GetEffectiveScale"), try("IsMouseEnabled"), try("IsEnabled"), try("IsVisible"))
        end
        print("box:  " .. (box and Info(box) or "none"))
        print("host: " .. (host and Info(host) or "none"))
        local n = 0
        for btn in pairs(held) do
            n = n + 1
            if n <= 4 then print("btn:  " .. Info(btn)) end
        end
        print("Hover a button in the box now - reading the mouse in 5 seconds...")
        Later(5, function()
            local list = {}
            if GetMouseFoci then list = GetMouseFoci() or {}
            elseif GetMouseFocus then list = { GetMouseFocus() } end
            for i, o in ipairs(list) do
                if i <= 3 then print("under the mouse: " .. Info(o)) end
            end
            if #list == 0 then print("under the mouse: nothing reported") end
        end)
    end,
    Debug = function(print)
        print(("button box: enabled=%s, %s, %d in the box, %d known, sort=%s, %s x %s"):format(
            tostring(db and db.enabled), (db and db.detached) and "detached" or "attached to the minimap",
            box and box.count or 0, (function() local n = 0 for _ in pairs(known) do n = n + 1 end return n end)(),
            tostring(db and db.sort), tostring(db and db.fill), tostring(db and db.count)))
    end,
}

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")
pcall(f.RegisterEvent, f, "ADDON_LOADED")
pcall(f.RegisterEvent, f, "PLAYER_REGEN_ENABLED")
local soon
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitDB().buttonBox
        DeepFill(root, ns.BOX_DEFAULTS)
        db = root
        local ok, err = pcall(Build)
        if not ok then ns.Print("|cffff5555button box error:|r " .. tostring(err)) return end
        Apply()
        -- other addons create their buttons a little after login
        for _, t in ipairs({ 1, 3, 6, 12 }) do Later(t, Rescan) end
    elseif not box then
        return
    elseif event == "ADDON_LOADED" then
        if not soon then
            soon = true
            Later(1, function() soon = false; Rescan() end)
        end
    else
        Rescan()
    end
end)
