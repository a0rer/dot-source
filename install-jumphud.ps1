#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the JumpHUD files from this repository into a Team Fortress 2 install.

.DESCRIPTION
    Mirrors <repo>\jumphud into <TF2>\tf\custom\jumphud so the game loads it as a custom
    HUD. Anything already sitting in that folder is backed up first, then replaced with an
    exact mirror - this is what removes files left over from older releases (for example
    v2.5.0's "speedograph" folder, which no longer exists upstream).

    JumpHUD also keeps your chosen customization values in <TF2>\tf\cfg\jumphud. Those are
    version specific: v2.6.4 moved them into a new "customization/" layout, so files written
    by an older release are not read. Use -ResetConfig when crossing releases to move that
    folder aside and let JumpHUD write fresh defaults on next launch. Either way the old
    folder is backed up, so this is reversible.

    The game must be closed while this runs.

.PARAMETER TfPath
    Team Fortress 2 install root (the folder containing tf.exe). Autodetected from the
    Steam registry key and libraryfolders.vdf if omitted.

.PARAMETER Source
    Folder holding the jumphud files to install. Defaults to <script dir>\jumphud.

.PARAMETER BackupRoot
    Where timestamped backups are written. Defaults to %LOCALAPPDATA%\TF2-Jumphud-Backups.

.PARAMETER ResetConfig
    Move tf\cfg\jumphud aside so JumpHUD regenerates defaults on next launch.

.PARAMETER KeepConfig
    Leave tf\cfg\jumphud in place. This is the default when -ResetConfig is not passed.

.PARAMETER SkipBackup
    Replace without backing anything up first.

.EXAMPLE
    .\install-jumphud.ps1
    Mirrors the repo onto the autodetected TF2 install, keeping your settings.

.EXAMPLE
    .\install-jumphud.ps1 -ResetConfig
    Same, but also resets your saved customization values (do this when updating releases).

.EXAMPLE
    .\install-jumphud.ps1 -TfPath 'D:\SteamLibrary\steamapps\common\Team Fortress 2'
    Installs to a non-default Steam library.

.EXAMPLE
    .\install-jumphud.ps1 -WhatIf
    Shows what would be copied and deleted without touching anything.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $TfPath,
    [string] $Source,
    [string] $BackupRoot,
    [switch] $ResetConfig,
    [switch] $KeepConfig,
    [switch] $SkipBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Repo-only metadata that has no business inside tf/custom.
$ExcludeDirs = @('.git', '.github')
$ExcludeFiles = @('.gitignore', '.prettierrc')

function Get-JhVersion {
    param([string] $Root)
    $versionFile = Join-Path $Root 'cfg\jh_versioninfo.cfg'
    if (-not (Test-Path -LiteralPath $versionFile)) { return 'unknown' }
    $match = Select-String -LiteralPath $versionFile -Pattern 'Release-v([0-9.]+)' |
        Select-Object -First 1
    if ($null -eq $match) { return 'unknown' }
    return $match.Matches[0].Groups[1].Value
}

function Test-Tf2Install {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    return (Test-Path -LiteralPath (Join-Path $Path 'tf.exe'))
}

function Get-SteamRoots {
    # Steam can live on a different drive, so ask the registry before falling back
    # to the Program Files guesses.
    $roots = [System.Collections.Generic.List[string]]::new()

    $regPaths = @(
        'HKCU:\Software\Valve\Steam',
        'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'
    )
    foreach ($regPath in $regPaths) {
        try {
            $item = Get-ItemProperty -Path $regPath -ErrorAction Stop
            if ($item.PSObject.Properties.Name -contains 'SteamPath' -and $item.SteamPath) {
                $roots.Add([string]$item.SteamPath)
            }
        } catch {
            continue
        }
    }

    foreach ($var in @('ProgramFiles(x86)', 'ProgramFiles')) {
        $base = [Environment]::GetEnvironmentVariable($var)
        if ($base) { $roots.Add((Join-Path $base 'Steam')) }
    }

    return $roots
}

function Resolve-Tf2Install {
    param([string] $ExplicitPath)

    if ($ExplicitPath) {
        $resolved = (Resolve-Path -LiteralPath $ExplicitPath -ErrorAction SilentlyContinue)
        if (-not $resolved) { throw "TfPath does not exist: $ExplicitPath" }
        $candidate = $resolved.Path
        if (-not (Test-Tf2Install $candidate)) {
            throw "Not a Team Fortress 2 install (no tf.exe found): $candidate"
        }
        return $candidate
    }

    $tried = [System.Collections.Generic.List[string]]::new()
    foreach ($steamRoot in (Get-SteamRoots)) {
        if (-not (Test-Path -LiteralPath $steamRoot -PathType Container)) { continue }

        $searchRoots = [System.Collections.Generic.List[string]]::new()
        $searchRoots.Add($steamRoot)

        $libraryFile = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $libraryFile) {
            $vdf = Get-Content -LiteralPath $libraryFile -Raw
            foreach ($m in [regex]::Matches($vdf, '"path"\s+"([^"]+)"')) {
                $searchRoots.Add($m.Groups[1].Value.Replace('\\', '\'))
            }
        }

        foreach ($searchRoot in $searchRoots) {
            $candidate = Join-Path $searchRoot 'steamapps\common\Team Fortress 2'
            if ($tried.Contains($candidate)) { continue }
            $tried.Add($candidate)
            if (Test-Tf2Install $candidate) {
                # Normalise to the on-disk casing so printed paths match what the user sees.
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }
    }

    throw ("Could not find Team Fortress 2. Looked in:`n  " +
        ($tried -join "`n  ") +
        "`nPass the install root explicitly with -TfPath.")
}

function Assert-Tf2NotRunning {
    $running = @(Get-Process -Name 'tf', 'tf_win64' -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        $names = ($running | ForEach-Object { "$($_.Name) (pid $($_.Id))" }) -join ', '
        throw "Team Fortress 2 is still running: $names`nClose the game and run this again."
    }
}

function Test-DirectoryWritable {
    param([string] $Path)
    $probe = Join-Path $Path ('.write-test-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType File -Path $probe -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    } finally {
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    }
}

function Move-ToBackup {
    param(
        [string] $Path,
        [string] $BackupPath,
        [string] $Label
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "  $Label : nothing to back up ($Path not found)" -ForegroundColor DarkGray
        return $false
    }

    if ($PSCmdlet.ShouldProcess($Path, "Back up $Label to $BackupPath")) {
        # Create only the parent - if the destination itself existed, Move-Item would
        # nest the folder inside it (tf/custom/jumphud/jumphud).
        New-Item -ItemType Directory -Path (Split-Path -Parent $BackupPath) -Force | Out-Null

        # A running Steam client routinely holds a handle on something inside the game
        # folder, which blocks a directory rename but not a file-by-file copy. Retry the
        # rename, then fall back to copy + delete. Leftovers the delete could not remove
        # are corrected by the mirror that follows.
        $moved = $false
        for ($attempt = 1; $attempt -le 3 -and -not $moved; $attempt++) {
            try {
                Move-Item -LiteralPath $Path -Destination $BackupPath -Force -ErrorAction Stop
                $moved = $true
            } catch {
                if ($attempt -lt 3) {
                    Start-Sleep -Milliseconds 800
                    continue
                }
                Write-Host "  rename blocked, falling back to copy+delete" -ForegroundColor Yellow
                & robocopy $Path $BackupPath /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
                if ($LASTEXITCODE -ge 8) {
                    throw "robocopy backup failed (exit code $LASTEXITCODE) for $Path"
                }
                Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
                $moved = $true
            }
        }
    }
    return $true
}

function Invoke-DirectoryMirror {
    param([string] $From, [string] $To)

    New-Item -ItemType Directory -Path $To -Force | Out-Null

    # /MIR makes the destination match the source exactly, which is what clears out
    # files that upstream deleted between releases.
    $roboArgs = @(
        $From, $To,
        '/MIR', '/NFL', '/NDL', '/NJH', '/NJS', '/NP',
        '/R:1', '/W:1', '/COPY:DAT',
        '/XD'
    ) + $ExcludeDirs + @('/XF') + $ExcludeFiles

    & robocopy @roboArgs | Out-Null
    $code = $LASTEXITCODE
    if ($code -ge 8) {
        throw "robocopy failed (exit code $code) copying '$From' to '$To'."
    }
    if ($code -ge 2) {
        Write-Host "  Removed $code flag(s) worth of stale files from the old install." -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------

if ($ResetConfig -and $KeepConfig) {
    throw '-ResetConfig and -KeepConfig are mutually exclusive.'
}

$script:Source = if ($Source) {
    (Resolve-Path -LiteralPath $Source -ErrorAction Stop).Path
} else {
    (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'jumphud') -ErrorAction Stop).Path
}

if (-not (Test-Path -LiteralPath (Join-Path $script:Source 'cfg\jh_setup.cfg'))) {
    throw "Source does not look like a JumpHUD folder (missing cfg\jh_setup.cfg): $script:Source"
}

$tfRoot = Resolve-Tf2Install -ExplicitPath $TfPath
Assert-Tf2NotRunning

$customDir = Join-Path $tfRoot 'tf\custom'
$hudDir = Join-Path $customDir 'jumphud'
$cfgDir = Join-Path $tfRoot 'tf\cfg\jumphud'

Write-Host ''
Write-Host 'JumpHUD installer' -ForegroundColor Cyan
Write-Host "  source     : $script:Source (v$(Get-JhVersion $script:Source))"
Write-Host "  install to : $tfRoot"
if (Test-Path -LiteralPath $hudDir) {
    Write-Host "  replacing  : existing install v$(Get-JhVersion $hudDir)" -ForegroundColor Yellow
}

if (-not (Test-DirectoryWritable $customDir)) {
    throw "Cannot write to '$customDir'. Re-run this script from an elevated PowerShell (Run as Administrator)."
}

if (-not $BackupRoot) {
    $BackupRoot = Join-Path $env:LOCALAPPDATA 'TF2-Jumphud-Backups'
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $BackupRoot $stamp

if ($SkipBackup) {
    Write-Host '  backups    : SKIPPED (-SkipBackup)' -ForegroundColor DarkYellow
}

Write-Host ''
Write-Host '1. Backing up' -ForegroundColor Cyan
if ($SkipBackup) {
    Write-Host '  skipped' -ForegroundColor DarkGray
} else {
    Write-Host "  -> $backupDir"
    $null = Move-ToBackup -Path $hudDir -BackupPath (Join-Path $backupDir 'tf\custom\jumphud') -Label 'tf/custom/jumphud'
    if ($ResetConfig) {
        $null = Move-ToBackup -Path $cfgDir -BackupPath (Join-Path $backupDir 'tf\cfg\jumphud') -Label 'tf/cfg/jumphud'
    } else {
        Write-Host '  tf/cfg/jumphud : kept (settings preserved)' -ForegroundColor DarkGray
    }
}

Write-Host ''
Write-Host '2. Installing HUD files' -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess($hudDir, "Mirror JumpHUD v$(Get-JhVersion $script:Source) from $script:Source")) {
    Invoke-DirectoryMirror -From $script:Source -To $hudDir
    Write-Host "  installed v$(Get-JhVersion $script:Source) to $hudDir" -ForegroundColor Green
}

Write-Host ''
Write-Host '3. Settings folder' -ForegroundColor Cyan
if ($ResetConfig) {
    Write-Host '  tf/cfg/jumphud was reset. JumpHUD will write defaults on first launch.' -ForegroundColor Green
} else {
    Write-Host '  tf/cfg/jumphud left untouched (use -ResetConfig to reset after a major update).' -ForegroundColor DarkGray
}

# jh_setup's animations manifest loads this every launch and spews
# "Couldn't find script file" until it exists. It is only written when the
# hitmarker setting is changed in the menu, so after a config reset it is
# missing until you happen to open that panel.
$animFile = Join-Path $cfgDir 'jh_hitmarker_animation.txt'
if (-not (Test-Path -LiteralPath $animFile)) {
    if ($PSCmdlet.ShouldProcess($animFile, 'Create empty hitmarker animation bindings file')) {
        New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
        New-Item -ItemType File -Path $animFile -Force | Out-Null
        Write-Host '  created jh_hitmarker_animation.txt (silences a startup error)' -ForegroundColor Green
    }
}

Write-Host ''
Write-Host 'Done. Launch TF2.' -ForegroundColor Cyan
Write-Host '  * If the JumpHUD X button does nothing, add "exec jh_setup" to tf\cfg\autoexec.cfg.'
Write-Host '  * For input display / pipe timer / mirror world, rebind keys via the in-game settings menu.'
if (-not $SkipBackup) {
    Write-Host "  * Previous files saved to: $backupDir"
}
Write-Host ''
