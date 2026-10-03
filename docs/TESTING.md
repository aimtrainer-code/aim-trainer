# Testing

VANTA uses a small built-in test runner instead of an external test framework.

## Two-phase verification

### 1. Compile and parse sweep

`tests/run_tests.gd` recursively scans the project source areas and loads every GDScript file it finds.

The test runner then reloads scripts where it is safe to do so. This catches syntax and compile errors in code that may not be exercised by a specific test case.

This phase is intentionally strict because a project should not pass CI while a rarely used script is broken.

### 2. Test case execution

Every `tests/test_*.gd` file is loaded and executed through the shared `VantaTestCase` base class.

The suite covers the core data and simulation contracts, including:

- content validation
- mathematical helpers
- deterministic random/binding behavior
- save and recovery behavior
- scenario runtime behavior
- sensitivity calculations
- settings validation
- scoring/content definitions

The exact number of assertions is printed by CI rather than duplicated in documentation.

## Local command

```bash
GODOT=/path/to/godot ./tools/test.sh
```

Use the optional filter for a focused case:

```bash
GODOT=/path/to/godot ./tools/test.sh --filter save
```

## CI contract

GitHub Actions runs the same `tools/test.sh` entry point on pushes and pull requests. This keeps local and CI verification aligned.

A test failure should be fixed in the project code or test, not hidden by changing the CI command.

## Debug artifacts

The test script records complete logs under `build/`. CI uploads the test log even when the test job fails, which makes compiler and runtime failures easier to reproduce.
