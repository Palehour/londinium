class_name SplashSettings
extends RefCounted

const SETTING: String = "londinium/splash/enabled"
const CLI_FLAG: String = "--no-splash"
const HEADLESS_DISPLAY: String = "headless"


# Off for tests and CI (headless), with `godot -- --no-splash`, or by the project setting.
static func is_enabled(
	user_args: PackedStringArray = OS.get_cmdline_user_args(), display_name: String = DisplayServer.get_name()
) -> bool:
	if display_name == HEADLESS_DISPLAY or user_args.has(CLI_FLAG):
		return false
	return bool(ProjectSettings.get_setting(SETTING, true))
