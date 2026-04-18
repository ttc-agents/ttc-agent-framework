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

$ErrorActionPreference = "Stop"

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
gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  [skip] gh already authenticated"
} else {
    Warn "gh is not authenticated. Starting device-flow login..."
    Write-Host "  A short one-time code will be displayed."
    Write-Host "  Open https://github.com/login/device in any browser and paste the code."
    gh auth login --hostname github.com --git-protocol https --web
}
Ok "GitHub ready"

# --- 4. Clone framework ------------------------------------------------------
Log "Step 4/6: Cloning framework"
if (-not (Test-Path $InstallRoot)) { New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null }
if (Test-Path (Join-Path $FrameworkDir ".git")) {
    Write-Host "  [skip] framework already cloned - pulling latest"
    git -C $FrameworkDir pull --ff-only 2>&1 | Out-Null
} else {
    gh repo clone "$GitHubOrg/$FrameworkRepo" $FrameworkDir
}
Ok "Framework at $FrameworkDir"

# --- 5. Discover + install every accessible agent ---------------------------
Log "Step 5/6: Discovering agents you have access to"

$accessibleJson = gh api --paginate "/user/repos" --jq "[.[] | select(.owner.login==`"$GitHubOrg`" and (.name | startswith(`"ttc-agent-`"))) | .name]" 2>$null
if (-not $accessibleJson) { $accessibleJson = "[]" }
$accessible = @($accessibleJson | ConvertFrom-Json) | Sort-Object -Unique
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

    if (Test-Path (Join-Path $target ".git")) {
        Write-Host "    [skip] already cloned - pulling latest"
        git -C $target pull --ff-only 2>&1 | Out-Null
        if ($agent.submodules) {
            git -C $target submodule update --init --recursive 2>&1 | Out-Null
        }
    } else {
        if ($agent.submodules) {
            gh repo clone "$GitHubOrg/$($agent.repo)" $target -- --recurse-submodules
        } else {
            gh repo clone "$GitHubOrg/$($agent.repo)" $target
        }
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
