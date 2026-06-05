# AutoMagFeeder + Magatama — Complete Guide

AutoMagFeeder is a PSOBB addon that **feeds your Mag automatically** by replaying menu
keystrokes through the in-game feed menu, following a **plan** that you design in the
**Magatama** desktop app. The two tools are a matched pair:

```
  ┌─────────────────────┐   exports    ┌──────────────────┐   loads &     ┌──────────────────┐
  │  Magatama (desktop)  │ ──.mag──►    │  plan .lua file   │ ── executes ──►│  AutoMagFeeder    │
  │  plan / calculator   │  convert     │ (in addon folder) │   in-game     │  (PSOBB addon)    │
  └─────────────────────┘              └──────────────────┘               └──────────────────┘
        you design here                  the shared contract                  it feeds here
```

* **Magatama** is the *brain*: it knows every Mag's feeding table, evolution rules, and
  section/class requirements, and computes the exact ordered list of items to feed to reach a
  target build.
* **AutoMagFeeder** is the *hands*: it reads your live inventory/Mag from game memory, figures
  out where in the plan your Mag currently is, and presses the menu keys to feed — while
  watching for danger and for you taking back control.

This document covers **both tools, how to use them together, and a thorough reference for every
function in `init.lua`**. It ends with a **"Known issues / track in this version"** section.

> ⚠️ This addon synthesizes keyboard input into an online game. Use it only on servers where
> automation is permitted. You are responsible for how you use it.

---

## Table of contents

1. [The Magatama release](#1-the-magatama-release)
2. [The plan file format (the contract between the two tools)](#2-the-plan-file-format)
3. [The AutoMagFeeder addon folder](#3-the-automagfeeder-addon-folder)
4. [End-to-end workflow: using both together](#4-end-to-end-workflow)
5. [The control window, button by button](#5-the-control-window)
6. [`options.lua` settings reference](#6-optionslua-settings-reference)
7. [Full function reference (`init.lua`)](#7-full-function-reference)
8. [`execute_feeder_tick()` — the main loop, step by step](#8-execute_feeder_tick-the-main-loop)
9. [Safety system](#9-safety-system)
10. [Known issues / things to track in this version](#10-known-issues--things-to-track-in-this-version)

---

## 1. The Magatama release

`Magatama_Release.zip` (at the repo root) is a standalone **Windows .NET (4.8) application** —
version **"βeta 9"** — for planning Mag builds. It ships two executables and a large `Data/`
tree.

> **Credit & lineage.** Magatama is the work of **Aether89**
> ([github.com/Aether89/Magatama](https://github.com/Aether89/Magatama)), itself a spiritual
> successor to *Mag Farm* by **James Baxter**. The build paired with AutoMagFeeder is a **fork**
> whose one functional addition is the **"Export AutoMag Plan"** command — a single VB.NET method
> (`ExportOutput()` in `Magatama/Magatama/frmMagatama.vb`) that writes the `plan.lua` this addon
> reads. Everything else is upstream Magatama. Magatama is Unlicense / public domain.

### 1.1 What's in the zip

| Path | What it is |
|------|-----------|
| `Magatama.exe` | The planner/calculator/simulator UI. You design a build here and it exports the feeding plan. |
| `MagDex.exe` | The companion **Mag database editor** (browse/edit Mag entries, evolution trees, photon blasts, art). |
| `*.exe.config` | .NET runtime + user-settings config (targets .NET Framework 4.8). |
| `Data/Init.xml` | Global defaults: game version, default Section ID, feeding time (210s), item costs, starting Mag stats (`DEF 5`). |
| `Data/FeedingTables/ep1/Table_*.xml`, `ep2/Table_*.xml` | **The feeding tables.** Per-Mag, per-item stat gains (`Sync`, `IQ`, `DEF`, `POW`, `DEX`, `MIND`). This is the core data that makes a plan correct for a given Mag. |
| `Data/Evolution/*.xml` | Evolution rules (which Mag a feed path evolves into, per class group HU/RA/FO and stage), plus Mag-cell error/exclusion tables. |
| `Data/Mag/*.xml`, `Data/MagDex/` | Per-Mag metadata used by the dex. |
| `Data/List/Class.xml` | Magatama's class list (note: this is Magatama's *internal* indexing, **not** the in-game class ID — see §2.3). |
| `Data/List/SectionID.xml` | The 10 Section IDs, `Viridia`(0) … `Whitill`(9). Matches the addon's `SECTION_IDS` table exactly. |
| `Data/List/MagCells.xml` | The Mag-cell catalog (Cell of MAG 213, Heart of Chao, … Yahoo! Engine). Mirrors the addon's `ITEM_NAME_TO_ID` cell aliases. |
| `Data/List/PhotonBlast.xml`, `Data/PhotonBlast.xml` | Photon Blast definitions. |
| `Data/Theme.xml`, `Graphics/` | The desktop app's own skin/art (unrelated to the in-game HUD theme). |

### 1.2 Running Magatama

1. Unzip `Magatama_Release.zip` anywhere. It is fully self-contained but **`Data/` and
   `Graphics/` must stay next to `Magatama.exe`** (paths are resolved relatively). It needs .NET
   Framework 4.8, present on modern Windows.
2. Run **`Magatama.exe`** to plan, or **`MagDex.exe`** to browse/edit the Mag database.
3. Pick your **game version** (Ep1 / Ep2 / Ep4 — selects which `FeedingTables` set is used),
   your **class**, **Section ID**, **starting Mag**, and design the feeds on the simulator grid
   (Monomate … Star Atomizer). To evolve via a **Mag cell** (Liberta Kit, Heart of Chao, …), feed
   the cell in the simulator — the planner records it as a cell-usage event.
4. Magatama walks the feeding tables and evolution rules and produces an **ordered feeding
   plan**: for each stage, *which item, how many times, on which class + Section ID*.

### 1.3 Exporting the plan to the addon

The fork adds **File → Export → "Export AutoMag Plan"** (or **`Ctrl+E`**). It writes a
**`plan.lua`** file (this is the `ExportOutput()` method in `frmMagatama.vb`). Save it, then move
`plan.lua` into your game's **`<PSOBB>/addons/AutoMagFeeder/`** directory. You can rename it —
the addon lists every `.lua` in that folder.

> `plan.lua` is the seam between the two programs. As long as a `.lua` plan matches the schema in
> §2 and its `feed_value`s match the Mag's real feeding table, the addon can execute it.
>
> *(The four bundled example plans predate this exporter — their headers say "Auto-converted from
> LEGACY plan `…​.mag`", Magatama's older native save format. They follow the same schema, minus
> the per-step `mag_name` that the βeta-9 exporter now emits.)*

### 1.4 The four bundled example plans

All four are FOmar→RAmar builds that stop at **level 99**, one feed short of the rare 4th
evolution (the trailing `1mf`/`1ad` tag = the single **M**ono**f**luid / **A**nti**d**ote that
triggers it). File naming: `<RareMag>-<Focus>-<SectionSet>-<evoFeed>.lua`.

| Plan file | Rare mag | Final DEF/POW/DEX/MIND | Evolution Section IDs |
|---|---|---|---|
| `Kama-MIND-VBRW-1mf.lua` | Kama | 5.00 / 0.00 / 45.00 / 49.90 | Viridia, Bluefull, Redria, Whitill |
| `Kama-MIND-GPuO-1mf.lua` | Kama | 5.00 / 0.00 / 50.00 / 44.90 | Greenill, Purplenum, Oran |
| `Bhirava-POW-SPiY-1ad.lua` | Bhirava | 5.00 / 45.00 / 49.84 / 0.00 | Skyly, Pinkal, Yellowboze |
| `Kama-POW-VBRW-1ad.lua` | Kama | 5.00 / 50.00 / 44.88 / 0.00 | Viridia, Bluefull, Redria, Whitill |

---

## 2. The plan file format

A plan is a Lua file that **returns one table**. Schema:

```lua
return {
    target_mag = "Kama",            -- display name of the final/target Mag
    sequence = {                    -- ordered list of steps; the addon executes them in order
        {
            step        = 1,                 -- step number (informational)
            class_name  = "FOmar",           -- class you must be on for this step
            class_id    = 10,                 -- in-game class id (re-derived at load — see §2.3)
            section_id  = "Redria",           -- Section ID name you must be on for this step
            item_id     = "0x030100",         -- flat item hex (re-derived at load — see §2.3)
            item        = "Monofluid",        -- item name; THIS is the source of truth at load
            count       = 15,                 -- how many of this item to feed in this step
            start_state = { level = 5, def = 5.00, pow = 0.00, dex = 0.00, mind = 0.00 },
            feed_value  = { def = 0, pow = 0, dex = 0, mind = 33 }, -- stat gain ×100 per feed
        },
        -- … more steps …
    }
}
```

### 2.1 Field meanings

* **`target_mag`** — shown in status messages; also used as the plan's identity.
* **`step.item`** — the consumable to feed (`Monomate`, `Difluid`, `Sol Atomizer`, `Antidote`,
  …). At load this name is looked up in `ITEM_NAME_TO_ID` to get the authoritative `item_id`.
* **`step.count`** — number of feeds for this step.
* **`step.class_name` / `step.section_id`** — the character identity required for this step.
  The addon refuses to run a step unless your live class **and** Section ID match, so a single
  plan can require you to switch characters mid-build (the example plans switch FOmar→RAmar).
* **`start_state`** — the Mag's stats *at the beginning of this step*. `feed_value` is the stat
  change **per single feed, ×100** (so `mind = 33` means +0.33 MIND each Monofluid for that
  Mag). Together these let the addon compute how far into a step a partially-fed Mag already is
  (see `calculate_plan_resume_point`, §7).
* **`step.is_mag_cell`** — emitted as `true` when the step's item is a Mag cell (the addon also
  detects cells by hex). The addon cannot use a cell via the feed menu, so it pauses and asks you
  to use the cell manually, then advances. (Absent on non-cell steps.)
* **`step.mag_name`** — the expected Mag name at this step. The βeta-9 exporter writes it on
  **every** step; the addon uses it to disambiguate progress after a cell evolution (cells change
  the name but not the stats). The bundled legacy-converted plans omit it, which is fine — the
  addon treats it as optional.

### 2.2 `feed_value` must match the Mag's real feeding table

The resume math divides your Mag's measured stat gains by `feed_value` to count feeds. If a
plan's `feed_value`s don't match the Mag's actual feeding table (the `Data/FeedingTables` data
in Magatama), the addon will mis-count and refuse to sync ("Mag stats do not match this plan").
**Always generate plans in Magatama for the correct episode/Mag** so the embedded `feed_value`s
are right.

### 2.3 `item_id` and `class_id` are re-derived at load (don't hand-trust them)

`load_feeder_plan` overwrites each step's `item_id` from `ITEM_NAME_TO_ID[step.item]` and each
`class_id` from solylib's `Classes[step.class_name]`. This is deliberate: the bundled plans
carry *legacy* values (e.g. Antidote stored as `0x030900`, RAmar as `3` under Magatama's
indexing) that wouldn't match game memory. The **names** (`item`, `class_name`, `section_id`)
are the real contract; the numeric IDs are advisory and get corrected. If you write plans by
hand, get the **names** right and the addon will resolve the rest.

---

## 3. The AutoMagFeeder addon folder

### 3.1 Installation

1. Install the base [psobbaddonplugin](https://github.com/Solybum/psobbaddonplugin).
2. Copy the **`AutoMagFeeder`** folder into your PSOBB `addons/` directory.
3. Ensure **`solylib`** and the **core addons** (`core_mainmenu`, `core_addonlist`) are present —
   they ship in the same addon pack and AutoMagFeeder depends on them.
4. Launch PSOBB. A **"AutoMag Feeder"** button appears in the addon main menu; click it to open
   the control window.

### 3.2 Files in the folder

| File | Role |
|------|------|
| `init.lua` | The entire addon. Loads plans, reads memory, runs the feed engine, draws the UI. |
| `options.lua` | Persisted settings (window position, toggles, selected plan). Auto-written; **gitignored** by the addon pack, so it is per-user and not shipped. |
| `*.lua` (other) | Feeding plans (see §2). The plan dropdown lists every `.lua` here except `init`/`configuration`/`options`. |
| `README.md` | This document. |

### 3.3 Dependencies it loads

```
core_mainmenu          -- adds the main-menu button
solylib.helpers        -- NotNilOrDefault, window position/track helpers
solylib.items.items    -- GetInventory (live inventory + parsed item.data/.mag/.equipped/.id)
solylib.characters     -- GetSelf, GetCurrentFloorSelf, GetPlayerClass/SectionID, Classes
solylib.items.items_list -- item id→name table
ffi                    -- native Windows keyboard + window-focus calls
imgui                  -- host-injected global UI table (captured as a local; not require()d)
```

All of these exist in the bundled `solylib`/core addons; the addon makes **no global writes**
and defines its FFI symbols nowhere else in the pack, so it cannot collide with sibling addons.

---

## 4. End-to-end workflow

1. **Plan in Magatama.** Choose episode, target Mag, Section ID(s)/class(es), and final stats.
   Export/convert the plan to a `.lua` file.
2. **Drop the `.lua` into `addons/AutoMagFeeder/`.**
3. **In game**, open **AutoMag Feeder** from the main menu.
4. **Select Plan** from the dropdown (hit **Refresh Folder** if you just added it).
5. **Select Mag** from the dropdown (hit **Refresh Mags** after inventory changes). The choice
   is remembered by the Mag's stable item id, so it survives inventory reordering.
6. Be on the **class + Section ID the current step requires**, with the **food items in your
   inventory**.
7. Click **Load Selected Plan.** The addon finds your resume point and reports
   *"Synced! Resuming '<mag>' at Step N …"*. If your Mag's stats don't fit the plan, it tells you.
8. Click **Start.** It feeds in batches of up to 3, waits out the digest timer, and progresses
   through the plan. It auto-pauses for danger, lost focus, lobbies, and your own keypresses.
9. When a step is a **Mag cell**, it pauses and asks you to use the cell manually, then continues.
10. At the end: *"Finished: Entire Mag feeding plan execution successful!"*

---

## 5. The control window

Open via the **AutoMag Feeder** main-menu button. The window has two modes.

### Always visible (both modes)
* **Status line** — current state, color-coded. Shows `[RUNNING]`, shortages (orange), combat
  pause (red), or the normal status message (blue).
* **Start / Pause** — `Start` is disabled until a plan is loaded. `Pause` halts the loop.
* **Minimize / Maximize** — `Minimize` shrinks to a compact status+Start/Pause bar
  (auto-resizes); `Maximize` restores the full window.

### Full mode only
* **Select Plan** (dropdown) + **Refresh Folder** — pick a plan; refresh re-scans the folder.
  Selecting a plan saves it to `options.plan_file_path`.
* **Select Mag** (dropdown) + **Refresh Mags** — pick which Mag in your inventory to feed,
  shown as `Name  Lv##  def/pow/dex/mind  [Equipped]`. Refresh re-reads inventory.
* **Load Selected Plan** — validates and syncs the plan to the selected Mag (see
  `load_feeder_plan`).
* **Reset Progress** — rewinds the in-memory timeline to step 1 (does not change your Mag).
* **Diagnostics Log** — the live, timestamped last-50 log lines.

Closing the window with the `[X]` just hides it (sets `show_toolbox=false`); reopen from the
main-menu button. The window is **freely draggable and resizable**: it opens at the saved
`x`/`y`/`w`/`h` (via `SetNextWindowPos`/`SetNextWindowSize` with `FirstUseEver`) and then stays
wherever you move/size it, exactly like Monster Reader and the other overlays in this setup.

---

## 6. `options.lua` settings reference

`options.lua` is loaded with `pcall(require, ...)` and each field is defaulted via
`lib_helpers.NotNilOrDefault`, so a missing or partial file is safe. `SaveOptions` rewrites it
whenever a setting changes (e.g. plan selection, or closing the window with `[X]`).

| Option | Default | Effect |
|--------|---------|--------|
| `enable` | `true` | Present in options for parity with sibling addons; the engine itself runs whenever the addon is loaded. |
| `enable_safety_checks` | `true` | Master switch for the **enemy-proximity** guard (`check_proximity_threats`). |
| `lock_inputs` | `true` | Enables the "**you pressed a key → pause**" guard (`get_interrupt_key`). |
| `show_toolbox` | `false` | Whether the control window is drawn. Toggled by the menu button and the window `[X]`. |
| `plan_file_path` | `""` | Path of the plan the dropdown loads. |
| `x`,`y` | 100 / 100 | Spawn position used on the window's first appearance. Drag freely after that. |
| `w`,`h` | 480 / 400 | Spawn size, applied on first open and after **Maximize**. Resize freely after that. |
| `anchor` | 1 | Unused by the window code (kept for option-file compatibility). This host's imgui binding rejects named `SetWindowPos`/`SetWindowSize`, so the window uses the plain `SetNextWindow*` calls instead of anchor docking. |
| `resolutionW`,`resolutionH` | 0 / 0 | Last-seen screen resolution (informational). |
| `max_safety_distance` | 100 | Enemy distance threshold (units²-compared) for the proximity guard. Read at runtime; add it to `options.lua` to tune. |

---

## 7. Full function reference

Every function in `init.lua`, in file order. The addon is a single file; these are all locals
except the framework entry point.

### Constants & lookup tables (top of file)
* **`ITEM_NAME_TO_ID`** — maps item/Mag-cell **names** (and common misspellings/aliases) to flat
  PSOBB hex ids. Used to re-derive `step.item_id` at load and to recognize Mag cells.
* **`ffi.cdef[[…]]`** — declares the native Windows calls: `keybd_event` (synthesize keys),
  `MapVirtualKeyA` (VK→scan code), `GetForegroundWindow` / `GetWindowThreadProcessId` /
  `GetCurrentProcessId` (focus check), `GetAsyncKeyState` (read live key state). These symbols are
  defined **only here** in the whole pack.
* **Timing**: `KEY_PRESS_HOLD_MS = 100` (key held before release), `KEY_DELAY_MS = 400` (gap
  between presses).
* **Virtual keys**: `VK_RETURN/UP/DOWN/ESCAPE/F4/F12`; flags `KEYEVENTF_KEYUP`,
  `KEYEVENTF_EXTENDEDKEY` (arrows need the extended flag). `EXTENDED_KEYS`, `KEY_NAMES` support
  these.
* **`SECTION_IDS`** — Section-ID number (0–9) → name; matches Magatama's `SectionID.xml`.
* **Memory offsets** (`_EntityCount`, `_PlayerCount`, `_Ent_*`, `_ephineaMonsterArrayPointer`,
  `_entity_array_base`) — used by the proximity scanner. **These are client-specific (Ephinea)
  addresses** — see §10.

### Logging
* **`debug_log(msg)`** — timestamps `msg`, prepends it to `debug_logs` (kept to the last 50, shown
  in the UI), and also `print`s `[AutoMagFeeder] …`.

### Hardware input
* **`key_down(vk)`** — maps `vk` to a scan code via `MapVirtualKeyA`, adds the extended flag for
  arrows, calls `keybd_event` to press the key, and logs it.
* **`key_up(vk)`** — same, with the KEYUP flag, to release the key.
* **`nav_presses(offset, count)`** — returns the **shortest** list of `VK_DOWN`/`VK_UP` presses to
  move a wrapping menu cursor from the top to a 0-based `offset` in a list of `count` items (going
  up wraps from top to bottom). This minimizes keystrokes for long inventories.

### Environment / focus
* **`is_game_window_active()`** — true only when the foreground window's process id equals this
  PSOBB instance's PID. Prevents keystrokes leaking to other apps / other game windows.
* **`get_safe_character()`** — returns the local character address, or `nil` if not logged in.
* **`is_in_game_instance()`** — true only when logged in **and** not in a visual lobby (floor 15)
  or main menu (`0xFFFFFFFF`). Pioneer 2 (floor 0) counts as in-game.

### Options
* **options load block** — `pcall(require, "AutoMagFeeder.options")`, then `NotNilOrDefault` for
  every field (or a full default table if the file is absent).
* **`SaveOptions(opts)`** — rewrites `options.lua` with the current settings/geometry.

### Plan & Mag discovery
* **`scan_plan_directory()`** — runs `dir "addons\AutoMagFeeder\*.lua" /b` via `io.popen`, lists
  every `.lua` except `init`/`configuration`/`options`, and selects the entry matching
  `plan_file_path`. (Windows-specific — see §10.)
* **`mag_info(item, mag_idx)`** — builds a parsed table for one Mag inventory item: `id`, `name`,
  `level`, `def/pow/dex/mind`, `timer`, `mag_index` (0-based position among Mags, used as the menu
  nav offset), `slot`, `equipped`.
* **`get_selected_mag()`** — returns the Mag the user picked, found by **stable item id**
  (`selected_mag_id`). Falls back to the equipped Mag, the combo index, or the first Mag if the
  selection is gone. This is what survives inventory reordering.
* **`scan_mags()`** — rebuilds the **Select Mag** dropdown from live inventory (Mags are item type
  `0x02`), keeping the current selection if it still exists, else defaulting to the equipped (or
  first) Mag.

### Inventory reading
* **`item_matches_hex(item, hex_str)`** — compares an item's first three data bytes to a flat hex
  like `"0x030000"`.
* **`has_item_in_inventory(hex_str)`** — true if any inventory item matches that hex. Used for Mag
  cell presence checks.
* **`is_feedable_item(item)`** — true only for consumables that actually appear in the Mag-feed
  submenu: Mates (Mono/Di/Tri), Fluids (Mono/Di/Tri), Sol/Moon/Star Atomizers, Antidote,
  Antiparalysis. The menu offset math depends on this filter matching the game's submenu contents.
* **`calculate_ui_offsets(target_hex_str)`** — the menu-navigation brain. From live inventory it
  returns four values: `mag_offset, mag_count` (selected Mag's 0-based position among Mags + total
  Mags) and `food_offset, food_count` (target food's 0-based position among **feedable** items +
  total feedable). Offsets are `nil` if not found (→ shortage). It resolves the Mag via
  `get_selected_mag` and falls back to the combo index / first Mag if needed. (Note: 0 is a valid
  offset, so callers guard with `nil`, not truthiness.)

### Plan math & tracking
* **`calculate_plan_resume_point(mag, plan_data)`** — given the Mag's current stats, walks the plan
  and computes `(step_index, items_remaining)` — i.e. *where a partially-fed Mag actually is*. It:
  enforces tight tolerance on stats that are never touched by the plan; for each step checks that
  inactive stats (and optional `mag_name`) still match the step's start; counts feeds from each
  active stat's gain (`(now − start) × 100 / feed_value`) and requires the active stats to **agree**
  (within ~2 feeds) before trusting the count; and, if no active step matches, checks whether the
  Mag equals the plan's fully-completed final state. Returns `nil` if nothing matches (the
  "stats don't fit this plan" case).
* **`track_plan_state()`** — runs each frame to keep `active_feeder_state` consistent: tops up
  `items_remaining_in_step` from the step `count`, detects completion (`idx > #sequence`), flags
  shortages (missing food, or selected Mag not found — using `has_item_in_inventory` for cell steps
  and `calculate_ui_offsets` for normal steps), and updates the running status string.
* **`load_feeder_plan(filepath)`** — loads and validates a plan: `dofile` it and confirm it returns
  a table with `target_mag` + `sequence`; **re-derive** each step's `item_id` (from
  `ITEM_NAME_TO_ID`, with a few legacy spelling fixes) and `class_id` (from `lib_characters.Classes`);
  confirm a Mag is selected; call `calculate_plan_resume_point` (bail if stats don't fit or it's
  already done); confirm your live **class** and **Section ID** match the resume step; then store the
  plan, set the resume step/count, and report *"Synced! Resuming …"*.

### Interrupt detection
* **`INTERRUPT_IGNORE`** — the keys the macro itself drives (Enter, Up, Down, Esc, F4, F12) plus
  mouse buttons, which must **not** count as you taking over.
* **`get_interrupt_key()`** — scans VK `0x08`–`0xFE` via `GetAsyncKeyState`; returns the first
  pressed key that isn't in `INTERRUPT_IGNORE`, or `nil`. A non-nil result means *you* pressed
  something and the feeder should yield.

### The core loop & UI
* **`execute_feeder_tick()`** — the heart of the addon; see §8.
* **`present()`** — the per-frame framework callback. It **always runs `execute_feeder_tick()`
  first** (so feeding works even with the window hidden), then, if `show_toolbox`, draws the
  control window (§5), applying the saved position/size and handling the `[X]`/compact-mode logic.
* **`init()`** — registers the **"AutoMag Feeder"** main-menu button (which toggles
  `show_toolbox`) and returns the addon metadata (`name`, `version`, `author`, `description`,
  `present`). The file returns `{ __addon = { init = init } }`, the framework entry point. **Note:
  this framework has no `pso.on_tick`; the engine is driven from `present()`.**

---

## 8. `execute_feeder_tick()` — the main loop

Runs every frame from `present()`. In order:

1. **Get character & time.** Bail if not logged in. Read `current_time = pso.get_tick_count()`.
2. **Track plan state** (`track_plan_state`) so shortages/step counts stay live even while paused.
3. **Cycle / timer bookkeeping.** Reset the per-cycle feed counter when the Mag's digest timer is
   (near) expired and we're idle.
4. **Auto-sync from memory.** When idle and out of cooldown, re-run `calculate_plan_resume_point`
   and silently adjust the current step/count to match reality — this absorbs manual feeds and
   recovers from desyncs (or suspends with a clear message if the Mag no longer fits the plan).
5. **Master safety / pause overrides** → abort if PSOBB isn't the active window, you're in a
   lobby/menu, or the loop isn't running. On abort, any held key is released and the macro queue is
   cleared.
6. **Your-keypress gate** (when `lock_inputs`): if you press a non-macro key (or the Mag timer is
   about to fire), the feed pauses for ~5s of input-idle before resuming, aborting any in-flight
   macro.
7. **Proximity gate** (when `enable_safety_checks`): if a living enemy is within range, pause and
   abort the macro until the area clears.
8. **Macro state machine** (when a macro is in flight): **Phase A** releases a held key after
   `KEY_PRESS_HOLD_MS`; **Phase B** presses the next queued key after `KEY_DELAY_MS`, decrementing
   `items_remaining_in_step` on feed keystrokes, and on queue-empty schedules a 5s cooldown and
   advances the step if it's done.
9. **Plan guard / cooldown / digest.** Do nothing without a loaded plan, during the post-feed
   cooldown, or while the Mag's `timer > 2.0` (still digesting).
10. **Mag-cell step** → pause, prompt you to use the cell manually, advance the step.
11. **Build the macro queue.** Get offsets via `calculate_ui_offsets`; feed up to
    `min(3 − cycle_feeds, items_remaining)` items. Each feed is a **self-contained open→feed→close
    cycle** so menus never get stuck:

    ```
    F12, ESC                         (guarantee all menus closed)
    repeat per feed:
      F4                             (open Mag menu)
      nav → selected Mag             (shortest Up/Down)
      ENTER                          (select Mag)
      ENTER                          (choose "feed")
      nav → target food             (shortest Up/Down among feedable items)
      ENTER                          (feed — counts as a feed)
      F4                             (close, clearing all menus)
    ```

---

## 9. Safety system

AutoMagFeeder will **stop feeding** (and drop any held key / clear the queue) whenever:

* **PSOBB is not the foreground window** — keys never leak to other apps.
* **You're in a lobby or main menu** — only Pioneer 2 / quest floors feed.
* **You press a key** (with `lock_inputs` on) — instant yield, ~5s input-idle before resuming.
* **An enemy is within `max_safety_distance`** (with `enable_safety_checks` on) — combat pause.
* **The Mag is still digesting** (`timer > 2.0`) or within the 5s post-feed cooldown.

It also paces itself: **batches of ≤3 feeds**, then waits out the digest timer + cooldown so the
server's Mag timer is fresh before the next read — rather than spamming the menu.

---

## 10. Known issues / things to track in this version

> Version reported by the addon: **`0.1.0.b`** (beta). The items below are foreseeable risks worth
> tracking before/towards a stable release. None are blocking for Ephinea use, but each is a place
> the addon could misbehave on a different client, server, or config.

**Resolved in this version**

- **Control window now opens and is draggable/resizable.** The original code positioned the window
  with `solylib.PrepareWindowPositionAndSize` / `TrackWindowPosition` (which don't exist in this
  bundle's solylib) and, after a first pass, `WindowPositionAndSize` (which calls the *named*
  `imgui.SetWindowPos`/`SetWindowSize`). **This host's imgui binding registers the named overloads as
  `SetWindowPos_2`/`SetWindowSize_2`; the plain names are the no-arg-name overloads that run
  `luaL_checknumber` on their first argument — so passing a window-name string throws, and
  `psointernal` then disables the addon (no window).** The window now uses only the plain-number
  `SetNextWindowPos`/`SetNextWindowSize` (`FirstUseEver`), like the core/Monster/Player addons.
  ⚠️ **Do not reintroduce `WindowPositionAndSize` or named `SetWindow*` calls in this setup.**
- **A tick error can no longer kill the UI.** `execute_feeder_tick()` is wrapped in `pcall`; an
  unexpected memory read is logged and feeding pauses that frame instead of disabling the addon.

**Open items to track**

1. **Hardcoded, client-specific memory addresses for the proximity guard.** The enemy scan uses
   fixed Ephinea offsets (`_EntityCount=0x00AAE164`, `_PlayerCount=0x00AAE168`,
   `_ephineaMonsterArrayPointer=0x00B5F800`, base from `0x7B4BA0+2`). On a different PSOBB build
   these are wrong, so the proximity check could silently read garbage or always return "clear" —
   i.e. feed while enemies are present. *Track:* gate this behind a known-client check, or source the
   addresses from solylib/Monster Reader rather than literals.

2. **`scan_plan_directory()` depends on `io.popen('dir …')`.** This is Windows-only, can briefly
   flash a console, and fails outright if `io.popen` is unavailable/sandboxed → empty plan list.
   *Track:* replace with a directory read that doesn't shell out (or cache results).

3. **Fixed menu timing (`KEY_DELAY_MS=400`, `KEY_PRESS_HOLD_MS=100`).** On a laggy server or low
   frame rate the menu may not keep up, so a nav keystroke can land in the wrong list position and
   feed the wrong item. Auto-sync corrects *progress* afterward but cannot un-feed a wrong item.
   *Track:* make timings configurable, or confirm menu state from memory between presses.

4. **Feed-submenu ordering assumption.** `calculate_ui_offsets`/`is_feedable_item` assume the
   in-game "give item to Mag" submenu lists feedable items in **inventory order**. If a server sorts
   that submenu differently, `food_offset` is wrong. *Track:* verify ordering per server; consider
   reading the menu cursor/highlight from memory.

5. **Fixed keymap assumption (F4 = Mag menu, ENTER/ENTER = select + feed).** Custom keybinds break
   navigation. The offsets stay valid; only the fixed key sequence in the queue builder needs to
   change. *Track:* expose the action keys as options.

6. **Interrupt scanner false positives.** `get_interrupt_key` polls the entire VK range via
   `GetAsyncKeyState`; held modifiers, sticky keys, or controller-mapped keys can trigger spurious
   "user keypress" pauses. *Track:* narrow the scanned range or debounce.

7. **Plan correctness is trusted, not verified.** The addon believes the plan's embedded
   `feed_value`s/`start_state`s. A plan built for the wrong episode or Mag table will fail to sync
   (best case) or mis-count (worst case). *Track:* stamp plans with episode/Mag-table identity and
   validate against the live Mag at load.

8. **Mag-cell hex accuracy.** Several cell aliases in `ITEM_NAME_TO_ID` (e.g. `Heart of Kapu Kapu`,
   `Heaven Striker Coat`) may not match a given server's real item ids; a wrong id makes a cell step
   read as a false shortage. *Track:* confirm cell ids against the target server.

9. **This repo ships only `AutoMagFeeder` + `Magatama_Release.zip`.** The root `.gitignore`
   whitelists just those, so solylib and the core addons are **not** included here — users must
   install the base addon pack separately (see the requirements in the repo's main `README.md`).
   `options.lua` also remains untracked (per-user; regenerated on first run from the in-code defaults).

---

> Built for [psobbaddonplugin](https://github.com/Solybum/psobbaddonplugin) · plans authored in
> **Magatama** (βeta 9). Use only where automation is permitted.
