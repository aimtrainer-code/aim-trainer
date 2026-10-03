# VANTA

**TRAIN WHAT MATTERS.**

A free, open-source, offline-first aim trainer for competitive FPS players. Godot 4,
typed GDScript, primary platform Windows 11 x64. No account, no telemetry, no network
requirement.

> **Project status: pre-release, not playable yet.** The simulation core is built and
> verified; the arena view, HUD, input rig and menus that turn it into something you
> can play are the next milestone. There is no downloadable build yet. What follows is
> the measured state of this repository, not a roadmap promise.

## What is built and verified

Every claim below is covered by the project's own self-test suite
(`tools/test.sh` → 63 scripts parsed, 8 test cases, 763 assertions, all passing):

- **Sensitivity and input math** — a mouse count converts to degrees by one stated
  coefficient; cm/360 and the inverse; calibration profiles; monitor-distance matched
  zoom. No smoothing, no acceleration, no curves, no hidden rounding.
- **Settings** — user-editable JSON is treated as hostile input: every value is
  checked, clamped, and *repaired with a report* rather than crashing the game.
- **Save layer** — versioned stores, atomic-ish writes (temp file, read back, then
  replace), automatic recovery from the previous generation, quarantine of damaged
  files (moved aside, never deleted), migration from the prototype format, and
  export/import with checksums. See [`docs/SAVE_FORMAT.md`](docs/SAVE_FORMAT.md).
- **Scenario format** — a versioned, validated schema with 12 modes, 5 transfer
  stages, and specs for spawn, lifetime, motion, reaction, ammunition, rules, scoring,
  success criteria and adaptive difficulty. A scenario that references a missing arena
  or weapon is refused at load, not at runtime.
- **Content as data** — 10 scenarios, 5 weapons and 3 arenas ship in
  [`content/`](content/), all validated on load.
- **Simulation** — a fixed 480 Hz step with interpolation for rendering, deterministic
  from a seed, analytic hit registration against the same primitives that are drawn
  (never a separate collider), cover resolved before targets, and one trigger pull
  counted as one shot in every statistic.
- **Scoring and statistics** — integer arithmetic, per-scenario terms, no opaque
  composite score, and pass/fail criteria declared by the scenario itself. See
  [`docs/SCORING.md`](docs/SCORING.md).

## What is not built yet

- The playable layer: arena view, HUD, results screen, menus. The project currently
  launches into an empty root scene.
- Windows builds and installers. There is no release workflow or release artifact yet.
- Rival, the training curriculum, community content browser, benchmark tools.
- Most of `docs/` (architecture, input, scenarios, training design, performance,
  building, releasing, modding, legal), `CONTRIBUTING.md`, `SECURITY.md`,
  `CODE_OF_CONDUCT.md`, `CHANGELOG.md` and `RELEASE_REPORT.md`.
- **A licence file.** VANTA is intended to be free and open source, but the licence
  has not been chosen yet — it will be decided once the dependency licence review is
  complete. Until a licence is committed, the code is all rights reserved.

## Running it

The test suite is the only thing that runs end to end today:

```bash
GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 ./tools/test.sh
```

The engine version is pinned in [`.github/godot-version.txt`](.github/godot-version.txt),
and CI runs exactly this command on every push and pull request
([`.github/workflows/tests.yml`](.github/workflows/tests.yml)). No test framework is
downloaded: the runner is [`tests/run_tests.gd`](tests/run_tests.gd) and the whole
suite needs nothing but a Godot binary and this repository.

Launching the project (`godot --path .`) boots the application, loads and validates all
content, and currently shows an empty frame — the view layer does not exist yet.

## Design rules

These are the rules the code is written against. They are the reason several obvious
shortcuts are deliberately not taken.

- **Offline first.** No account, no telemetry, no server. A save file is local JSON that
  the player can read, export and edit.
- **Input is sacred.** One coefficient, one multiplication, nothing else. Frame-time
  compensation, smoothing and acceleration are not implemented, and neither are fake
  latency numbers.
- **Determinism.** A scenario with a fixed seed produces the same run on any machine,
  which is what makes a benchmark repeatable and a regression test possible.
- **What you see is what is hit.** Hit regions are the same primitives the renderer
  draws, resolved analytically on the same interpolated state that was displayed.
- **No invented authority.** VANTA does not claim to be scientifically validated, to be
  used by professionals, or to guarantee improvement. Numbers that cannot be measured
  are not shown.
- **No proprietary game content.** No game assets, maps, models, sounds or UI copies,
  and no interaction with another title's memory, files or anti-cheat.

## Repository layout

| Path | Contents |
| --- | --- |
| `src/core/` | Application bootstrap, logging, settings, display, math, RNG, style |
| `src/input/` | Mouse input service, sensitivity model, bindings, diagnostics |
| `src/player/` | Player state, crosshair model and geometry |
| `src/simulation/` | Clock, hit registration, spawn director, attempt runtime, statistics, arenas, target motion |
| `src/weapons/`, `src/targets/` | Weapon definitions/runtime and target hit regions |
| `src/scenarios/` | Scenario schema and its specs |
| `src/save/` | Profile, progress and history stores with recovery |
| `content/` | Shipped scenarios, weapons and arenas as JSON |
| `tests/`, `tools/` | Self-test suite and the entry-point script |
| `docs/` | Save format and scoring documentation (more to come) |

## Third-party assets

The two bundled fonts are Inter and JetBrains Mono, both under the SIL Open Font
License 1.1, with their licence texts committed next to the files in
[`assets/fonts/`](assets/fonts/). VANTA ships no third-party code, models, textures or
sounds.
