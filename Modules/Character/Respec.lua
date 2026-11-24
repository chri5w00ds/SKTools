--[[-------------------------------------------------------------------------
  SKTools - talent respec cost timer (per character)

  WoW Forever's talent reset cost climbs with each reset (as players report it:
  1g, 5g, 10g, then 5g more each time up to 50g) and drops back one step for
  every 7 days without a reset - counted from the reset itself, not the weekly
  reset (also as reported; Blizzard has only said "once a week").

  The game tells an addon the price only at the trainer, when you ask to
  unlearn your talents (CONFIRM_TALENT_WIPE). So:
    - a reset is noticed when it happens (the unlearn confirmed, your money
      going down; or your unspent talent points jumping back), with the price
      the trainer asked: that starts the countdown
    - from it, the price now and when it next drops are worked out
    - whenever the trainer is asked again, the price it gives is compared with
      the worked-out one; a difference is noted in the report log and the
      timer follows the trainer from then on

  Kept per character, in SKToolsCharDB.respec. Shown on the Profiles tab.
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

local WEEK = 7 * 24 * 60 * 60
-- the price steps, in gold (as players report them)
local LADDER = { 1, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50 }

local function Now() return (time and time()) or 0 end
local function DB()
    if type(SKToolsCharDB) ~= "table" then return nil end
    SKToolsCharDB.respec = SKToolsCharDB.respec or {}
    return SKToolsCharDB.respec
end

-- the step a price stands on (the nearest one at or under it)
local function Step(gold)
    local idx = 1
    for i, g in ipairs(LADDER) do if gold >= g - 0.001 then idx = i end end
    return idx
end

-- the price now, the next lower price, and when it drops to it (nil when at the lowest / unknown)
local function Predict(at)
    local d = DB()
    if not d or not d.at then return nil end
    at = at or Now()
    local drops = math.max(0, math.floor((at - d.at) / WEEK))
    local idx
    if d.seen and d.seen.at and d.seen.at >= d.at then
        -- the trainer's word, carried on from when it was given
        local dropsThen = math.max(0, math.floor((d.seen.at - d.at) / WEEK))
        idx = Step(d.seen.gold) - (drops - dropsThen)
    else
        idx = math.min(#LADDER, Step(d.paid or 1) + 1) - drops
    end
    idx = math.max(1, math.min(#LADDER, idx))
    local nextAt = (idx > 1) and (d.at + (drops + 1) * WEEK) or nil
    return LADDER[idx], (idx > 1) and LADDER[idx - 1] or nil, nextAt
end

local function Gold(copper) return (Plain(copper) or 0) / 10000 end
local function GoldText(g)
    if g == math.floor(g) then return ("%dg"):format(g) end
    return ("%.2fg"):format(g)
end
local function When(t) return (date and date("%a %d %b, %H:%M", t)) or tostring(t) end
local function Span(secs)
    secs = math.max(0, secs)
    local d = math.floor(secs / 86400)
    local h = math.floor((secs % 86400) / 3600)
    local m = math.floor((secs % 3600) / 60)
    if d > 0 then return ("%d day%s %d h"):format(d, d == 1 and "" or "s", h) end
    if h > 0 then return ("%d h %d min"):format(h, m) end
    return ("%d min"):format(m)
end

----------------------------------------------------------------------
-- Noticing a reset
----------------------------------------------------------------------

local offer = nil             -- { gold, at }: the last price the trainer asked
local recentAt = 0            -- the last reset noted (two ways of noticing one: noted once)

local function Points()
    local p = Ask(_G.UnitCharacterPoints, "player")
    if type(p) ~= "number" then p = Ask(_G.GetUnspentTalentPoints) end
    return type(p) == "number" and p or nil
end
local lastPoints

local function Noted(gold, how)
    local d = DB()
    if not d then return end
    local t = Now()
    if t - recentAt < 60 then return end          -- the same reset, noticed the other way
    recentAt = t
    d.at, d.paid, d.seen = t, gold, nil
    d.count = (d.count or 0) + 1
    d.history = d.history or {}
    table.insert(d.history, 1, { at = t, paid = gold })
    while #d.history > 10 do table.remove(d.history) end
    local now, nextCost = Predict(t)
    if ns.LogAdd then
        ns.LogAdd("respec", { ("talents reset for %s (%s); next reset costs %s, dropping a step every 7 days from now"):format(
            gold and GoldText(gold) or "an unknown price", how, now and GoldText(now) or "?") })
    end
    if ns.Respec and ns.Respec.OnChange then ns.Respec.OnChange() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "CONFIRM_TALENT_WIPE", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE" }) do
    pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        lastPoints = Points()
        -- the unlearn confirmed: a reset, if your money goes down for it
        if _G.ConfirmTalentWipe and hooksecurefunc then
            hooksecurefunc("ConfirmTalentWipe", function()
                local before = Ask(_G.GetMoney)
                local gold = offer and offer.gold
                C_Timer.After(2, function()
                    local after = Ask(_G.GetMoney)
                    if before and after and after < before then
                        Noted(gold or Gold(before - after), "unlearned at the trainer")
                    end
                end)
            end)
        end
        return
    end
    if event == "CONFIRM_TALENT_WIPE" then
        -- the trainer's price: noted, and checked against what the timer expected
        local gold = Gold(arg1)
        offer = { gold = gold, at = Now() }
        local d = DB()
        if d then
            local expected = Predict()
            if d.at and expected and math.abs(expected - gold) > 0.001 and ns.LogAdd then
                ns.LogAdd("respec", { ("the trainer asks %s; the timer expected %s - it follows the trainer from now on"):format(
                    GoldText(gold), GoldText(expected)) })
            end
            d.seen = { at = offer.at, gold = gold }
            if ns.Respec and ns.Respec.OnChange then ns.Respec.OnChange() end
        end
        return
    end
    -- unspent talent points jumping back up right after the trainer asked: a reset
    local p = Points()
    if p and lastPoints and p - lastPoints >= 2 and offer and Now() - offer.at < 300 then
        Noted(offer.gold, "talent points given back")
    end
    lastPoints = p or lastPoints
end)

----------------------------------------------------------------------
-- For the Profiles tab
----------------------------------------------------------------------

ns.Respec = {
    -- the lines shown under "Character specific information"
    Text = function()
        local d = DB()
        if not d then return "" end
        local lines = {}
        local now, lower, nextAt = Predict()
        if now then
            if lower and nextAt then
                lines[#lines + 1] = ("|cffffd200Talent respec:|r %s now. Drops to %s in %s (%s)."):format(
                    GoldText(now), GoldText(lower), Span(nextAt - Now()), When(nextAt))
            else
                lines[#lines + 1] = ("|cffffd200Talent respec:|r %s now, the lowest it goes."):format(GoldText(now))
            end
            lines[#lines + 1] = ("Last reset: %s, for %s."):format(When(d.at), d.paid and GoldText(d.paid) or "an unknown price")
            if d.seen and d.seen.at >= d.at then
                lines[#lines + 1] = ("The trainer last asked %s (%s)."):format(GoldText(d.seen.gold), When(d.seen.at))
            end
        elseif d.seen then
            lines[#lines + 1] = ("|cffffd200Talent respec:|r the trainer asked %s (%s). The countdown starts at your next reset."):format(
                GoldText(d.seen.gold), When(d.seen.at))
        else
            lines[#lines + 1] = "|cffffd200Talent respec:|r no reset noted on this character yet. The countdown starts at your next one."
        end
        return table.concat(lines, "\n")
    end,
    Predict = Predict,
    Ladder = LADDER,
    OnChange = nil,               -- set by the Profiles tab: redraw when something changes
}
