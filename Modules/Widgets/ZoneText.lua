--[[-------------------------------------------------------------------------
  SKTools - zone text position

  The game's own zone text (the area name in big letters as you enter it, the
  sub-zone under it, and the PvP line) moved wherever you like. Only its
  place changes: the text, timing and fade stay the game's. Off to start
  (Berry Mode too); while off the game's frames are not touched. Moved with
  the other widgets (Widgets tab, "Unlock widgets").

  Kept as a shift from the game's own spot (dx, dy), so it is put back
  exactly when turned off or reset.
---------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

local DEFAULTS = {
    enabled = false,
    berryEnabled = false,
    dx = 0, dy = 0,
}

local db
local function DeepFill(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then dst[k] = v end
    end
end
local function Unlocked()
    local b = ns.Buffs and ns.Buffs.Settings and ns.Buffs.Settings()
    return b and b.unlocked == true
end

-- the game's frames, and where the game put them (read once, before we move anything)
local frames, home = {}, {}
local function Frames()
    if #frames > 0 then return frames end
    local zone, sub = _G.ZoneTextFrame, _G.SubZoneTextFrame
    if type(zone) ~= "table" or not zone.GetPoint then return frames end
    frames[1] = zone
    -- the sub-zone line: moved too, unless it hangs on the zone text already
    if type(sub) == "table" and sub.GetPoint then
        local _, rel = sub:GetPoint(1)
        if rel ~= zone then frames[2] = sub end
    end
    for _, f in ipairs(frames) do
        local pts = {}
        for i = 1, (f:GetNumPoints() or 0) do pts[i] = { f:GetPoint(i) } end
        home[f] = pts
    end
    return frames
end

local moved = false
local function Place()
    if not db then return end
    local on = ns.FeatureOn(db)
    if not on and not moved then return end        -- never touched: left entirely to the game
    local dx, dy = on and (db.dx or 0) or 0, on and (db.dy or 0) or 0
    for _, f in ipairs(Frames()) do
        local pts = home[f]
        if pts and #pts > 0 then
            f:ClearAllPoints()
            for _, p in ipairs(pts) do f:SetPoint(p[1], p[2], p[3], (p[4] or 0) + dx, (p[5] or 0) + dy) end
        end
    end
    moved = on
end

----------------------------------------------------------------------
-- While unlocked: an example to drag, where the zone text shows
----------------------------------------------------------------------

local mover
local function Mover()
    if mover then return mover end
    mover = CreateFrame("Frame", "SKToolsZoneTextMover", UIParent)
    mover:SetFrameStrata("DIALOG")
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    ns.W.Fill(mover, 0.1, 0.4, 0.6, 0.25)
    ns.W.Border(mover, 0.4, 0.8, 1, 0.9, 1)
    mover.label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mover.label:SetPoint("BOTTOM", mover, "TOP", 0, 2)
    mover.label:SetText("Zone text")
    mover.zone = mover:CreateFontString(nil, "OVERLAY")
    mover.zone:SetPoint("TOP", 0, -6)
    mover.sub = mover:CreateFontString(nil, "OVERLAY")
    mover.sub:SetPoint("TOP", mover.zone, "BOTTOM", 0, -4)
    for _, pair in ipairs({ { mover.zone, "ZoneTextFont", 26 }, { mover.sub, "SubZoneTextFont", 18 } }) do
        local fs, obj, size = pair[1], pair[2], pair[3]
        if _G[obj] then fs:SetFontObject(_G[obj]) else fs:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE") end
        fs:SetTextColor(1, 0.82, 0)
    end
    mover:SetScript("OnDragStart", function(self)
        self.from = { self:GetCenter() }
        self:StartMoving()
    end)
    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local from = self.from
        self.from = nil
        if db and from and from[1] and x then
            local k = (self:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
            db.dx = math.floor((db.dx or 0) + (x - from[1]) * k + 0.5)
            db.dy = math.floor((db.dy or 0) + (y - from[2]) * k + 0.5)
            Place()
        end
        ns.ZoneText.Refresh()
    end)
    mover:Hide()
    return mover
end

local function Update()
    if not db then return end
    Place()
    local show = ns.FeatureOn(db) and Unlocked()
    if not show then
        if mover then mover:Hide() end
        return
    end
    local m = Mover()
    local zone = Frames()[1]
    if not zone then m:Hide(); return end
    m.zone:SetText((_G.GetZoneText and GetZoneText() ~= "" and GetZoneText()) or "Zone name")
    local sub = _G.GetSubZoneText and GetSubZoneText() or ""
    m.sub:SetText(sub ~= "" and sub or "Sub-zone")
    local w = math.max(m.zone:GetStringWidth() or 0, m.sub:GetStringWidth() or 0) + 36
    local h = (m.zone:GetStringHeight() or 26) + (m.sub:GetStringHeight() or 18) + 18
    m:SetSize(math.max(w, 120), math.max(h, 50))
    -- over the zone text's own name line
    m:ClearAllPoints()
    local zs = _G.ZoneTextString
    if type(zs) == "table" and zs.GetCenter and zs:GetCenter() then
        m:SetPoint("TOP", zs, "TOP", 0, 6)
    else
        m:SetPoint("TOP", zone, "TOP", 0, 6)
    end
    m:Show()
end

----------------------------------------------------------------------

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do
    pcall(driver.RegisterEvent, driver, e)
end
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitDB().range
        root.zoneText = root.zoneText or {}
        DeepFill(root.zoneText, DEFAULTS)
        db = root.zoneText
    end
    Update()
end)

ns.ZoneText = {
    Settings = function() return db end,
    Refresh = function() Update() end,
    ResetPosition = function()
        if not db then return end
        db.dx, db.dy = 0, 0
        Update()
    end,
    Mover = function() return mover end,
}

-- timed by /skt cpu
ns.Profile("Zone text", driver)
