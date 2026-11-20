-- SKTools settings tab: Keybinds (keys for things the game has none for).

local ADDON, ns = ...
local W = ns.W

local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true }

-- the key pressed, with Alt / Ctrl / Shift held, as the game writes it ("ALT-CTRL-SHIFT-K")
local function Chord(key)
    if _G.CreateKeyChordStringUsingMetaKeyState then
        local ok, c = pcall(CreateKeyChordStringUsingMetaKeyState, key)
        if ok and c then return c end
    end
    local m = ""
    if IsAltKeyDown() then m = m .. "ALT-" end
    if IsControlKeyDown() then m = m .. "CTRL-" end
    if IsShiftKeyDown() then m = m .. "SHIFT-" end
    return m .. key
end

local function KeyOf(command)
    local ok, k = pcall(GetBindingKey, command)
    return ok and k or nil
end

local function Save()
    local set = (_G.GetCurrentBindingSet and GetCurrentBindingSet()) or 1
    pcall(SaveBindings, set)
end

local function Pretty(key)
    if not key then return "|cff888888Not bound|r" end
    if _G.GetBindingText then
        local ok, t = pcall(GetBindingText, key)
        if ok and t and t ~= "" then return t end
    end
    return key
end

local listening              -- the button waiting for a key

local function KeyButton(panel, bind)
    local b = W.Button(panel, "", 180, nil)
    local function Show()
        b:SetLabel(listening == b and "|cffffd100Press a key...|r" or Pretty(KeyOf(bind.command)))
    end
    local function Stop()
        listening = nil
        b:EnableKeyboard(false)
        b:SetScript("OnKeyDown", nil)
        Show()
    end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, mouse)
        if InCombatLockdown and InCombatLockdown() then
            ns.Print("key bindings can't be changed in combat.")
            return
        end
        if mouse == "RightButton" then
            -- right-click: unbind
            local old = KeyOf(bind.command)
            if old then SetBinding(old, nil); Save() end
            Stop()
            return
        end
        if listening == self then Stop(); return end
        if listening and listening.stop then listening.stop() end
        listening = self
        self:EnableKeyboard(true)
        if self.SetPropagateKeyboardInput then pcall(self.SetPropagateKeyboardInput, self, false) end
        self:SetScript("OnKeyDown", function(_, key)
            if MODIFIER_KEYS[key] then return end            -- wait for the real key
            if key == "ESCAPE" then Stop(); return end
            local chord = Chord(key)
            local was = GetBindingAction and GetBindingAction(chord)
            local old = KeyOf(bind.command)
            if old and old ~= chord then SetBinding(old, nil) end
            if SetBinding(chord, bind.command) then
                Save()
                if was and was ~= "" and was ~= bind.command then
                    ns.Print(("%s now does %s (it was %s)."):format(chord, bind.text,
                        (_G["BINDING_NAME_" .. was]) or was))
                end
            end
            Stop()
        end)
        Show()
    end)
    b.stop = Stop
    b.Sync = Show
    b.tooltip = bind.tip .. "\n\nClick, then press a key (Alt, Ctrl and Shift can be held). Right-click to unbind; Esc to cancel."
    b.command = bind.command
    return b
end

local function Build(panel)
    local L, CW = 24, 700
    W.Header(panel, "Keys for things the game has none for", L, -8, CW)
    for i, bind in ipairs(ns.KEYBINDS) do
        local y = -40 - (i - 1) * 32
        local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("TOPLEFT", panel, "TOPLEFT", L, y - 4)
        label:SetText(bind.text)
        panel:Add(KeyButton(panel, bind), L + 220, y)
        -- what it is set to now, where the game shows it
        if bind.command == "SKTOOLS_SOUND_IN_BACKGROUND" then
            local now = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            now:SetPoint("TOPLEFT", panel, "TOPLEFT", L + 416, y - 5)
            local holder = CreateFrame("Frame", nil, panel)
            holder.Sync = function() now:SetText("now " .. (ns.SoundInBackground() and "on" or "off")) end
            panel:Add(holder, L + 416, y)
        end
    end
    W.Note(panel, "Click a key box, then press the key you want (Alt, Ctrl and Shift can be held with it). "
        .. "Right-click a box to unbind it; Esc cancels. The keys are saved with your other key bindings and "
        .. "are also listed in the game's own Key Bindings, under AddOns.", L, -40 - #ns.KEYBINDS * 32 - 12, CW)
end

ns.RegisterTab({
    key = "keybinds", title = "Keybinds", order = 4, Build = Build,
    OnHide = function() if listening and listening.stop then listening.stop() end end,
})
