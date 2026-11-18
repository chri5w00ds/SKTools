-- SKTools settings window (/skt or the minimap button).
-- One window, one tab per feature. The tabs themselves are registered by the
-- modules with ns.RegisterTab and built the first time they are opened.

local ADDON, ns = ...

local W = ns.W
local GOLD, EDGE = W.GOLD, W.EDGE

local WIDTH, HEIGHT = 780, 566
local TAB_TOP = -40          -- tab row
local PANEL_TOP = -76        -- where a tab's content starts
local FOOTER = 44

local frame
local LayoutTabs
local tabButtons = {}
local panels = {}            -- key -> panel frame
local current

local function Window() return ns.InitDB().window end

-- every tab shows (Berry Mode switches features off in their tabs, it does not hide the tabs)
local function TabShown(tab) return true end

local function TabByKey(key)
    for _, tab in ipairs(ns.tabs) do
        if tab.key == key and TabShown(tab) then return tab end
    end
end

local function FirstTab()
    for _, tab in ipairs(ns.tabs) do if TabShown(tab) then return tab end end
end

local function Select(key)
    local tab = TabByKey(key) or FirstTab()
    if not tab then return end
    current = tab.key
    Window().tab = tab.key

    for k, p in pairs(panels) do
        if k ~= tab.key then p:Hide() end
    end

    local panel = panels[tab.key]
    if not panel then
        panel = CreateFrame("Frame", nil, frame)
        panel:SetFrameLevel(frame:GetFrameLevel() + 2)       -- above the content box
        panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, PANEL_TOP)
        panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, FOOTER)
        panel:Hide()
        W.Panel(panel)
        panels[tab.key] = panel
        local ok, err = pcall(tab.Build, panel)
        if not ok then
            ns.Print("|cffff5555error building the " .. tab.title .. " tab:|r " .. tostring(err))
        end
        panel:SetScript("OnShow", function(self)
            self:SyncAll()
            if tab.OnShow then tab.OnShow(self) end
        end)
        panel:SetScript("OnHide", function(self)
            if tab.OnHide then tab.OnHide(self) end
        end)
    end
    panel:Show()

    -- the open tab is the raised one, with a gold bar under it as well as white text
    for _, b in ipairs(tabButtons) do
        b:SetActive(b.key == tab.key)
    end
end

-- the tabs: the same margin on both sides of the window and the same gap between each two; each
-- as wide as its title needs, with less padding round the titles if they would not fit otherwise.
-- Only the tabs in use are laid out (Berry Mode leaves some out).
LayoutTabs = function()
    local MARGIN, LEFT, RIGHT = 10, 14, WIDTH - 14
    local shown = {}
    for _, b in ipairs(tabButtons) do
        if TabShown(b.tab) then shown[#shown + 1] = b; b:Show() else b:Hide() end
    end
    local n = #shown
    local room = (RIGHT - MARGIN) - (LEFT + MARGIN)
    local texts, sum = {}, 0
    for i, b in ipairs(shown) do texts[i] = (b.label and b.label:GetStringWidth()) or 70; sum = sum + texts[i] end
    local pad = 34
    while pad > 14 and sum + n * pad + (n - 1) * 4 > room do pad = pad - 2 end
    local total = 0
    for i, b in ipairs(shown) do
        b:SetWidth(texts[i] + pad)
        total = total + texts[i] + pad
    end
    local gap = (n > 1) and (room - total) / (n - 1) or 0
    local x = LEFT + MARGIN
    for _, b in ipairs(shown) do
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, TAB_TOP)
        x = x + b:GetWidth() + gap
    end
end

-- Berry Mode switched: the open tab shows the switches of the mode now in use
function ns.RefreshTabs()
    if not frame then return end
    LayoutTabs()
    if frame.berry then frame.berry:Sync() end
    if current and not TabByKey(current) then Select(nil) end
    for k, p in pairs(panels) do if p:IsShown() then p:SyncAll() end end
end

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "SKToolsSettings", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        Window().point = { p, rp, x, y }
    end)
    W.Skin(frame, "dialog")
    tinsert(UISpecialFrames, "SKToolsSettings")      -- Esc closes it

    local p = Window().point
    if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else frame:SetPoint("CENTER") end

    W.TitlePlate(frame, "SKTools")

    -- the bee sits on the top-left corner, like a portrait on the old windows
    local art = CreateFrame("Frame", nil, frame)
    art:SetAllPoints()
    art:SetFrameLevel(frame:GetFrameLevel() + 20)
    local logo = W.Logo(art, 64)
    logo:SetPoint("TOPLEFT", frame, "TOPLEFT", -22, 26)
    -- and the berry (Berry Mode) on the bottom-left corner, 80% of the bee's size
    local berryArt = art:CreateTexture(nil, "OVERLAY", nil, 6)
    berryArt:SetTexture(ns.MEDIA .. "Berry")
    berryArt:SetSize(51, 51)
    berryArt:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -24, -15)
    frame.berryArt = berryArt
    local sub = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", 50, -18)
    sub:SetText("v" .. tostring(ns.version))

    local close = W.CloseButton(frame, function() frame:Hide() end)
    close:SetPoint("TOPRIGHT", -5, -5)

    -- the tabs stand on a bronze-edged box that holds the open tab's controls
    local box = CreateFrame("Frame", nil, frame)
    box:SetPoint("TOPLEFT", 14, TAB_TOP - 24)
    box:SetPoint("BOTTOMRIGHT", -14, FOOTER - 2)
    box:SetFrameLevel(frame:GetFrameLevel() + 1)
    W.Skin(box, "inset")

    -- the tabs: the same margin on both sides of the window and the same gap between each two; each
    -- as wide as its title needs, with less padding round the titles if they would not fit otherwise
    for i, tab in ipairs(ns.tabs) do
        local b = W.Tab(frame, tab.title, function(self) Select(self.key) end)
        b.key = tab.key
        b.tab = tab
        b:SetFrameLevel(frame:GetFrameLevel() + 3)
        tabButtons[i] = b
    end
    LayoutTabs()

    -- footer: things that belong to no single tab
    -- whose settings the tabs are changing (click to open the Profiles tab)
    local who = CreateFrame("Button", nil, frame)
    who:SetSize(230, 18)
    who:SetPoint("BOTTOM", frame, "BOTTOM", 0, 18)
    who.text = who:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    who.text:SetPoint("CENTER")
    who:SetScript("OnClick", function() ns.OpenSettings("profiles") end)
    function who:Sync()
        if ns.UsingCharProfile() then
            self.text:SetText("|cffffffffSettings:|r this character only")
        else
            self.text:SetText("|cffffffffSettings:|r account-wide")
        end
    end
    frame.who = who

    -- Berry Mode, for the whole addon
    -- no label: the berry beside it says what it is (the tooltip names it)
    local berry = W.Check(frame, "", function() return ns.BerryMode() end,
        function(v) ns.SetBerryMode(v) end, 24)
    berry:SetPoint("BOTTOMLEFT", 40, 18)             -- by the berry in the corner
    berry:SetFrameLevel(frame:GetFrameLevel() + 3)
    berry.tooltip = "A more chill place to start!"
    frame.berry = berry

    local note = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("BOTTOMRIGHT", -24, 21)
    note:SetText("Scroll on a slider or use - / + for single steps.")

    frame:SetScript("OnShow", function(self) self.who:Sync(); self.berry:Sync(); LayoutTabs() end)
    frame:Hide()
end

function ns.OpenSettings(key)
    Build()
    -- old names still work: "prd" (the resource display) is a page of the Cooldowns tab now
    local page
    if key == "prd" then page = "prd" end
    if key and not TabByKey(key) and ns.TAB_ALIASES and ns.TAB_ALIASES[key] then key = ns.TAB_ALIASES[key] end
    Select(key or current or Window().tab)
    if page and panels[current] and panels[current].ShowPage then panels[current].ShowPage(page) end
    frame:Show()
    frame:Raise()
end

function ns.ToggleSettings(key)
    Build()
    if frame:IsShown() and (not key or key == current) then
        frame:Hide()
    else
        ns.OpenSettings(key)
    end
end

-- keep an open window in step after a chat command changed something
function ns.RefreshSettings()
    if not frame or not frame:IsShown() then return end
    frame.who:Sync()
    local panel = current and panels[current]
    if panel then panel:SyncAll() end
end

function ns.SettingsShown(key)
    return frame and frame:IsShown() and (not key or key == current) or false
end

-- small entry in Esc > Options > AddOns that opens the window
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    pcall(function()
        local stub = CreateFrame("Frame")
        local text = stub:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("TOPLEFT", 16, -16)
        text:SetText("SKTools settings live in their own window, so you can watch the game while you tweak.")
        local open = W.Button(stub, "Open SKTools settings", 190, function()
            if SettingsPanel then HideUIPanel(SettingsPanel) end
            ns.OpenSettings()
        end)
        open:SetPoint("TOPLEFT", 16, -44)
        local cat = Settings.RegisterCanvasLayoutCategory(stub, "SKTools")
        Settings.RegisterAddOnCategory(cat)
    end)
end)
