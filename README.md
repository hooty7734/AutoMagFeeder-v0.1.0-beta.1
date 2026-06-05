# AutoMagFeeder

A PSOBB addon that **feeds your Mag automatically**, following a plan you design in the
**Magatama** desktop app. Magatama works out the exact item-by-item feeding chart to reach a
target Mag build; AutoMagFeeder reads your live inventory/Mag in-game and presses the menu keys
to feed it — pausing for combat, lost focus, and your own input.

This repository ships two things:

| Path | What it is |
|------|-----------|
| [`addons/AutoMagFeeder/`](addons/AutoMagFeeder/) | The PSOBB addon (the in-game feeder). |
| `Magatama_Release.zip` | The **Magatama** desktop planner (`Magatama.exe` + `MagDex.exe`) that exports the feeding plans the addon runs. |

> 📖 **Full instructions, setup walkthrough, and a function-by-function reference live here:**
> **[addons/AutoMagFeeder/README.md](addons/AutoMagFeeder/README.md)**

---

## Requirements

To make this tool function you need all of the following:

1. **Phantasy Star Online Blue Burst — Ephinea.** The addon is built and tested against the
   Ephinea client. Its enemy-proximity safety check reads Ephinea-specific memory addresses, so on
   another server/client build that guard may not work correctly (see the *Known issues* section of
   the instructions).
2. **Windows.** The feeder synthesizes keystrokes and checks window focus through Win32
   (`keybd_event`, `GetForegroundWindow`) via LuaJIT FFI — it is Windows-only.
3. **The base addon plugin:** [psobbaddonplugin](https://github.com/Solybum/psobbaddonplugin)
   (Solybum's fork), installed into your PSOBB folder.
4. **The base addon pack (dependencies).** AutoMagFeeder `require`s **`solylib`** and the **core
   addons** (`core_mainmenu`, `core_addonlist`, …). **These are *not* included in this repo** — install
   the [PSOBBMod-Addons](https://github.com/Solybum/PSOBBMod-Addons) pack so that `solylib/` and the
   `core_*` addons sit in the same `addons/` directory as `AutoMagFeeder/`.
5. **Magatama** (to create plans), from `Magatama_Release.zip`. It is a standalone app but needs
   **.NET Framework 4.8** (present on modern Windows).

## Quick start

1. Install **psobbaddonplugin**, then install the **PSOBBMod-Addons** pack (this provides `solylib`
   and the `core_*` addons that AutoMagFeeder depends on).
2. Copy **`addons/AutoMagFeeder/`** from this repo into your PSOBB `addons/` directory.
3. Unzip **`Magatama_Release.zip`** somewhere and run `Magatama.exe` to design a build; export the
   plan (**File → Export → Export AutoMag Plan**, or `Ctrl+E`) as `plan.lua` and drop it into
   `addons/AutoMagFeeder/`.
4. Launch PSOBB, open **AutoMag Feeder** from the addon main menu, select your plan + Mag, **Load**,
   then **Start**.

Step-by-step details for every part of this are in
**[addons/AutoMagFeeder/README.md](addons/AutoMagFeeder/README.md)**.

---

## Credits

- **Magatama** is the work of **[Aether89](https://github.com/Aether89/Magatama)** (a spiritual
  successor to *Mag Farm* by **James Baxter**); the bundled build is a fork that adds the
  `plan.lua` exporter. Magatama is Unlicense / public domain.
- **AutoMagFeeder** and **[solylib](https://github.com/Solybum/PSOBBMod-Addons)** / the core addon
  framework build on **Solybum**'s PSOBBMod-Addons and **Eidolon**'s addon system.

> ⚠️ This addon synthesizes keyboard input into an online game. Use it only on servers where
> automation is permitted. You are responsible for how you use it.
