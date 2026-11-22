# Runs the verification CLI headless on Windows and keeps stdout+stderr as log.txt in the evidence folder.
# Usage: $env:GODOT = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
#        powershell -ExecutionPolicy Bypass -File tools\verificar.ps1 [verificar.gd options]
# Exit code: the CLI's (0 ok, 1 failed expectation, 2 usage/data error); 2 also if the log cannot be saved.
# Does not run --import: tools\run_tests.ps1 builds the .godot cache.
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CliArgs)
# "Continue": Godot writes warnings to stderr, which must not abort the script.
$ErrorActionPreference = "Continue"
$godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
try {
    Set-Location -LiteralPath (Join-Path $PSScriptRoot "..") -ErrorAction Stop
} catch {
    [Console]::Error.WriteLine("verificar: cannot enter the repo root")
    exit 2
}
if (-not (Get-Command $godot -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine("verificar: Godot not found ('$godot'); set `$env:GODOT to the 4.7.2 console binary")
    exit 2
}

# Per-run temp log, so two worktrees never share a file.
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("verificar." + [guid]::NewGuid().ToString("N") + ".log")
$utf8 = New-Object System.Text.UTF8Encoding($false)
try {
    [System.IO.File]::WriteAllText($tmp, "", $utf8)
} catch {
    [Console]::Error.WriteLine("verificar: cannot create temp log")
    exit 2
}

function Fail([string]$msg) { [Console]::Error.WriteLine("verificar: $msg"); exit 2 }

$script:marker = $null
$script:captureFailed = $false
try {
    & $godot --headless --path . -s tools/verificar.gd -- @CliArgs 2>&1 | ForEach-Object {
        $line = "$_"
        $line
        try { [System.IO.File]::AppendAllText($tmp, $line + "`n", $utf8) } catch { $script:captureFailed = $true }
        # Only the FIRST marker counts: the CLI prints it before running anything, so later
        # output (game text, push_error) cannot redirect the copy.
        if ($null -eq $script:marker -and $line.StartsWith("VERIFICAR_SALIDA=")) {
            $script:marker = $line.Substring("VERIFICAR_SALIDA=".Length).TrimEnd("`r")
        }
    }
    $status = $LASTEXITCODE

    # Unexpected native status (crash, signal): pass it through untouched.
    if ($status -notin 0, 1, 2) { exit $status }
    if ($script:captureFailed) { Fail "could not capture the log" }

    $out = $script:marker
    if ([string]::IsNullOrEmpty($out)) {
        # No marker is legitimate only for a sole --help (exit 0) or a CLI error before it chose a folder (exit 2).
        if ($status -eq 0 -and @($CliArgs).Count -eq 1 -and $CliArgs[0] -eq "--help") { exit 0 }
        if ($status -eq 2) { exit 2 }
        Fail "no output directory marker found, log.txt not saved"
    }
    if (-not [System.IO.Path]::IsPathRooted($out)) { Fail "output directory '$out' is not absolute, log.txt not saved" }
    if (-not (Test-Path -LiteralPath $out -PathType Container)) { Fail "invalid output directory '$out', log.txt not saved" }
    $dest = Join-Path $out "log.txt"
    # An existing log.txt must be a plain file: reject directories and symlinks/junctions (reparse points).
    $existing = Get-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
    if ($null -ne $existing -and ($existing.PSIsContainer -or ($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint))) {
        Fail "'$dest' is not a regular file, log.txt not saved"
    }
    try {
        Copy-Item -LiteralPath $tmp -Destination $dest -Force -ErrorAction Stop
    } catch {
        Fail "could not write $dest"
    }
    # Keep the CLI's own status: 0 ok, 1 failed expectation, 2 data error (log kept for all three).
    exit $status
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
