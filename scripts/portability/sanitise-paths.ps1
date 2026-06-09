# sanitise-paths.ps1 -- replace THIS machine's real paths with portable placeholders
# SANITISE-SKIP -- this file documents/does the substitution; must survive.
#
# Forward direction (ready-to-run tree -> GitHub-neutral). The exact inverse of
# materialise-paths.ps1: it resolves the SAME real-path strings (via the same
# TTC_AI_VAULT / TTC_HOME / OneDrive-probe logic) and replaces them back with
# {{AI_VAULT}} / {{HOME}} / {{ONEDRIVE_SHARED}}. Parameterised by the current
# machine (NOT hardcoded to any user), so it sanitises correctly on any host.
# Windows / PowerShell 5.1 compatible. ASCII, no BOM. Idempotent.
#
# Used by sync-repo.ps1 Guard 2 to detect genuine authored edits vs reproducible
# materialisation, WITHOUT mutating the live tree (it runs on temp copies).
#
# Usage:
#   .\sanitise-paths.ps1 -Path C:\path\to\repo
#   .\sanitise-paths.ps1 -Path C:\path\to\file.md
# Environment overrides: $env:TTC_AI_VAULT, $env:TTC_HOME, $env:TTC_ONEDRIVE_SHARED

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string[]] $Path
)

$ErrorActionPreference = 'Continue'

# --- Resolve this machine's real paths (identical logic to materialise-paths.ps1) ---
if ($env:TTC_HOME)            { $HomeRoot = $env:TTC_HOME }
elseif ($env:USERPROFILE)     { $HomeRoot = $env:USERPROFILE }
elseif ($env:HOME)            { $HomeRoot = $env:HOME }
else { Write-Error "Cannot resolve user home: set TTC_HOME, USERPROFILE, or HOME."; exit 1 }

if ($env:TTC_AI_VAULT) { $AiVault = $env:TTC_AI_VAULT } else { $AiVault = Join-Path $HomeRoot 'AI-Vault' }

$AiVaultFwd  = $AiVault  -replace '\\', '/'
$HomeRootFwd = $HomeRoot -replace '\\', '/'

# Probe DEFENSIVELY. A Test-Path that throws (odd mount / bad drive) or a probe
# miss must NEVER leave $OnedriveShared empty — an empty replace target below
# would throw and abort the WHOLE substitution, leaving every path un-reversed.
# Use string concat (not Join-Path, which resolves the drive and can throw).
$OnedriveShared = $env:TTC_ONEDRIVE_SHARED
if (-not $OnedriveShared) {
    foreach ($cand in @(
        @("$HomeRoot\TTC Global\Joerg Pietzsch - Sales",                              "$HomeRoot\TTC Global\Joerg Pietzsch - "),
        @("$HomeRoot\OneDrive - SharedLibraries - TTC Global\Joerg Pietzsch - Sales", "$HomeRoot\OneDrive - SharedLibraries - TTC Global\Joerg Pietzsch - "),
        @("$HomeRoot\OneDrive - TTC Global\Sales",                                    "$HomeRoot\OneDrive - TTC Global\")
    )) {
        try { if (Test-Path -LiteralPath $cand[0]) { $OnedriveShared = $cand[1]; break } } catch { }
    }
}
if (-not $OnedriveShared) { $OnedriveShared = "$HomeRoot\TTC Global\Joerg Pietzsch - " }
$OnedriveSharedFwd = $OnedriveShared -replace '\\', '/'

$TextExtensions = @('.md','.py','.sh','.json','.ps1','.yml','.yaml','.toml','.txt','.cfg','.ini','.plist','.xml','.ts','.tsx','.js','.jsx','.mjs','.cjs')
$PruneDirs = @('.git','__pycache__','.venv','node_modules')

function Invoke-SanitiseFile {
    param([string] $FilePath)
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { return }
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    if ($TextExtensions -notcontains $ext) { return }

    try { $content = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8) }
    catch { Write-Warning "read failed: $FilePath ($_)"; return }

    # SANITISE-SKIP self-protection: files that legitimately carry literal real
    # paths (this file, the materialiser) opt out via the marker in their head.
    $head = ($content -split "`n" | Select-Object -First 50) -join "`n"
    if ($head -match '#\s*SANITISE-SKIP') { return }

    # Reverse-order replace: ONEDRIVE and AI_VAULT before HOME (both contain the
    # home prefix). Forward-slash form first (what the materialiser emits), then
    # the raw backslash form, defensively. Each replace is GUARDED against an
    # empty target: String.Replace("", x) throws, and a chained throw would abort
    # the whole substitution and leave EVERY path un-reversed (the bug that made
    # Guard 2 flag every materialised file as "authored").
    $new = $content
    foreach ($sub in @(
        @($OnedriveSharedFwd, '{{ONEDRIVE_SHARED}}/'),
        @($AiVaultFwd,        '{{AI_VAULT}}'),
        @($HomeRootFwd,       '{{HOME}}'),
        @($OnedriveShared,    '{{ONEDRIVE_SHARED}}/'),
        @($AiVault,           '{{AI_VAULT}}'),
        @($HomeRoot,          '{{HOME}}')
    )) {
        if (-not [string]::IsNullOrEmpty($sub[0])) { $new = $new.Replace($sub[0], $sub[1]) }
    }

    if ($new -eq $content) { return }
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($FilePath, $new, $utf8NoBom)
        Write-Host "sanitised: $FilePath"
    } catch { Write-Warning "write failed: $FilePath ($_)" }
}

function Invoke-SanitiseDir {
    param([string] $DirPath)
    Get-ChildItem -LiteralPath $DirPath -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        $skip = $false; $parent = $_.Directory
        while ($parent -ne $null) {
            if ($PruneDirs -contains $parent.Name) { $skip = $true; break }
            $parent = $parent.Parent
        }
        if (-not $skip) { Invoke-SanitiseFile -FilePath $_.FullName }
    }
}

foreach ($p in $Path) {
    if (Test-Path -LiteralPath $p -PathType Container) { Invoke-SanitiseDir -DirPath $p }
    elseif (Test-Path -LiteralPath $p -PathType Leaf) { Invoke-SanitiseFile -FilePath $p }
    else { Write-Warning "skip (not file/dir): $p" }
}
