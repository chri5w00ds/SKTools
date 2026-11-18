-- SKTools - Profession DB map pins: world map and minimap icons for
-- tracked items and mobs, drawn through HereBeDragons-Pins (which already
-- supports WoW Forever). Also tells the database window when the world map
-- opens and closes, so it can sit beside it.

local ADDON, ns = ...
local DB = SKToolsProfessionDB

local HBDPins = LibStub("HereBeDragons-Pins-2.0")
local Pins = {}
DB.Pins = Pins

local MAX_PINS = 1500     -- per map, protects against tracking e.g. Runecloth at 0%
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local VENDOR = "Interface\\GossipFrame\\VendorGossipIcon"

local worldPool, miniPool = {}, {}
local worldUsed, miniUsed = {}, {}

----------------------------------------------------------------------
-- Pin frames
----------------------------------------------------------------------

local function PinOnEnter(self)
    local e, mob = self.entry, DB.mobs[self.npc]
    if not mob then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local c = (mob.r == 1 or mob.r == 2 or mob.r == 3) and { 1, 0.82, 0 } or { 1, 1, 1 }
    GameTooltip:AddDoubleLine(mob.n, "Level " .. DB:FormatLevel(mob), c[1], c[2], c[3], 0.8, 0.8, 0.8)
    if mob.t then GameTooltip:AddLine("<" .. mob.t .. ">", 0.8, 0.8, 0.8) end
    if mob.dg then GameTooltip:AddLine("Inside " .. mob.dg .. " (pin marks the entrance)", 1, 0.5, 0.25) end
    for i, r in ipairs(e.reasons) do
        if i > 8 then
            GameTooltip:AddLine("  ...and " .. (#e.reasons - 8) .. " more", 0.7, 0.7, 0.7)
            break
        end
        local module, itemID, kind, chance = r[1], r[2], r[3], r[4]
        local item = module.items[itemID]
        local q = DB.QUALITY[item.q or 1] or DB.QUALITY[1]
        local k = DB.KIND[kind]
        GameTooltip:AddDoubleLine("|T" .. DB:ItemIcon(itemID) .. ":14|t " .. item.n,
            k.label .. "  " .. DB:FormatChance(kind, chance),
            q[1], q[2], q[3], k.color[1], k.color[2], k.color[3])
    end
    if e.direct then GameTooltip:AddLine("Tracked mob", 0.6, 0.6, 0.6) end
    GameTooltip:AddLine("Click to open in the Profession DB", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function PinOnLeave() GameTooltip:Hide() end

local function PinOnClick(self)
    if DB.UI then DB.UI:Show(); DB.UI:ShowMob(self.npc) end
end

local function NewPin(parentName)
    local p = CreateFrame("Button", nil, UIParent)
    p:SetSize(14, 14)
    p:EnableMouse(true)
    p.ring = p:CreateTexture(nil, "BACKGROUND")
    p.ring:SetAllPoints()
    p.ring:SetColorTexture(0, 0, 0, 1)
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetPoint("TOPLEFT", 1.5, -1.5)
    p.icon:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
    p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    p:SetScript("OnEnter", PinOnEnter)
    p:SetScript("OnLeave", PinOnLeave)
    p:SetScript("OnClick", PinOnClick)
    return p
end

local function Acquire(pool, used)
    local p = table.remove(pool) or NewPin()
    used[#used + 1] = p
    return p
end

local function Style(p, npc, entry, size)
    p.npc, p.entry = npc, entry
    p:SetSize(size, size)
    local r = entry.reasons[1]
    if r then
        local k = DB.KIND[r[3]].color
        p.ring:SetColorTexture(k[1], k[2], k[3], 1)
        if r[3] == "V" then
            p.icon:SetTexture(VENDOR); p.icon:SetTexCoord(0, 1, 0, 1)
        else
            p.icon:SetTexture(DB:ItemIcon(r[2])); p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    else
        p.ring:SetColorTexture(0.85, 0.2, 0.2, 1)
        p.icon:SetTexture(SKULL); p.icon:SetTexCoord(0, 1, 0, 1)
    end
    p:Show()
end

----------------------------------------------------------------------
-- Refresh. Pins are only created for the map being looked at (world map)
-- and the zone the player is in (minimap), so tracking something common
-- like Light Leather doesn't create thousands of frames.
----------------------------------------------------------------------

local byMap = {}      -- uiMapID -> { {npc, entry, x, y}, ... }
local worldShownMap, miniShownMap

local function ReleaseAll(pool, used)
    for i = #used, 1, -1 do
        local p = used[i]; p:Hide(); p:ClearAllPoints(); pool[#pool + 1] = p; used[i] = nil
    end
end

local function ParentOf(mapID)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and info.parentMapID
end

function Pins:DrawWorld()
    HBDPins:RemoveAllWorldMapIcons(Pins)
    ReleaseAll(worldPool, worldUsed)
    worldShownMap = nil
    if not DB.db.worldmap or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if not mapID then return end
    worldShownMap = mapID
    local n = 0
    local function add(list, flag)
        for _, e in ipairs(list) do
            if n >= MAX_PINS then return end
            local p = Acquire(worldPool, worldUsed)
            Style(p, e[1], e[2], DB.db.pinSize)
            HBDPins:AddWorldMapIconMap(Pins, p, e[5], e[3], e[4], flag)
            n = n + 1
        end
    end
    if byMap[mapID] then add(byMap[mapID], 0) end
    if DB.db.continent then
        -- viewing a continent: add the pins of its zones, shown on the parent map
        for zone, list in pairs(byMap) do
            if zone ~= mapID and ParentOf(zone) == mapID then
                add(list, HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2)
            end
        end
    end
end

function Pins:DrawMinimap()
    HBDPins:RemoveAllMinimapIcons(Pins)
    ReleaseAll(miniPool, miniUsed)
    miniShownMap = nil
    if not DB.db.minimap then return end
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    miniShownMap = mapID
    -- inside a sub-map (city, cave): use the zone it belongs to as well
    local maps = { mapID }
    local parent = ParentOf(mapID)
    if parent and byMap[parent] then maps[2] = parent end
    local n = 0
    for _, m in ipairs(maps) do
        for _, e in ipairs(byMap[m] or {}) do
            if n >= MAX_PINS then return end
            local p = Acquire(miniPool, miniUsed)
            Style(p, e[1], e[2], DB.db.minimapPinSize)
            HBDPins:AddMinimapIconMap(Pins, p, e[5], e[3], e[4], false, false)
            n = n + 1
        end
    end
end

function Pins:Refresh()
    if not self.ready or not DB.db then return end
    wipe(byMap)
    local total = 0
    for npc, entry in pairs(DB:CollectPinned()) do
        local mob = DB.mobs[npc]
        for mapID, pts in pairs(mob.sp or {}) do
            local list = byMap[mapID]
            if not list then list = {}; byMap[mapID] = list end
            for i = 1, #pts - 1, 2 do
                list[#list + 1] = { npc, entry, pts[i] / 100, pts[i + 1] / 100, mapID }
                total = total + 1
            end
        end
    end
    self.count = total
    self:DrawWorld()
    self:DrawMinimap()
end

function Pins:Init()
    self.ready = true
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    ev:RegisterEvent("ZONE_CHANGED")
    ev:RegisterEvent("ZONE_CHANGED_INDOORS")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function()
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if mapID ~= miniShownMap then Pins:DrawMinimap() end
    end)
    -- follow the world map: redraw when it opens or the shown map changes.
    -- Blizzard_WorldMap can load after us, so attach once it exists.
    local function attach()
        if Pins.watcher or not WorldMapFrame then return end
        local elapsed = 0
        local watcher = CreateFrame("Frame", nil, WorldMapFrame)
        Pins.watcher = watcher
        watcher:SetScript("OnShow", function()
            Pins:DrawWorld()
            if DB.UI and DB.UI.OnMapShown then DB:SafeCall("map window", function() DB.UI:OnMapShown() end) end
        end)
        watcher:SetScript("OnHide", function()
            Pins:DrawWorld()
            if DB.UI and DB.UI.OnMapHidden then DB:SafeCall("map window", function() DB.UI:OnMapHidden() end) end
        end)
        watcher:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            if elapsed < 0.2 then return end
            elapsed = 0
            if WorldMapFrame:GetMapID() ~= worldShownMap then Pins:DrawWorld() end
        end)
        if DB.UI and DB.UI.CreateMapButton then
            DB:SafeCall("map button", function() DB.UI:CreateMapButton() end)
        end
    end
    attach()
    if not Pins.watcher then
        local wl = CreateFrame("Frame")
        wl:RegisterEvent("ADDON_LOADED")
        wl:SetScript("OnEvent", function(self, _, name)
            if name == "Blizzard_WorldMap" then attach(); self:UnregisterAllEvents() end
        end)
    end
end
