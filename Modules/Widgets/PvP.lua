--[[-------------------------------------------------------------------------
  SKTools - PvP flag icon

  The game's own PvP icon (your faction's, or the free-for-all one) while you
  are flagged for PvP, hidden otherwise. While the flag is wearing off, a
  countdown under it. Moved and resized with the other widgets (Widgets tab,
  "Unlock the panes"); Berry Mode keeps its own on / off for it (off until
  turned on).
---------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function Ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if ok then return Plain(a) end
end

local DEFAULTS = {
    enabled = true,
    berryEnabled = false,                      -- Berry Mode keeps its own switch, off until turned on
    size = 36,
    point = "CENTER", x = -260, y = -180,
    timer = true,                              -- the countdown while the flag wears off
}
-- the game's icons: the modern player frame's (atlases), where the client has them; else the classic
-- textures, whose shield sits in the top left of a 64 px texture
local ATLAS = {
    Alliance = "UI-HUD-UnitFrame-Player-PVP-AllianceIcon",
    Horde    = "UI-HUD-UnitFrame-Player-PVP-HordeIcon",
    FFA      = "UI-HUD-UnitFrame-Player-PVP-FFAIcon",
}
local TEX = {
    Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
    Horde    = "Interface\\TargetingFrame\\UI-PVP-Horde",
    FFA      = "Interface\\TargetingFrame\\UI-PVP-FFA",
}
local CROP = 40 / 64

local db
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
local function Unlocked()
    local b = ns.Buffs and ns.Buffs.Settings and ns.Buffs.Settings()
    return b and b.unlocked == true
end

local state = { why = "not set up" }

----------------------------------------------------------------------
-- The icon
----------------------------------------------------------------------

local f = CreateFrame("Frame", "SKToolsPvPIcon", UIParent)
f:SetFrameStrata("MEDIUM")
f:SetClampedToScreen(true)
f:SetMovable(true)
f.tex = f:CreateTexture(nil, "ARTWORK")
f.tex:SetPoint("CENTER")
f.timer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
f.timer:SetPoint("TOP", f, "BOTTOM", 0, -1)
f.timer:SetShadowOffset(1, -1)
f:Hide()

-- while unlocked: a frame to drag, a corner to resize (as the buff panes)
f.frame = CreateFrame("Frame", nil, f)
f.frame:SetAllPoints()
f.frame:SetFrameLevel(f:GetFrameLevel() + 10)
f.frame:EnableMouse(true)
f.frame:RegisterForDrag("LeftButton")
f.frame:Hide()

local Update
local function Place()
    if not db or f.moving then return end
    f:ClearAllPoints()
    f:SetPoint(db.point or "CENTER", UIParent, db.point or "CENTER", db.x or 0, db.y or 0)
    f:SetSize(db.size or 36, db.size or 36)
    local fs = math.max(9, math.floor((db.size or 36) * 0.36 + 0.5))
    pcall(f.timer.SetFont, f.timer, "Fonts\\FRIZQT__.TTF", fs, "OUTLINE")
end

local function SetupFrame()
    if f.frame.done then return end
    f.frame.done = true
    ns.W.Fill(f.frame, 0.1, 0.4, 0.6, 0.25)
    ns.W.Border(f.frame, 0.4, 0.8, 1, 0.9, 1)
    f.frame.text = f.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.frame.text:SetPoint("BOTTOM", f.frame, "TOP", 0, 2)
    f.frame.text:SetText("PvP flag")
    f.frame:SetScript("OnDragStart", function() f.moving = true; f:StartMoving() end)
    f.frame:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        f.moving = nil
        local px, py = f:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if px and ux then
            local k = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
            db.point, db.x, db.y = "CENTER", math.floor(px * k - ux + 0.5), math.floor(py * k - uy + 0.5)
            if ns.Snap then db.x, db.y = ns.Snap(db.x, db.y) end
        end
        Update()
    end)
    f.frame:SetScript("OnHide", function()
        if f.moving then f:StopMovingOrSizing(); f.moving = nil end
    end)
    local grip = CreateFrame("Button", nil, f.frame)
    grip:SetSize(8, 8)
    grip:SetPoint("BOTTOMRIGHT", 0, 0)
    ns.W.Fill(grip, 1, 1, 1, 1)
    grip:SetScript("OnMouseDown", function(self)
        local cx = GetCursorPosition()
        self.drag = { cx = cx, size = db.size or 36 }
    end)
    grip:SetScript("OnMouseUp", function(self) self.drag = nil end)
    grip:SetScript("OnUpdate", function(self)
        if not self.drag then return end
        if _G.IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then self.drag = nil; return end
        local cx = GetCursorPosition()
        local scale = f:GetEffectiveScale() or 1
        db.size = math.max(16, math.min(96, math.floor(self.drag.size + (cx - self.drag.cx) / scale + 0.5)))
        Place()
    end)
end

-- which icon, if any: free-for-all first, then your faction's
local function Flag()
    if Ask(_G.UnitIsPVPFreeForAll, "player") then return "FFA" end
    if Ask(_G.UnitIsPVP, "player") then
        local faction = Ask(_G.UnitFactionGroup, "player")
        if TEX[faction] then return faction end
        return "FFA"
    end
    return nil
end

-- the countdown while the flag wears off, in seconds (nil while it is not running)
local function Remaining()
    if not Ask(_G.IsPVPTimerRunning) then return nil end
    local ms = Ask(_G.GetPVPTimer)
    if type(ms) ~= "number" or ms <= 0 then return nil end
    return ms / 1000
end

Update = function()
    if not db then return end
    if not ns.FeatureOn(db) then
        f:Hide(); state.why = "switched off"; return
    end
    Place()
    local unlocked = Unlocked()
    if unlocked then SetupFrame() end
    f.frame:SetShown(unlocked)
    local flag = Flag()
    if not flag and unlocked then flag = Ask(_G.UnitFactionGroup, "player") or "Alliance" end   -- an example to place
    if not TEX[flag or ""] then
        f:Hide(); state.why = "not flagged"; return
    end
    -- an atlas keeps its own shape, fitted inside the square; the classic texture fills it
    local size = db.size or 36
    local info = C_Texture and C_Texture.GetAtlasInfo and Ask(C_Texture.GetAtlasInfo, ATLAS[flag])
    if type(info) == "table" and f.tex.SetAtlas and pcall(f.tex.SetAtlas, f.tex, ATLAS[flag]) then
        local w, h = info.width or 1, info.height or 1
        local k = size / math.max(w, h, 1)
        f.tex:SetSize(w * k, h * k)
        f.shows = "atlas " .. ATLAS[flag]
    else
        f.tex:SetTexture(TEX[flag])
        f.tex:SetTexCoord(0, CROP, 0, CROP)
        f.tex:SetSize(size, size)
        f.shows = "texture " .. TEX[flag]
    end
    f.flag = flag
    local left = db.timer ~= false and Remaining() or nil
    if left then
        f.timer:SetText(("%d:%02d"):format(math.floor(left / 60), math.floor(left % 60)))
        f.timer:Show()
    else
        f.timer:Hide()
    end
    f:Show()
    state.why = (unlocked and not Flag()) and "unlocked (an example)" or ("flagged: " .. flag .. (left and (", " .. math.floor(left) .. " s left") or ""))
end

----------------------------------------------------------------------
-- Driving it: the flag changes by event; the countdown and the unlocked frame twice a second
----------------------------------------------------------------------

local driver = CreateFrame("Frame")
local acc = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.5 then return end
    acc = 0
    if not db then return end
    if (f:IsShown() and f.timer:IsShown()) or Unlocked() or f.frame:IsShown() or Ask(_G.IsPVPTimerRunning) then Update() end
end)
driver:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_FLAGS_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_UPDATE_RESTING" }) do
    pcall(driver.RegisterEvent, driver, e)
end
pcall(driver.RegisterUnitEvent or driver.RegisterEvent, driver, "UNIT_FACTION", "player")
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitDB().range
        root.pvp = root.pvp or {}
        DeepFill(root.pvp, DEFAULTS)
        db = root.pvp
    end
    Update()
end)

ns.PvPIcon = {
    Settings = function() return db end,
    Refresh = function() Update() end,
    ResetPosition = function()
        if not db then return end
        db.point, db.x, db.y, db.size = DEFAULTS.point, DEFAULTS.x, DEFAULTS.y, DEFAULTS.size
        Update()
    end,
    Frame = function() return f end,
    Debug = function(print)
        print(("PvP flag icon: %s; flag %s; timer %s; drawn from %s"):format(state.why, tostring(Flag()), tostring(Remaining()), tostring(f.shows)))
    end,
}

-- timed by /skt cpu
ns.Profile("PvP icon", driver)
