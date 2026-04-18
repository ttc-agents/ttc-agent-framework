<#
.SYNOPSIS
    Install a single TTC agent by name (Windows).

.EXAMPLE
    .\add-agent.ps1 hr
    .\add-agent.ps1 personal-template
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Name
)

$ErrorActionPreference = "Stop"

$FrameworkDir = Split-Path -Parent $PSScriptRoot
$Config       = Join-Path $FrameworkDir "install-config.json"
$InstallRoot  = if ($env:TTC_INSTALL_ROOT) { $env:TTC_INSTALL_ROOT } else { Join-Path $env:USERPROFILE "AI-Vault" }
$AgentsDir    = Join-Path $InstallRoot "Agents"
$ClaudeMd     = Join-Path $env:USERPROFILE "CLAUDE.md"

if (-not (Test-Path $Config)) {
    Write-Host "[err] install-config.json not found at $Config" -ForegroundColor Red
    exit 1
}

$cfg = Get-Content $Config -Raw | ConvertFrom-Json
$key = $Name.ToLower()

# Match by short repo name, full repo name, or apply key.
$candidates = @($cfg.agents | Where-Object {
    $short = $_.repo -replace '^ttc-agent-',''
    ($key -eq $short) -or ($key -eq $_.repo) -or ($key -eq $_.apply)
})

if ($candidates.Count -eq 0) {
    Write-Host "[err] Unknown agent '$Name'. Available names:" -ForegroundColor Red
    foreach ($a in $cfg.agents) {
        $short = $a.repo -replace '^ttc-agent-',''
        Write-Host ("  {0,-25}  ({1})" -f $short, $a.apply)
    }
    exit 1
}

# Prefer the candidate whose short repo matches exactly
$agent = $candidates | Where-Object { ($_.repo -replace '^ttc-agent-','') -eq $key } | Select-Object -First 1
if (-not $agent) { $agent = $candidates[0] }

$Target = Join-Path $AgentsDir $agent.dir
$GitHubOrg = $cfg.github_org

if (-not (Test-Path $AgentsDir)) { New-Item -ItemType Directory -Path $AgentsDir -Force | Out-Null }

if (Test-Path (Join-Path $Target ".git")) {
    Write-Host "[skip] $($agent.repo) already cloned - pulling latest"
    git -C $Target pull --ff-only 2>&1 | Out-Null
    if ($agent.submodules) {
        git -C $Target submodule update --init --recursive 2>&1 | Out-Null
    }
} else {
    Write-Host "[clone] $GitHubOrg/$($agent.repo) -> $Target"
    if ($agent.submodules) {
        gh repo clone "$GitHubOrg/$($agent.repo)" $Target -- --recurse-submodules
    } else {
        gh repo clone "$GitHubOrg/$($agent.repo)" $Target
    }
}

$installPs1 = Join-Path $Target "install.ps1"
if (Test-Path $installPs1) {
    Write-Host "[run]  $installPs1"
    Push-Location $Target
    try { & $installPs1 } finally { Pop-Location }
} else {
    Write-Host "[info] no install.ps1 in $($agent.repo) - clone only"
}

$line = "| ``apply $($agent.apply)`` | ``$((Join-Path $Target 'system-prompt.md') -replace '\\','/')`` |"
if (Test-Path $ClaudeMd) {
    $content = Get-Content $ClaudeMd -Raw
    if ($content -match [regex]::Escape("apply $($agent.apply)")) {
        Write-Host "[skip] apply $($agent.apply) already in $ClaudeMd"
    } else {
        Add-Content -Path $ClaudeMd -Value $line
        Write-Host "[add]  apply $($agent.apply) -> $ClaudeMd"
    }
} else {
    Set-Content -Path $ClaudeMd -Value "# Claude Code - Agent Routing`n`n| Command | System Prompt File |`n|---|---|`n$line" -Encoding UTF8
    Write-Host "[create] $ClaudeMd with apply $($agent.apply)"
}

Write-Host ""
Write-Host "Done. Try it in Claude Code:  apply $($agent.apply)" -ForegroundColor Green
