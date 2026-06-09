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

if ($env:TTC_ONEDRIVE_SHARED) {
    $OnedriveShared = $env:TTC_ONEDRIVE_SHARED
} elseif (Test-Path -LiteralPath (Join-Path $HomeRoot 'TTC Global/Joerg Pietzsch - Sales')) {
    $OnedriveShared = Join-Path $HomeRoot 'TTC Global/Joerg Pietzsch - '
} elseif (Test-Path -LiteralPath (Join-Path $HomeRoot 'OneDrive - SharedLibraries - TTC Global/Joerg Pietzsch - Sales')) {
    $OnedriveShared = Join-Path $HomeRoot 'OneDrive - SharedLibraries - TTC Global/Joerg Pietzsch - '
} elseif (Test-Path -LiteralPath (Join-Path $HomeRoot 'OneDrive - TTC Global/Sales')) {
    $OnedriveShared = Join-Path $HomeRoot 'OneDrive - TTC Global/'
} else {
    $OnedriveShared = Join-Path $HomeRoot 'TTC Global/Joerg Pietzsch - '
}
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
    # home prefix). Handle forward-slash (what the materialiser emits) AND the
    # raw backslash form, defensively. No-op when no real path is present.
    $new = $content.Replace($OnedriveSharedFwd, '{{ONEDRIVE_SHARED}}/').Replace($AiVaultFwd, '{{AI_VAULT}}').Replace($HomeRootFwd, '{{HOME}}')
    $new = $new.Replace($OnedriveShared, '{{ONEDRIVE_SHARED}}/').Replace($AiVault, '{{AI_VAULT}}').Replace($HomeRoot, '{{HOME}}')

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
