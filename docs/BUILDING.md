# Building VANTA

## Requirements

- Godot 4.7.2 stable
- Git
- A desktop environment capable of running Godot

The exact engine version is pinned in `.github/godot-version.txt`.

## Run locally

Open the repository in Godot and run the main scene.

The main scene is `scenes/root.tscn`.

## Run the self-test suite

From the repository root:

```bash
GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 ./tools/test.sh
```

The script imports the project first, then performs the full headless self-test. Logs are written to:

- `build/import.log`
- `build/test.log`

A non-zero exit code means the repository should not be treated as a passing build.

## Windows export

The repository contains a Windows Desktop export preset. The GitHub Actions workflow in `.github/workflows/windows-build.yml` installs the pinned Godot version and produces an x64 ZIP artifact.

Version tags use the same pipeline for GitHub Releases.

## Repository rules

Keep generated Godot state out of source control. Do not commit local `.godot` caches, exported binaries, or personal save data.

The project is intentionally offline-first and does not require an external service to build or test.
