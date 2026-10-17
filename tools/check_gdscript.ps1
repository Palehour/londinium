# Flags Godot 3 APIs in *.gd files, then parses them. The default parse is two Godot
# processes (src, then tests): one process that loads both reports GUT scenes as leaks.
# Usage: $env:GODOT = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
#        powershell -ExecutionPolicy Bypass -File tools\check_gdscript.ps1 [--renames-only|--parse-only] [paths...]
# With no paths, scans src/ and tests/. Directories that contain .gdignore are skipped
# unless that directory (or a file inside it) was named on the command line.
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$ErrorActionPreference = "Continue"
$godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root

$mode = "all"
$paths = @()
foreach ($arg in @($Rest)) {
	if ($arg -eq "--renames-only") { $mode = "renames" }
	elseif ($arg -eq "--parse-only") { $mode = "parse" }
	elseif ($arg) { $paths += $arg }
}

function Get-RelativePath([string]$full) {
	$base = $root.TrimEnd('\', '/')
	if ($full.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
		return $full.Substring($base.Length).TrimStart('\', '/').Replace('\', '/')
	}
	return $full.Replace('\', '/')
}

if ($mode -ne "parse") {
	$rules = @()
	foreach ($row in [System.IO.File]::ReadAllLines((Join-Path $PSScriptRoot "gdscript_renames.txt"))) {
		$clean = $row.TrimEnd("`r")
		if ($clean -match '^\s*#' -or $clean.Trim() -eq "") { continue }
		$parts = $clean.Split("`t")
		if ($parts.Count -lt 4) {
			Write-Host "check_gdscript: bad rule: $clean"
			exit 1
		}
		$rules += [pscustomobject]@{
			Group = $parts[0]
			Old = $parts[1]
			Pattern = $parts[2]
			Replacement = $parts[3]
		}
	}

	$files = New-Object System.Collections.Generic.List[string]
	$missing = $false
	function Add-GdFiles([string]$path, [bool]$explicit) {
		if (-not (Test-Path -LiteralPath $path)) {
			Write-Host "check_gdscript: not found: $path"
			$script:missing = $true
			return
		}
		$item = Get-Item -LiteralPath $path
		if (-not $item.PSIsContainer) {
			if ($item.Name.EndsWith(".gd")) { $script:files.Add($item.FullName) }
			return
		}
		if (-not $explicit -and ($item.Name -eq "addons" -or (Test-Path -LiteralPath (Join-Path $item.FullName ".gdignore")))) {
			return
		}
		Get-ChildItem -LiteralPath $item.FullName -File -Filter *.gd | ForEach-Object { $script:files.Add($_.FullName) }
		Get-ChildItem -LiteralPath $item.FullName -Directory | ForEach-Object { Add-GdFiles $_.FullName $false }
	}
	if ($paths.Count -eq 0) {
		Add-GdFiles (Join-Path $root "src") $true
		Add-GdFiles (Join-Path $root "tests") $true
	} else {
		foreach ($path in $paths) { Add-GdFiles $path $true }
	}
	if ($missing) { exit 1 }

	$found = $false
	foreach ($file in $files) {
		$n = 0
		foreach ($line in [System.IO.File]::ReadAllLines($file)) {
			$n++
			if ($line -match '^\s*#' -or $line.Trim() -eq "") { continue }
			$seen = @{}
			foreach ($rule in $rules) {
				if ($rule.Group -ne "-" -and $seen.ContainsKey($rule.Group)) { continue }
				if ([regex]::IsMatch($line, $rule.Pattern)) {
					$rel = Get-RelativePath $file
					Write-Host ("{0}:{1}: Godot 3 API '{2}' -> {3}" -f $rel, $n, $rule.Old, $rule.Replacement)
					$found = $true
					if ($rule.Group -ne "-") { $seen[$rule.Group] = $true }
				}
			}
		}
	}
	if ($found) { exit 1 }
}

if ($mode -eq "renames") { exit 0 }

if ($mode -eq "all") {
	New-Item -ItemType Directory -Force -Path .godot | Out-Null
	& $godot --headless --path . --import 2>&1 | ForEach-Object { "$_" } | Out-File -FilePath .godot\import.log
}
# One Godot process for src and another for tests. Loading both in one process makes Godot
# report GUT scenes as leaks at exit, which hides a real parse error in the log.
function Invoke-Parse([string[]]$ParsePaths) {
	& $godot --headless --path . -s tools/check_gdscript.gd -- --parse-only @ParsePaths | Out-Host
	$script:parseCode = $LASTEXITCODE
}
if ($paths.Count -eq 0) {
	Invoke-Parse @("src")
	if ($parseCode -ne 0) { exit $parseCode }
	Invoke-Parse @("tests")
	exit $parseCode
}
Invoke-Parse @($paths)
exit $parseCode
