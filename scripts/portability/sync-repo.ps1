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

# Decide whether the tree holds genuine authored content (beyond materialisation)
# WITHOUT mutating the live tree (mirrors bash _sr_has_authored_edits / H1).
# Copies changed tracked files to a temp dir, sanitises the COPIES, and compares
# each against its HEAD blob via `git diff --no-index` (byte-faithful, and
# --ignore-cr-at-eol so Windows autocrlf checkouts don't read as authored).
function Test-SrAuthoredEdits {
    param([string]$Dir, [string]$Sanitiser)
    $names = @(git -C $Dir diff --name-only HEAD 2>$null | Where-Object { $_ })
    if ($names.Count -eq 0) { return $false }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("srchk_" + [guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $authored = $false
    try {
        foreach ($f in $names) {
            $src = Join-Path $Dir $f
            if (-not (Test-Path -LiteralPath $src)) { $authored = $true; break }   # deleted tracked = authored
            $dest = Join-Path $tmp $f
            New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $src -Destination $dest -Force
        }
        if (-not $authored) {
            & $Sanitiser -Path $tmp | Out-Null
            $headFile = Join-Path $tmp "__headblob.tmp"
            foreach ($f in $names) {
                $dest = Join-Path $tmp $f
                if (-not (Test-Path -LiteralPath $dest)) { continue }
                # Byte-faithful extraction of the HEAD blob via cmd redirection
                # (the PS pipeline would mangle encoding/newlines).
                & cmd /c "git -C `"$Dir`" show `"HEAD:$f`" > `"$headFile`" 2>nul"
                git diff --no-index --quiet --ignore-cr-at-eol -- "$headFile" "$dest" 2>$null
                if ($LASTEXITCODE -ne 0) { $authored = $true; break }
            }
        }
    } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    return $authored
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
    # Sanitiser ships with the framework (so Guard 2 works on Windows too);
    # fall back to the AI-Vault-root copy used by the Mac auto-commit pipeline.
    $sanitiser    = Join-Path $fwDir "scripts\portability\sanitise-paths.ps1"
    if (-not (Test-Path $sanitiser)) {
        $altSan = Join-Path $aivault "scripts\portability\sanitise-paths.ps1"
        if (Test-Path $altSan) { $sanitiser = $altSan }
    }

    # Fetch -- surface failure, never reset against a stale remote-tracking ref.
    git -C $Target fetch --quiet origin 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-SrWarn "  $name -- fetch failed (offline / SSH down?); repo left unchanged"
        return
    }
    $br = Get-SrDefaultBranch -Dir $Target

    if (-not $Discard) {
        # Guard 1 -- protect unpushed authored commits.
        $ahead = (git -C $Target rev-list --count "origin/$br..HEAD" 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($ahead) -and [int]$ahead -gt 0) {
            Write-SrWarn "  $name -- $ahead local commit(s) not on origin; skipping reset (auto-commit owns these), re-materialising only"
            Invoke-SrMaterialise -Dir $Target -Materialiser $materialiser
            return
        }
        # Guard 2 -- authored working-tree edits. NON-MUTATING: sanitises temp
        # copies, never the live tree (W1 ships a PS sanitiser so this now runs
        # on Windows too, not just the Mac).
        if ((Test-Path $sanitiser) -and (Test-SrAuthoredEdits -Dir $Target -Sanitiser $sanitiser)) {
            Write-SrWarn "  $name -- authored edits present; skipping reset (leaving for auto-commit), re-materialising"
            Invoke-SrMaterialise -Dir $Target -Materialiser $materialiser
            return
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
    $after = (git -C $Target rev-parse --short HEAD 2>$null)
    if ($after) { $after = $after.Trim() } else { $after = '?' }
    if ($before -ne $after) {
        Write-SrOk "  $name -- synced to origin/$br ($before -> $after)"
    } else {
        Write-SrOk "  $name -- already at origin/$br ($after)"
    }
    # C2 -- advance submodules to the superproject's reset pointer (reset --hard
    # moves the gitlink but never updates the submodule tree).
    if (Test-Path (Join-Path $Target ".gitmodules")) {
        git -C $Target submodule update --init --recursive 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-SrWarn "  $name -- submodule update failed" }
    }
    Invoke-SrMaterialise -Dir $Target -Materialiser $materialiser
}
