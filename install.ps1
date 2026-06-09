<#
.SYNOPSIS
    TTC Agent Framework - One-command installer (Windows)

.DESCRIPTION
    Installs prerequisites (Git, GitHub CLI, Node, Python, 1Password CLI),
    Claude Code, the framework, and every TTC agent the authenticated
    GitHub user has read access to. Idempotent - safe to re-run.

.NOTES
    One-liner install:
      iwr https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.ps1 | iex
#>

# "Continue" - PS 5.1 treats native-command stderr as an error under "Stop",
# which breaks git pull / gh clone / winget install whose progress messages
# are written to stderr. We check $LASTEXITCODE explicitly where it matters.
$ErrorActionPreference = "Continue"

$GitHubOrg     = "ttc-agents"
$FrameworkRepo = "ttc-agent-framework"
$InstallRoot   = if ($env:TTC_INSTALL_ROOT) { $env:TTC_INSTALL_ROOT } else { Join-Path $env:USERPROFILE "AI-Vault" }
$FrameworkDir  = Join-Path $InstallRoot $FrameworkRepo
$AgentsDir     = Join-Path $InstallRoot "Agents"
$ClaudeMd      = Join-Path $env:USERPROFILE "CLAUDE.md"

function Log   ($msg) { Write-Host "[install] $msg" -ForegroundColor Cyan }
function Ok    ($msg) { Write-Host "[ok] $msg" -ForegroundColor Green }
function Warn  ($msg) { Write-Host "[warn] $msg" -ForegroundColor Yellow }
function Err   ($msg) { Write-Host "[err] $msg" -ForegroundColor Red }
function Has   ($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

Write-Host ""
Write-Host "=== TTC Agent Framework - Install (Windows) ===" -ForegroundColor Cyan
Write-Host "Install root: $InstallRoot"
Write-Host ""

# --- 1. Prerequisites --------------------------------------------------------
Log "Step 1/6: Checking prerequisites"
if (-not (Has "winget")) {
    Err "winget not found. Install 'App Installer' from the Microsoft Store and re-run."
    exit 1
}

$Packages = @(
    "Git.Git",
    "GitHub.cli",
    "OpenJS.NodeJS.LTS",
    "Python.Python.3.12",
    "1Password.CLI"
)
foreach ($pkg in $Packages) {
    $installed = winget list --id $pkg --exact 2>$null | Select-String -Pattern $pkg -Quiet
    if ($installed) {
        Write-Host "  [skip] $pkg"
    } else {
        Log "Installing $pkg..."
        winget install --id $pkg --exact --silent --accept-source-agreements --accept-package-agreements
    }
}
# Refresh PATH in current session so newly-installed tools are visible
$machinePath = [Environment]::GetEnvironmentVariable("Path","Machine"); $userPath = [Environment]::GetEnvironmentVariable("Path","User"); $env:Path = "$machinePath;$userPath"
Ok "Prerequisites ready"

# --- 2. Claude Code ----------------------------------------------------------
Log "Step 2/6: Installing Claude Code"
if (Has "claude") {
    Write-Host "  [skip] claude already on PATH"
} else {
    npm install -g "@anthropic-ai/claude-code"
}
Ok "Claude Code ready"

# --- 3. GitHub auth ----------------------------------------------------------
Log "Step 3/6: GitHub authentication"
$ghAuthOk = $false
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"
try {
    gh auth status 2>&1 | Out-Null
    $ghAuthOk = ($LASTEXITCODE -eq 0)
} finally {
    $ErrorActionPreference = $prevEAP
}

if ($ghAuthOk) {
    Write-Host "  [skip] gh already authenticated"
} else {
    Warn "gh is not authenticated. Starting device-flow login..."
    Write-Host "  A short one-time code will be displayed."
    Write-Host "  Open https://github.com/login/device in any browser and paste the code."
    Write-Host "  When prompted, choose 'SSH' as preferred git protocol and accept"
    Write-Host "  uploading your public key — this avoids gh-token-expiry pain later."
    gh auth login --hostname github.com --git-protocol ssh --web
}

# Verify SSH to GitHub actually works.
$sshTest = ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new git@github.com 2>&1
if ($sshTest -match "successfully authenticated") {
    Ok "GitHub ready (SSH)"
} else {
    Warn "SSH to git@github.com is NOT working yet."
    Warn "Generate + upload a key:"
    Warn "  ssh-keygen -t ed25519 -C `"$env:USERNAME@$env:COMPUTERNAME`""
    Warn "  gh ssh-key add `$env:USERPROFILE\.ssh\id_ed25519.pub --title `"$env:USERNAME@$env:COMPUTERNAME ($(Get-Date -Format yyyy-MM))`""
    Warn "Re-run this installer once that's done."
    exit 1
}

# --- 4. Clone framework ------------------------------------------------------
Log "Step 4/6: Cloning framework"
if (-not (Test-Path $InstallRoot)) { New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null }
if (Test-Path (Join-Path $FrameworkDir ".git")) {
    Write-Host "  [skip] framework already cloned - syncing to origin"
} else {
    git clone "git@github.com:$GitHubOrg/$FrameworkRepo.git" $FrameworkDir
}
Ok "Framework at $FrameworkDir"

# Source the shared sync helper (inside the framework we just ensured). All repo
# updates go through Sync-RepoToOrigin: fetch -> guarded reset --hard origin
# -> re-materialise. Replaces `git pull --ff-only 2>&1 | Out-Null`, which
# silently failed on the always-dirty (materialised) tree and never pulled new
# files (e.g. KB docs). PowerShell loads scripts fully before running, so
# updating the framework mid-run is safe (no re-exec needed).
$env:TTC_AI_VAULT      = $InstallRoot
$env:TTC_FRAMEWORK_DIR = $FrameworkDir
$env:TTC_HOME          = $env:USERPROFILE
$SyncHelper = Join-Path $FrameworkDir "scripts\portability\sync-repo.ps1"
if (Test-Path $SyncHelper) {
    . $SyncHelper
    if (Test-Path (Join-Path $FrameworkDir ".git")) { Sync-RepoToOrigin -Target $FrameworkDir }
} else {
    Warn "sync helper not found at $SyncHelper - repo updates may be incomplete"
}

# --- 5. Discover + install every accessible agent ---------------------------
Log "Step 5/6: Discovering agents you have access to"

$accessible = @()
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"
try {
    $repoListJson = gh repo list $GitHubOrg --limit 200 --json name 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and $repoListJson.Trim()) {
        $parsed = $repoListJson | ConvertFrom-Json
        $accessible = @($parsed | ForEach-Object { $_.name } | Where-Object { $_ -like 'ttc-agent-*' } | Sort-Object -Unique)
    }
} finally {
    $ErrorActionPreference = $prevEAP
}
Write-Host "  Found $($accessible.Count) accessible ttc-agent-* repo(s)."

$config  = Get-Content (Join-Path $FrameworkDir "install-config.json") -Raw | ConvertFrom-Json
$skip    = @($config.skip_repos)
$seenDir = @{}
$toInstall = @()
foreach ($agent in $config.agents) {
    if ($accessible -notcontains $agent.repo) { continue }
    if ($skip -contains $agent.repo)          { continue }
    if (-not $agent.auto_install)             { continue }
    if ($seenDir.ContainsKey($agent.dir))     { continue }
    $seenDir[$agent.dir] = $true
    $toInstall += $agent
}

if ($toInstall.Count -eq 0) {
    Warn "No accessible agent repos found. Ask the org owner to grant you team access, then re-run."
} else {
    Ok "$($toInstall.Count) agent(s) will be installed"
}

if (-not (Test-Path $AgentsDir)) { New-Item -ItemType Directory -Path $AgentsDir -Force | Out-Null }

$installed = @()
foreach ($agent in $toInstall) {
    $target = Join-Path $AgentsDir $agent.dir
    Write-Host ""
    Log "  Agent: $($agent.apply) ($($agent.repo))"

    if (-not (Test-Path (Join-Path $target ".git"))) {
        $sshUrl = "git@github.com:$GitHubOrg/$($agent.repo).git"
        if ($agent.submodules) {
            git clone --recurse-submodules $sshUrl $target
        } else {
            git clone $sshUrl $target
        }
    } else {
        Write-Host "    [skip] already cloned - syncing to origin"
    }

    # Sync to origin + re-materialise (handles both the fresh clone and updates;
    # replaces the silent-failing `pull --ff-only` + separate materialise).
    if (Get-Command Sync-RepoToOrigin -ErrorAction SilentlyContinue) {
        Sync-RepoToOrigin -Target $target
    } else {
        $materialiser = Join-Path $FrameworkDir "scripts\portability\materialise-paths.ps1"
        if (Test-Path $materialiser) {
            $env:TTC_AI_VAULT = $InstallRoot
            $env:TTC_HOME     = $env:USERPROFILE
            try { & $materialiser -Path $target | Out-Null } catch { Warn "    materialise-paths failed for $($agent.apply): $_" }
        }
    }
    if ($agent.submodules) {
        git -C $target submodule update --init --recursive 2>&1 | Out-Null
    }

    $installPs1 = Join-Path $target "install.ps1"
    if (Test-Path $installPs1) {
        Push-Location $target
        try { & $installPs1 } catch { Warn "    $($agent.apply) install.ps1 failed: $_" }
        Pop-Location
    } else {
        Write-Host "    [info] no install.ps1 - clone only"
    }
    $installed += $agent
}
Ok "Agents installed: $($installed.Count)"

# --- 6. Configure CLAUDE.md --------------------------------------------------
Log "Step 6/6: Configuring $ClaudeMd"
if (-not (Test-Path $ClaudeMd)) {
    $template = Join-Path $FrameworkDir "CLAUDE.md.template"
    if (Test-Path $template) {
        $content = Get-Content $template -Raw
        $content = $content -replace "\{\{AGENTS_DIR\}\}", ($AgentsDir -replace '\\','/')
        Set-Content -Path $ClaudeMd -Value $content -Encoding UTF8
        Ok "Created $ClaudeMd from template"
    } else {
        $header = @(
            "# Claude Code - Agent Routing",
            "",
            "When the user says **`"apply <agent>`"**, read the matching system prompt and adopt it fully.",
            "",
            "| Command | System Prompt File |",
            "|---|---|"
        )
        Set-Content -Path $ClaudeMd -Value ($header -join "`n") -Encoding UTF8
    }
}

$existing = Get-Content $ClaudeMd -Raw
foreach ($agent in $installed) {
    $pattern = [regex]::Escape("apply $($agent.apply)")
    $line    = "| ``apply $($agent.apply)`` | ``$((Join-Path (Join-Path $AgentsDir $agent.dir) 'system-prompt.md') -replace '\\','/')`` |"
    if ($existing -match $pattern) {
        Write-Host "  [skip] apply $($agent.apply) already registered"
    } else {
        Add-Content -Path $ClaudeMd -Value $line
        Write-Host "  [add]  apply $($agent.apply)"
    }
}
Ok "CLAUDE.md configured"

# --- 7. Minimal MCP config ---------------------------------------------------
Log "Minimal MCP config"
$McpJson = Join-Path $env:USERPROFILE ".claude.json"
if (Test-Path $McpJson) {
    Write-Host "  [skip] $McpJson exists - not touching"
} else {
    $fsRoot = $InstallRoot -replace '\\','/'
    $mcp = @{
        mcpServers = @{
            filesystem = @{
                command = "npx"
                args = @("-y", "@modelcontextprotocol/server-filesystem", $fsRoot)
            }
        }
    }
    $mcp | ConvertTo-Json -Depth 6 | Set-Content -Path $McpJson -Encoding UTF8
    Ok "Wrote starter $McpJson (filesystem root: $fsRoot)"
}

# --- Summary -----------------------------------------------------------------
Write-Host ""
Write-Host "=== Install complete ===" -ForegroundColor Cyan
Write-Host "  Install root: $InstallRoot"
Write-Host "  Framework:    $FrameworkDir"
Write-Host "  Agents:       $AgentsDir"
Write-Host "  CLAUDE.md:    $ClaudeMd"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Run 'claude' to authenticate Claude Code"
Write-Host "  2. Inside Claude Code, type one of your installed agents:"
foreach ($agent in $installed) {
    Write-Host "       apply $($agent.apply)"
}
Write-Host "  3. To add more agents later (e.g. if you get access to a new one):"
Write-Host "       & $FrameworkDir\scripts\add-agent.ps1 <name>"
Write-Host ""
