> How SKTools works out a Hunter's range to the target, shown by the range crescent on the
> target's nameplate (settings on the Nameplates tab).

# Hunter range detection

Based on [RangeBar (Hunter)](https://github.com/AlwaysFourth/RangeBarHunter) by AlwaysFourth (MIT).
It started as a vertical range bar; the bar is gone, and what it worked out now drives the
crescent on your target's nameplate. It only matters on a Hunter with a bow, gun or crossbow, and
only for targets you can attack.

| Zone                | Distance                            |
|---------------------|-------------------------------------|
| Melee range         | 0 - 5 yd                            |
| **Dead zone**       | 5 - 8 yd - can't shoot, can't melee |
| Ranged weapon range | 8 - 35 yd (41 with 3/3 Hawk Eye)    |
| Out of range        | > max range                         |

## Commands

```
/skt range debug        print what every range check reports on your target
/skt range watch        print a line whenever the zone or auto attack changes
/skt range plates N     nameplate distance used to help spot the dead zone
/skt range max N        max ranged range, 0 = auto (35 + Hawk Eye)
/skt range min N        minimum ranged range / top of the dead zone (default 8)
/skt range reset        restore defaults
```

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

Max ranged range is auto-detected as 35 yd plus 2 yd per point of Hawk Eye.


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
as dead zone - `/skt range plates 20` if you want that gone.

**Never use auto attack (`Attack`, spell 6603) or wand `Shoot` as range checks.**
They report "in range" for any attackable unit at any distance, which makes the
melee band swallow every other zone. Noted here because it is an easy trap.

## Notes

* If you play on a realm where the Hunter dead zone has been removed, run
  `/skt range min 5` and the dead zone disappears.
* Testing range behavior is easiest on a **critter** - squirrel, rabbit,
  chicken. They are attackable NPCs, so every check behaves as it would on a
  real mob, and they cannot hurt you, which matters on Hardcore.

## Forever notes

The Forever client runs on the modern game engine, which can hide some API
answers from addons ("secret values"), mostly in combat. Any hidden answer is
treated as "no answer" rather than causing an error, so detection keeps working
on whatever checks are still available. `/skt range debug` shows how many hidden
answers it has met.

## License

MIT - see [LICENSE](LICENSE).
