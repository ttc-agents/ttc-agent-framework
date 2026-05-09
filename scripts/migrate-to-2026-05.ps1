<#
.SYNOPSIS
  TTC Agent Framework — Windows migration to the 2026-05 layout.

.DESCRIPTION
  Idempotent one-shot migration for installations that pre-date the
  2026-05-09 cleanup. Bash sibling: scripts/migrate-to-2026-05.sh.

  What changed (relevant on Windows):

    1. PPTX agent renamed -> Docs agent. `apply pptx` is now `apply docs`.
       Repo: ttc-agent-pptx -> ttc-agent-docs. Old PPTX/ folder -> Docs/.

    2. mcp-proton MCP server moved out of <USERPROFILE>\Personal\ into
       <USERPROFILE>\AI-Vault\Tools\ and is now version-controlled
       (ttc-mcp-proton-server). Configs no longer carry plaintext
       PROTON_PASSWORD; the server reads it from 1Password
       ("Proton Bridge PWD" in vault "AI Vault").

    3. Brand assets split: logos + imagery now read from OneDrive directly
       via Agents/Docs/brand_paths.py. Standards memos live in their own
       repo: ttc-brand-standards -> AI-Vault/brand/.

    4. Git remotes switched HTTPS -> SSH (no more gh-token-expiry pain).

    5. ~/CLAUDE.md is a symlink to AI-Vault/Claude-Config/CLAUDE.md
       (and ~/.claude/commands -> Claude-Config/commands). Symlink
       creation on Windows requires either (a) Developer Mode enabled in
       Settings, or (b) running PowerShell as Administrator. The script
       falls back to a copy + warning if neither is available.

  Safe to run multiple times — every step checks current state first.

.PARAMETER DryRun
  Print what would change, but make no modifications.

.PARAMETER InstallRoot
  Override install root. Default: $env:USERPROFILE\AI-Vault

.EXAMPLE
  .\migrate-to-2026-05.ps1 -DryRun

.EXAMPLE
  .\migrate-to-2026-05.ps1
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$InstallRoot = "$env:USERPROFILE\AI-Vault"
)

$ErrorActionPreference = "Stop"
$GithubOrg = "ttc-agents"
$AgentsDir = Join-Path $InstallRoot "Agents"

function Write-Log     { param($m) Write-Host "[migrate] $m" -ForegroundColor Cyan }
function Write-Ok      { param($m) Write-Host "[ok]      $m" -ForegroundColor Green }
function Write-WarnMsg { param($m) Write-Host "[warn]    $m" -ForegroundColor Yellow }
function Write-Err     { param($m) Write-Host "[err]     $m" -ForegroundColor Red }
function Invoke-OrDry  {
    param([scriptblock]$Block, [string]$Description)
    if ($DryRun) {
        Write-Host "  DRY: $Description" -ForegroundColor DarkGray
    } else {
        & $Block
    }
}

Write-Host ""
Write-Host "=== TTC Agent Framework -- Migration to 2026-05 layout ===" -ForegroundColor Cyan
if ($DryRun) { Write-WarnMsg "DRY-RUN MODE -- no changes will be made" }
Write-Host "Install root: $InstallRoot"
Write-Host ""

# ─── 1. Verify SSH to GitHub works (everything depends on this) ─────────────
Write-Log "Step 1/8: Verify SSH access to GitHub"
$sshOut = & ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new git@github.com 2>&1
if ($sshOut -match "successfully authenticated") {
    Write-Ok "SSH to git@github.com works"
} else {
    Write-Err "SSH to GitHub is NOT working. Fix this first:"
    Write-Err "  ssh-keygen -t ed25519 -C `"$env:USERNAME@$env:COMPUTERNAME`""
    Write-Err "  gh ssh-key add `"$env:USERPROFILE\.ssh\id_ed25519.pub`" --title `"$env:USERNAME@$env:COMPUTERNAME ($(Get-Date -Format 'yyyy-MM'))`""
    Write-Err "Probe output was: $sshOut"
    exit 1
}

# ─── 2. Bootstrap: ensure ttc-agent-framework is present + current ──────────
# The migrate script normally lives inside the framework, but it can also be
# fetched standalone (`iwr ... migrate-to-2026-05.ps1 | iex`). Either way,
# every later step needs the framework's scripts on disk.
Write-Log "Step 2/8: Bootstrap framework"
$frameworkDir = Join-Path $InstallRoot "ttc-agent-framework"
if (Test-Path (Join-Path $frameworkDir ".git")) {
    Write-Log "  Framework present -- pulling latest"
    Invoke-OrDry -Description "git -C `"$frameworkDir`" pull --ff-only" -Block {
        & git -C $frameworkDir pull --ff-only --quiet 2>$null
        if ($LASTEXITCODE -ne 0) { Write-WarnMsg "  pull failed -- continuing" }
    }
} else {
    Write-Log "  Framework not yet on disk -- cloning"
    Invoke-OrDry -Description "git clone framework into $frameworkDir" -Block {
        New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
        & git clone "git@github.com:$GithubOrg/ttc-agent-framework.git" $frameworkDir
    }
}
Write-Ok "Framework at $frameworkDir"

# ─── 3. Convert HTTPS remotes to SSH ────────────────────────────────────────
Write-Log "Step 3/8: Convert HTTPS remotes to SSH"
$converted = 0
$repoDirs = @()
if (Test-Path $AgentsDir) {
    $repoDirs += Get-ChildItem -Path $AgentsDir -Directory | ForEach-Object { $_.FullName }
}
$repoDirs += @(
    (Join-Path $InstallRoot "ttc-agent-framework"),
    (Join-Path $InstallRoot "Claude-Config"),
    (Join-Path $InstallRoot "brand"),
    (Join-Path $InstallRoot "Tools\mcp-proton")
)
foreach ($d in $repoDirs) {
    if (-not (Test-Path (Join-Path $d ".git"))) { continue }
    $url = (& git -C $d remote get-url origin 2>$null) | Out-String
    $url = $url.Trim()
    if ($url -like "https://github.com/*") {
        $newUrl = $url -replace '^https://github\.com/','git@github.com:'
        Invoke-OrDry -Description "git -C `"$d`" remote set-url origin `"$newUrl`"" -Block {
            & git -C $d remote set-url origin $newUrl
        }
        $converted++
    }
}
Write-Ok "$converted remote(s) converted to SSH"

# ─── 3. Old PPTX agent → Docs agent ─────────────────────────────────────────
Write-Log "Step 4/8: Migrate PPTX agent to Docs"
$oldPptx = Join-Path $AgentsDir "PPTX"
$newDocs = Join-Path $AgentsDir "Docs"
if ((Test-Path $oldPptx) -and -not (Test-Path $newDocs)) {
    Write-Log "  Found old Agents\PPTX\ but no Agents\Docs\ -- cloning Docs from GitHub"
    Invoke-OrDry -Description "git clone git@github.com:$GithubOrg/ttc-agent-docs.git `"$newDocs`"" -Block {
        & git clone "git@github.com:$GithubOrg/ttc-agent-docs.git" $newDocs
    }
    Write-WarnMsg "  Old Agents\PPTX\ is preserved on disk for safety. Verify Docs\ has all"
    Write-WarnMsg "  your customer work, then remove it manually:"
    Write-WarnMsg "    Remove-Item -Recurse -Force `"$oldPptx`""
} elseif ((Test-Path $oldPptx) -and (Test-Path $newDocs)) {
    Write-WarnMsg "  Both Agents\PPTX\ and Agents\Docs\ exist. Verify Docs\ is current,"
    Write-WarnMsg "  then remove old PPTX dir manually: Remove-Item -Recurse -Force `"$oldPptx`""
} elseif (-not (Test-Path $newDocs)) {
    Write-Log "  Neither exists -- installing Docs"
    Invoke-OrDry -Description "git clone git@github.com:$GithubOrg/ttc-agent-docs.git `"$newDocs`"" -Block {
        & git clone "git@github.com:$GithubOrg/ttc-agent-docs.git" $newDocs
    }
}
Write-Ok "Docs agent in place"

# ─── 4. mcp-proton: ~/Personal → AI-Vault/Tools, into git, password to 1P ─
Write-Log "Step 5/8: Relocate + version mcp-proton"
$toolsProton = Join-Path $InstallRoot "Tools\mcp-proton"
$personalProton = Join-Path $env:USERPROFILE "Personal\mcp-proton"
if (-not (Test-Path (Join-Path $toolsProton ".git"))) {
    if ((Test-Path $personalProton) -and -not ((Get-Item $personalProton).LinkType)) {
        Write-Log "  Found old Personal\mcp-proton\ -- replacing with git clone"
        Invoke-OrDry -Description "create AI-Vault\Tools dir + remove old, clone new" -Block {
            New-Item -ItemType Directory -Path (Join-Path $InstallRoot "Tools") -Force | Out-Null
            if (Test-Path $toolsProton) { Remove-Item -Recurse -Force $toolsProton }
            & git clone "git@github.com:$GithubOrg/ttc-mcp-proton-server.git" $toolsProton
            if (Test-Path (Join-Path $toolsProton "package.json")) {
                Push-Location $toolsProton
                try { & npm install --silent } catch { Write-WarnMsg "  npm install issues" }
                Pop-Location
            }
            Remove-Item -Recurse -Force $personalProton
        }
    } else {
        Write-Log "  No existing Personal\mcp-proton -- fresh clone"
        Invoke-OrDry -Description "fresh clone mcp-proton + npm install" -Block {
            New-Item -ItemType Directory -Path (Join-Path $InstallRoot "Tools") -Force | Out-Null
            & git clone "git@github.com:$GithubOrg/ttc-mcp-proton-server.git" $toolsProton
            if (Test-Path (Join-Path $toolsProton "package.json")) {
                Push-Location $toolsProton
                try { & npm install --silent } catch { Write-WarnMsg "  npm install issues" }
                Pop-Location
            }
        }
    }
} else {
    Write-Ok "  Tools\mcp-proton already a git repo -- skipping clone"
}

# Strip PROTON_PASSWORD + rewrite mcp-proton path in known config files
Write-Log "  Patching configs (path -> AI-Vault\Tools, remove plaintext password)"
$cfgs = @(
    (Join-Path $env:USERPROFILE ".claude.json"),
    (Join-Path $env:APPDATA "Claude\claude_desktop_config.json"),
    (Join-Path $InstallRoot "Claude-Config\.mcp.json"),
    (Join-Path $InstallRoot "Claude-Config\claude_desktop_config.json")
)
$patched = 0
foreach ($cfg in $cfgs) {
    if (-not (Test-Path $cfg)) { continue }
    $content = Get-Content -Raw $cfg
    if ($content -match '/Personal/mcp-proton/' -or $content -match 'PROTON_PASSWORD') {
        if ($DryRun) {
            Write-Host "  DRY: would patch $cfg" -ForegroundColor DarkGray
            continue
        }
        try {
            $data = $content | ConvertFrom-Json -AsHashtable
            function Walk-Strip([object]$node) {
                if ($node -is [hashtable]) {
                    if ($node.ContainsKey('args') -and $node['args'] -is [array]) {
                        $node['args'] = @($node['args'] | ForEach-Object {
                            if ($_ -is [string]) {
                                $_ -replace '/Personal/mcp-proton/','/AI-Vault/Tools/mcp-proton/'
                            } else { $_ }
                        })
                    }
                    if ($node.ContainsKey('env') -and $node['env'] -is [hashtable] -and $node['env'].ContainsKey('PROTON_PASSWORD')) {
                        $node['env'].Remove('PROTON_PASSWORD')
                    }
                    foreach ($k in @($node.Keys)) { Walk-Strip $node[$k] }
                } elseif ($node -is [array]) {
                    foreach ($v in $node) { Walk-Strip $v }
                }
            }
            Walk-Strip $data
            ($data | ConvertTo-Json -Depth 50) | Set-Content -Path $cfg -Encoding UTF8
            $patched++
        } catch {
            Write-WarnMsg "  could not patch $cfg as JSON: $_"
        }
    }
}
Write-Ok "  Patched $patched config(s); password now resolved from 1Password at runtime"

$personalDir = Join-Path $env:USERPROFILE "Personal"
if ((Test-Path $personalDir) -and -not (Get-ChildItem -Path $personalDir -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.DS_Store' })) {
    Invoke-OrDry -Description "remove empty $personalDir" -Block {
        Remove-Item -Recurse -Force $personalDir
    }
    Write-Ok "  removed empty Personal dir"
}

# ─── 5. Brand-split: clone ttc-brand-standards, drop old imagery/logos ──────
Write-Log "Step 6/8: Brand split (logos + imagery -> OneDrive)"
$brandDir = Join-Path $InstallRoot "brand"
if (-not (Test-Path (Join-Path $brandDir ".git"))) {
    if (Test-Path $brandDir) {
        Write-Log "  Existing brand\ folder is not a git repo -- replacing with ttc-brand-standards"
        $tmp = "$brandDir.tmp"
        Invoke-OrDry -Description "rename + clone + restore manifest" -Block {
            Rename-Item -Path $brandDir -NewName (Split-Path $tmp -Leaf)
            & git clone "git@github.com:$GithubOrg/ttc-brand-standards.git" $brandDir
            $manifestSrc = Join-Path $tmp "manifest.json"
            if (Test-Path $manifestSrc) {
                Copy-Item -Path $manifestSrc -Destination $brandDir -Force
            }
            Remove-Item -Recurse -Force $tmp
        }
    } else {
        Invoke-OrDry -Description "fresh clone ttc-brand-standards" -Block {
            & git clone "git@github.com:$GithubOrg/ttc-brand-standards.git" $brandDir
        }
    }
} else {
    Write-Ok "  brand\ already a git repo -- pulling latest"
    Invoke-OrDry -Description "git -C `"$brandDir`" pull --ff-only" -Block {
        & git -C $brandDir pull --ff-only
    }
}

# Old local imagery + logos cache -> delete (assets read from OneDrive now)
foreach ($stale in @((Join-Path $brandDir "imagery"), (Join-Path $brandDir "logos"))) {
    if (Test-Path $stale) {
        Write-Log "  Removing stale local cache: $stale"
        Invoke-OrDry -Description "Remove-Item -Recurse -Force `"$stale`"" -Block {
            Remove-Item -Recurse -Force $stale
        }
    }
}

# Verify OneDrive central branding is mounted (path differs slightly per Windows install)
$onedriveBrand = $null
foreach ($candidate in @(
    "$env:USERPROFILE\TTCGlobal\Branding - TTC Global Branding",
    "$env:USERPROFILE\OneDrive - TTCGlobal\Branding - TTC Global Branding",
    "$env:OneDrive\Branding - TTC Global Branding"
)) {
    if (Test-Path $candidate) {
        $onedriveBrand = $candidate
        break
    }
}
if ($onedriveBrand) {
    Write-Ok "  OneDrive central branding mounted at: $onedriveBrand"
} else {
    Write-WarnMsg "  OneDrive central branding NOT found in any standard Windows path."
    Write-WarnMsg "  Sign in to OneDrive and sync the 'Branding - TTC Global Branding' library."
    Write-WarnMsg "  brand_paths.py uses a Mac-style path; you may need to add a Windows fallback."
}

# ─── 6. ~/CLAUDE.md → symlink to Claude-Config ──────────────────────────────
Write-Log "Step 7/8: Ensure CLAUDE.md is a symlink to Claude-Config"
$claudeMd  = Join-Path $env:USERPROFILE "CLAUDE.md"
$ccConfig  = Join-Path $InstallRoot "Claude-Config"
$targetMd  = Join-Path $ccConfig "CLAUDE.md"
if (-not (Test-Path (Join-Path $ccConfig ".git"))) {
    Write-Log "  Cloning Claude-Config (was missing)"
    Invoke-OrDry -Description "git clone Claude-Config" -Block {
        & git clone "git@github.com:$GithubOrg/ttc-agent-claude-config.git" $ccConfig
    }
}

function New-LinkOrCopy {
    param([string]$LinkPath, [string]$Target, [string]$Kind)
    $existing = Get-Item -LiteralPath $LinkPath -ErrorAction SilentlyContinue
    if ($existing -and $existing.LinkType) {
        Write-Ok "  $LinkPath already a $($existing.LinkType.ToLower())"
        return
    }
    if (Test-Path $LinkPath) {
        $bak = "$LinkPath.pre-migrate-$(Get-Date -Format 'yyyyMMdd')"
        Invoke-OrDry -Description "back up $LinkPath -> $bak" -Block {
            Move-Item -Path $LinkPath -Destination $bak -Force
        }
    }
    try {
        Invoke-OrDry -Description "create symlink $LinkPath -> $Target" -Block {
            New-Item -ItemType SymbolicLink -Path $LinkPath -Target $Target -Force | Out-Null
        }
        Write-Ok "  Created symlink: $LinkPath"
    } catch {
        # Symlink failed (likely no Developer Mode + not admin). Fall back to copy + warn.
        Write-WarnMsg "  Could not create symlink (need Developer Mode or admin)."
        Write-WarnMsg "  Falling back to a copy. Edits made on one Mac won't auto-flow here."
        Invoke-OrDry -Description "copy $Target -> $LinkPath" -Block {
            Copy-Item -Path $Target -Destination $LinkPath -Force -Recurse
        }
    }
}

New-LinkOrCopy -LinkPath $claudeMd -Target $targetMd -Kind "file"

$commandsLink   = Join-Path $env:USERPROFILE ".claude\commands"
$commandsTarget = Join-Path $ccConfig "commands"
if (Test-Path $commandsTarget) {
    Invoke-OrDry -Description "ensure ~/.claude exists" -Block {
        New-Item -ItemType Directory -Path (Join-Path $env:USERPROFILE ".claude") -Force | Out-Null
    }
    New-LinkOrCopy -LinkPath $commandsLink -Target $commandsTarget -Kind "dir"
}

# ─── 7. Final pull-everything-current ───────────────────────────────────────
Write-Log "Step 8/8: Pull every repo to its current GitHub state"
$updateAll = Join-Path $InstallRoot "ttc-agent-framework\scripts\update-all.ps1"
if ($DryRun) {
    Write-Host "  DRY: would run update-all.ps1 -Force" -ForegroundColor DarkGray
} else {
    if (Test-Path $updateAll) {
        & $updateAll -Force -InstallRoot $InstallRoot
    } else {
        Write-WarnMsg "  update-all.ps1 not found at $updateAll -- skipping"
    }
}

Write-Host ""
Write-Ok "Migration complete."
Write-Host ""
Write-Host "Manual verification recommended:"
Write-Host "  1. Open Claude Desktop and try Proton tools (mcp__proton__list_mailboxes)"
Write-Host "  2. Try 'apply docs' to confirm the new Docs agent loads"
Write-Host "  3. Run a Word generation test (LOGO_PATH should resolve to OneDrive)"
Write-Host ""
