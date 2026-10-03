# Save format

Everything VANTA stores is plain JSON in the operating system's own per-user data
directory. There is no account, no server, and no telemetry: a save file is the only
record that a session happened, and it never leaves the machine unless the player
exports it.

This document describes **format version 1**, which is what `main` writes today.
`VantaVersion.SAVE_SCHEMA_VERSION` is the authority; if it disagrees with this page,
the code wins and this page is a bug.

## Where the files live

| File | Contents |
| --- | --- |
| `user://saves/profile.json` | Lifetime totals: sessions, play time, shots, hits, targets, training days |
| `user://saves/progress.json` | Personal bests, lesson states, skill levels, placement, qualification results, unlocks, adaptive state |
| `user://saves/history.json` | The most recent runs (capped at 500 entries) |
| `user://settings.json` | Display, mouse, crosshair, audio, accessibility and interface settings |

On Windows `user://` resolves to
`%APPDATA%\Godot\app_userdata\VANTA\`. On Linux it is
`~/.local/share/godot/app_userdata/VANTA/`.

Settings deliberately live **next to** the save directory rather than inside it:
deleting a profile must never change how the mouse feels.

### Companion files

| Pattern | Meaning |
| --- | --- |
| `*.bak.json` | The previous contents of a store, written before every replacement |
| `*.tmp` | The in-flight write of a store; deleted if it fails verification |
| `*.corrupt-<unix>.json` | A file that could not be read, moved aside instead of deleted |
| `*.reset-<unix>.json` | A copy taken by "reset progress" before the stores are cleared |

`*.corrupt-` and `*.reset-` files are never cleaned up automatically. They are the
player's data; VANTA moves them out of the way so the game can start, and leaves them
for the player to inspect or delete.

## Schema version 1

Common to all three stores:

```json
{
  "schema_version": 1,
  "created_at": 1700000000,
  "updated_at": 1700000000
}
```

`profile.json`

```json
{
  "schema_version": 1, "created_at": 0, "updated_at": 0,
  "player_name": "PLAYER", "sessions": 0,
  "total_play_seconds": 0.0, "total_shots": 0, "total_hits": 0,
  "total_targets": 0, "last_session_unix": 0,
  "training_days": [20000]
}
```

`progress.json`

```json
{
  "schema_version": 1, "created_at": 0, "updated_at": 0,
  "personal_bests": { "<scenario id>": { "score": 0, "accuracy_percent": 0.0,
      "consistency_percent": 0.0, "average_time_to_kill": 0.0, "kills": 0,
      "at": 0, "cleared": true } },
  "lesson_states": { "<lesson id>": { "completed": true, "attempts": 1,
      "best_score": 0, "completed_at": 0 } },
  "skill_levels": {}, "placement": {}, "qualification_results": {},
  "unlocked": [], "adaptive_state": {}
}
```

`history.json`

```json
{
  "schema_version": 1,
  "entries": [ { "scenario_id": "", "mode": "", "skill": "", "score": 0,
      "accuracy_percent": 0.0, "kills": 0, "shots": 0,
      "average_time_to_kill": 0.0, "consistency_percent": 0.0,
      "duration_seconds": 0.0, "passed": false, "finish_reason": "",
      "at": 0 } ]
}
```

Keys that this build does not know are ignored on read and dropped on the next write.
That is what lets a newer build add a field without breaking an older one.

### A note on number types

Godot's JSON parser returns every number as a float, so `12` in a file comes back as
`12.0`. Every store coerces and range-checks what it reads (`_int`, `_float`,
`_string`, `_bool`) instead of casting, which is also what makes a hand-edited file
safe. Do not "optimise" those helpers away.

## Writing

1. The payload is serialised and written to `<store>.tmp`.
2. The temporary file is read back and parsed. If that fails, it is deleted and the
   store is left untouched — a half-written file can never become the live one.
3. If the store already exists, it is copied to `<store>.bak.json`.
4. The temporary file is renamed over the store.

A write is therefore either fully applied or not applied at all, with one previous
generation available for recovery.

## Reading

For each store, in order:

1. Missing → defaults are used and the run is recorded as a first run. This is not an
   error.
2. Present and parseable → migrated if needed, then validated with repairs reported.
3. Present but unreadable (bad JSON, empty, wrong root type, larger than 8 MiB) → the
   backup is tried; if it parses, it is restored to the live path and the recovery is
   reported.
4. Unreadable with no usable backup → the file is moved to `*.corrupt-<unix>.json` and
   defaults are used. The load always produces a usable set of stores.

A file whose `schema_version` is **newer** than this build supports is refused. The
store stays at defaults and the refusal is reported. Guessing at a format we do not
know is how saves get destroyed.

## Migration

Version 0 is the pre-release prototype format: flat keys and bare numbers.

| v0 | v1 |
| --- | --- |
| `profile: created` / `updated` / `name` / `sessions` / `play_seconds` | `created_at` / `updated_at` / `player_name` / `sessions` / `total_play_seconds` |
| `progress: completed: ["id"]` | `lesson_states["id"] = {completed: true, attempts: 1, best_score: 0, completed_at: 0}` |
| `progress: pbs: {"id": 1337}` | `personal_bests["id"] = {score: 1337}` |
| `history: runs: [{scenario, score, accuracy, at}]` | `entries: [{scenario_id, score, accuracy_percent, at}]` |

Fields the prototype never recorded (shot counts, hit counts, consistency) start at
zero. They are **not** estimated from what is left: a made-up statistic in a training
log is worse than a missing one.

## Export and import

`export_bundle()` writes one file containing every store plus a header:

```json
{
  "vanta_bundle": 1, "app_version": "0.1.0", "save_version": 1,
  "exported_at": 1700000000, "profile": {}, "progress": {}, "history": {},
  "checksum": "<sha256>"
}
```

The checksum is taken over the payload **after a JSON round trip**
(`JSON.stringify(JSON.parse_string(body))`) because Godot's parser turns integral
values into floats. Checksumming the freshly built dictionary instead would make a
healthy bundle look edited on import, which is exactly the bug the save tests caught.

Import re-validates every store through the same migration and repair path as a load
from disk, so an import can never produce a state that loading could not. An edited or
damaged bundle is refused by the checksum; a bundle from a newer build is refused by
version. All three stores are applied together or not at all.

## What is not stored

- No telemetry, no usage analytics, no identifiers beyond the player's chosen name.
- No hardware identifiers, no IP address, no install fingerprint.
- No raw input traces or replay data (a replay feature, if it ships, will be an
  explicit export).
