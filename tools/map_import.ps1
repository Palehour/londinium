# Rebuilds data/maps/<id>.json from its traced sources in data/maps/sources/<id>/ on Windows.
# Usage: $env:GODOT = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
#        powershell -ExecutionPolicy Bypass -File tools\map_import.ps1 <map_id>|all [--check]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$ImportArgs)
# "Continue": Godot writes warnings to stderr, which must not abort the script.
$ErrorActionPreference = "Continue"
$godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
Set-Location (Join-Path $PSScriptRoot "..")
New-Item -ItemType Directory -Force -Path .godot | Out-Null
& $godot --headless --path . --import 2>&1 | ForEach-Object { "$_" } | Out-File -FilePath .godot\import.log
& $godot --headless --path . -s tools/map_import/map_import.gd -- @ImportArgs
exit $LASTEXITCODE
