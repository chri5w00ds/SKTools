-- SKTools: a Profession DB, nameplates, cooldown panes, action bars on mouseover, the
-- Hunter range crescent and a minimap button box, in one addon for WoW Forever.
--
-- This file is the shared core: saved variables, profiles, the settings-tab registry and the slash
-- command. Each feature lives in Modules/ and keeps its own table of settings:
--
--   .db     Profession DB
--   .marks  Nameplate quest marks
--   .range  Nameplates, range crescent (.crescent), action bar mouseover (.hover), combo points (.combo),
--           cooldown panes (.cooldowns), widgets (.buffs) and the rest
--
-- And tables that are always account-wide: .minimap, .window, .buttonBox (the minimap button box).
--
-- Profiles: those tables normally live in SKToolsDB, which is saved per account, so a change
-- applies to every character. A character can opt into its own copy (SKToolsCharDB.profile,
-- Profiles tab); then the modules are handed that copy instead. Modules never look at the saved
-- variables themselves, only at what ns.InitDB() returns.

local ADDON, ns = ...

SKTools = ns
ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

local CA = C_AddOns or {}
local GetMeta = CA.GetAddOnMetadata or _G.GetAddOnMetadata
ns.version = (GetMeta and GetMeta(ADDON, "Version")) or "?"

local PREFIX = "|cffffd200SKTools|r"

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. ": " .. tostring(msg))
end

-- a Print for one module, e.g. "SKTools (Range): ..."
function ns.Printer(tag)
    local head = PREFIX .. " |cffaaaaaa(" .. tag .. ")|r: "
    return function(msg) DEFAULT_CHAT_FRAME:AddMessage(head .. tostring(msg)) end
end

local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local t = {}
    for k, v in pairs(src) do t[k] = DeepCopy(v) end
    return t
end
ns.DeepCopy = DeepCopy


----------------------------------------------------------------------
-- Saved variables
----------------------------------------------------------------------

local PARTS = { "db", "marks", "range" }

-- Safe to call from any module once ADDON_LOADED has fired for SKTools.
-- Returns the settings in use (account-wide, or this character's own) and
-- the per-character data.
function ns.InitDB()
    if ns.root then return ns.root, ns.char end
    -- a fresh install starts from the starter settings (Starter.lua); the modules fill in the rest
    if SKToolsDB == nil and type(ns.STARTER) == "table" then SKToolsDB = DeepCopy(ns.STARTER) end
    SKToolsDB = SKToolsDB or {}
    SKToolsCharDB = SKToolsCharDB or {}
    local acc, char = SKToolsDB, SKToolsCharDB

    if type(acc.minimap) ~= "table" then acc.minimap = {} end
    if acc.minimap.hide == nil then acc.minimap.hide = false end
    if acc.minimap.angle == nil then acc.minimap.angle = 210 end
    if type(acc.window) ~= "table" then acc.window = {} end
    if type(acc.buttonBox) ~= "table" then acc.buttonBox = {} end
    -- left over from older versions: the copied-in settings of the old separate addons, and the
    -- Blizzard resource display's settings (that part is gone)
    acc.imported, acc.prd, char.imported = nil, nil, nil
    if type(char.profile) == "table" then char.profile.prd = nil end
    -- the action bar tint is gone (3.7.0)
    if type(acc.range) == "table" then acc.range.tint = nil end
    if type(char.profile) == "table" and type(char.profile.range) == "table" then char.profile.range.tint = nil end
    if type(acc.charProfiles) ~= "table" then acc.charProfiles = {} end
    for _, k in ipairs(PARTS) do
        if type(acc[k]) ~= "table" then acc[k] = {} end
    end

    for _, k in ipairs({ "db", "marks" }) do
        if type(char[k]) ~= "table" then char[k] = {} end
    end

    -- which copy of the four settings tables the modules get
    local src = acc
    if char.useOwn then
        if type(char.profile) ~= "table" then char.profile = {} end
        for _, k in ipairs(PARTS) do
            -- a part with no copy yet starts from the account's settings
            if type(char.profile[k]) ~= "table" then char.profile[k] = DeepCopy(acc[k]) end
        end
        src = char.profile
        -- things the addon has learned are facts, not preferences: every
        -- character keeps sharing them (mobs that drop quest starters, melee
        -- spells this client reports wrongly)
        if type(acc.marks.starters) ~= "table" then acc.marks.starters = {} end
        if type(acc.range.meleeBad) ~= "table" then acc.range.meleeBad = {} end
        src.marks.starters = acc.marks.starters
        src.range.meleeBad = acc.range.meleeBad
    end

    ns.account, ns.char = acc, char
    ns.root = {
        -- always account-wide
        minimap = acc.minimap, window = acc.window, buttonBox = acc.buttonBox,
        -- account-wide, or this character's own
        db = src.db, marks = src.marks, range = src.range,
    }
    return ns.root, ns.char
end

----------------------------------------------------------------------
-- Profiles. The modules keep hold of their settings table from the moment
-- they load, so every change of profile is followed by a UI reload.
----------------------------------------------------------------------

function ns.UsingCharProfile()
    ns.InitDB()
    return ns.char.useOwn and true or false
end

function ns.HasCharProfile()
    ns.InitDB()
    return type(ns.char.profile) == "table"
end

local function CharKey()
    local name = UnitName and UnitName("player")
    if not name then return nil end
    local realm = GetRealmName and GetRealmName()
    return realm and realm ~= "" and (name .. " - " .. realm) or name
end
ns.CharKey = CharKey

-- remember which characters have their own settings, to list on the Profiles tab
local function NoteCharProfile()
    ns.InitDB()
    local key = CharKey()
    if key then ns.account.charProfiles[key] = ns.char.useOwn and true or nil end
end

-- on = true: this character uses its own settings (an existing copy is kept,
-- a new one starts from the account's). Reload afterwards.
function ns.SetCharProfile(on)
    ns.InitDB()
    ns.char.useOwn = on and true or nil
    NoteCharProfile()
end

-- overwrite this character's copy with the account's settings. Reload afterwards.
function ns.CopyAccountToChar()
    ns.InitDB()
    ns.char.profile = {}
    for _, k in ipairs(PARTS) do ns.char.profile[k] = DeepCopy(ns.account[k]) end
end

-- make this character's settings the account's. Reload afterwards.
function ns.CopyCharToAccount()
    ns.InitDB()
    if type(ns.char.profile) ~= "table" then return end
    for _, k in ipairs(PARTS) do
        if type(ns.char.profile[k]) == "table" then ns.account[k] = DeepCopy(ns.char.profile[k]) end
    end
end

-- ask, then run fn and reload the UI
function ns.ConfirmReload(text, fn)
    if not (StaticPopupDialogs and StaticPopup_Show) then
        fn(); ReloadUI()
        return
    end
    StaticPopupDialogs["SKTOOLS_RELOAD"] = {
        text = "%s",
        button1 = "Reload",
        button2 = "Cancel",
        OnAccept = function() fn(); ReloadUI() end,
        OnCancel = function() ns.RefreshSettings() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("SKTOOLS_RELOAD", text .. "\n\nThe interface reloads to apply it.")
end

----------------------------------------------------------------------
-- Settings tabs (built by Settings.lua, filled in by the modules)
----------------------------------------------------------------------

ns.tabs = {}

----------------------------------------------------------------------
-- Berry Mode: a mode for the whole addon (it began as a nameplate option, every enemy bar red).
-- It keeps to what it has always used: the nameplates (in red), the action bar, the Profession DB,
-- the Button Box and the profiles. Everything else, the cooldown panes, our resource display, the
-- widgets, and any feature added from now on, starts off in Berry Mode, but has its own switch there:
-- a Berry Mode player turns on what they like. Such a feature keeps two switches, enabled (normal)
-- and berryEnabled (Berry Mode, off until turned on), read through ns.FeatureOn.
-- Saved with the nameplate settings (as before), so it follows the profile: account-wide or a
-- character's own.
----------------------------------------------------------------------

function ns.BerryMode()
    local root = ns.root
    local plates = root and root.range and root.range.plates
    return plates and plates.berry == true or false
end

function ns.SetBerryMode(v)
    local root = ns.InitDB()
    root.range.plates = root.range.plates or {}
    root.range.plates.berry = v and true or false
    for _, m in ipairs({ ns.Plates, ns.Cooldowns, ns.Buffs }) do
        if m and m.Refresh then pcall(m.Refresh) end
    end
    if ns.RefreshTabs then ns.RefreshTabs() end
end

-- a feature's own on / off, for the mode in use (see Berry Mode above)
function ns.FeatureOn(t)
    if type(t) ~= "table" then return false end
    if ns.BerryMode() then return t.berryEnabled == true end
    return t.enabled ~= false
end
function ns.SetFeatureOn(t, v)
    if type(t) ~= "table" then return end
    if ns.BerryMode() then t.berryEnabled = v and true or false else t.enabled = v and true or false end
end

-- tab = { key, title, order, Build = function(panel) end, OnShow = fn, OnHide = fn }
function ns.RegisterTab(tab)
    ns.tabs[#ns.tabs + 1] = tab
    table.sort(ns.tabs, function(a, b) return (a.order or 99) < (b.order or 99) end)
end

-- These are replaced by Settings.lua; the stubs keep early callers safe.
function ns.OpenSettings() end
function ns.ToggleSettings() end
function ns.RefreshSettings() end

-- The stand-alone bee button is gone: the bag button of the Button Box does its job.
-- The old commands that toggled it now just open or close the box.
function ns.SetMinimapButtonShown() end

function ns.ToggleMinimapButton()
    if ns.ButtonBox and ns.ButtonBox.Toggle then ns.ButtonBox.Toggle() end
end

----------------------------------------------------------------------
-- Startup
----------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON then return end
        ns.InitDB()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        NoteCharProfile()
    end
end)

----------------------------------------------------------------------
-- /skt
----------------------------------------------------------------------

local TAB_ALIASES = {
    db = "db", prof = "db",
    action = "action", mouseover = "action", bars = "action",
    quests = "quests", quest = "quests", tracker = "quests",
    widgets = "widgets", buffs = "widgets",
    cursor = "cursor",
    keybinds = "keybinds", keys = "keybinds",
    cooldowns = "cooldowns", cd = "cooldowns", prd = "cooldowns",
    nameplate = "nameplate", nameplates = "nameplate", plates = "nameplate", marks = "nameplate", range = "nameplate",
    profiles = "profiles", profile = "profiles",
    buttons = "buttons", box = "buttons",
}
ns.TAB_ALIASES = TAB_ALIASES

----------------------------------------------------------------------
-- /skt cpu: how much time each part of the addon takes. Each part's driver frame has its scripts
-- wrapped (ns.Profile); while a measurement runs, each call is timed. Off, the wrapper costs one
-- check per call.
----------------------------------------------------------------------
local prof = { on = false, t = {}, n = {} }
local function Clock()
    if debugprofilestop then return debugprofilestop() end
    return GetTime() * 1000
end
function ns.Timed(name, fn)
    return function(...)
        if not prof.on then return fn(...) end
        local s = Clock()
        fn(...)
        prof.t[name] = (prof.t[name] or 0) + (Clock() - s)
        prof.n[name] = (prof.n[name] or 0) + 1
    end
end
function ns.Profile(name, frame)
    if not (frame and frame.GetScript) then return end
    for _, sc in ipairs({ "OnUpdate", "OnEvent" }) do
        local f = frame:GetScript(sc)
        if f then frame:SetScript(sc, ns.Timed(name, f)) end
    end
end
----------------------------------------------------------------------
-- The report log. Every /skt report (cpu and the debug ones) is kept in SKToolsLog, which the game
-- writes to WTF/Account/<account>/SavedVariables/SKTools.lua at /reload or logout; /skt log shows it
-- in a window you can copy from. The newest reports are kept, up to LOG_MAX lines.
----------------------------------------------------------------------
local LOG_MAX = 3000
local function Log()
    if type(SKToolsLog) ~= "table" then SKToolsLog = {} end
    if type(SKToolsLog.lines) ~= "table" then SKToolsLog.lines = {} end
    return SKToolsLog.lines
end
local function AddReport(title, lines)
    local log = Log()
    local stamp = (date and date("%Y-%m-%d %H:%M:%S")) or tostring(GetTime())
    log[#log + 1] = ("==== %s  /skt %s  (SKTools %s)"):format(stamp, title, tostring(ns.version))
    for _, l in ipairs(lines) do log[#log + 1] = tostring(l) end
    log[#log + 1] = ""
    local extra = #log - LOG_MAX
    if extra > 0 then
        local keep = {}
        for i = extra + 1, #log do keep[#keep + 1] = log[i] end
        SKToolsLog.lines = keep
    end
end

-- a few lines into the log quietly (no chat line): for tracers that write as things happen
function ns.LogAdd(title, lines) AddReport(title, lines) end

local logWin
local function LogText()
    return table.concat(Log(), "\n")
end
local BuildLog
function ns.ShowLog()
    -- anything going wrong here is said in chat, so it can be passed on
    local ok, err = pcall(BuildLog)
    if not ok then ns.Print("the log window could not open: " .. tostring(err)); return end
end
BuildLog = function()
    local W = ns.W
    if not logWin then
        local win = CreateFrame("Frame", "SKToolsLogWindow", UIParent)
        win:SetSize(720, 460)
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)        -- (without a place it was never drawn)
        win:SetFrameStrata("DIALOG")
        win:SetToplevel(true)
        win:EnableMouse(true)
        win:SetMovable(true)
        win:SetClampedToScreen(true)
        win:RegisterForDrag("LeftButton")
        win:SetScript("OnDragStart", win.StartMoving)
        win:SetScript("OnDragStop", win.StopMovingOrSizing)
        W.Skin(win, "dialog")
        W.TitlePlate(win, "SKTools report log")
        local close = W.CloseButton(win, function() win:Hide() end)
        close:SetPoint("TOPRIGHT", -5, -5)
        tinsert(UISpecialFrames, "SKToolsLogWindow")      -- Esc closes it
        -- the standard scroll frame with its bar; a plain one, scrolled by the mouse wheel, if the
        -- client has no such template
        local okSF, sf = pcall(CreateFrame, "ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
        if not okSF or not sf then
            sf = CreateFrame("ScrollFrame", nil, win)
            sf:EnableMouseWheel(true)
            sf:SetScript("OnMouseWheel", function(self, d)
                local range = self:GetVerticalScrollRange() or 0
                self:SetVerticalScroll(math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - d * 40)))
            end)
        end
        sf:SetPoint("TOPLEFT", 14, -40)
        sf:SetPoint("BOTTOMRIGHT", -32, 48)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlightSmall)
        eb:SetWidth(660); eb:SetHeight(400)
        eb:SetScript("OnEscapePressed", function() win:Hide() end)
        -- read only: typing puts the log back
        eb:SetScript("OnTextChanged", function(self, user) if user then self:SetText(win.text or "") end end)
        sf:SetScrollChild(eb)
        win.edit, win.scroll = eb, sf
        local all = W.Button(win, "Select all", 120, function()
            eb:SetFocus(); eb:HighlightText()
            ns.Print("selected - press Ctrl+C to copy")
        end)
        all:SetPoint("BOTTOMLEFT", 14, 14)
        local clear = W.Button(win, "Clear log", 120, function()
            SKToolsLog.lines = {}
            win.text = ""; eb:SetText("")
        end)
        clear:SetPoint("LEFT", all, "RIGHT", 8, 0)
        local note = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        note:SetPoint("LEFT", clear, "RIGHT", 12, 0)
        note:SetPoint("RIGHT", win, "RIGHT", -14, 0)
        note:SetJustifyH("LEFT")
        note:SetText("Also saved to WTF/Account/<account>/SavedVariables/SKTools.lua (written at /reload or logout).")
        win:Hide()
        logWin = win
    end
    logWin.text = LogText()
    logWin.edit:SetText(logWin.text)
    logWin:Show()
    -- newest at the bottom: scroll there
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() pcall(function() logWin.scroll:SetVerticalScroll(logWin.scroll:GetVerticalScrollRange()) end) end)
    end
end


-- run a report: its lines go to the log (not the chat); one line in chat says where it went
function ns.Report(title, fn, open)
    local lines = {}
    local ok, err = pcall(fn, function(...)
        local parts = { ... }
        for i = 1, select("#", ...) do parts[i] = tostring(parts[i]) end
        lines[#lines + 1] = table.concat(parts, " ")
    end)
    if not ok then lines[#lines + 1] = "error: " .. tostring(err) end
    AddReport(title, lines)
    if open then
        ns.ShowLog()
        ns.Print(("/skt %s: %d lines, in the log window"):format(title, #lines))
    else
        ns.Print(("/skt %s: %d lines saved to the log - /skt log to see and copy them"):format(title, #lines))
    end
end

local function CpuReport(secs, print)
    local rows, total = {}, 0
    for name, ms in pairs(prof.t) do rows[#rows + 1] = { name, ms, prof.n[name] or 0 }; total = total + ms end
    table.sort(rows, function(a, b) return a[2] > b[2] end)
    print(("CPU over %d seconds: %.2f ms a second in all"):format(secs, total / secs))
    if #rows == 0 then print("  nothing ran") end
    for _, r in ipairs(rows) do
        print(("  %-22s %6.2f ms/s  %3d%%  (%d calls)"):format(r[1], r[2] / secs, total > 0 and math.floor(r[2] / total * 100 + 0.5) or 0, r[3]))
    end
    -- the game's own figure for the whole addon, where it has one
    if C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric then
        local ok, v = pcall(C_AddOnProfiler.GetAddOnMetric, ADDON, Enum.AddOnProfilerMetric.RecentAverageTime)
        if ok and type(v) == "number" then print(("  the game's own measure of SKTools: %.3f ms a frame (recent average)"):format(v)) end
    end
end
function ns.CpuMeasure(secs)
    if prof.on then ns.Print("already measuring - wait for the report"); return end
    secs = math.max(2, math.min(120, math.floor(tonumber(secs) or 10)))
    wipe(prof.t); wipe(prof.n)
    prof.on = true
    ns.Print(("measuring CPU for %d seconds - play as normal"):format(secs))
    C_Timer.After(secs, function()
        prof.on = false
        -- opened by itself when out of combat; in a fight, once it is over
        local inFight = InCombatLockdown and InCombatLockdown()
        ns.Report("cpu " .. secs, function(out) CpuReport(secs, out) end, not inFight)
        if inFight then
            local f = CreateFrame("Frame")
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function(self) self:UnregisterAllEvents(); ns.ShowLog() end)
        end
    end)
end
ns.prof = prof

-- /rl: reload the UI (the game only has /reload)
SLASH_SKTOOLSRELOAD1 = "/rl"
SlashCmdList.SKTOOLSRELOAD = function() ReloadUI() end

SLASH_SKTOOLS1 = "/skt"
SLASH_SKTOOLS2 = "/sktools"
-- /skt debug <part>: what each part sees, into the report log (and opened)
local DEBUG = {
    plates = function(out) ns.Plates.Debug(out) end,
    platelist = function(out) ns.Plates.List(out) end,
    icons = function(out) if ns.Feral and ns.Feral.Debug then ns.Feral.Debug(out) end end,
    buffs = function(out) if ns.Buffs and ns.Buffs.Debug then ns.Buffs.Debug(out) end end,
    totems = function(out) if ns.Totems and ns.Totems.Debug then ns.Totems.Debug(out) end end,
    cd = function(out) if ns.Cooldowns and ns.Cooldowns.Debug then ns.Cooldowns.Debug(out) end end,
    box = function(out) if ns.ButtonBox and ns.ButtonBox.Probe then ns.ButtonBox.Probe(out) end end,
}
local DEBUG_LIST = "plates | platelist | icons | buffs | totems | cd | box"

local function Help()
    ns.Print("version " .. tostring(ns.version) .. " - commands:")
    print("  /skt  - open or close the settings window")
    print("  /skt db | mouseover | quests | widgets | cursor | keybinds | cooldowns | nameplate | buttons | profiles  - open that tab")
    print("  /skt map [search]  - the Profession DB window (/skt map help for more)")
    print("  /skt minimap  - open or close the minimap button box")
    print("  /skt marks help  - quest marks: test mode, debug, quest-starter mobs")
    print("  /skt range help  - Hunter range checks: debug, watch, nameplate distance")
    print("  /skt debug " .. DEBUG_LIST .. "  - what that part sees, into the report log")
    print("  /skt cpu [seconds]  - how much CPU each part takes (10 seconds unless you say)")
    print("  /skt log  - the report log, to read and copy (/skt log clear empties it)")
    print("  /rl  - reload the UI")
end

SlashCmdList.SKTOOLS = function(msg)
    local raw = strtrim(msg or "")
    local cmd = raw:lower()
    local word, rest = raw:match("^(%S*)%s*(.-)$")
    word = (word or ""):lower()
    if cmd == "" or cmd == "config" or cmd == "options" then
        ns.ToggleSettings()
    elseif word == "map" or word == "window" then
        if SKToolsProfessionDB and SKToolsProfessionDB.Command then SKToolsProfessionDB.Command(rest) end
    elseif word == "marks" and rest ~= "" then
        if ns.Marks and ns.Marks.Command then ns.Marks.Command(rest) end
    elseif word == "range" and rest ~= "" then
        if ns.RangeBar and ns.RangeBar.Command then ns.RangeBar.Command(rest) end
    elseif TAB_ALIASES[cmd] then
        ns.OpenSettings(TAB_ALIASES[cmd])
    elseif cmd == "minimap" then
        ns.ToggleMinimapButton()                -- opens / closes the button box
    elseif cmd == "cpu" or cmd:match("^cpu %d+$") then
        ns.CpuMeasure(cmd:match("^cpu (%d+)$"))
    elseif cmd == "log" then
        ns.ShowLog()
    elseif cmd == "log clear" then
        Log(); SKToolsLog.lines = {}
        ns.Print("report log cleared")
    elseif word == "debug" then
        local part = rest:lower()
        if DEBUG[part] then
            ns.Report("debug " .. part, DEBUG[part], true)
        else
            ns.Print("/skt debug " .. DEBUG_LIST)
        end
    else
        Help()
    end
end

----------------------------------------------------------------------
-- AddOns drop-down by the minimap (named in the .toc)
----------------------------------------------------------------------

function SKTools_OnCompartmentClick(_, button)
    if button == "RightButton" then
        if SKToolsProfessionDB and SKToolsProfessionDB.Toggle then SKToolsProfessionDB:Toggle() end
    else
        ns.ToggleSettings()
    end
end

function SKTools_OnCompartmentEnter(_, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:AddLine("SKTools")
    GameTooltip:AddLine("Left-click: settings", 1, 1, 1)
    GameTooltip:AddLine("Right-click: Profession DB window", 1, 1, 1)
    GameTooltip:Show()
end

function SKTools_OnCompartmentLeave()
    GameTooltip:Hide()
end
