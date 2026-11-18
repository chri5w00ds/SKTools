-- SKTools - Profession DB: a modular mob / material database.
-- Data files in Data/ (Leatherworking, Tailoring, ...) call SKToolsProfessionDB:RegisterModule();
-- this file provides searching and tracking, Window.lua the database window
-- and Pins.lua the map pins. Its global table, SKToolsProfessionDB, is what the generated data
-- files register with.

local ADDON, ns = ...

SKToolsProfessionDB = SKToolsProfessionDB or {}
local DB = SKToolsProfessionDB
DB.ns = ns
DB.version = ns.version

DB.modules = {}        -- key -> module table
DB.moduleOrder = {}    -- keys in registration order
DB.mobs = {}           -- npcID -> mob (merged from every module)
DB.zones = {}          -- uiMapID -> zone name

local DEFAULTS = {
    minChance = 5,         -- % : drops/skins below this are hidden from pins and greyed in lists
    showVendors = true,
    worldmap = true,
    minimap = true,
    continent = false,     -- also draw pins on the continent map
    pinSize = 14,
    minimapPinSize = 12,
    collapsed = {},        -- list headers the player collapsed
    point = nil,           -- window position when opened on its own
    mapPoint = nil,        -- window position beside the world map (nil = docked to its right edge)
    mapButton = true,      -- button on the world map that opens the window
    mapButtonCorner = "BOTTOMLEFT",
    openWithMap = false,   -- open the window whenever the world map opens
    compactMap = true,     -- narrow layout while it sits beside the world map
    compactAlone = false,  -- narrow layout when opened on its own
}
DB.DEFAULTS = DEFAULTS
local CHAR_DEFAULTS = {
    module = nil,
    mode = "items",        -- "items" or "mobs"
    tracked = { items = {}, mobs = {} },   -- items[module:itemID] = true, mobs[npcID] = true
}

DB.KIND = {
    S = { label = "Skinning", color = { 0.35, 0.85, 0.35 } },
    D = { label = "Drop",     color = { 1.00, 0.82, 0.20 } },
    V = { label = "Vendor",   color = { 0.40, 0.70, 1.00 } },
}
DB.QUALITY = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 },
    [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
}

function DB:Print(...)
    print("|cffffd200SKTools|r |cffaaaaaa(DB)|r:", ...)
end

local function copyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            copyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

----------------------------------------------------------------------
-- Module registration
----------------------------------------------------------------------

-- module = { name, icon, categories = {..}, items = {[itemID] = {n,c,q,sk,w,src={{npc,kind,chance},..}}},
--            mobs = {[npcID] = {n,l={min,max},r,t,f,dg,sp={[uiMapID]={x,y,x,y..}}}}, zones = {[uiMapID]=name} }
function DB:RegisterModule(key, module)
    if self.modules[key] then return end
    module.key = key
    self.modules[key] = module
    table.insert(self.moduleOrder, key)
    for id, mob in pairs(module.mobs or {}) do
        if not self.mobs[id] then self.mobs[id] = mob end
    end
    for id, name in pairs(module.zones or {}) do
        self.zones[id] = self.zones[id] or name
    end
    module.mobItems = nil   -- reverse index, built on first use
    if self.ready and self.OnModulesChanged then self:OnModulesChanged() end
end

-- npcID -> { {itemID, kind, chance}, ... } for one module
function DB:GetMobItems(module, npc)
    if not module.mobItems then
        local idx = {}
        for itemID, item in pairs(module.items) do
            for _, s in ipairs(item.src) do
                local list = idx[s[1]]
                if not list then list = {}; idx[s[1]] = list end
                list[#list + 1] = { itemID, s[2], s[3] }
            end
        end
        for _, list in pairs(idx) do
            table.sort(list, function(a, b) return a[3] > b[3] end)
        end
        module.mobItems = idx
    end
    return module.mobItems[npc] or {}
end

function DB:CurrentModule()
    local key = self.char and self.char.module
    if not key or not self.modules[key] then key = self.moduleOrder[1] end
    return key and self.modules[key]
end

-- does this source show up on the map with the current settings?
function DB:SourceVisible(kind, chance)
    if kind == "V" then return self.db.showVendors end
    return chance >= self.db.minChance
end

function DB:ItemIcon(itemID)
    local icon
    if C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(itemID) end
    if not icon and GetItemIcon then icon = GetItemIcon(itemID) end
    return icon or 134400   -- question mark
end

function DB:MobZones(mob)
    local names = {}
    for mapID in pairs(mob.sp or {}) do
        names[#names + 1] = self.zones[mapID] or ("Map " .. mapID)
    end
    table.sort(names)
    return table.concat(names, ", ")
end

function DB:FormatChance(kind, chance)
    if kind == "V" then return "sold" end
    if chance >= 10 then return string.format("%d%%", math.floor(chance + 0.5)) end
    return string.format("%.1f%%", chance)
end

function DB:FormatLevel(mob)
    local l = mob.l or { 0, 0 }
    local s = (l[1] == l[2] or l[2] == 0) and tostring(l[1]) or (l[1] .. "-" .. l[2])
    if mob.r == 1 then s = s .. "+" elseif mob.r == 2 then s = s .. " rare+" elseif mob.r == 3 then s = s .. " boss"
    elseif mob.r == 4 then s = s .. " rare" end
    return s
end

----------------------------------------------------------------------
-- Tracking (what is drawn on the maps)
----------------------------------------------------------------------

local function itemKey(module, itemID) return module.key .. ":" .. itemID end

function DB:IsItemTracked(module, itemID)
    return self.char.tracked.items[itemKey(module, itemID)] and true or false
end

function DB:SetItemTracked(module, itemID, on)
    self.char.tracked.items[itemKey(module, itemID)] = on and true or nil
    self:RefreshPins()
end

function DB:IsMobTracked(npc)
    return self.char.tracked.mobs[npc] and true or false
end

function DB:SetMobTracked(npc, on)
    self.char.tracked.mobs[npc] = on and true or nil
    self:RefreshPins()
end

function DB:ClearTracked()
    wipe(self.char.tracked.items)
    wipe(self.char.tracked.mobs)
    self:RefreshPins()
end

-- Collect every mob that should get pins: npc -> { reasons = {{module,itemID,kind,chance}}, direct = bool }
function DB:CollectPinned()
    local out = {}
    for key in pairs(self.char.tracked.items) do
        local modKey, id = key:match("^(.-):(%d+)$")
        local module = modKey and self.modules[modKey]
        local item = module and module.items[tonumber(id)]
        if item then
            for _, s in ipairs(item.src) do
                if self:SourceVisible(s[2], s[3]) and self.mobs[s[1]] then
                    local e = out[s[1]]
                    if not e then e = { reasons = {} }; out[s[1]] = e end
                    e.reasons[#e.reasons + 1] = { module, tonumber(id), s[2], s[3] }
                end
            end
        end
    end
    for npc in pairs(self.char.tracked.mobs) do
        if self.mobs[npc] then
            local e = out[npc]
            if not e then e = { reasons = {} }; out[npc] = e end
            e.direct = true
        end
    end
    for _, e in pairs(out) do
        table.sort(e.reasons, function(a, b) return a[4] > b[4] end)
    end
    return out
end

function DB:RefreshPins()
    if self.Pins then self.Pins:Refresh() end
    if self.UI and self.UI.Refresh then self.UI:Refresh() end
end

----------------------------------------------------------------------
-- Searching
----------------------------------------------------------------------

local function norm(s)
    return (s or ""):lower():gsub("[%p%s]", "")
end
DB.Normalize = norm

-- items of a module that match a search string (name, or a mob that gives it)
function DB:SearchItems(module, text)
    local q = norm(text)
    local res = {}
    for id, item in pairs(module.items) do
        if q == "" or norm(item.n):find(q, 1, true) then
            res[#res + 1] = id
        end
    end
    return res
end

-- mobs of a module that match by mob name, title or zone
function DB:SearchMobs(module, text)
    local q = norm(text)
    local seen, res = {}, {}
    for _, item in pairs(module.items) do
        for _, s in ipairs(item.src) do
            local npc = s[1]
            if not seen[npc] then
                seen[npc] = true
                local mob = self.mobs[npc]
                if mob and (q == ""
                    or norm(mob.n):find(q, 1, true)
                    or (mob.t and norm(mob.t):find(q, 1, true))
                    or (mob.dg and norm(mob.dg):find(q, 1, true))
                    or norm(self:MobZones(mob)):find(q, 1, true)) then
                    res[#res + 1] = npc
                end
            end
        end
    end
    return res
end

----------------------------------------------------------------------
-- Startup, slash command, addon compartment
----------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        local root, char = ns.InitDB()
        copyDefaults(root.db, DEFAULTS)
        copyDefaults(char.db, CHAR_DEFAULTS)
        DB.db, DB.char = root.db, char.db
        -- settings of the old stand-alone minimap button (now one shared button)
        DB.db.minimapAngle, DB.db.hideMinimapButton = nil, nil
    elseif event == "PLAYER_LOGIN" then
        DB.ready = true
        if #DB.moduleOrder == 0 then
            DB:Print("no profession data loaded.")
        end
        -- each step on its own, so one failing can't stop the others
        DB:SafeCall("map pins", function() DB.Pins:Init() end)
        DB:SafeCall("map pins", function() DB:RefreshPins() end)
    end
end)

DB.errors = {}
function DB:SafeCall(what, fn)
    local ok, err = pcall(fn)
    if not ok then
        table.insert(self.errors, what .. ": " .. tostring(err))
        self:Print("|cffff5555error in " .. what .. ":|r " .. tostring(err))
    end
    return ok
end

function DB:Debug()
    self:Print("version " .. tostring(self.version) .. ", interface " .. tostring(select(4, GetBuildInfo())))
    print("  modules: " .. (#self.moduleOrder > 0 and table.concat(self.moduleOrder, ", ") or "none"))
    local mb = self.UI and self.UI.mapButton
    print("  world map button: " .. (mb and ("created, shown=" .. tostring((mb:IsShown()))
        .. ", strata=" .. tostring((mb:GetFrameStrata()))) or "not created")
        .. ", setting=" .. tostring(self.db.mapButton) .. ", corner=" .. tostring(self.db.mapButtonCorner))
    print("  world map loaded: " .. tostring(WorldMapFrame ~= nil) .. ", pins tracked: " .. tostring(self.Pins and self.Pins.count))
    print("  map: " .. tostring((C_Map.GetBestMapForUnit("player"))) .. ", tracked: " .. self:CountTracked())
    if #self.errors == 0 then print("  no errors") end
    for _, e in ipairs(self.errors) do print("  |cffff5555" .. e .. "|r") end
end

function DB:Toggle(search)
    if not self.UI then return end
    if search and search ~= "" then
        self.UI:Show(); self.UI:SetSearch(search)
    else
        self.UI:Toggle()
    end
end

function DB:CountTracked()
    local n = 0
    for _ in pairs(self.char.tracked.items) do n = n + 1 end
    for _ in pairs(self.char.tracked.mobs) do n = n + 1 end
    return n
end

SLASH_SKTOOLSPROF1 = "/sdb"
SlashCmdList.SKTOOLSPROF = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "clear" then
        DB:ClearTracked(); DB:Print("map cleared.")
    elseif cmd == "chance" and tonumber(rest) then
        DB.db.minChance = math.max(0, math.min(100, tonumber(rest)))
        DB:RefreshPins(); DB:Print("minimum chance set to " .. DB.db.minChance .. "%.")
    elseif cmd == "minimap" then
        DB.db.minimap = not DB.db.minimap; DB:RefreshPins()
        DB:Print("minimap pins " .. (DB.db.minimap and "on" or "off") .. ".")
    elseif cmd == "map" then
        DB.db.worldmap = not DB.db.worldmap; DB:RefreshPins()
        DB:Print("world map pins " .. (DB.db.worldmap and "on" or "off") .. ".")
    elseif cmd == "debug" then
        DB:Debug()
    elseif cmd == "button" then
        ns.ToggleMinimapButton()
    elseif cmd == "settings" or cmd == "config" or cmd == "options" then
        ns.OpenSettings("db")
    elseif cmd == "reset" then
        DB.db.point, DB.db.mapPoint = nil, nil
        if DB.UI and DB.UI.frame then DB.UI:Place() end
        DB:Print("window position reset.")
    elseif cmd == "help" or cmd == "?" then
        DB:Print("commands:")
        print("  /sdb  - open or close the window")
        print("  /sdb <text>  - open and search, e.g. /sdb devilsaur")
        print("  /sdb clear  - remove everything from the maps")
        print("  /sdb chance <0-100>  - minimum drop/skin chance shown on the maps")
        print("  /sdb map | minimap  - toggle world map / minimap pins")
        print("  /sdb settings  - open the Profession DB settings tab")
        print("  /sdb button  - open or close the minimap button box")
        print("  /sdb reset  - put the window back where it started")
        print("  /sdb debug  - show what loaded (paste this if something is missing)")
    else
        DB:Toggle(msg)
    end
    ns.RefreshSettings()
end
