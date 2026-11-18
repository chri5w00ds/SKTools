> The Hunter range bar part of SKTools. The commands below work in SKTools.

# Hunter range bar

Range and resource awareness for **WoW Forever**.

## Action bar tint (every class)

Action bar icons are tinted so you can read them at a glance:

| Situation                     | Tint                                   |
|-------------------------------|----------------------------------------|
| Out of range                  | red                                    |
| Not enough mana               | blue                                   |
| Not enough energy             | yellow                                 |
| Not enough rage / focus       | their own colours                      |
| Out of range **and** short    | resource colour on top, red underneath where it has receded |

With **Shrink as resource fills** on, the resource tint only covers the part
of the cost you are still missing. As the resource comes back, the tint
recedes towards the top-right corner along a 45 degree edge, which ripples
gently while it waits. If you are also out of range, the red range layer fills
in behind it from the bottom-left as it recedes.

Every colour is picked with the colour wheel, and the tint opacity is
adjustable so the icons underneath stay readable. Works with the default
bars, Bartender4 and Dominos.

## Combo points (Rogues and Druids)

Five dots in an arc on the right of your target's level badge, filling
clockwise from the top. Nothing shows until you have a point; then all five
frames appear, filled ones in red with a soft glow. Dot size, distance from the
badge, position, glow strength, background and colour are all adjustable, and
the settings window shows a 3-point preview on your target while it is open.

`/skr combo on|off` switches them on or off, `/skr combo debug` shows what the
addon sees.

## Range bar (Hunters with a ranged weapon)

The range bar is a WoW Forever port of
[RangeBar (Hunter)](https://github.com/AlwaysFourth/RangeBarHunter) by
AlwaysFourth (MIT). It only appears on a Hunter with a bow, gun or crossbow
equipped.

A vertical range bar for **WoW Forever**, built around the one thing Hunters
actually need to know: **are you in the dead zone right now?**

The bar shows all four zones as faint bands. The band you are currently in
lights up in its own color, so you can read it out of the corner of your eye
without taking your attention off the mob.

| Color  | Zone                | Distance                            |
|--------|---------------------|-------------------------------------|
| Orange | Melee range         | 0 - 5 yd                            |
| Red    | **Dead zone**       | 5 - 8 yd - can't shoot, can't melee |
| Green  | Ranged weapon range | 8 - 35 yd (41 with 3/3 Hawk Eye)    |
| Grey   | Out of range        | > max range                         |

Above the bar is the zone name (`MELEE`, `DEAD ZONE`, `SHOOT`, `TOO FAR`), below
it the estimated distance, and the zone boundaries are labelled down the side.

The bar only appears for targets you can actually attack. Friendly players and
NPCs never show it.

**Hunter with a ranged weapon only.** The bar is built on the dead zone, which
is a Hunter mechanic - ranged weapons have an 8 yard minimum and nothing else in
Classic does. On other classes, or with no bow, gun or crossbow equipped, the
bar stays hidden; the action bar tint keeps working.

## Installing

It comes with SKTools: put the `SKTools` folder in your WoW Forever `Interface/AddOns/` folder.
Don't run it next to the original RangeBar (Hunter), since both draw the same bar.

## Using it

Click the minimap button, or type `/skr` (also `/rangebar` and `/rb`) to open the options
window. Everything is in there - it is not slash-command-only.

```
/rangebar               open the options window
/rb move | lock         move the bar with the mouse (also right-click the
                        minimap button)
/rb center              snap the bar back to the middle of the screen
/rb height N            bar height in pixels (default 220)
/rb width N             bar width in pixels (default 26)
/rb alpha N             0.1 - 1
/rb max N               max ranged range, 0 = auto (35 + Hawk Eye)
/rb min N               minimum ranged range / top of the dead zone (default 8)
/rb ticksize N          size of the distance numbers beside the bar (6 - 24)
/rb plates N            nameplate distance used to help spot the dead zone
/rb text on|off         zone + distance text
/rb ticks on|off        tick lines and numbers
/rb autohide on|off     hide the bar when you have no target (default on)
/rb minimap on|off      show the minimap button (default on)
/rb debug               print what every range check currently reports
/rb reset               restore defaults
```

Settings and position are saved per account.

## How the range is worked out

WoW never gives addons an exact distance, so the addon combines everything the
client *will* answer. The **color is exact** - it comes from the game's own range
checks. The **number is an estimate**, which is why it reads as a bracket like
`5 - 8 yd` rather than a single figure.

* `IsSpellInRange` on **Auto Shot** (falling back to Arcane Shot, Serpent Sting,
  Concussive Shot, Distracting Shot, Multi-Shot, Aimed Shot) - the authoritative
  "can I shoot right now" test, including the client's own minimum-range rule.
* `IsSpellInRange` on **Wing Clip / Raptor Strike / Mongoose Bite /
  Counterattack** - the authoritative melee test, which correctly accounts for
  big mobs having a larger melee reach.
* `CheckInteractDistance` at 9.9 / 11.11 / 28 yd, plus **Hunter's Mark** at
  100 yd, to narrow the estimate.

Max ranged range is auto-detected as 35 yd plus 2 yd per point of Hawk Eye. The
top of the bar's scale is fixed at 42 yd, which fits both 35 and 41.

### Why the dead zone is hard, and how this addon does it

Auto Shot failing is **ambiguous**. It means you are either too close (< 8 yd) or
too far (> 35 yd), and the client gives one bit, not a reason. Failing both the
melee and the shot check only narrows you to:

```
distance in (5, 8)  or  (35, infinity)
        dead zone       too far
```

Telling those apart needs a probe that proves you are within *some* distance
below 35. In order of preference the addon uses:

1. **`CheckInteractDistance` at 9.9 yd.** Proven at runtime rather than assumed -
   any index returning true is proof the call answers for NPCs, and index 3
   returning false while the melee check says you are within 5 yd is proof it
   does not, at which point it is switched off.
2. **Scatter Shot** (15 yd) or **Scare Beast** (10 yd, beasts only) - the only
   Hunter abilities with no minimum range, so they prove the dead zone outright.
3. **The mob's melee swings** landing on you - it is inside its own reach.
4. **Nameplates** - a plate only exists within `nameplateMaxDistance` yards.
   Only ever used as proof you are *close*; a missing plate proves nothing,
   since plates can be switched off, and the addon detects that case.

If your nameplate distance is set below your max ranged range, detection is
exact. Set above it, there is a thin sliver just out of shot range that can read
as dead zone - `/rb plates 20` if you want that gone.

**Never use auto attack (`Attack`, spell 6603) or wand `Shoot` as range checks.**
They report "in range" for any attackable unit at any distance, which makes the
melee band swallow every other zone. Noted here because it is an easy trap.

## Notes

* If you play on a realm where the Hunter dead zone has been removed, run
  `/rb min 5` and the red band disappears.
* Testing range behavior is easiest on a **critter** - squirrel, rabbit,
  chicken. They are attackable NPCs, so every check behaves as it would on a
  real mob, and they cannot hurt you, which matters on Hardcore.

## Forever notes

The Forever client runs on the modern game engine, which can hide some API
answers from addons ("secret values"), mostly in combat. Any hidden answer is
treated as "no answer" rather than causing an error, so the bar keeps working
on whatever checks are still available. `/skr debug` shows how many hidden
answers it has met and whether the combat log is available.

## License

MIT - see [LICENSE](LICENSE).
