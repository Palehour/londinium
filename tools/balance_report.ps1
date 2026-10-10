# Per-minute balance CSV for the scripted scenarios on Windows.
# Usage: $env:GODOT = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
#        powershell -ExecutionPolicy Bypass -File tools\balance_report.ps1 [--scenario <id>|all] [--out <dir>]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$ReportArgs)
# "Continue": Godot writes warnings to stderr, which must not abort the script.
$ErrorActionPreference = "Continue"
$godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
Set-Location (Join-Path $PSScriptRoot "..")
New-Item -ItemType Directory -Force -Path .godot | Out-Null
& $godot --headless --path . --import 2>&1 | ForEach-Object { "$_" } | Out-File -FilePath .godot\import.log
& $godot --headless --path . -s tools/balance_report.gd -- @ReportArgs
exit $LASTEXITCODE
