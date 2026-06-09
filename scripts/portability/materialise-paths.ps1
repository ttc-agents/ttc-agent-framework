# materialise-paths.ps1 -- replace portable placeholders with this machine's real paths
#
# Reverse direction (fresh clone on user machine -> ready-to-run).
# Windows / PowerShell 5.1 compatible. ASCII, no BOM.
#
# Substitutions:
#   {{AI_VAULT}}         -> $env:TTC_AI_VAULT (or $env:USERPROFILE\AI-Vault)
#   {{HOME}}             -> $env:TTC_HOME     (or $env:USERPROFILE)
#   {{ONEDRIVE_SHARED}}  -> probed per host:
#                              <home>/TTC Global/Joerg Pietzsch -            (team member, default Windows SharedLibraries mount)
#                           OR <home>/OneDrive - TTC Global/                 (Joerg, owner — personal mount)
#                          The placeholder syntax {{ONEDRIVE_SHARED}}/<Folder>/...
#                          ensures the suffix joins cleanly with either form.
#                          Probe tracer folder: "Sales".
#
# Idempotent.
#
# Usage:
#   .\materialise-paths.ps1 -Path C:\path\to\agent-repo
#   .\materialise-paths.ps1 -Path C:\path\to\file.md
#
# Environment overrides:
#   $env:TTC_AI_VAULT, $env:TTC_HOME, $env:TTC_ONEDRIVE_SHARED (skips probe)

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string[]] $Path
)

# Survive native stderr noise from `file`/`sed`-style helpers if any future
# step shells out. See PowerShell installer guidance in MEMORY.
$ErrorActionPreference = 'Continue'

# Resolve the user's home root. On Windows: $env:USERPROFILE. On Mac/Linux
# (for local testing): $env:HOME. TTC_HOME overrides both.
if ($env:TTC_HOME) {
    $HomeRoot = $env:TTC_HOME
} elseif ($env:USERPROFILE) {
    $HomeRoot = $env:USERPROFILE
} elseif ($env:HOME) {
    $HomeRoot = $env:HOME
} else {
    Write-Error "Cannot resolve user home: set TTC_HOME, USERPROFILE, or HOME."
    exit 1
}

# Resolve AI-Vault root. TTC_AI_VAULT overrides; default: <home>/AI-Vault.
if ($env:TTC_AI_VAULT) {
    $AiVault = $env:TTC_AI_VAULT
} else {
    $AiVault = Join-Path $HomeRoot 'AI-Vault'
}

# Forward slashes are usable in PowerShell, Python, Node, and most build tools
# even on Windows. Keep paths forward-slashed to match the on-disk file content
# (which already uses forward slashes). This avoids backslash-escape headaches
# inside string literals, regexes, JSON, and Python code.
$AiVaultFwd  = $AiVault  -replace '\\', '/'
$HomeRootFwd = $HomeRoot -replace '\\', '/'

# Probe the OneDrive-shared mount on this machine.
# Common Windows variants for Joerg's shared folders:
#   Team member:  $env:USERPROFILE\TTC Global\Joerg Pietzsch - <Folder>
#                 (some setups also show as "OneDrive - SharedLibraries - TTC Global\...")
#   Joerg:        $env:USERPROFILE\OneDrive - TTC Global\<Folder>
# Probe tracer: "Sales" subfolder.
if ($env:TTC_ONEDRIVE_SHARED) {
    $OnedriveShared = $env:TTC_ONEDRIVE_SHARED
} elseif (Test-Path -LiteralPath (Join-Path $HomeRoot 'TTC Global/Joerg Pietzsch - Sales')) {
    # Team member (Win — shared folder mount)
    $OnedriveShared = Join-Path $HomeRoot 'TTC Global/Joerg Pietzsch - '
} elseif (Test-Path -LiteralPath (Join-Path $HomeRoot 'OneDrive - SharedLibraries - TTC Global/Joerg Pietzsch - Sales')) {
    # Alternative team-member Windows layout
    $OnedriveShared = Join-Path $HomeRoot 'OneDrive - SharedLibraries - TTC Global/Joerg Pietzsch - '
} elseif (Test-Path -LiteralPath (Join-Path $HomeRoot 'OneDrive - TTC Global/Sales')) {
    # Owner (Joerg) Windows variant
    $OnedriveShared = Join-Path $HomeRoot 'OneDrive - TTC Global/'
} else {
    # Fall back to most-common team layout — agent files will materialise to a path
    # that may not exist yet (e.g. share invite not accepted). Failure surfaces
    # at agent-runtime with a clear "folder not found" rather than corrupting paths.
    $OnedriveShared = Join-Path $HomeRoot 'TTC Global/Joerg Pietzsch - '
}
$OnedriveSharedFwd = $OnedriveShared -replace '\\', '/'

# File extensions we treat as text.
$TextExtensions = @(
    '.md', '.py', '.sh', '.json', '.ps1', '.yml', '.yaml',
    '.toml', '.txt', '.cfg', '.ini', '.plist', '.xml',
    '.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs'
)

# Directory names to prune.
$PruneDirs = @('.git', '__pycache__', '.venv', 'node_modules')

function Invoke-MaterialiseFile {
    param([string] $FilePath)

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { return }

    $ext = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    if ($TextExtensions -notcontains $ext) { return }

    try {
        # Read as UTF-8 (preserves BOM if present; we won't introduce one).
        $content = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
    } catch {
        Write-Warning "read failed: $FilePath ($_)"
        return
    }

    if ($content -notmatch '\{\{(AI_VAULT|HOME|ONEDRIVE_SHARED)\}\}') { return }

    # Order: {{ONEDRIVE_SHARED}}/ FIRST (its substitution already contains a fully-
    # resolved $HOME, so no inner placeholder to re-expand).
    $newContent = $content.Replace('{{ONEDRIVE_SHARED}}/', $OnedriveSharedFwd) `
                          .Replace('{{AI_VAULT}}', $AiVaultFwd) `
                          .Replace('{{HOME}}', $HomeRootFwd)

    if ($newContent -eq $content) { return }

    try {
        # Write back as UTF-8 without BOM.
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($FilePath, $newContent, $utf8NoBom)
        Write-Host "materialised: $FilePath"
    } catch {
        Write-Warning "write failed: $FilePath ($_)"
    }
}

function Invoke-MaterialiseDir {
    param([string] $DirPath)

    Get-ChildItem -LiteralPath $DirPath -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        $skip = $false
        # Skip if any parent dir is in $PruneDirs
        $parent = $_.Directory
        while ($parent -ne $null) {
            if ($PruneDirs -contains $parent.Name) { $skip = $true; break }
            $parent = $parent.Parent
        }
        if (-not $skip) {
            Invoke-MaterialiseFile -FilePath $_.FullName
        }
    }
}

Write-Host "AI_VAULT placeholder        -> $AiVaultFwd"
Write-Host "HOME placeholder            -> $HomeRootFwd"
Write-Host "ONEDRIVE_SHARED placeholder -> $OnedriveSharedFwd"

foreach ($p in $Path) {
    if (Test-Path -LiteralPath $p -PathType Container) {
        Invoke-MaterialiseDir -DirPath $p
    } elseif (Test-Path -LiteralPath $p -PathType Leaf) {
        Invoke-MaterialiseFile -FilePath $p
    } else {
        Write-Warning "skip (not file/dir): $p"
    }
}
