class_name VantaVersion
extends RefCounted

## Single source of truth for the product version reported to the user.
##
## `project.godot` also carries a version string because the engine uses it for
## the exported binary metadata; `tests/test_version.gd` asserts that the two
## stay in sync so a release can never ship a mismatched version number.

const MAJOR: int = 0
const MINOR: int = 1
const PATCH: int = 0
const LABEL: String = ""  ## e.g. "beta", "rc1"; empty for a stable build.

## Save schema version. Bump this whenever a persisted structure changes in an
## incompatible way and add a migration in src/persistence/migrations.gd.
const SAVE_SCHEMA_VERSION: int = 1

## Scenario/definition schema version understood by the scenario parser.
const CONTENT_SCHEMA_VERSION: int = 1


static func string() -> String:
	var v := "%d.%d.%d" % [MAJOR, MINOR, PATCH]
	if LABEL != "":
		v += "-%s" % LABEL
	return v


static func project_version() -> String:
	var configured: String = str(ProjectSettings.get_setting("application/config/version", ""))
	return configured


static func is_release_candidate() -> bool:
	return LABEL == ""
