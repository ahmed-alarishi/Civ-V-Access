<#
.SYNOPSIS
    Machine-agnostic locations for the dev scripts: the Civ V install, the
    Civ V SDK, the Civ V Documents tree, the VC9 / Windows SDK 7.0 toolchain,
    and LLVM. Mirrors tools/civ5_paths.py.

.DESCRIPTION
    Dot-source this (dlc-assembly.ps1 does, so its dot-sourcers get it too).
    Defines functions only. Every resolver honors an explicit path first, then
    an environment override, then the standard install locations.
#>

# The shell's Documents folder (CSIDL_PERSONAL), honoring redirection -- the
# same lookup the game makes, so a redirected or synced Documents still lands
# on the folder the game actually writes to.
function Get-Civ5DocsDir {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if ([string]::IsNullOrWhiteSpace($docs)) { throw 'Could not resolve the Documents folder.' }
    return (Join-Path $docs "My Games\Sid Meier's Civilization 5")
}

function Add-CandidateGameDir {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Path
    )
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $normalized = $Path.Trim().Trim('"')
        if (-not [string]::IsNullOrWhiteSpace($normalized) -and -not $List.Contains($normalized)) {
            $List.Add($normalized)
        }
    }
}

# Every Steam library root we can find: Steam's own install (HKCU, HKLM, the
# default Program Files location), then each library its libraryfolders.vdf lists.
function Get-SteamLibraryDirs {
    $roots = New-Object 'System.Collections.Generic.List[string]'
    try {
        $steam = Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($steam.SteamPath)) {
            Add-CandidateGameDir -List $roots -Path (($steam.SteamPath -replace '/', '\').TrimEnd('\'))
        }
    } catch { }
    foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        try {
            $hklmSteam = Get-ItemProperty -Path $key -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($hklmSteam.InstallPath)) {
                Add-CandidateGameDir -List $roots -Path $hklmSteam.InstallPath.TrimEnd('\')
            }
        } catch { }
    }
    if (${env:ProgramFiles(x86)}) {
        Add-CandidateGameDir -List $roots -Path (Join-Path ${env:ProgramFiles(x86)} 'Steam')
    }

    foreach ($root in @($roots)) {
        $libraryVdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path $libraryVdf) {
            $raw = Get-Content -Raw $libraryVdf
            foreach ($m in [regex]::Matches($raw, '"path"\s*"([^"]+)"')) {
                Add-CandidateGameDir -List $roots -Path ($m.Groups[1].Value -replace '\\\\', '\')
            }
        }
    }
    return ,$roots
}

function Resolve-CivVInstallDir {
    param([string]$ExplicitPath)

    $appName = "Sid Meier's Civilization V"
    $candidates = New-Object 'System.Collections.Generic.List[string]'

    Add-CandidateGameDir -List $candidates -Path $ExplicitPath
    Add-CandidateGameDir -List $candidates -Path $env:CIV5_DIR

    $uninstallKeys = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 8930',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 8930'
    )
    foreach ($key in $uninstallKeys) {
        try {
            $props = Get-ItemProperty -Path $key -ErrorAction Stop
            Add-CandidateGameDir -List $candidates -Path $props.InstallLocation
        } catch { }
    }

    foreach ($lib in (Get-SteamLibraryDirs)) {
        Add-CandidateGameDir -List $candidates -Path (Join-Path $lib "steamapps\common\$appName")
    }

    foreach ($candidate in $candidates) {
        $exe = Join-Path $candidate 'CivilizationV.exe'
        if (Test-Path $exe) {
            return (Resolve-Path $candidate).Path
        }
    }

    $searched = if ($candidates.Count -gt 0) { $candidates -join '; ' } else { '<none>' }
    throw "Could not find Civilization V install directory. Pass -GameDir or set CIV5_DIR. Searched: $searched"
}

# The Civ V Modding SDK's CvGameCoreSource folder (the root holding
# CvGameCoreDLL_Expansion2 and its sibling libs). CIV5_SDK_DIR names the SDK
# install root.
function Resolve-Civ5SdkSourceDir {
    param([string]$ExplicitPath)

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    Add-CandidateGameDir -List $candidates -Path $ExplicitPath
    if ($env:CIV5_SDK_DIR) {
        Add-CandidateGameDir -List $candidates -Path (Join-Path $env:CIV5_SDK_DIR 'CvGameCoreSource')
    }
    foreach ($lib in (Get-SteamLibraryDirs)) {
        Add-CandidateGameDir -List $candidates -Path (Join-Path $lib "steamapps\common\Sid Meier's Civilization V SDK\CvGameCoreSource")
    }

    foreach ($candidate in $candidates) {
        if (Test-Path (Join-Path $candidate 'CvGameCoreDLL_Expansion2')) {
            return (Resolve-Path $candidate).Path
        }
    }

    $searched = if ($candidates.Count -gt 0) { $candidates -join '; ' } else { '<none>' }
    throw "Could not find Civ V SDK source. Pass -SdkSourceDir, set CIV5_SDK_DIR, or install the SDK from Steam (`Sid Meier's Civilization V SDK`). Searched: $searched"
}

# VC9 (Visual C++ 2008 SP1) and Windows SDK 7.0, as laid down by
# build/sdk7-install/install.cmd. VC9_ROOT / WINSDK7_ROOT override the
# Program Files (x86) defaults.
function Get-Vc9Toolchain {
    $pf86 = ${env:ProgramFiles(x86)}
    $vsRoot = if ($env:VC9_ROOT) { Split-Path -Parent $env:VC9_ROOT } else { Join-Path $pf86 'Microsoft Visual Studio 9.0' }
    $vc9Root = if ($env:VC9_ROOT) { $env:VC9_ROOT } else { Join-Path $vsRoot 'VC' }
    $sdk7Root = if ($env:WINSDK7_ROOT) { $env:WINSDK7_ROOT } else { Join-Path $pf86 'Microsoft SDKs\Windows\v7.0' }
    return [pscustomobject]@{
        Vc9Root      = $vc9Root
        Sdk7Root     = $sdk7Root
        # cl.exe / link.exe load mspdb80.dll, msobj80.dll, mspdbcore.dll from
        # Common7\IDE\ rather than VC\bin\.
        VsCommon7Ide = Join-Path $vsRoot 'Common7\IDE'
    }
}

# Directory holding the LLVM tools (clang-cl, lld-link, llvm-objdump): the one
# already on PATH, else the LLVM installer's default under Program Files.
# Returns $null when LLVM is not found.
function Resolve-LlvmBin {
    $onPath = Get-Command clang-cl.exe -ErrorAction SilentlyContinue
    if ($onPath) { return (Split-Path -Parent $onPath.Source) }
    foreach ($base in @($env:ProgramW6432, $env:ProgramFiles)) {
        if ($base) {
            $bin = Join-Path $base 'LLVM\bin'
            if (Test-Path (Join-Path $bin 'clang-cl.exe')) { return $bin }
        }
    }
    return $null
}
