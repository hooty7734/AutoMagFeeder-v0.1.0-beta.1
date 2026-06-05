# AutoMagFeeder — `init.lua` Reference

This document describes the **complete function of `AutoMagFeeder/init.lua`** — the single-file
engine that powers the AutoMagFeeder PSOBB addon. It loads a feeding **plan** (a Lua table
exported by Magatama), works out where to resume on your equipped Mag, and then feeds the Mag
automatically by playing simulated keystrokes through the in-game feed menu — while continuously
enforcing safety checks.

`init.lua` is the entire addon logic. The other files are supporting: `options.lua` (persisted settings) and plan files. The bundled examples are four FOmar→RAmar builds, named `<RareMag>-<Focus>-<SectionSet>-<evoFeed>.lua` (each stops at **level 99**, one feed from the rare 4th evolution — the `1mf`/`1ad` tag is the single Monofluid/Antidote that triggers it). You can drop in any plan exported by Magatama. The settings/configuration menu has been integrated directly into the control window.

| Plan file | Rare mag | Final DEF/POW/DEX/MIND | Evolution Section IDs |
|---|---|---|---|
| `Kama-MIND-VBRW-1mf.lua` | Kama | 5.00 / 0.00 / 45.00 / 49.90 | Viridia, Bluefull, Redria, Whitill |
| `Kama-MIND-GPuO-1mf.lua` | Kama | 5.00 / 0.00 / 50.00 / 44.90 | Greenill, Purplenum, Oran |
| `Bhirava-POW-SPiY-1ad.lua` | Bhirava | 5.00 / 45.00 / 49.84 / 0.00 | Skyly, Pinkal, Yellowboze |
| `Kama-POW-VBRW-1ad.lua` | Kama | 5.00 / 50.00 / 44.88 / 0.00 | Viridia, Bluefull, Redria, Whitill |

(Exact stats and the `Leilla.Pilla.Mylla` lineage are also preserved in each file's header comment.)

---

## 1. The big picture

Every game tick, `init.lua`:

1. Decides whether it's **safe** to act (window focused, no enemies near, you're not typing).
2. If a feed macro is mid-flight, advances its **key-press state machine**.
3. Otherwise checks the **Mag timer** (don't feed a Mag that's still digesting).
4. Builds and fires a **macro queue** of virtual key presses to feed up to 3 items.
5. Tracks **progress** through the plan (items left in step → next step → plan complete).

A live ImGui window lets you pick a plan, load it, start/pause/reset, and watch a diagnostics log.

```
plan.lua (from Magatama)
        │  load_feeder_plan()  →  calculate_plan_resume_point()
        ▼
active_feeder_state  ──tick──►  execute_feeder_tick()
        │                              │
        │                              ├─ safety gates (focus / enemies / your keys / timer)
        │                              ├─ calculate_ui_offsets()  (where is the food in the menu?)
        │                              └─ macro_state queue  →  keybd_event()  →  game
        ▼
present()  (ImGui control window + diagnostics log)
```

---

## 2. Dependencies and FFI

```lua
core_mainmenu, solylib.helpers, solylib.items.items, solylib.characters,
ffi, imgui, solylib.items.items_list
```

It declares four native Windows functions via FFI:

- `keybd_event` — synthesizes key presses/releases (this is how it "types" into the game).
- `GetForegroundWindow`, `GetWindowThreadProcessId`, `GetCurrentProcessId` — used to confirm PSOBB
  is the **active** window before sending any keys.

---

## 3. Constants & lookup tables

| Name | Purpose |
|------|---------|
| `KEY_PRESS_HOLD_MS = 100` | How long a key is "held" before release. |
| `KEY_DELAY_MS = 400` | Gap between consecutive key presses (matches the menu's response speed). |
| `VK_RETURN / VK_DOWN / VK_F4 / VK_ESCAPE / VK_F12` | Virtual-key codes used to drive the feed menu. |
| `KEYEVENTF_KEYUP / KEYEVENTF_EXTENDEDKEY` | Flags for `keybd_event` (extended flag is required for arrow keys). |
| `SECTION_IDS` | Maps Section ID numbers (0–9) to names (Viridia … Whitill) for class/ID matching. |

---

## 4. State

### `options` (persisted)
Loaded via `pcall(require, "AutoMagFeeder.options")`, with safe defaults applied through
`lib_helpers.NotNilOrDefault`. Fields: `enable`, `enable_safety_checks`, `lock_inputs`,
`show_toolbox`, `plan_file_path`, `anchor`, `x`, `y`, `w`, `h` (window coordinates and anchors).
`SaveOptions(opts)` rewrites `options.lua` whenever a setting changes or the control window is moved/resized.

### `active_feeder_state` (runtime)
The master state object. Key fields:
`plan_loaded`, `plan_data`, `current_step_idx`, `items_remaining_in_step`, `is_running`,
`last_action_tick`, `status_msg`, `enemy_danger_tripped`, `input_lockout_active`,
`inventory_shortage`, `shortage_msg`, `game_lost_focus`, `post_feed_cooldown`.

### `macro_state` (the keystroke player)
`is_executing`, `queue` (list of VK codes to press), `items_fed_this_queue`,
`current_held_key`, `key_action_tick`.

Plus directory-scan state: `available_plans`, `selected_plan_index`, `plans_scanned`.

---

## 5. Functions, in detail

### Environment / focus
- **`is_game_window_active()`** — true only when the foreground window's process ID equals this
  PSOBB instance's PID. Prevents keystrokes leaking to other apps.
- **`is_in_game_instance()`** — true if the player is logged in and not in a visual lobby (floor `15`), on the main menu / character selection screen (floor `0xFFFFFFFF` / `4294967295`). Pioneer 2 starts at floor `0` (which is a valid feeding area).
- **`get_safe_character()`** — returns the player's character address, or nil if unavailable.

### Logging
- **`debug_log(msg)`** — timestamps a message, keeps the last 50 in `debug_logs` (shown in the UI),
  and also `print`s it.

### Plan discovery
- **`scan_plan_directory()`** — runs `dir addons\AutoMagFeeder\*.lua` and lists every `.lua` that
  isn't `init`/`configuration`/`options`, populating the plan dropdown. Selects the entry matching
  the current `plan_file_path`.

### Hardware input
- Keys are sent using Windows virtual key-to-scan code mapping via `MapVirtualKeyA` for DirectInput compatibility.
- **`is_key_pressed(vk_code)`** — thin wrapper over `pso.is_key_pressed`.
- **`is_interrupt_key_pressed()`** — scans the whole keyboard range **except** the keys the macro
  itself uses (Enter, Down, Esc, F4, F12) and the mouse buttons. If *you* press anything else, the
  loop treats it as "take over now" and stops.

### Safety
- **`check_proximity_threats()`** — directly scans the game's live memory entity array, returning true if any living enemy is within `options.max_safety_distance` (default 100) of the player. Skipped if safety checks are off.

### Inventory / Mag reading
- **`item_matches_hex(item, hex_str)`** — compares an item's first three data bytes to a flat hex code like `"0x030000"` (Monomate).
- **`is_feedable_item(item)`** — checks if a tool item matches the flat category indices in memory for feedable consumables: category values `0` through `9` and `19` (representing Mates, Fluids, Sol/Moon/Star Atomizers, Antidote, and Antiparalysis).
- **`calculate_ui_offsets(target_hex_str)`** — using solylib's `GetInventory` reader, returns
  **two** Down-press offsets: `mag_offset` (top of the item list → the equipped Mag, via
  `item.index - 1`) and `food_offset` (position of the target food among feedable consumables
  only). Either is nil if not found (no equipped Mag / food not carried) → inventory shortage.
- **`get_equipped_mag()`** — finds the equipped Mag (data type `0x02`) and returns its parsed
  `level, def, pow, dex, mind, timer, slot` (using solylib's `item.mag.*`).

### Plan math & tracking
- **`calculate_plan_resume_point(mag, plan_data)`** — the resume brain. Walks the plan's steps and,
  from your Mag's current DEF/POW/DEX/MIND vs each step's `start_state` and `feed_value`, computes
  how many items were already fed in the current step and **how many remain**, returning
  `(step_index, items_remaining)`. This is what lets a half-fed Mag continue instead of restarting.
  It performs a case-insensitive check on `step.mag_name` against the equipped `mag.name` to identify if a
  Mag cell has already been used (since Mag cells evolve the Mag but do not alter stats, stats alone are
  insufficient to determine progress).
- **`track_plan_state()`** — keeps `active_feeder_state` consistent each frame: tops up
  `items_remaining_in_step` from the step `count`, detects plan completion (`idx > #sequence`),
  flags inventory shortages (missing food or no Mag), and updates the running status message. For Mag cell
  steps, it calls `has_item_in_inventory` to check for cell presence without interfering with regular feedable
  item menu offsets.
- **`has_item_in_inventory(hex_str)`** — scans the inventory for the specified item hex code. Used for Mag cell checks.
- **`load_feeder_plan(filepath)`** — loads and validates a plan:
  1. `dofile` the plan and confirm it returns a table with `target_mag` + `sequence`.
  2. Confirm a Mag is equipped.
  3. Call `calculate_plan_resume_point`; bail if stats don't fit the plan or it's already done.
  4. Confirm your **class** and **Section ID** match the resume step (so you don't feed on the wrong character).
  5. Automatically maps legacy/incorrect plan item IDs to the correct flat PSOBB hex IDs (e.g. mapping `0x030A00` to `0x030000` for Monomate) on-the-fly.
  6. On success, store the plan, set the resume step/count, and report "Synced! Resuming …".

### The core loop
- **`execute_feeder_tick()`** — runs every tick (see §6).

### UI & lifecycle
- **`present()`** — runs the tick, then (if `show_toolbox`) draws the ImGui control window:
  status monitor, plan dropdown + Refresh, Load, Start/Pause, Reset Progress, and the live
  diagnostics log. Minimizing/maximizing toggles compact status vs full configuration mode. Saves options on change.
- **`init()`** — registers `execute_feeder_tick` with `pso.on_tick` (falling back to `present`-driven ticking if unavailable), adds the **"AutoMag Feeder"** button to the addon main menu, and returns the addon metadata + `present`.
- The file returns `{ __addon = { init = init } }`, the entry point the addon framework calls.

---

## 6. `execute_feeder_tick()` — step by step

This is the heart of the addon. Each tick:

1. **Get character & time.** Bail if no character. Read `current_time = pso.get_tick_count()`.

2. **Safety / pause overrides** — set `abort_execution` if **any** of:
   - PSOBB is not the active window (`is_game_window_active` false) — also stops the loop;
   - the loop isn't running;
   - input lockout is on and **you** pressed a non-macro key (`is_interrupt_key_pressed`) — stops the loop;
   - you're in a game and an enemy is in range (`check_proximity_threats`) — stops the loop.

   On abort, if a macro was mid-flight it **releases any held key**, clears the queue, and resets
   `macro_state`. Then returns.

3. **Macro state machine** (when `macro_state.is_executing`):
   - **Phase A – release:** if a key is currently held and `KEY_PRESS_HOLD_MS` has elapsed, send
     the key-up (with scan code mapped from `MapVirtualKeyA` + KEYUP flag) and clear `current_held_key`.
   - **Phase B – press:** once `KEY_DELAY_MS` has elapsed, pop the next VK from the queue and send
     its key-down (scan code mapped from `MapVirtualKeyA` + flags). When the queue empties, mark the macro
     done, schedule a cooldown, subtract `items_fed_this_queue` from `items_remaining_in_step`, and
     advance `current_step_idx` if the step is finished.

4. **Plan guard.** If there's no loaded plan/sequence, return.

5. **Mag Cell Pause Override.** If `step.is_mag_cell` is true, the feeder automatically pauses, displays
   a user prompt to manually use the cell, advances the step index to the next step, and exits the tick.

6. **Post-feed cooldown & Mag timer.** If still inside `post_feed_cooldown`, do nothing (lets the
   server update the Mag timer). If the equipped Mag's `timer > 2.0`, it's still digesting — log
   occasionally and wait.

7. **Generate the macro queue.** Get both offsets via `calculate_ui_offsets` (if not a Mag cell step). Feed
   `min(3, items_remaining_in_step)` items this cycle. Enqueue (default keymap):

   ```
   F4 → Down × mag_offset → Enter (select Mag) → Enter (Give item, default)
      → Down × food_offset → Enter × feeds → F4 (close)
   ```

   The `Down × mag_offset` step is what selects the **equipped Mag** in the item list. Set
   `items_fed_this_queue`, flip `is_executing = true`, and let the state machine play it out.

---

## 7. Settings that affect behavior

| Option | Effect |
|--------|--------|
| `enable` | Master enable for the addon. |
| `enable_safety_checks` | Toggles the enemy-proximity guard. |
| `lock_inputs` | Toggles the "abort if you press a key" guard. |
| `show_toolbox` | Shows/hides the main control window. |
| `plan_file_path` | The plan file the dropdown loads. |
| `max_safety_distance` | Enemy distance threshold (default 100) for the proximity check. |
| `feed_delay_ms` | Used by older code paths as the inter-cycle throttle. |

---

## 8. Notes & quirks

- The tick sends keys by mapping virtual keys to hardware scan codes using **`MapVirtualKeyA`** (DirectInput-friendly) for maximum compatibility.
- The macro feeds in **batches of up to 3**, then waits out the Mag's digest timer and a post-feed
  cooldown before the next batch — pacing itself to the server rather than spamming.
- Includes a resolution-independent anchoring system that automatically snaps the window to screen edges/corners on resolution changes.
- In `execute_feeder_tick`'s Phase B, the branch taken when `KEY_DELAY_MS` has **not** yet elapsed
  also terminates the macro and starts a 5-second cooldown; review this if feeds end prematurely.
- The feed-menu key path assumes the default keymap where **F4 opens the Mag menu** and **"Give
  item to mag" is the default-highlighted option**. If a server/keybind differs, the only change
  needed is the fixed key sequence in the macro-queue builder — the offsets stay valid.

---

## 9. HUD theme (matches your installed HUD)

The addon windows can be styled to match the in-game PSOBB HUD by extracting the game's actual
texture. The theme is derived from **whatever HUD texture is installed** — the extractor samples the
texture's accent colour, so it's cyan on stock PSO but adapts to a recoloured / custom HUD.

### HUD Theme Extraction (run BEFORE launching PSOBB)
The extractor writes `theme.ini` / `hud_panel.png` that the framework reads at load time, and may
need to set up Python the first time — so it's a pre-launch step, not an in-game one:

1. **Double-click `Extract HUD Theme.bat`** in your PSOBB folder (it calls
   `addons/Theme Editor/extract_hud.bat`). It finds your Python — or downloads a small self-contained
   one if you have none (no admin, nothing added to your system) — installs `Pillow`, then reads
   `data/f256_hyouji.prs` (loose, or unpacked from `data.gsl`), decompresses it, extracts the HUD
   sheet (tex13), builds the tileable scanline panel `addons/hud/hud_panel.png`, and writes a
   matching `addons/theme.ini` from the texture's accent colour.
2. **Launch PSOBB** — the theme is already applied.

Extraction is done **only** by the pre-launch batch (not in-game). In the in-game Theme Editor you
just toggle **"Apply Extracted HUD"** on/off (non-destructive) and use **"Revert to Default"** to go
back to the stock palette.

### Global Window Skinning
Once `hud_panel.png` is extracted (and **Apply Extracted HUD** is on), the loader framework hooks
`imgui.Begin` globally:
* All standard panel windows get the translucent dark-teal scanline tile stretched as their
  background, with the bright cyan HUD frame (`#52EFFF` glow + corner brackets) painted on top.
* Borderless overlay windows (like timers, clocks, or damage overlays that have `NoTitleBar` set) are automatically skipped to prevent visual artifacts.
* The bright accent colour also drives the global `theme.ini` palette (window border, buttons,
  checkmarks, …), so even the standard ImGui widgets pick up the HUD blue.
* If the toggle is off, or the texture is missing, windows fall back to the plain `theme.ini` look.


---

> This addon synthesizes keyboard input into an online game. Use only where permitted.
