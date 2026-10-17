# Runs the full GUT suite headless on Windows.
# Usage: $env:GODOT = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
#        powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GutArgs)
# "Continue": Godot writes warnings to stderr, which must not abort the script.
$ErrorActionPreference = "Continue"
$godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
Set-Location (Join-Path $PSScriptRoot "..")
New-Item -ItemType Directory -Force -Path .godot | Out-Null
# Godot 3 renames are a text scan, so they run before Godot starts. A hit stops the suite.
& "$PSScriptRoot\check_gdscript.ps1" --renames-only
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
# Import log kept in .godot\import.log (check it for new warnings).
& $godot --headless --path . --import 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath .godot\import.log
& "$PSScriptRoot\check_gdscript.ps1" --parse-only
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit @GutArgs
exit $LASTEXITCODE
