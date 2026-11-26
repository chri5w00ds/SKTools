--[[-------------------------------------------------------------------------
  SKTools - action bars that only show when you hover over them

  A master switch, and a switch per bar. A bar that is switched on fades out
  and comes back while the mouse is over it (and for a moment after, so you
  can move between bars). Every bar shows while:
    * you are dragging a spell, item or macro (so you can drop it on a bar)
    * Edit Mode is open
    * a spell flyout is open
  The flight path / vehicle exit button, which sits inside Action Bar 1,
  never fades with it.

  Only the bars' opacity is changed. The game allows that on action bars at
  any time, combat included, and a faded bar's buttons still work (and still
  answer their key bindings). Default Blizzard bars only, plus the XP bar and
  the second status bar (reputation, honor...).
---------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

-- each bar: the frame names it may go by (the first that exists is used) and its buttons
ns.HOVER_BARS = {
    { key = "bar1", label = "Action Bar 1", frames = { "MainActionBar", "MainMenuBar" }, buttons = "ActionButton" },
    { key = "bar2", label = "Action Bar 2", frames = { "MultiBarBottomLeft" }, buttons = "MultiBarBottomLeftButton" },
    { key = "bar3", label = "Action Bar 3", frames = { "MultiBarBottomRight" }, buttons = "MultiBarBottomRightButton" },
    { key = "bar4", label = "Action Bar 4", frames = { "MultiBarRight" }, buttons = "MultiBarRightButton" },
    { key = "bar5", label = "Action Bar 5", frames = { "MultiBarLeft" }, buttons = "MultiBarLeftButton" },
    { key = "bar6", label = "Action Bar 6", frames = { "MultiBar5" }, buttons = "MultiBar5Button" },
    { key = "bar7", label = "Action Bar 7", frames = { "MultiBar6" }, buttons = "MultiBar6Button" },
    { key = "bar8", label = "Action Bar 8", frames = { "MultiBar7" }, buttons = "MultiBar7Button" },
    { key = "stance", label = "Stance bar", frames = { "StanceBar", "StanceBarFrame" }, buttons = "StanceButton", count = 10 },
    { key = "pet", label = "Pet bar", frames = { "PetActionBar", "PetActionBarFrame" }, buttons = "PetActionButton", count = 10 },
    { key = "xp", label = "XP bar", frames = { "MainStatusTrackingBarContainer", "MainMenuExpBar" } },
    { key = "status2", label = "Status bar 2", frames = { "SecondaryStatusTrackingBarContainer", "ReputationWatchBar" } },
}

ns.HOVER_DEFAULTS = {
    enabled = false,         -- master switch
    bars = {},               -- [key] = true fades that bar; unticked (the default) keeps it shown
    linger = 0.5,            -- seconds a bar stays after the mouse leaves it
    fade = 0.15,             -- seconds to fade in or out
}

local db
local touched = {}           -- bars whose opacity we changed: handed back at 1 when switched off

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

local function BarFrame(bar)
    for _, name in ipairs(bar.frames) do
        local f = _G[name]
        if type(f) == "table" and f.SetAlpha then return f, name end
    end
end

-- The mouse over the bar: one check a bar, against the bar's area - its frame, grown to take in its
-- buttons (on older clients they can sit outside it). The area is measured once a second, not on
-- every check; the check itself is a little arithmetic on the cursor's place.
local areas = {}              -- [bar key] = { left, bottom, right, top } in screen pixels
local function Measure(bar, f)
    local L, B, R, T
    local function Take(fr)
        if not (fr and fr.GetLeft) then return end
        local okV, vis = pcall(fr.IsVisible, fr)
        if not (okV and vis) then return end
        local s = fr:GetEffectiveScale() or 1
        local l, b, w, h = fr:GetLeft(), fr:GetBottom(), fr:GetWidth(), fr:GetHeight()
        if not (l and b and w and h) or w <= 0 or h <= 0 then return end
        l, b = l * s, b * s
        local r, t = l + w * s, b + h * s
        L = L and math.min(L, l) or l; B = B and math.min(B, b) or b
        R = R and math.max(R, r) or r; T = T and math.max(T, t) or t
    end
    Take(f)
    if bar.buttons then
        for i = 1, bar.count or 12 do Take(_G[bar.buttons .. i]) end
    end
    areas[bar.key] = L and { L, B, R, T } or false
end
local cx, cy = 0, 0           -- the cursor, read once a step
local function Hovered(bar, f)
    local a = areas[bar.key]
    if a == nil then Measure(bar, f); a = areas[bar.key] end
    if not a then return false end
    return cx >= a[1] and cx <= a[3] and cy >= a[2] and cy <= a[4]
end

-- every bar shows while you are placing something on one, in Edit Mode, or with a flyout open
local function ShowAll()
    if _G.GetCursorInfo then
        local ok, kind = pcall(GetCursorInfo)
        if ok and (kind == "spell" or kind == "item" or kind == "macro" or kind == "petaction" or kind == "mount" or kind == "flyout") then
            return true, "dragging"
        end
    end
    local em = _G.EditModeManagerFrame
    if em and em.IsEditModeActive then
        local ok, on = pcall(em.IsEditModeActive, em)
        if ok and on then return true, "Edit Mode" end
    end
    local fly = _G.SpellFlyout
    if fly and fly.IsShown and fly:IsShown() then return true, "flyout open" end
    return false
end

-- buttons Blizzard keeps inside a bar that must never fade with it: the flight path / vehicle exit
-- button lives in Action Bar 1's frame. It is set to ignore its bar's opacity while that bar fades;
-- on a client without that, the bar itself stays shown while the button is up.
local KEEP = { "MainMenuBarVehicleLeaveButton" }
local kept = {}              -- [button] = the bar frame it was freed from

local function Inside(child, f)
    local p = child.GetParent and child:GetParent()
    for _ = 1, 12 do
        if not p then return false end
        if p == f then return true end
        p = p.GetParent and p:GetParent()
    end
    return false
end

-- frees the exit button from a fading bar; true when the bar must stay shown instead
local function KeepButtons(f)
    local hold = false
    for _, name in ipairs(KEEP) do
        local b = _G[name]
        if type(b) == "table" and Inside(b, f) then
            if b.SetIgnoreParentAlpha then
                if kept[b] ~= f then
                    local ok = pcall(b.SetIgnoreParentAlpha, b, true)
                    if ok then kept[b] = f else hold = hold or (b.IsShown and b:IsShown()) end
                end
            elseif b.IsShown and b:IsShown() then
                hold = true
            end
        end
    end
    return hold
end
local function ReleaseButtons(f)
    for b, from in pairs(kept) do
        if from == f then
            pcall(b.SetIgnoreParentAlpha, b, false)
            kept[b] = nil
        end
    end
end

local function Wanted(bar)
    return db and db.enabled and db.bars[bar.key] == true
end

local state = {}             -- [key] = { alpha, lastOver, why }
local busy = false            -- a bar mid-fade or lingering: keep stepping smoothly
local function Step(elapsed)
    busy = false
    cx, cy = GetCursorPosition()
    local all, allWhy = ShowAll()
    for _, bar in ipairs(ns.HOVER_BARS) do
        local f = BarFrame(bar)
        local st = state[bar.key] or { alpha = 1, lastOver = -100 }
        state[bar.key] = st
        if f then
            if Wanted(bar) then
                local now = GetTime()
                local over = Hovered(bar, f)
                if over then st.lastOver = now end
                local hold = KeepButtons(f)
                local show = all or over or hold or (now - st.lastOver) < (db.linger or 0.5)
                st.why = all and allWhy or (over and "mouse over it") or (hold and "exit button up")
                    or (show and "just left") or "hidden"
                local target = show and 1 or 0
                local rate = elapsed / math.max(db.fade or 0.15, 0.01)
                if st.alpha < target then st.alpha = math.min(target, st.alpha + rate)
                elseif st.alpha > target then st.alpha = math.max(target, st.alpha - rate) end
                if st.alpha ~= target or (show and not over and not all and not hold) then busy = true end
                -- Blizzard may set the bar's opacity itself: ours goes back whenever it differs
                if math.abs((f:GetAlpha() or 1) - st.alpha) > 0.001 then f:SetAlpha(st.alpha) end
                touched[f] = true
            elseif touched[f] then
                f:SetAlpha(1)
                touched[f] = nil
                ReleaseButtons(f)
                st.alpha, st.why = 1, "always shown"
            else
                st.why = "always shown"
            end
        else
            st.why = "not found"
        end
    end
end

-- Smooth steps (30 a second) only while something moves: the cursor, or a bar fading or lingering.
-- Otherwise a look ten times a second (Blizzard may set a bar's opacity itself), and the bars'
-- areas measured again once a second.
local driver = CreateFrame("Frame")
local acc, measureAcc = 0, 0
local lastX, lastY
driver:SetScript("OnUpdate", function(_, elapsed)
    acc, measureAcc = acc + elapsed, measureAcc + elapsed
    if acc < 0.03 then return end
    if not db then acc = 0; return end
    -- nothing to do while switched off, once the bars have been handed back
    if not db.enabled and next(touched) == nil then acc = 0; return end
    if measureAcc >= 1 then measureAcc = 0; wipe(areas) end
    local x, y = GetCursorPosition()
    local moved = x ~= lastX or y ~= lastY
    lastX, lastY = x, y
    if not (busy or moved) and acc < 0.1 then return end      -- (the time keeps counting)
    local dt = acc
    acc = 0
    Step(dt)
end)
driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function()
    local root = ns.InitDB().range
    root.statusBars = nil            -- the status bar width sliders (2.16.0 preview) are gone
    root.hover = root.hover or {}
    DeepFill(root.hover, ns.HOVER_DEFAULTS)
    db = root.hover
end)

ns.Hover = {
    Settings = function() return db end,
    Refresh = function() wipe(areas); Step(1) end,
    Reset = function()
        local root = ns.InitDB().range
        root.hover = {}
        DeepFill(root.hover, ns.HOVER_DEFAULTS)
        db = root.hover
        Step(1)
    end,
    Bars = function() return ns.HOVER_BARS end,
    Exists = function(bar) return BarFrame(bar) ~= nil end,
    State = function(key) return state[key] end,
    Debug = function(print)
        print(("hover bars: %s"):format(db and db.enabled and "on" or "off"))
        for _, bar in ipairs(ns.HOVER_BARS) do
            local f, name = BarFrame(bar)
            local st = state[bar.key] or {}
            print(("  %s: %s, %s, %s, opacity %.2f"):format(bar.label, name or "no frame",
                Wanted(bar) and "fades" or "always shown", tostring(st.why or "-"), f and (f:GetAlpha() or 1) or 0))
        end
    end,
}

-- timed by /skt cpu
ns.Profile("Action bar fade", driver)
