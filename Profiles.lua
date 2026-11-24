-- SKTools settings tab: Profiles.
-- Settings are account-wide as standard: change something and every
-- character has it. A character can be given its own copy instead.

local ADDON, ns = ...

local W = ns.W

local function Build(panel)
    local L, R = 24, 400
    local me = ns.CharKey() or "this character"

    ------------------------------------------------------------------
    W.Header(panel, "Whose settings do the tabs change?", L, -8, 330)

    -- two boxes that work as a pair: exactly one is ticked
    local acc = panel:Add(W.Check(panel, "Account-wide: all my characters (standard)",
        function() return not ns.UsingCharProfile() end,
        function(v)
            if not ns.UsingCharProfile() then return end
            ns.ConfirmReload("Switch " .. me .. " back to the account-wide settings?\n\n"
                .. "Its own settings are kept in case you want them again.",
                function() ns.SetCharProfile(false) end)
        end, 330), L, -36)
    acc.tooltip = "Every change you make applies to all characters that use the account-wide settings."

    local own = panel:Add(W.Check(panel, "Own settings for " .. me,
        function() return ns.UsingCharProfile() end,
        function(v)
            if ns.UsingCharProfile() then return end
            ns.ConfirmReload(ns.HasCharProfile()
                and ("Switch " .. me .. " to its own settings?\n\nIt picks up the character profile it had before.")
                or ("Give " .. me .. " its own settings?\n\nThey start as a copy of the account-wide ones; "
                    .. "after that, changes made on this character stay on this character."),
                function() ns.SetCharProfile(true) end)
        end, 330), L, -60)
    own.tooltip = "This character gets its own copy of every tab's settings. Other characters are not affected."

    panel.state = W.Note(panel, "", L, -92, 330)

    ------------------------------------------------------------------
    W.Header(panel, "Copy settings", L, -150, 330)

    panel.toChar = panel:Add(W.Button(panel, "Account  >  this character", 200, function()
        ns.ConfirmReload("Replace " .. me .. "'s own settings with a fresh copy of the account-wide ones?",
            function() ns.CopyAccountToChar() end)
    end), L, -176)
    panel.toChar.tooltip = "Start this character's profile again from the account-wide settings."

    panel.toAcc = panel:Add(W.Button(panel, "This character  >  account", 200, function()
        ns.ConfirmReload("Make " .. me .. "'s settings the account-wide ones?\n\n"
            .. "Every character on the account-wide settings gets them.",
            function() ns.CopyCharToAccount() end)
    end), L, -204)
    panel.toAcc.tooltip = "Use this character's settings as the account-wide settings from now on."

    panel.copyNote = W.Note(panel, "", L, -236, 330)

    ------------------------------------------------------------------
    -- things about this character (more may come here)
    W.Header(panel, "Character specific information", L, -290, 330)
    panel.respec = W.Note(panel, "", L, -316, 330)
    -- the countdown kept current while the tab is open
    local tick = CreateFrame("Frame", nil, panel)
    local acc = 0
    tick:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 30 then return end
        acc = 0
        if ns.Respec then panel.respec:SetText(ns.Respec.Text()) end
    end)
    if ns.Respec then
        ns.Respec.OnChange = function() if panel:IsShown() then panel.respec:SetText(ns.Respec.Text()) end end
    end

    ------------------------------------------------------------------
    W.Header(panel, "What is shared", R, -8, 330)

    W.Note(panel, "|cffffd200Follows the choice on the left|r\nEverything on the Profession DB, Action Bar, "
        .. "Nameplate and Personal Resource Bars tabs.", R, -34, 330)

    W.Note(panel, "|cffffd200Always account-wide|r\nThe minimap button, where the windows sit, and what the "
        .. "addon has learned: mobs that drop quest starters, and melee spells this client reports wrongly.",
        R, -92, 330)

    W.Note(panel, "|cffffd200Always per character|r\nWhat you are tracking on the maps, the Profession DB "
        .. "window's profession and list mode, the quests a character has already seen, and its talent respec timer.", R, -160, 330)

    W.Header(panel, "Characters with their own settings", R, -230, 330)
    panel.chars = W.Note(panel, "", R, -256, 330)

    function panel:OnSync()
        local using = ns.UsingCharProfile()
        if using then
            self.state:SetText("|cffffffffNow:|r changes you make apply to " .. me .. " only.")
        elseif ns.HasCharProfile() then
            self.state:SetText("|cffffffffNow:|r changes you make apply to all your characters. "
                .. me .. " has a character profile stored, not in use.")
        else
            self.state:SetText("|cffffffffNow:|r changes you make apply to all your characters.")
        end
        -- copying only makes sense while this character is on its own settings
        self.toChar:SetShown(using)
        self.toAcc:SetShown(using)
        self.copyNote:SetText(using and "" or "Copying is available once this character has its own settings.")

        if ns.Respec then self.respec:SetText(ns.Respec.Text()) end

        local names = {}
        for name in pairs(ns.account.charProfiles) do names[#names + 1] = name end
        table.sort(names)
        self.chars:SetText(#names > 0 and table.concat(names, "\n")
            or "None. Every character you have logged in uses the account-wide settings.")
    end
end

ns.RegisterTab({ key = "profiles", title = "Profiles", order = 6, Build = Build })
