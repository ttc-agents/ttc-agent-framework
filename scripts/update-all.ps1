<#
.SYNOPSIS
  TTC Agent Framework — pull latest for framework, all agents, and shared repos.

.DESCRIPTION
  Windows native counterpart to update-all.sh. Iterates over:
    - the framework (ttc-agent-framework)
    - every agent under <InstallRoot>/Agents/
    - shared repos under <InstallRoot>/{Claude-Config,brand,Tools/mcp-proton}
  and refreshes the runtime KB scripts under "Claude Folder/".

  Default mode: fast-forward pulls only; skips repos with uncommitted changes
  with a warning.

  -Force flag: fetches origin and hard-resets every repo to its tracked
  branch, discarding local working-tree changes. Use this if you've been
  reading Mini-side commits via OneDrive/file-share and your local index
  drifted, or after a Mac mini auto-commit pushed state you want to land
  cleanly.

  Windows is treated as a standard git client — no Syncthing pool means no
  Mini pre-flight, unlike the Mac variant.

.PARAMETER Force
  Discard local working-tree changes and reset every repo to origin.

.PARAMETER InstallRoot
  Override install root. Default: $env:USERPROFILE\AI-Vault

.EXAMPLE
  .\update-all.ps1
  Default: fast-forward pulls, skip dirty repos.

.EXAMPLE
  .\update-all.ps1 -Force
  Reset every repo to its origin tracked branch.
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [string]$InstallRoot = "$env:USERPROFILE\AI-Vault"
)

$ErrorActionPreference = "Stop"

function Write-Log     { param($m) Write-Host "[update] $m" -ForegroundColor Cyan }
function Write-Ok      { param($m) Write-Host "[ok]     $m" -ForegroundColor Green }
function Write-WarnMsg { param($m) Write-Host "[warn]   $m" -ForegroundColor Yellow }
function Write-ResetMsg { param($m) Write-Host "[reset]  $m" -ForegroundColor Magenta }

function Get-DefaultBranch {
    param([string]$RepoDir)
    $b = git -C $RepoDir symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $b) {
        return ($b -replace '^origin/','')
    }
    return "main"
}

function Update-Repo {
    param([string]$Dir)
    if (-not (Test-Path (Join-Path $Dir ".git"))) { return }

    # Both default and -Force now go through Sync-RepoToOrigin: fetch -> guarded
    # reset --hard origin/<branch> -> re-materialise. This is what finally lets a
    # *materialised* (always-dirty) repo receive new commits and files (e.g. KB
    # docs) — the old default mode skipped every dirty repo and never pulled.
    if (Get-Command Sync-RepoToOrigin -ErrorAction SilentlyContinue) {
        if ($Force) { Sync-RepoToOrigin -Target $Dir -Discard } else { Sync-RepoToOrigin -Target $Dir }
        return
    }

    # Fallback (helper missing): preserve the previous best-effort behaviour.
    $name = Split-Path $Dir -Leaf
    $dirty = -not [string]::IsNullOrWhiteSpace((git -C $Dir status --porcelain 2>$null))
    if ($Force) {
        $branch = Get-DefaultBranch -RepoDir $Dir
        git -C $Dir fetch --quiet origin 2>$null
        if ($LASTEXITCODE -eq 0) {
            git -C $Dir reset --hard "origin/$branch" --quiet 2>$null
            Write-Ok "  $name -- reset to origin/$branch"
        } else { Write-WarnMsg "  $name -- fetch failed" }
        return
    }
    if ($dirty) {
        Write-WarnMsg "  $name -- uncommitted changes, skipping (use -Force to discard and reset)"
        return
    }
    git -C $Dir pull --ff-only --quiet 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Ok "  $name -- updated" } else { Write-WarnMsg "  $name -- pull failed (non-FF?)" }
}

$FrameworkDir = Join-Path $InstallRoot "ttc-agent-framework"
$AgentsDir    = Join-Path $InstallRoot "Agents"
$KbRuntimeDir = Join-Path $InstallRoot "Claude Folder"

# Source the shared sync helper before any Update-Repo call.
$env:TTC_AI_VAULT      = $InstallRoot
$env:TTC_FRAMEWORK_DIR = $FrameworkDir
$env:TTC_HOME          = $env:USERPROFILE
$SyncHelper = Join-Path $FrameworkDir "scripts\portability\sync-repo.ps1"
if (Test-Path $SyncHelper) {
    . $SyncHelper
} else {
    Write-WarnMsg "sync helper not found at $SyncHelper -- falling back to ff-only pulls"
}

Write-Host ""
if ($Force) {
    Write-Host "=== TTC Agent Framework -- Update All (FORCE: GitHub is truth) ===" -ForegroundColor Cyan
    Write-WarnMsg "  Force mode: local working-tree changes will be DISCARDED."
    Write-WarnMsg "  Gitignored files (working/, .venv, *.log) are kept."
} else {
    Write-Host "=== TTC Agent Framework -- Update All ===" -ForegroundColor Cyan
}
Write-Host ""

# 1. Framework
Write-Log "Updating framework..."
Update-Repo -Dir $FrameworkDir

# 2. All agents
Write-Host ""
Write-Log "Updating agents..."
if (Test-Path $AgentsDir) {
    Get-ChildItem -Path $AgentsDir -Directory | ForEach-Object {
        Update-Repo -Dir $_.FullName
    }
}

# 3. Shared repos (Claude-Config, brand, Tools/mcp-proton)
Write-Host ""
Write-Log "Updating shared repos..."
foreach ($shared in @(
    (Join-Path $InstallRoot "Claude-Config"),
    (Join-Path $InstallRoot "brand"),
    (Join-Path $InstallRoot "Tools\mcp-proton")
)) {
    if (Test-Path (Join-Path $shared ".git")) {
        Update-Repo -Dir $shared
    }
}

# 4. Refresh runtime KB scripts from the framework's versioned copy
Write-Host ""
Write-Log "Refreshing runtime KB scripts..."
$KbSrc     = Join-Path $FrameworkDir "scripts\kb"
$KbDocsSrc = Join-Path $FrameworkDir "docs\KB_CONVENTIONS.md"
if (Test-Path $KbSrc) {
    New-Item -ItemType Directory -Path $KbRuntimeDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $InstallRoot "docs") -Force | Out-Null
    foreach ($f in @(
        "kb_bootstrap_customer.sh",
        "kb_refresh_customer.sh",
        "kb_discover_customers.sh",
        "kb_discover_customers.py",
        "convert_to_knowledge_base.py",
        "kb_vectorize.py"
    )) {
        $src = Join-Path $KbSrc $f
        if (Test-Path $src) {
            Copy-Item -Path $src -Destination $KbRuntimeDir -Force
        }
    }
    Write-Ok "  KB scripts -> $KbRuntimeDir\"
}
if (Test-Path $KbDocsSrc) {
    Copy-Item -Path $KbDocsSrc -Destination (Join-Path $InstallRoot "docs\KB_CONVENTIONS.md") -Force
    Write-Ok "  KB_CONVENTIONS.md -> $InstallRoot\docs\"
}

# 5. Materialise {{AI_VAULT}} / {{HOME}} placeholders in newly-pulled files.
# Idempotent -- files with no placeholders are skipped.
Write-Host ""
Write-Log "Materialising path placeholders..."
$Materialiser = Join-Path $FrameworkDir "scripts\portability\materialise-paths.ps1"
if (Test-Path $Materialiser) {
    $env:TTC_AI_VAULT = $InstallRoot
    $env:TTC_HOME     = $env:USERPROFILE
    if (Test-Path $AgentsDir) {
        Get-ChildItem -Path $AgentsDir -Directory | ForEach-Object {
            if (Test-Path (Join-Path $_.FullName ".git")) {
                try { & $Materialiser -Path $_.FullName | Out-Null } catch { Write-WarnMsg "  materialise failed for $($_.Name): $_" }
            }
        }
    }
    foreach ($shared in @(
        (Join-Path $InstallRoot "Claude-Config"),
        (Join-Path $InstallRoot "brand"),
        (Join-Path $InstallRoot "Tools\mcp-proton")
    )) {
        if (Test-Path (Join-Path $shared ".git")) {
            try { & $Materialiser -Path $shared | Out-Null } catch { Write-WarnMsg "  materialise failed for ${shared}: $_" }
        }
    }
    # Non-repo directories that still need materialising (sanitised content arrives
    # via Syncthing from a machine where the path IS in a repo). Run unconditionally
    # -- materialiser is idempotent and only rewrites files that have placeholders.
    foreach ($nonrepo in @(
        (Join-Path $InstallRoot "Claude Folder")
    )) {
        if (Test-Path $nonrepo) {
            try { & $Materialiser -Path $nonrepo | Out-Null } catch { Write-WarnMsg "  materialise failed for ${nonrepo}: $_" }
        }
    }
    Write-Ok "  Placeholders materialised across agents + shared repos + Claude Folder"
} else {
    Write-WarnMsg "  Materialiser not found at $Materialiser -- skipped"
}

Write-Host ""
Write-Ok "Update complete. System-prompt changes take effect in the next conversation."
Write-Host ""
