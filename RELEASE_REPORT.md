# VANTA 0.2.0 Release Report

## Scope

This release turns the existing simulation/content foundation into a playable public vertical slice.

The release loop is:

```
Scenario selection
      ↓
Timed session
      ↓
Live score and accuracy
      ↓
Results
      ↓
Replay or choose another scenario
```

## Engineering goals

### Playable

The application opens directly into a scenario selector and provides a complete input-to-result loop.

### Testable

The repository includes a headless self-test runner that first checks project scripts and then executes the test cases.

### Reproducible

The Godot version is pinned. CI and local testing use the same `tools/test.sh` entry point.

### Maintainable

Scenario data remains outside the presentation code. The renderer consumes the existing content definitions rather than duplicating scenario configuration.

### Offline-first

No account, server, or telemetry service is required for the core experience.

## Known limitations

The public renderer is intentionally lightweight. It is a 2D vertical slice rather than the final full 3D presentation.

The next major phase is to expose more of the existing deterministic simulation through a richer visual layer without breaking the existing data and test contracts.

## Verification

The authoritative verification result is the latest GitHub Actions test run for the exact commit being released. The README deliberately avoids hard-coding a historical assertion count so documentation cannot become stale.
