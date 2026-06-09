<#
.SYNOPSIS
  Bring a managed repo's working tree to origin truth, safely. PowerShell
  counterpart to sync-repo.sh.

.DESCRIPTION
  Dot-source this file, then call:  Sync-RepoToOrigin -Target <dir> [-Discard]

  Managed repos are kept *materialised* on disk (path placeholders replaced
  with real paths), so the working tree is permanently dirty vs. the committed
  (placeholder) form on origin. `git pull --ff-only` therefore always fails or
  is skipped, so new commits — and new files like Knowledge Base docs — never
  arrive. The materialised dirt is reproducible derived state, not authored
  content, so the safe primitive is: fetch -> reset --hard origin/<branch> ->
  re-materialise. Errors are reported, never swallowed. We do NOT stash/pop
  (that conflicts on every path-bearing line).

  Guards (skipped by -Discard, which restores the old destructive -Force):
    1. Unpushed local commits  -> reset skipped, only re-materialise.
    2. Authored working-tree edits, detected by round-tripping through the
       sanitiser and diffing vs HEAD. The PowerShell sanitiser does not exist
       (authoring happens on the Mac), so on Windows Guard 2 auto-skips and
       Guard 1 suffices — consumer Windows installs carry no authored content.
#>

function Write-SrOk      { param($m) Write-Host "[ok]     $m" -ForegroundColor Green }
function Write-SrWarn    { param($m) Write-Host "[warn]   $m" -ForegroundColor Yellow }

function Get-SrDefaultBranch {
    param([string]$Dir)
    $b = git -C $Dir symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $b) { return ($b -replace '^origin/','') }
    return "main"
}

function Invoke-SrMaterialise {
    param([string]$Dir, [string]$Materialiser)
    if (-not (Test-Path $Materialiser)) {
        Write-SrWarn "  $(Split-Path $Dir -Leaf) -- materialiser not found at $Materialiser; left in committed form"
        return
    }
    try { & $Materialiser -Path $Dir | Out-Null }
    catch { Write-SrWarn "  $(Split-Path $Dir -Leaf) -- materialise-paths failed: $_" }
}

function Sync-RepoToOrigin {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Target,
        [switch]$Discard
    )
    if (-not (Test-Path (Join-Path $Target ".git"))) { return }   # not a git repo
    $name = Split-Path $Target -Leaf

    # Resolve materialiser + sanitiser from the install root the callers know
    # and export (TTC_AI_VAULT / TTC_FRAMEWORK_DIR), falling back to defaults.
    $aivault = if ($env:TTC_AI_VAULT) { $env:TTC_AI_VAULT }
               elseif ($env:TTC_INSTALL_ROOT) { $env:TTC_INSTALL_ROOT }
               else { Join-Path $env:USERPROFILE "AI-Vault" }
    $fwDir = if ($env:TTC_FRAMEWORK_DIR) { $env:TTC_FRAMEWORK_DIR } else { Join-Path $aivault "ttc-agent-framework" }
    $materialiser = Join-Path $fwDir "scripts\portability\materialise-paths.ps1"
    $sanitiser    = Join-Path $aivault "scripts\portability\sanitise-paths.ps1"

    # Fetch -- surface failure, never reset against a stale remote-tracking ref.
    git -C $Target fetch --quiet origin 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-SrWarn "  $name -- fetch failed (offline / SSH down?); repo left unchanged"
        return
    }
    $br = Get-SrDefaultBranch -Dir $Target

    if (-not $Discard) {
        # Guard 1 -- protect unpushed authored commits.
        $ahead = (git -C $Target rev-list --count "origin/$br..HEAD" 2>$null)
        if ($LASTEXITCODE -eq 0 -and [int]$ahead -gt 0) {
            Write-SrWarn "  $name -- $ahead local commit(s) not on origin; skipping reset (auto-commit owns these), re-materialising only"
            Invoke-SrMaterialise -Dir $Target -Materialiser $materialiser
            return
        }
        # Guard 2 -- authored working-tree edits (only where a PS sanitiser exists).
        if (Test-Path $sanitiser) {
            try { & $sanitiser -Path $Target | Out-Null } catch { }
            git -C $Target diff --quiet HEAD -- . 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-SrWarn "  $name -- authored edits present; skipping reset (leaving for auto-commit), re-materialising"
                Invoke-SrMaterialise -Dir $Target -Materialiser $materialiser
                return
            }
        }
    }

    # Reset to origin truth. reset --hard leaves gitignored/untracked files
    # alone; we deliberately do NOT git-clean (2026-06-09 gotcha).
    $before = (git -C $Target rev-parse --short HEAD 2>$null)
    if ($before) { $before = $before.Trim() } else { $before = '?' }
    git -C $Target reset --hard "origin/$br" --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-SrWarn "  $name -- reset to origin/$br failed; re-materialising in place"
        Invoke-SrMaterialise -Dir $Target -Materialiser $materialiser
        return
    }
    $after = (git -C $Target rev-parse --short HEAD 2>$null).Trim()
    if ($before -ne $after) {
        Write-SrOk "  $name -- synced to origin/$br ($before -> $after)"
    } else {
        Write-SrOk "  $name -- already at origin/$br ($after)"
    }
    Invoke-SrMaterialise -Dir $Target -Materialiser $materialiser
}
