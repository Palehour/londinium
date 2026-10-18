# Rebuilds the GeoJSON layers of data/maps/sources/<id>/ from its committed raw downloads (sources.json) on Windows;
# then run tools\map_import.ps1.
# Usage: $env:GODOT = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
#        powershell -ExecutionPolicy Bypass -File tools\map_sources.ps1 <map_id>|all [--check]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$SourceArgs)
# "Continue": Godot writes warnings to stderr, which must not abort the script.
$ErrorActionPreference = "Continue"
$godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
Set-Location (Join-Path $PSScriptRoot "..")
New-Item -ItemType Directory -Force -Path .godot | Out-Null
& $godot --headless --path . --import 2>&1 | ForEach-Object { "$_" } | Out-File -FilePath .godot\import.log
& $godot --headless --path . -s tools/map_sources/map_sources.gd -- @SourceArgs
exit $LASTEXITCODE
