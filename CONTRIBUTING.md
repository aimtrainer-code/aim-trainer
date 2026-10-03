# Contributing to VANTA

Thanks for taking an interest in VANTA.

## Development flow

1. Make a focused change.
2. Keep the existing content-driven architecture intact.
3. Run the self-test suite locally.
4. Review the resulting `build/test.log`.
5. Open a pull request that explains what changed and why.

## Code style

VANTA uses typed GDScript where practical.

Prefer:

- small, single-purpose functions
- explicit validation at data boundaries
- deterministic behavior for simulation code
- readable names over clever shortcuts
- comments for design decisions rather than obvious syntax

Avoid:

- hidden global state
- unvalidated content flowing directly into runtime logic
- silently ignored errors
- unrelated refactors in feature changes

## Tests

Changes to a core contract should include a regression test. A fix that prevents a previously observed failure should be reproducible through the test suite when practical.

## Scope

VANTA is an offline-first project. Contributions should not add mandatory online services, telemetry, accounts, or proprietary external assets.
