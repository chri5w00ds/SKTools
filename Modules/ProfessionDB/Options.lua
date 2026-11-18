-- SKTools settings tab: Profession DB.
-- Map pin settings and how the database window behaves. The database itself
-- (search, lists, tracking) is its own window beside the world map.

local ADDON, ns = ...

local W = ns.W
local DB = SKToolsProfessionDB

local function Changed()
    DB:RefreshPins()
end

local function Build(panel)
    local L, R = 24, 400
    local function db() return DB.db end

    ------------------------------------------------------------------
    W.Header(panel, "Map pins", L, -8, 330)

    panel:Add(W.Check(panel, "Pins on the world map",
        function() return db().worldmap end,
        function(v) db().worldmap = v; Changed() end, 300), L, -34)

    local cont = panel:Add(W.Check(panel, "...also on continent maps",
        function() return db().continent end,
        function(v) db().continent = v; Changed() end, 300), L + 14, -56)
    cont.tooltip = "Also show pins when viewing a whole continent."

    panel:Add(W.Check(panel, "Pins on the minimap",
        function() return db().minimap end,
        function(v) db().minimap = v; Changed() end, 300), L, -78)

    local vend = panel:Add(W.Check(panel, "Include vendors",
        function() return db().showVendors end,
        function(v) db().showVendors = v; Changed() end, 300), L, -100)
    vend.tooltip = "Include vendors that sell the material or pattern."

    panel:Add(W.Slider(panel, "Minimum drop / skinning chance on the maps", 0, 50, 1,
        function() return db().minChance end,
        function(v) db().minChance = v; Changed() end, W.percentInt, 300), L, -134)

    panel:Add(W.Slider(panel, "World map pin size", 8, 32, 1,
        function() return db().pinSize end,
        function(v) db().pinSize = v; Changed() end, W.px, 300), L, -180)

    panel:Add(W.Slider(panel, "Minimap pin size", 6, 24, 1,
        function() return db().minimapPinSize end,
        function(v) db().minimapPinSize = v; Changed() end, W.px, 300), L, -226)

    W.Note(panel, "Pins show the item's icon. The rim tells you the source: green = skinning, "
        .. "yellow = drop, blue = vendor (vendor pins also use the vendor's coin-bag icon). "
        .. "A skull is a mob you tracked directly. Hover a pin for the details in words.",
        L, -274, 330)

    panel.status = W.Note(panel, "", L, -340, 330)
    panel:Add(W.Button(panel, "Clear map", 110, function()
        DB:ClearTracked()
        panel:SyncAll()
    end), L, -362)

    ------------------------------------------------------------------
    W.Header(panel, "Database window", R, -8, 330)

    panel:Add(W.Button(panel, "Open the database", 160, function() DB:Toggle() end), R, -34)

    local mb = panel:Add(W.Check(panel, "Button on the world map",
        function() return db().mapButton end,
        function(v) db().mapButton = v; DB.UI:UpdateMapButton() end, 300), R, -70)
    mb.tooltip = "A small book button on the world map that opens the database beside it."

    panel:Add(W.Dropdown(panel, "Button corner", {
        { value = "TOPLEFT", text = "Top left" },
        { value = "TOPRIGHT", text = "Top right" },
        { value = "BOTTOMLEFT", text = "Bottom left" },
        { value = "BOTTOMRIGHT", text = "Bottom right" },
    }, function() return db().mapButtonCorner end,
       function(v) db().mapButtonCorner = v; DB.UI:UpdateMapButton() end, 130), R + 14, -94)

    local owm = panel:Add(W.Check(panel, "Open together with the world map",
        function() return db().openWithMap end,
        function(v) db().openWithMap = v end, 300), R, -128)
    owm.tooltip = "Show the database every time you open the world map."

    local function Relayout()
        if DB.UI.frame then
            DB.UI:ApplyLayout()
            DB.UI:Place()
            DB.UI:Refresh(true)
        end
    end
    panel:Add(W.Check(panel, "Narrow layout beside the world map",
        function() return db().compactMap end,
        function(v) db().compactMap = v; Relayout() end, 300), R, -150)

    panel:Add(W.Check(panel, "Narrow layout when opened on its own",
        function() return db().compactAlone end,
        function(v) db().compactAlone = v; Relayout() end, 300), R, -172)

    panel:Add(W.Button(panel, "Reset window position", 160, function()
        db().point, db().mapPoint = nil, nil
        if DB.UI.frame then DB.UI:Place() end
    end), R, -204)

    W.Note(panel, "Opened while the world map is up, the database sits beside the map and closes "
        .. "and re-opens with it. Drag it anywhere; the spot beside the map and the spot on its own "
        .. "are remembered separately. /sdb opens it from chat, /sdb <text> searches.",
        R, -238, 330)

    W.Note(panel, "Loot, skinning and recipe data: CMaNGOS classic-db. Spawn points and vendors: "
        .. "QuestieDB. Chances are vanilla 1.12 values and may differ on Forever.",
        R, -340, 330)

    function panel:OnSync()
        local n = DB:CountTracked()
        self.status:SetText(n == 0 and "Nothing is on the map."
            or string.format("%d tracked, %d pins.", n, DB.Pins and DB.Pins.count or 0))
    end
end

ns.RegisterTab({ key = "db", title = "Profession DB", order = 5, Build = Build })
