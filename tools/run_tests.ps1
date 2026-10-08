# Runs the full GUT suite headless on Windows.
# Usage: $env:GODOT = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"; .\tools\run_tests.ps1
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GutArgs)
$ErrorActionPreference = "Stop"
$godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
Set-Location (Join-Path $PSScriptRoot "..")
& $godot --headless --path . --import *> $null
& $godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit @GutArgs
exit $LASTEXITCODE
