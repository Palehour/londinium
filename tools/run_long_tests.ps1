# Runs the long scenario tests (tests/scenarios/long/long_test_*.gd) headless on Windows: 20 seeds of
# 70-minute games, the 4- and 8-hour drift games and the Hard scripts of tests/scenarios/hard/, too slow for CI. Their files do not start with test_, so run_tests and CI never pick them up.
# Usage: $env:GODOT = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
#        powershell -ExecutionPolicy Bypass -File tools\run_long_tests.ps1
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GutArgs)
# "Continue": Godot writes warnings to stderr, which must not abort the script.
$ErrorActionPreference = "Continue"
$godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
Set-Location (Join-Path $PSScriptRoot "..")
New-Item -ItemType Directory -Force -Path .godot | Out-Null
# Import log kept in .godot\import.log (check it for new warnings).
& $godot --headless --path . --import 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath .godot\import.log
# -gconfig= skips .gutconfig.json, whose dirs and prefix are the ones of the short suite.
& $godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit -gconfig= `
	-gdir=res://tests/scenarios/long -gprefix=long_test_ @GutArgs
exit $LASTEXITCODE
