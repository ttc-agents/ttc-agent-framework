<#
.SYNOPSIS
    TTC Agent Framework - One-command installer (Windows)

.DESCRIPTION
    Installs prerequisites (Git, GitHub CLI, Node, Python, 1Password CLI),
    Claude Code, the framework, and the standard bundle of 4 work agents
    (SAP, Test, TAF, Tender). Idempotent - safe to re-run.

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

$BaseAgents = @(
    @{ Repo = "ttc-agent-sap";    Dir = "SAP";    Apply = "sap";    Submodules = $true  },
    @{ Repo = "ttc-agent-test";   Dir = "Test";   Apply = "test";   Submodules = $false },
    @{ Repo = "ttc-agent-taf";    Dir = "TAF";    Apply = "taf";    Submodules = $false },
    @{ Repo = "ttc-agent-tender"; Dir = "Tender"; Apply = "tender"; Submodules = $false }
)

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
Log "Step 1/7: Checking prerequisites"
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
Log "Step 2/7: Installing Claude Code"
if (Has "claude") {
    Write-Host "  [skip] claude already on PATH"
} else {
    npm install -g "@anthropic-ai/claude-code"
}
Ok "Claude Code ready"

# --- 3. GitHub auth ----------------------------------------------------------
Log "Step 3/7: GitHub authentication"
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
Log "Step 4/7: Cloning framework"
if (-not (Test-Path $InstallRoot)) { New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null }
if (Test-Path (Join-Path $FrameworkDir ".git")) {
    Write-Host "  [skip] framework already cloned - pulling latest"
    git -C $FrameworkDir pull --ff-only 2>&1 | Out-Null
} else {
    gh repo clone "$GitHubOrg/$FrameworkRepo" $FrameworkDir
}
Ok "Framework at $FrameworkDir"

# --- 5. Install base bundle --------------------------------------------------
Log "Step 5/7: Installing base agent bundle"
if (-not (Test-Path $AgentsDir)) { New-Item -ItemType Directory -Path $AgentsDir -Force | Out-Null }

foreach ($agent in $BaseAgents) {
    $target = Join-Path $AgentsDir $agent.Dir
    Write-Host ""
    Log "  Agent: $($agent.Apply) ($($agent.Repo))"

    if (Test-Path (Join-Path $target ".git")) {
        Write-Host "    [skip] already cloned - pulling latest"
        git -C $target pull --ff-only 2>&1 | Out-Null
        if ($agent.Submodules) {
            git -C $target submodule update --init --recursive 2>&1 | Out-Null
        }
    } else {
        if ($agent.Submodules) {
            gh repo clone "$GitHubOrg/$($agent.Repo)" $target -- --recurse-submodules
        } else {
            gh repo clone "$GitHubOrg/$($agent.Repo)" $target
        }
    }

    $installPs1 = Join-Path $target "install.ps1"
    if (Test-Path $installPs1) {
        Push-Location $target
        try { & $installPs1 } catch { Warn "    $($agent.Apply) install.ps1 failed: $_" }
        Pop-Location
    } else {
        Write-Host "    [info] no install.ps1 - clone only"
    }
}
Ok "Base bundle installed"

# --- 6. Configure CLAUDE.md --------------------------------------------------
Log "Step 6/7: Configuring $ClaudeMd"
if (Test-Path $ClaudeMd) {
    $existing = Get-Content $ClaudeMd -Raw
    foreach ($agent in $BaseAgents) {
        $pattern = [regex]::Escape("apply $($agent.Apply)")
        $line    = "| ``apply $($agent.Apply)`` | ``$((Join-Path (Join-Path $AgentsDir $agent.Dir) 'system-prompt.md') -replace '\\','/')`` |"
        if ($existing -match $pattern) {
            Write-Host "  [skip] apply $($agent.Apply) already registered"
        } else {
            Add-Content -Path $ClaudeMd -Value $line
            Write-Host "  [add]  apply $($agent.Apply)"
        }
    }
} else {
    $template = Join-Path $FrameworkDir "CLAUDE.md.template"
    if (Test-Path $template) {
        $content = Get-Content $template -Raw
        $content = $content -replace "\{\{AGENTS_DIR\}\}", ($AgentsDir -replace '\\','/')
        Set-Content -Path $ClaudeMd -Value $content -Encoding UTF8
        Ok "Created $ClaudeMd from template"
    } else {
        Warn "Template not found - writing minimal CLAUDE.md"
        $lines = @(
            "# Claude Code - Agent Routing",
            "",
            "When the user says **`"apply <agent>`"**, read the matching system prompt and adopt it fully.",
            "",
            "| Command | System Prompt File |",
            "|---|---|"
        )
        foreach ($agent in $BaseAgents) {
            $lines += "| ``apply $($agent.Apply)`` | ``$((Join-Path (Join-Path $AgentsDir $agent.Dir) 'system-prompt.md') -replace '\\','/')`` |"
        }
        Set-Content -Path $ClaudeMd -Value ($lines -join "`n") -Encoding UTF8
    }
}
Ok "CLAUDE.md configured"

# --- 7. Minimal MCP config ---------------------------------------------------
Log "Step 7/7: Minimal MCP config"
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
Write-Host "  2. Inside Claude Code, try: apply sap | apply test | apply taf | apply tender"
Write-Host "  3. Add more agents any time:"
Write-Host "       & $FrameworkDir\scripts\add-agent.ps1 <name>"
Write-Host ""
