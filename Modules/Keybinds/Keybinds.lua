-- SKTools - key bindings for things the game has no key for. Each is a binding the game knows
-- (Bindings.xml, so it is in Blizzard's Key Bindings too, under AddOns) and a row on the Keybinds tab.

local ADDON, ns = ...

BINDING_HEADER_SKTOOLS = "SKTools"
BINDING_NAME_SKTOOLS_SOUND_IN_BACKGROUND = "Sound in background on / off"

-- the actions: [binding name] = { text, run }
ns.KEYBINDS = {
    {
        command = "SKTOOLS_SOUND_IN_BACKGROUND",
        text = "Sound in background",
        tip = "Turns the game's \"Sound in Background\" option on or off: whether you hear the game while "
            .. "another window is in front.",
    },
}

-- Sound in background: the game's own setting, flipped
local CVAR = "Sound_EnableSoundWhenGameIsInBG"
local function GetCV(name)
    local get = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
    local ok, v = pcall(get, name)
    return ok and v or nil
end
local function SetCV(name, v)
    local set = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
    return pcall(set, name, v)
end

function ns.SoundInBackground()
    return GetCV(CVAR) == "1"
end

function SKTools_ToggleSoundInBackground()
    local on = not ns.SoundInBackground()
    SetCV(CVAR, on and "1" or "0")
    ns.Print("sound in background " .. (on and "|cff66ff66on|r" or "|cffff6666off|r") .. ".")
end
