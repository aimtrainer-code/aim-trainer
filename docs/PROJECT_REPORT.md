# VANTA — Project Report

## 1. Project summary

VANTA is a desktop, offline-first aim training project built with Godot and typed GDScript.

The project separates training content, simulation logic, persistence and presentation so that individual parts can be tested without requiring the full application loop.

## 2. Problem being addressed

A training tool needs repeatable measurements. A result is useful only when the same input rules and scenario definition can be applied consistently across runs.

VANTA therefore treats:

- input conversion
- scenario definitions
- target behavior
- statistics
- save data
- validation

as explicit software contracts rather than UI-only behavior.

## 3. Architecture

### Presentation

The current public renderer is implemented in `src/core/root.gd`. It handles screen state, input routing, session presentation and result display.

### Application layer

`src/core/app.gd` initializes the application services and owns shared runtime state.

### Content layer

Scenario and training data live in `content/` as versioned JSON. This keeps content editable without rewriting the rendering code.

### Simulation layer

The repository contains deterministic simulation components for timing, movement, hit registration and statistics. The public 0.2.0 renderer is a lightweight interface over that foundation.

### Persistence

The save layer uses versioned stores, validation, recovery and import/export checks.

## 4. Validation strategy

The project uses a two-stage automated test approach:

1. compile/parse verification of project scripts
2. execution of the test cases

This is intentionally stricter than testing only the code paths used by the main scene.

## 5. Reliability decisions

Several project decisions are designed to fail safely:

- malformed settings are validated and repaired
- damaged save files are quarantined rather than silently discarded
- imported data passes through migration before it becomes runtime state
- test import failures are no longer ignored
- test and import logs are preserved for debugging

## 6. User experience

The current playable version intentionally prioritizes a complete loop over presentation complexity:

```
Choose → Train → Measure → Review → Repeat
```

The result screen surfaces a small set of directly measured values rather than inventing a hidden composite metric.

## 7. Current limitations

The project is not presented as a scientifically validated measurement instrument. It is a software engineering project with a deterministic simulation foundation and a playable vertical slice.

The current 0.2.0 renderer is 2D. A later phase can expose more of the existing simulation through richer visuals while keeping the same contracts.

## 8. Future work

Planned areas include:

- richer visualisation of existing simulation state
- curriculum and progression tools
- community content workflows
- benchmark and analysis tooling
- broader documentation and release automation

The key constraint is backwards compatibility with the existing content and test contracts.
