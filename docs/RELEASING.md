# Releasing VANTA

## Release contract

VANTA releases are versioned with Git tags in the form `vX.Y.Z`.

The tag version must match `config/version` in `project.godot`. The release workflow checks this before exporting.

## Release pipeline

A tag such as `v0.2.0` triggers `.github/workflows/windows-build.yml`.

The workflow:

1. installs the pinned Godot version
2. validates the project in headless editor mode
3. runs the same self-test suite used by CI
4. verifies the tag matches the project version
5. exports the Windows x64 build
6. verifies both the executable and PCK exist
7. packages both files into `VANTA-windows-x64.zip`
8. writes a SHA-256 checksum file
9. uploads the artifact
10. creates the GitHub Release with the ZIP and checksum attached

## Creating a release

Update `project.godot` and `src/core/version.gd` first, then commit those changes.

From a local Git checkout:

```bash
git tag -a v0.2.0 -m "VANTA 0.2.0"
git push origin v0.2.0
```

The exact version should be changed to match the project version being released.

## Release contents

The Windows release ZIP contains:

- `VANTA.exe`
- `VANTA.pck`

The adjacent `.sha256` file can be used to verify the downloaded ZIP.

## Pre-release checklist

Before creating a tag:

- [ ] project version is updated
- [ ] changelog describes the release
- [ ] README run instructions are current
- [ ] CI is green on the exact commit
- [ ] the project opens in Godot without errors
- [ ] the export preset is present
- [ ] no local save data or generated cache is committed

The release workflow is intentionally gated so a broken project cannot be turned into a release artifact by accident.
