class_name VantaEvents
extends Node

## Process-wide signal bus.
##
## Screens, the simulation and services talk through this bus instead of holding
## references to each other. That keeps menu code out of gameplay logic and lets
## systems be tested in isolation (a test can connect to a signal and assert that
## it fired with the expected payload).
##
## Rules of thumb used across the project:
##  - Signals carry plain data (no node references) so listeners cannot mutate
##    the emitter's state by accident.
##  - High-frequency signals (shots, hits) must stay argument-light.

# --- lifecycle -------------------------------------------------------------

## Emitted once the app has finished booting and the first screen is up.
signal app_ready()
## Emitted when the active screen changes. `screen_id` is a stable string id.
signal screen_changed(screen_id: String)
## Global navigation request, e.g. "back" from a HUD or a keyboard shortcut.
signal navigate(screen_id: String, payload: Dictionary)

# --- configuration ---------------------------------------------------------

signal settings_changed(section: String)
signal crosshair_changed()
signal profile_changed()

# --- training session ------------------------------------------------------

signal session_started(context: Dictionary)
signal session_finished(summary: Dictionary)
signal session_aborted(context: Dictionary)
## Emitted when a scenario step inside a playlist/session changes.
signal step_changed(step_index: int, step_count: int, definition_id: String)

# --- in-session gameplay ---------------------------------------------------

signal shot_fired(shot: Dictionary)
signal target_hit(hit: Dictionary)
signal target_eliminated(target_id: int, region: String)
signal score_changed(score: int)
signal hud_notice(text: String, kind: String)
signal combo_changed(streak: int)

# --- progression -----------------------------------------------------------

signal progress_changed()
signal level_changed(level_id: String, previous_level_id: String)
signal placement_completed(placement: Dictionary)
signal qualification_result(result: Dictionary)

# --- misc ------------------------------------------------------------------

## User-facing transient message (toast). `kind` is "info" | "warn" | "error".
signal toast(text: String, kind: String)
signal diagnostics_updated(snapshot: Dictionary)
