-- SKTools: a Profession DB, nameplates, cooldown panes, action bar range and resource tint, the
-- Hunter range crescent and a minimap button box, in one addon for WoW Forever.
--
-- This file is the shared core: saved variables, profiles, the settings-tab registry and the slash
-- command. Each feature lives in Modules/ and keeps its own table of settings:
--
--   .db     Profession DB
--   .marks  Nameplate quest marks
--   .range  Nameplates, range crescent (.crescent), action bar tint (.tint), combo points (.combo),
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
ns.name = ADDON
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
    db = "db", database = "db", profession = "db", professions = "db", prof = "db",
    action = "action", actionbar = "action", bar = "action", tint = "action",
    widgets = "widgets", widget = "widgets", buffs = "widgets",
    cursor = "cursor", mouse = "cursor", glow = "cursor",
    cooldowns = "cooldowns", cd = "cooldowns", cdm = "cooldowns",
    nameplate = "nameplate", nameplates = "nameplate", plates = "nameplate", healthbar = "nameplate", designer = "nameplate",
    marks = "nameplate", quest = "nameplate", combo = "nameplate",
    hunter = "nameplate", range = "nameplate", rangebar = "nameplate", crescent = "nameplate",
    feral = "nameplate", cat = "nameplate", claw = "nameplate", shred = "nameplate",
    prd = "cooldowns", resource = "cooldowns", resources = "cooldowns", bars = "cooldowns", personal = "cooldowns",
    profile = "profiles", profiles = "profiles",
    box = "buttons", buttons = "buttons", buttonbox = "buttons", minimapbuttons = "buttons",
}
ns.TAB_ALIASES = TAB_ALIASES

SLASH_SKTOOLS1 = "/skt"
SLASH_SKTOOLS2 = "/sktools"
SlashCmdList.SKTOOLS = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "" or cmd == "config" or cmd == "options" then
        ns.ToggleSettings()
    elseif TAB_ALIASES[cmd] then
        ns.OpenSettings(TAB_ALIASES[cmd])
    elseif cmd == "map" or cmd == "window" then
        if SKToolsProfessionDB and SKToolsProfessionDB.Toggle then SKToolsProfessionDB:Toggle() end
    elseif cmd == "minimap" then
        ns.ToggleMinimapButton()                -- opens / closes the button box
    elseif cmd == "platesdebug" then
        ns.Plates.Debug(function(m) print(m) end)
    elseif cmd == "platelist" then
        ns.Plates.List(function(m) print(m) end)
    elseif cmd == "feraldebug" or cmd == "icondebug" then
        if ns.Feral and ns.Feral.Debug then ns.Feral.Debug(function(m) print(m) end) end
    elseif cmd == "cddebug" then
        if ns.Cooldowns and ns.Cooldowns.Debug then ns.Cooldowns.Debug(function(m) print(m) end) end
    elseif cmd == "totemdebug" then
        if ns.Totems and ns.Totems.Debug then ns.Totems.Debug(function(m) print(m) end) end
    elseif cmd == "buffdebug" then
        if ns.Buffs and ns.Buffs.Debug then ns.Buffs.Debug(function(m) print(m) end) end
    elseif cmd == "boxdebug" then
        if ns.ButtonBox and ns.ButtonBox.Probe then ns.ButtonBox.Probe(function(m) print(m) end) end
    else
        ns.Print("version " .. tostring(ns.version) .. " - commands:")
        print("  /skt  - open or close the settings window")
        print("  /skt db | action | widgets | cursor | cooldowns | nameplate | buttons | profiles  - open that settings tab")
        print("  /skt map  - open or close the Profession DB window (also /sdb)")
        print("  /skt minimap  - open or close the minimap button box\n  /skt platesdebug | platelist | icondebug  - print what the game tells the plates / every plate it has / the ready icons\n  /skt buffdebug  - print what the buff widgets see\n  /skt totemdebug - print the totems and Lightning Shield charges seen\n  /skt cddebug    - print what the cooldown panes show")
        print("  Short commands for their own parts: /sdb, /sm, /skr (/rb)")
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
