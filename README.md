# SKTools

A set of interface tools in one addon for **WoW Forever**.

| Part | What it does |
| --- | --- |
| Profession DB | Search materials and mobs, pin their locations on the world map and minimap (Leatherworking, Tailoring data) |
| Action Bar | Tints action bar icons when out of range or short on mana, rage, energy or focus; bars that hide until hovered |
| Nameplates | Enemy nameplates with quest counters, quest-starter icon and rare glow, class sets (combo points, Hunter range crescent, skill icons, Shaman totems), GCD meter |
| Cooldowns | Our own panes for Blizzard's Cooldown Manager, with health, power and cast bars |
| Widgets | Personal and missing class buff icons |
| Button Box | Gathers the buttons other addons put round the minimap into one box |

## Look

The settings window and the Profession DB window use classic WoW chrome with Forever's cleaner
spacing: stone dialog border and title plate, red panel buttons, classic tick boxes, sliders
and tabs. It is built from the game's own templates and texture files, each checked first; a
control whose art this client lacks is drawn flat instead. The bee logo (`Media/Logo.tga`,
`Media/LogoSmall.tga`) is the button on the minimap, the AddOns-list icon and the settings window's
corner portrait.

## Use

- **`/skt`**, the bee button (right-click) or the AddOns drop-down opens the settings window, with one
  tab per part. `/skt db | action | nameplate | cooldowns | widgets | buttons | profiles` opens a tab directly.
- **Profession DB window**: the book button on the world map, a right-click on the minimap
  button, or `/sdb` (`/sdb <text>` searches). Opened while the world map is up it sits beside
  the map in a narrow layout and closes and re-opens with the map; opened on its own it is the
  full two-column window. `>>` / `<<` in its title bar switches layout.
- Short chat commands for their own parts: `/sdb`, `/sm`, `/skr` (`/rb`, `/rangebar`). Add `help`
  for the list.

## Minimap button box

The **Button Box** tab gathers the round buttons other addons add to the minimap into one box.

- **Attached:** the bee button sits on the minimap's left edge (Shift+left-click to release it). Left-click opens
  the box beside it, right-click opens these settings.
- **Detached:** tick "Detach from the minimap" and the box becomes free-standing; drag it by
  its top strip to any point on the screen ("Attach" on the strip puts it back). "Lock" stops
  it being dragged by accident.
- **Icon size:** the slider scales the buttons in the box (20 to 64 px).
- **Order:** Alphabetical, or Manual, where you drag the buttons inside the box into your own
  order. A button that turns up later goes last.
- **Layout:** "Icons wide" fills rows of N left to right; "Icons tall" fills columns of N top to
  bottom.
- **Which buttons:** the list on the right shows every button found; untick one to leave it
  on the minimap. The old stand-alone SKTools minimap button is gone: the bee button replaces it. Blizzard's own buttons (tracking, mail, calendar, zoom...) are never touched.

Buttons are only moved, never changed, and go back exactly as they were when you untick them
or turn the box off. `/skt buttons` opens the tab. The box settings are always account-wide.

**Bee button:** always on screen, on the minimap's left edge by default. Left-click opens/closes the box, right-click opens the SKTools settings, Shift+left-click releases it so you can drag it anywhere, Shift+right-click snaps it back to the minimap.

## Nameplates (Plates tab)

Version 2.0 redraws every enemy nameplate with its own square-edged frames. Blizzard's plate is not replaced, only made invisible (health bar, name, cast bar, level, highlights); its buff and debuff rows, raid marker and widgets stay. "Use these nameplates" on the **Plates** tab puts Blizzard's look straight back.

- **Health bar:** rounded corners, thin silver border, a light-to-dark gradient. Name on the left; percent over value on the right.
- **Colours:** bosses purple, casters light blue (mage, warlock, priest, shaman and druid NPCs), everything else green. Enemy players use their class colour, friendly units are grey-blue, tapped mobs grey. All of them can be changed.
- **Your target:** 20% bigger, with a thicker white border (both are settings).
- **Cast bar:** under the health bar with the spell icon on the left, then the spell name and the time left. Yellow normally, deep orange when the cast is aimed at you.
- **Level box:** to the right of the bar, crossed swords over the level. The quest kill count sits above it (diamond marker) and the loot count below it (purse marker); the quest-starter icon sits outside it on the right.
- **Left of the bar** (all scaling with the target): combo points (Rogue, Druid) or the Hunter crescent, hugging the bar. The crescent is cut from the same arc as the combo points so they share one slot. Left of those: Shred over Claw, almost touching, with the Bite / Shifting Power icon laid over the middle of the pair, leaving 30% of each showing.
- **Crowd-control icon:** Blizzard's shared CC icon is moved under the cast bar.

If something looks wrong in the game, `/skt platesdebug` (or "Debug to chat" on the Plates tab) lists what the game gave us: which API calls exist, what Blizzard's plate holds, and whether the cast bar has a timer. Forever can hide health and cast values from addons; they are only ever handed to status bars and text, never compared.

## Feral cat: Claw and Shred icons

On a Druid in Cat Form, two icons sit by the target's level box: **Shred** directly above it
and **Claw** directly below it. Each is as wide as the level box and the same distance from it
on both sides ("Gap from the level box"). The five combo points sit to the right of the box:
the middle one stays where it always was and the other four curve in towards it, about 2 px
apart and never touching ("Tight cluster" on the Combo panel switches that off for the old wide
arc). Blizzard's shared CC icon moves to just under the Claw icon while they show. "Beside the
level badge" off puts the two icons side by side under the health bar instead.

An icon only shows while its skill could be used right now, and only in combat ("Hide when not
ready" and "Only in combat" on the Cat skills panel; untick the first to keep grey, dimmed icons
for skills you cannot cast). An icon is lit when its skill could be used right now:

- **Energy:** asked of the game itself, so talents and procs that make a skill cheaper
  are already counted.
- **Range:** the skill's own melee range check on your target.
- **Cooldown:** the global cooldown does not count against it.

Lit means full colour, a bright rim, a soft glow and a gentle pulse. Not ready means a grey,
dimmed icon with no rim, so the two states differ by more than colour. "Hide when not ready"
removes the dimmed ones. Horizontal / Vertical / Icon size / Gap sliders and Claw, Shred,
Glow and Pulse switches are on the Nameplate tab under **Cat skills**; `/skt feral` opens it.
Shred's "must be behind the target" rule is not something addons can read, so it is not
part of "ready".


## Feral cat: Ferocious Bite / Shifting Power icon

A third icon sits to the left of the target's health bar (Druid, Cat Form, attackable target; shown in combat only, like Claw and Shred).

- **Ferocious Bite** shows with 5 combo points and full energy.
- **Shifting Power** shows with 5 combo points when it is learned, off cooldown and affordable, and casting it would take you to full energy for a Bite. The check is: current energy + the energy Shifting Power gives + the energy you regenerate during the global cooldown that follows >= maximum energy.
- The global cooldown is the spell's own, shortened by your spell haste (never below 0.75 s). Regeneration is the rate the game reports, which already includes haste.
- The energy Shifting Power gives is read from the spell's description. If it is not read correctly, set it with the "Energy from Shifting Power" slider on the **Bite** tab.
- `/skt` > Nameplate > Bite: position, switches, reset and a debug print that shows exactly what the check saw.

Combo points and energy may be hidden by the game in some situations; if they are, the icon stays off rather than guessing.

## Hunter range crescent (test)

The vertical range bar is replaced by a crescent on the target's nameplate, in the spot the
combo points use for Rogues and Druids. It has two states: **green** in shoot range and **red**
in melee range (it pulses, so the two differ by more than colour). In the dead zone and out
past shoot range there is no crescent. It only shows for a Hunter with a bow equipped; a gun or
crossbow hides it.

It has a thin classic silver rim and a soft glow in the zone colour (the Silver border and dome shading (dark under the rim, full colour along the middle) and Glow
boxes switch them off). While it shows, Blizzard's shared crowd-control icon, normally right
under the level badge, is moved out to its right and handed back when the crescent hides ("Move
CC icons aside"). Position, size, colours and the range settings are on the Nameplate tab under
**Range crescent**. `/skr bar on` brings the old bar back for comparison; `docs/HunterBar.md`
describes how the range detection works.

## Profiles

Settings are account-wide as standard: change something and every character has it. On the
**Profiles** tab a character can be given its own copy instead (it starts as a copy of the
account-wide settings), switched back, or have settings copied either way. Each switch reloads
the interface. The minimap button, window positions and what the addon has learned (quest-starter
mobs) are always shared; tracked map pins and seen quests are always per character.

## Adding a profession

Data files live in `Modules/ProfessionDB/Data/` and call
`SKToolsProfessionDB:RegisterModule(key, { name, categories, items, mobs, zones })`. Generate one with
`tools/build_module.py <profession> <output .lua>` and add it to `SKTools.toc`.

## Data and licence

- Loot, skinning and recipe data: [CMaNGOS classic-db](https://github.com/cmangos/classic-db) (GPLv3).
  Chances are vanilla 1.12 values and may differ on Forever.
- Spawn points, vendors and quest-starter drops: [QuestieDB](https://github.com/Questie/QuestieDB) (GPLv3).
- Map pins: HereBeDragons.
- The Hunter range bar is based on RangeBar (Hunter) by AlwaysFourth (MIT, see
  `LICENSE-RangeBar-MIT.txt`).

Because of the GPLv3 data, the combined addon is licensed GPLv3 (`LICENSE.txt`).

3.7.2: The empty white box after a reload, found from the login report: when a cooldown pane got fewer icons (Blizzard settles its list just after login), the white frames of the icons no longer there stayed up until the next relayout (up to the 5 s safety net). The ring and line pools now hide what was not drawn right after each layout (since 3.6.0 the panes no longer redraw every tick, which used to hide them).
3.7.1: /skt cddebug lists every frame Blizzard has in each cooldown pane (shown, picture, known, active, kept or left out) and each of our icons (spell, picture). /skt cddebug login: two such reports 1 s and 6 s after the next login or reload, saved to the log - for the empty box that shows for a few seconds after a reload.
3.7.0: Action bar tint and resource tint removed (Tint.lua, its 36 Media images, /skr tint, its saved settings); the Action Bar tab is now Mouseover, with the fade and linger times on it. Mouseover checks each bar once, by its area (frame plus buttons, measured once a second) against the cursor, instead of asking every button; smooth steps only while the mouse moves or a bar fades, ten looks a second otherwise. Cooldown panes: each icon set up on its Blizzard frame once (safety check every 2 s), picture and colours set only on change, spell costs kept a second (cleared on spell / form / talent change), target looked up once a frame. Combo points placed and styled only when something changed. The empty slot after login is gone: icons for spells the character has not learned, or with no picture yet, are left out (the spellbook check stopped early on clients without IsPlayerSpell).
3.6.3: Log window fixed: it had no place on screen, so the game never drew it. Level box joined to the bar: it runs on a few pixels under the bar's rounded left end, masked by an inverted copy of the bar mask (Media/PlateMaskInv.tga) so it only fills the bar's corners: the top and bottom lines run straight, the bar's curved edge is the line between them, and nothing sits behind the bar to show through faded plates. With a gap to the bar the box stays square.
3.6.2: Level box ends at the bar's left edge (it reached 8 px under the bar, which showed through faded plates as a short line). Cooldown panes skip icons Blizzard keeps hidden (a spell set up in the Cooldown Manager that the character has not learned), which showed as an empty white frame. /skt cpu opens the log window when done (after the fight if it ends in one). If the log window cannot open, the reason is said in chat.
3.6.1: Report log. /skt cpu and the debug commands (cddebug, platesdebug, platelist, icondebug, totemdebug, buffdebug, boxdebug) now save their output to SKToolsLog (written to SavedVariables/SKTools.lua at /reload or logout) instead of flooding chat; /skt log opens a window with the whole log to select and copy (Select all, Clear log); /skt log clear empties it. The newest 3000 lines are kept. The debug commands open the window; /skt cpu does not (it may finish mid-fight).
3.6.0: Performance. /skt cpu [seconds] times each part of the addon and lists them, slowest first (ms a second, share, calls). Cooldown panes lay out their icons, bars, frames and seams only when something changes (sizes, place, the spells in them, UI scale, a settings change; and every 5 s as a safety net) instead of 10 times a second; contents still refresh 10 times a second. Combo points listen to your own power changes only, not every unit around you.
3.5.3: Heal prediction on the health bar uses the game's heal prediction calculator (as Blizzard's bars do since Midnight): heal absorbs taken off, held to your missing health; the raw incoming number only as a fallback. /skt debug shows both side by side.
3.5.2: Combo points on SKTools plates: the curve a little flatter (radius 48 to 58), and the cluster is held back so no dot level with the kill / loot boxes reaches over them, whatever the combo nudge (the left icons move out with it).
3.5.1: /rl reloads the UI.
3.5.0: Level box moved to the left of the nameplate, with the kill (crossed swords) and loot (bag) counters above and below it. The combo points, Hunter crescent, Shaman totems and the left class-set icons stand past it (combo points drawn on top, clear of the counter icons); the right class-set icons moved in to the bar where the box was. GCD sweep: 85% black with a white line on its moving edge and a white frame round the box while it runs ("GCD sweep darkness" now gcdDark, default 85).
3.4.0: GCD meter moved back into your target's level box as a dark radial sweep that recedes clockwise while your global cooldown runs, the same as SKTools-ESO's skill bars (black, 62% by default: "GCD sweep darkness" slider with the level settings); no countdown numbers. The line and steam on the health bar are gone (Media/GcdSteam1-2.tga removed).
3.3.0: New Keybinds tab: keys for things the game has none for. First: Sound in background on / off (the game's own setting flipped, with a chat line saying which). Click the key box and press a key (Alt, Ctrl, Shift can be held); right-click unbinds, Esc cancels. Saved with your key bindings, and listed in the game's Key Bindings under AddOns too (Bindings.xml).
3.2.3: The centre big icon is centred on the health bar: still square at 1.5x the bar's height, it now overhangs equally above and below (a quarter of the bar's height each way).
3.2.2: Ferocious Bite (the big icon's Bite rule) works in combat: the game hides your energy there, so with 5 combo points Bite is shown through a gate the game itself opens at full energy (a hidden bar from 99 to 100 energy; the icon is clipped to its fill), the way the combo dots work. Shifting Power still needs readable energy.
3.2.1: Cursor glow goes the moment the game hides the cursor: while you turn the camera or steer with the right button, or drag the left one on the world; it fades back when you let go.
3.2.0: Class sets: behind-only skills (Shred, Ravage, Pounce, Backstab, Ambush, Garrote) only light up while you can be behind your target: hidden while it targets you (a mob faces whoever it attacks), and for a moment after the game says "You must be behind your target". Any other skill the game turns down that way is learned and treated the same. "Behind-only skills" switch in the class set settings.
3.1.1: Cursor glow shows on any ground: a dark halo under a bright glow, drawn as colour rather than added light (which washed out on snow, sand and bright spells); a "Dark halo" slider and an optional gentle pulse (Media/CursorShadow.tga).
3.1.0: New Cursor tab. Combat glow: a soft warm halo behind the cursor, following it, fading in when combat starts and out when it ends (or always); size, brightness and colour; shown while the tab is open so changes can be seen (Media/CursorGlow.tga). Alt tooltips: hold Alt as you point at something and its tooltip shows beside the cursor, following it. Both start off in Berry Mode, each with its own switch there.
3.0.2: Bee button clicks open in a window of their own, framed like the settings window with its title plate, closed with the red X at its top (or Esc); the Back button is gone. It closes with the settings window and can be dragged.
3.0.1: Tidy-up: the support for moving over from the old separate addons is gone (the import, the "turn the old addons off" popup, the optional dependencies), and so is the carry-over from the old name; every remaining internal name says SKTools (the Profession DB's table is SKToolsProfessionDB). /sdb, /sm and /skr stay. Old left-overs in the saved settings are tidied away.
3.0.0: Renamed to SKTools: the folder, the .toc, the saved settings (SKToolsDB, SKToolsCharDB), frame names, /sktools (/skt as before) and all the text. Author: Scotskoogen-Chris.
2.30.0: Cooldown icons (Essential, Utility, Tracked buffs, Items): a white frame round each icon, rounded at all four corners, neighbours sharing one line (overlapping by half) with a small dip where corners meet; the picture and the cooldown sweep are rounded too (Media/IconMask3-12.tga), so no square corner shows past the frame. Sizes, grid and snapping unchanged.
2.29.5: Nameplates tab: a "GCD meter" switch where Berry Mode's was; the GCD meter now keeps its own on / off in Berry Mode (off there until turned on). Cooldowns tab: a box left of each pane's title switches that pane on or off on its own (turning the bars off gives Blizzard's resource display and cast bar back).
2.29.4: The Berry Mode check is gone from the Nameplates tab: the berry switch at the bottom of the settings window is the one.
2.29.3: Clearer numbers on the resource display and tracked bars: no outline (drawn unevenly at that size, it clogged the figures), a crisp drop shadow instead, the text set on whole pixels, a touch larger.
2.29.2: GCD meter: nothing of it shows in the level box any more; the line across the health bar has the steam trailing under it (clipped to the bar). The centre big icon can hold the set's own big-icon rule (Ferocious Bite / Shifting Power; Primal Bite in Bear Form), like the left one.
2.29.1: The GCD line runs the length of the health bar only (none in the level box, which keeps its steam). Cast cost on our power bars, as on Blizzard's: while you cast a spell, the end of the fill of the power it costs is picked out in a lighter shade, as long as the cost (works with hidden numbers; channels, paid at the start, show none).
2.29.0: Bee clicks: "Hide / show action bars" (the Action Bar tab's main switch: the bars ticked there hide until hovered, or all show). Nameplates: the GCD line runs the whole plate, from the health bar's left edge across the level box (the steam stays in the box). Class sets: a centre big icon (cb) for every set with skill icons: square, 1.5x the health bar's height, standing on the bar's bottom edge at its middle so half the bar's height shows above it; in the editor drawn under the sample, click to choose its skill, its own sliders to nudge it.
2.28.0: Bee button clicks: every mix of Shift, Ctrl and Alt with the left and the right button can be given an action (Button Box tab, "Bee button clicks..."): the box, release / put back the bee, any settings tab, the Profession DB window, Blizzard's Cooldown Manager, unlock / lock the panes, Berry Mode, reload. The old four clicks are the defaults; the bee's tooltip lists what is set. Long drop-down lists show in two columns.
2.27.1: A fresh install starts with Scotskoogen-Chris's own setup (Starter.lua): nameplates and class sets, cooldown panes and their places, widgets, action bar fading, the Button Box, Profession DB options. Berry Mode is off, and the cooldown panes and widgets are off in it. Left out: window positions, learned data and Profession DB lists. Existing installs keep their own settings.
2.27.0: Healing on its way shows on our health bar as on Blizzard's: a lighter segment from the end of the health fill, as long as the incoming heal, cut off at the bar's end (works with hidden numbers in combat).
2.26.9: Cooldown panes in combat: when the game hides cooldown and buff times (in combat), our icons' spirals are set from the game's own duration objects instead (the buff's while it is up, otherwise the spell's cooldown or next charge), as a spiral won't take hidden times from an addon. Fixes Enrage (and any such spell) showing nothing in combat.
2.26.8: Cooldown pane frames: each frame line is put on a whole screen pixel once the pane is placed (a one-pixel line falling between two pixels could be drawn as none, which lost the right-hand line of the Essential pane).
2.26.7: Cooldown panes follow Blizzard's icons more faithfully: an icon handed another spell or buff lets go of the one it had (which could clear or overwrite it, so a buff such as Enrage could show no time), and starts from that spell's current cooldown or buff time; the swipe is drawn as Blizzard draws it (gold for a buff that is up, dark for a cooldown); Blizzard's "use it now" spell alerts glow round our icons (Media/IconGlow.tga). /skt cddebug lists every tracked spell with its state.
2.26.6: Blizzard's own player cast bar is hidden while our cast bar shows (the cooldown panes on), changed out of combat; a "Hide Blizzard's cast bar" check on the Resource display page turns it back on.
2.26.5: The berry sits a little further up and to the left on its corner.
2.26.4: Smooth cast bar and tracked bars: each fills or drains from its own every-frame update (the cast bar used to move only when all the panes were redrawn, about 30 times a second, and the tracked bars only 10 times a second where Blizzard's numbers can be read). Where cast times are hidden, the game's timer is started once per cast instead of restarted on every redraw.
2.26.3: The Berry Mode check's tooltip reads "A more chill place to start!"
2.26.2: The berry lost its white sticker border and got rounded light-and-shade like the bee; the Berry Mode check has no text (the berry beside it, and its tooltip, say what it is).
2.26.1: A berry on the bottom-left corner of the settings window (80% of the bee's size, as the bee sits on the top-left), with the Berry Mode check beside it; "Settings: account-wide" moved to the bottom centre.
2.26.0: Berry Mode is now a switch for the whole addon (bottom of the settings window, and still on the Nameplates tab). It keeps the nameplates (red), action bar, Profession DB and Button Box; the cooldown panes and the widgets start off in it but have their own Berry Mode on/off, so they can be turned on. New features will start off in Berry Mode the same way. The Blizzard personal resource display module is gone; the Cooldowns tab's second page is now "Resource display" for our own bars: background opacity, left-to-right gradient, cylinder shading, Druid energy bar, and colours for health, mana, energy, rage, focus, other power and the cast bar, which is now pink.
2.25.6: Settings tabs reordered (Button Box, Nameplates, Cooldowns, Widgets, Action Bar, Profession DB, Profiles). The Personal Resource Bars tab is now the "Blizzard's resource display" page of the Cooldowns tab, next to "Cooldown panes" (/skt prd still opens it). New "Open Blizzard's Cooldown Manager" button on the Cooldowns tab, to add or remove what is tracked.
2.25.5: Cooldown pane sizes in grid boxes: the Cooldowns tab's size sliders (bar width, the bar heights, icon sizes, the tracked bars' width and height) count whole grid boxes, shown with their pixels, and while snapping is on every pane is drawn in grid lengths with a pixel taken off its far side, so its far frame lines land on grid lines too.

2.25.4: Cooldown panes move box by box while dragged: the pane follows the cursor in grid steps with its frame lines on the grid lines, so where it shows is where it stays, and one box of cursor movement moves it one box. Snapping to another pane only pulls within 3 pixels of where you drag it (it pulled from 8, a whole box, so a centred pane jumped back unless moved two boxes).

2.25.3: Settings window: the tabs are spread evenly, the same margin on both sides and the same gap between each two (the last one no longer sits too far right). Cooldowns tab: the right column's settings are two to a row, clear of the frame at the bottom.

2.25.2: Snap to grid matches the grid: the grid lines are exactly one screen pixel, starting at their grid position, and a dropped pane's frame lines (left, and along its fixed edge) land on them.

2.25.1: Tracked buffs and tracked bars show only what is up right now: a tracked buff appears when it lands and goes when it falls off (examples still show while the panes are unlocked).

2.25.0: Cooldown panes, frames redone: each pane (or each run of equal-width rows in one) has a frame ring drawn over its content: smooth rounded corner pieces (Media/RingCorner, which also cover the content's square corners, so nothing pokes out and no masks are needed) and edges exactly one screen pixel thick at your UI scale, in the widget frames' silver. The Essential icons are a pane of their own (their size and per-row settings move over). A dropped pane also snaps to other panes: flush against one's top or bottom (the two frames sharing a line) and onto its centre line.

2.24.5: Cooldown panes: outline lines now sit just outside the edges they outline (they straddled them by half a pixel, which left a see-through pixel between the health bar and the line above it); the silver line between the icons and the bars fills the pixel left for it, with the icons above it; the icons' rounded-corner masks are set once instead of being taken off and put back every refresh, which left the icons square; the tracked bars' icons have a frame of their own, so their rounded corners are cut to the icon instead of being stretched over the whole row.

2.24.4: Cooldown panes: the outlines take the buff widget frames' silver, bright at the top and darker towards the bottom; the main block has a silver line between its icons and its health bar, in a pixel left for it.

2.24.3: Cooldown panes: subtler corners, a 2 px radius instead of 3 (outline and masks).

2.24.2: Cooldown panes: the outline is drawn above the icons and bars (they used to cover it), and the icons and bars are cut to the same rounded outer corners with small masks (Media/RoundIcon_*, RoundBar_*), only where the shape has an outer corner. The drag box while unlocked is exactly the pane's visible edge (it had padding, and ignored icon rows wider than the bars), and snapping lines up the pane's left edge with the grid.

2.24.1: Cooldown panes: the health, power, form, cast and tracked bars (and their dark tracks) carry the nameplates' gradient, light at the top and dark at the bottom. Snap to grid: while panes are unlocked a faint grid shows (brighter lines through the middle of the screen); a dropped pane, cooldown or buff widget, snaps to it. Grid size and an on/off switch are on the Cooldowns tab.

2.24.0: Cooldown panes: icons are a fixed size you choose (no longer stretched to fill the width), grown from the centre line; the cast bar runs along the bottom of the main block, below any form bar, only while casting; a thin white outline follows each pane's shape with its outer corners rounded; the resource frame sits on the icon's own edge with a 75% black track.

2.23.1: Lightning Shield is left out of the Tracked buffs pane while its charges show on the nameplate (as the only tracked buff it filled the pane's whole width).

2.23.0: Cooldowns: our own panes for Blizzard's Cooldown Manager, on a new Cooldowns tab. You track spells in Blizzard's Cooldown Manager; its panes are made invisible and ours show them: a main block (the cast bar on top only while casting, the Essential cooldowns, health and power with the percentage left and the value right, and a Druid form's power below), plus Tracked buffs, Utility, Items (on-use trinkets) and Tracked bars panes. Icons mirror the game's cooldowns and stack or charge counts (hidden ones too), turn red out of range, grey with a thin frame in the resource's colour filling clockwise as you build up to the cost, and inactive tracked buffs stay in place, dimmed. Icons per row is a cap: rows spread evenly, sized to fill the pane's width, the shorter rows on top for the block and tracked buffs and at the bottom for Utility and Items; the outline follows the shape. Blizzard's personal resource display is switched off while the block shows. `/skt cddebug` prints what they show.

2.22.0: Lightning Shield pips read from Blizzard's Cooldown Manager: with Lightning Shield among its Tracked Buffs, its icon's copy of the aura (refreshed by the game in combat) says whether the shield is up, and its charge count, hidden in combat, goes straight to the pips. That icon is made invisible (a setting in the Totem timers part). Without it, the hit counting from 2.21.8 is used. `/skt totemdebug` shows which.

2.21.8: Lightning Shield pips count down in combat from the hits you take: in combat the game sends addons no aura changes and refuses to look the shield up, but it does say when you are hit. Each physical hit (wounded, blocked or absorbed) spends a charge, at most one every few seconds (a ball can only fire that often): the wait starts at 3 s and is learned after each fight by checking the real count against the hits taken. `/skt totemdebug` shows the wait and logs the hits.

2.21.7: Lightning Shield pips in combat: the shield's own aura is now asked for by the id it had out of combat, and its (hidden) charge count goes straight to the pips; `/skt totemdebug` also lists the last few aura changes the game reported and whether their ids could be read.

2.21.6: Lightning Shield pips in combat: the game answers "not on you" for the shield in combat even while it is up, which hid the pips; that answer is now only believed out of combat, the pips go when the shield's aura is removed, each change to the shield's aura takes a charge whenever the real count is hidden, and a shield recast mid-fight is matched to your cast.

2.21.5: Lightning Shield pips show only in combat and only while the shield is up (no dark outlines out of combat or with the shield gone). This client shows the shield without a charge count, so charges are now counted: three on casting it, one less each time the game reports a change to the shield's aura (a charge used), hidden when it is removed; a client that does show counts uses those. `/skt totemdebug` reports which it sees.

2.21.4: Lightning Shield charge bars now drop as charges are used in combat: the shield is found by its spell id, each bar is a tiny status bar fed the charge count (the game's bars can show it even while it is hidden from addons), and the count is read from whichever field the client fills (stacks or charges). `/skt totemdebug` prints what the client reports.

2.21.3: Shaman: Lightning Shield charges on the target's nameplate, three short blue bars in the gap between the totem timers and the health bar, one per charge, going dark from the top as charges are used (all dark while the shield is down); shown even with no totems down, can be switched off in the Totem timers part. Widgets tab: a switch to leave your class buff out of the middle (kept per class), for Lightning Shield, which runs out by its charges rather than by time.

2.21.2: buff widgets now clear in combat when you buff someone. The game hides auras from addons in combat, so the panes used to keep what they last knew until combat ended; now they remember each person's buffs and your own casts update them (Mark of the Wild on a party member, Thorns on yourself, Gift of the Wild on everyone). Out of combat the real auras win again.

2.21.1: totem timers show only the totems you have down, laid out by how many: one on the bar's centre line, two either side of it, three as one on the line with one above and one below, four as the chevron (no more dark empty squares).

2.21.0: Shaman class sets: Enhancement, Elemental and Restoration (picked by the talent tree with the most points), each with its own icon slots either side of the level box, and the new totem timers at the bar's left end: Earth, Fire, Water, Air from top to bottom in a chevron (the top and bottom boxes end at the bar's left end, the middle two half a box further out), each the totem you have down with a dark radial countdown; an element with no totem is a dark square, and they hide with no totems down.

2.20.9: the swing strip is pulled in at both ends so its white outline lines up with where the health bar's rounded corners meet its flat top (it used to overhang the bar's ends).

2.20.8: swing timer: the thin white outline now goes round the whole strip (melee and ranged), and the marker is a tall faceted diamond (8 x 18 on the default strip, Media/SwingDiamond.tga) lit from the top left so its centre looks raised; drawn smooth and free of the pixel grid so it glides along.

2.20.7: a very thin (1 px) white outline round the red section of the ranged swing timer, just outside it so the red keeps its height; the pip still passes over it.

2.20.6: the red stand-still section of the ranged swing timer has a gradient: full red at its right edge, darkening towards the left end.

2.20.5: the Hunter crescent's black outline is a little thicker (about 1.6 px on screen), grown outward: it is now drawn below the silver line, so it never covers it (the two were on the same draw level, so the game could draw the black on top).

2.20.4: thinner black outline round the Hunter range crescent on SKTools nameplates (Media/ArcCrescentEdge.tga redrawn at about half the width: roughly 1.2 px on screen at the default size instead of 2.5).

2.20.3: the flight path / vehicle exit button no longer disappears when Action Bar 1 is set to show on mouseover. It sits inside bar 1's frame, so it faded with it; it now ignores the bar's opacity (or, on a client that can't do that, bar 1 stays shown while the button is up).

2.20.2: each buff widget icon sits in its own polished silver frame with slightly rounded corners (Media/BuffFrame.tga), spaced so the frames never touch; the tank shield sits on top of the frame.

2.20.1: fixed dragging the unlocked buff panes: the twice-a-second refresh put a pane back at its saved place mid-drag, so it kept jumping back to the centre. The place is now saved as the pane's centre, so it stays centred where you put it when its size changes.

2.20.0: buff widgets, on a new Widgets tab. Personal buffs: your class buff (Mark of the Wild, Fortitude, Arcane Intellect, a Blessing, Battle Shout...) in the middle, lit while you or anyone in range in your group is missing it, and up to two chosen buffs either side, lit while you are missing them or, for buffs that can go on others like Thorns, while your tank is (a small tank shield on the icon). Missing class buffs: the class buffs your group members could give you that you don't have; hover to see who can cast each. Both show only what is missing, grown out from the centre, and can be unlocked to move and resize. Rebirth moved here from the nameplate icons. `/skt buffdebug` prints what they see.

2.19.6: the right side's skill icons have their own size: drag the white handle on their outer (bottom-right) corner in the Nameplates editor, or use the Icon size slider on the Right icons panel. Until changed it matches the left side; the right big icon grows with it.

2.19.5: fixed a plate layout error from 2.18.5: removing the health value also removed the text size the level number and cast timer use, so setting up each plate stopped partway. Everything laid out after that point was skipped: the swing timer strip, the quest kill/loot counters, the quest-item icon's place and the cast bar's size.

2.19.4: the target plate is found by comparing plate frames (the game's target plate against ours) instead of asking UnitIsUnit, whose answer can be kept secret in combat; that read as "not the target", so in a fight the swing timer, the GCD meter and the target's size and border could all go missing.

2.19.3: removed the combat-log backup for the swing timer: registering for the combat log is a protected action in this client and brought up an "action blocked" warning. The swing timer runs on PLAYER_SWING (read in either order), with Auto Shot as a backup for Hunters.

2.19.2: swing timer fixes. PLAYER_SWING's values are read in either order, or as the swing type alone (the length then comes from your weapon speed); before, any other order than "length, type" was dropped and the timer never moved. Backups if the event never comes: your own white hits and misses in the combat log (where the game lets addons read it) start the melee timer, and Auto Shot going off starts the ranged one. `/skt platesdebug` reports what the swing timer last heard.

2.19.1: fixed elite and rare mobs showing two dragons: the game's own elite marker is now hidden while SKTools' dragon shows, and comes back if you switch ours off. (Built on 2.19.0, so it keeps everything since 2.18.2.)

2.19.0: **Button box.** The box that opens from the bee now holds the bee as one of its buttons: the bee takes the corner of the grid nearest the screen's edge (top right with the minimap top right) and the box opens around it, every button the bee's size (31 px). The bee faces left while the box is open and right again when it shuts. A free-standing (detached) box is as before, sized by its setting.

2.18.5: the health value is gone; the bar shows the percentage only, on its centre line at the right end, one size under the name (10 at the default 11).

2.18.4: in Berry Mode the aggro flash is white: the whole bar flashes bright white and its frame flashes thick white with it, three times (0.15 s up, 0.15 s down), since a red flash does not show on a red bar. Outside Berry Mode the flash is as before.

2.18.3: the health readout (% above, value below) stands either side of the bar's centre line, sized so the two lines keep clear of the bar's border and the white target border (9 on the 28 px bar; never larger than one less than the name).

2.18.2: in Berry Mode, neutral mobs keep their yellow-beige until they turn on someone (in combat, or you on their threat list), then go red; back to beige when they leave combat.

2.18.1: a rare elite shows the gold icon in front of a bigger silver one that frames it (elites: gold; rares: silver).

2.18.0: **Elite dragon by the name.** Elite and rare mobs get the game's elite dragon left of their name, which moves right to make room: gold for elites and bosses, silver for rares and rare elites. Where the game has no such picture, a small winged crest of our own stands in (`Media/EliteGold.tga`, `EliteSilver.tga`). It can be switched off on the Level box panel of the Nameplates tab.

2.17.1: in Berry Mode, a mob someone else has tagged stays grey, as it does outside Berry Mode.

2.17.0: **New defaults and tab order.** Berry Mode leaves enemy players in their class colour (only NPCs turn red). Every skill icon slot in every class set starts empty: choose them in the Nameplates editor. Settings saved before this keep the icons they showed (written down once, on the first login). The mouseover action bars start with every bar unticked as well as the switch off. The Druid energy bar on the Personal Resource Bars tab starts off. Tabs now run: Button Box, Nameplates, Action Bar, Personal Resource Bars, Profession DB, Profiles.

2.16.1: the XP bar and status bar 2 (reputation, honor...) join the mouseover list on the Action Bar tab, each with its own tick box. (The status bar width sliders tried briefly are gone.)

2.15.0: **Action bars on mouseover.** On the Action Bar tab: a switch that hides your action bars until you hover over them, and a tick box per bar (Action Bars 1-8, stance bar, pet bar) to choose which ones. A bar fades in while the mouse is over it and stays a moment after, so you can move between bars. All bars show while you drag a spell or item, in Edit Mode, and while a spell flyout is open. Only the bars' opacity changes, so buttons and key bindings keep working while faded, in combat too. Blizzard's own bars only.

2.14.3: the level number is back to its 2.14.0 look (plain outlined, normal size, no white ring), in colours a little brighter than the game's: red 1/0.2/0.2, orange 1/0.58/0.3, yellow 1/0.9/0.15, green 0.35/0.88/0.35, white for no experience.

2.14.2: the white ring round the level number is half a pixel wide (was one).

2.14.1: the level number is bigger (about half the box's height), in brighter colours, with a thin white ring inside its black border (layered copies of the number, as the game only draws black outlines). The GCD meter no longer depends on the game's "global cooldown" spell: if that gives no answer, it reads the cooldown of the spell you just cast, and failing that guesses (1 s for energy users, else 1.5 s shortened by haste). `/skt platesdebug` says where the GCD came from.

2.14.0: **Level box.** The crossed swords are gone and the level number is centred. It is coloured the way the game does it, by how far the mob is from your level: red 5 or more above you (and ??), orange 3-4 above, yellow within 2, green lower while it still gives experience, and white once it gives none (where the game shows grey). **GCD meter:** while your global cooldown runs, a white line rises through your target's level box from the bottom to the top, with soft steam trailing under it (two drifting layers, `Media/GcdSteam1.tga` and `GcdSteam2.tga`), hidden between GCDs. When the game keeps cooldown numbers from addons in combat, its own timer drives the line. Both can be switched off on the Level box panel of the Nameplates tab; `/skt platesdebug` reports the meter.

2.13.2: Rebirth in an icon slot only lights while someone in your party or raid lies dead (not a released ghost) and you carry its seed (the Classic seed for your rank; for a rank Forever numbers differently, the game's own usable check decides). `/skt icondebug` says who is dead and how many seeds you have.

2.13.1: the skill list now opens above the sample (it was drawn behind it), and a click that twitches a pixel or two still counts as a click; it takes 3 px of movement to start a drag.

2.13.0: **Choose your skill icons.** Each class set (Cat Form, Bear Form, Hunter) now has three stacked icons and a big one on each side of the plate: left of the combo points or crescent as before, and a mirror image to the right of the level box (skills only). In the Nameplates editor, click any icon on the sample to pick its skill from your spell book, or empty it; each set keeps its own choices. On the plates, two filled slots sit where the two-icon stack always did and one sits on the centre line; in the editor every slot is shown and the big icons stand beside their stacks. The defaults are the old layout (Claw / Shred / Bite; Maul / Swipe / Primal Bite; Raptor Strike / Mongoose Bite), with the right side empty. A chosen skill lights when it is usable, in range and off cooldown. The quest-item icon moved above the bar's right end, its bottom level with the debuff row.

2.12.2: a plate that appears shows our bar on its first frame. It used to wait up to half a second for the plate's size to settle, and the game removes and re-adds a plate each time a mob crosses the edge of the screen; on a moving mob that wait ran in full every time, so the bar lagged behind (Questie's icon on the same plate showed at once).

2.12.1: `/skt platelist` lists every nameplate the game has right now (ours or not), what is showing on each, including other addons' frames such as Questie's icon, and the last ten plates added or removed.

2.12.0: **Late nameplates.** An enemy whose plate appeared before the game knew it was hostile (often the first time you meet a mob in an area) was left without our bar until something else woke it, typically action targeting picking it. Plates are now looked at again five times a second and on every soft-target change, and one picked up late shows at once. Setting up a new bar can no longer stop halfway and leave it unshown. `/skt platesdebug` reports how many plates were picked up late and any setup step that failed.

2.11.2: Primal Bite's icon is looked up by its spell id (407995) before it is learned, and its stand-in is the Cannibalize icon the wiki lists for it, so the sample no longer shows Ferocious Bite.

2.11.1: the editor's sample shows each skill's real icon from the game (so Primal Bite is no longer the old Mangle icon). The stand-in used before the skill is learned is now the Ferocious Bite icon.

2.11.0: **Class and subclass drop-downs in the Nameplates editor.** The drop-down beside the top strip now lists classes only (My class, Druid, Rogue, Hunter). A second drop-down in the top left corner of the sample plate picks the subclass: for a Druid, Cat Form or Bear Form, so the sample can show Maul, Swipe and the Primal Bite icon. It only appears for a class with more than one set. Saves from before (which held a set's name) still work.

2.10.0: **Druid Bear Form.** The ready icons become Maul (bottom) and Swipe (top), with Primal Bite as the big icon laid over both, like Bite in Cat Form, shown when it is usable, in range and off cooldown. The combo arc counts Growl's 8 s cooldown: all five red dots while it is ready, the top one goes at 7 s left and one more each second, none from 3 s; during the last three seconds the inner three dots carry a small white dot each, counting 3, 2, 1. Driven by the game's own cooldown timer through step curves, so it works while cooldown numbers are hidden in combat. Role detection scaffold (`ns.ClassSets.Role()`): most talent points in Restoration or Balance, or any in Thick Hide, mark the other Druid roles; their sets are still to come, and the Feral set stands in for them meanwhile.

2.9.0: new defaults taken from a tuned setup: plates at 80%, dark swing strip at 80% opacity, crescent 34 px nudged 3 left, ready icons 19 px (not matched to the level box) with a 2 px gap, combo points 4 px left, quest-starter icon 46 px on Blizzard plates, button box 3 per row. Existing saved settings are untouched; Reset buttons land on these.

2.8.0: the ready icons are per class. Druid in Cat Form: Claw (bottom) and Shred (top), with the Bite/Shifting Power finisher. Hunter: Raptor Strike (bottom) and Mongoose Bite (top), left of the range crescent; an icon shows when the game says the skill is usable, the target is in its range and it is off cooldown. Other classes are added in `STACKS` in `Modules/Nameplate/Feral.lua`.

2.7.0: **swing timer** on your target's plate: a thin strip above the health bar (bar width only, under the debuffs) with a pip that travels with each swing. Melee runs left to right; ranged runs right to left, with the last 0.5 s in red at the left end. Driven by WoW Forever's own `PLAYER_SWING` event. Settings: click the strip on the sample plate.

2.6.0: the Nameplate and Plates tabs are one tab, **Nameplates**, built around a sample plate. Click a part (health bar, level box, cast bar, debuffs, quest marks, combo points, Claw/Shred icons, Bite icon, range crescent) to see only that part's settings. Drag a part to move it; drag the white square on its corner to resize it. The **Class set** drop-down picks which class's extras are on the sample: Druid (Feral), Rogue or Hunter. In the game each character shows its own class's set. New sets are added with `ns.ClassSets.Register` in `Modules/Nameplate/Designer.lua`. **Berry Mode** (2.5.0) makes every enemy bar red; the aggro flash still plays.

2.4.1: two plate sizes, normal and your target (120%, white frame). Plates that are neither your target nor the action-targeting (soft) target are 70% opaque (Other plates opacity); the soft target is solid.

2.3.0: plates default to 50% overall size, and the level box reaches back under the bar so the bar sits on top of it (the white target frame is on the bar only; the box grows with the bar when you target).

2.2.0: plates are drawn at 75% overall (Overall size slider), the level box joins the bar, neutral enemies are a soft yellow-beige, and combo points appear when combat starts (Only in combat, in the Combo options).

Plates, the red aggro bar, the debuff row and the combo/crescent/feral overlays on plates only apply to enemies. Friendly players and NPCs keep Blizzard's plate (2.1.1).

Aggro and debuffs (2.1.0):
- The bar turns red while the mob has you as its target, and flashes three times when it gets on you.
- Your own debuffs sit above the bar, left-aligned. They blink during their last three seconds; auras with no end never blink.
- Blizzard's crowd-control icon sits over the right end of the cast bar, whether or not the mob is casting. Blizzard's own buff and debuff rows are hidden (switchable).

