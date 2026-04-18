<#
.SYNOPSIS
    Install a single TTC agent by name (Windows).

.EXAMPLE
    .\add-agent.ps1 hr
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Name
)

$ErrorActionPreference = "Stop"

$GitHubOrg   = "ttc-agents"
$InstallRoot = if ($env:TTC_INSTALL_ROOT) { $env:TTC_INSTALL_ROOT } else { Join-Path $env:USERPROFILE "AI-Vault" }
$AgentsDir   = Join-Path $InstallRoot "Agents"
$ClaudeMd    = Join-Path $env:USERPROFILE "CLAUDE.md"

$DirMap = @{
    "sap"="SAP"; "test"="Test"; "taf"="TAF"; "tender"="Tender"
    "hr"="HR"; "bwbm"="BwBm"; "pptx"="PPTX"; "odoo"="Odoo"
    "contracts"="Contracts"; "finance"="Finance"; "personal"="Personal"
    "personal-template"="Personal"
    "private"="Private"; "infra"="Infrastructure"; "tom"="QA_TOM_Generator"
}

$key = $Name.ToLower()
if (-not $DirMap.ContainsKey($key)) {
    Write-Host "[err] Unknown agent '$Name'. Known: $($DirMap.Keys -join ', ')" -ForegroundColor Red
    Write-Host "      Trading agents are personal-only and not installable via this script." -ForegroundColor Red
    exit 1
}

$Dir    = $DirMap[$key]
$Repo   = "ttc-agent-$key"
$Target = Join-Path $AgentsDir $Dir

if (-not (Test-Path $AgentsDir)) { New-Item -ItemType Directory -Path $AgentsDir -Force | Out-Null }

if (Test-Path (Join-Path $Target ".git")) {
    Write-Host "[skip] $Repo already cloned - pulling latest"
    git -C $Target pull --ff-only 2>&1 | Out-Null
} else {
    Write-Host "[clone] $GitHubOrg/$Repo -> $Target"
    try {
        gh repo clone "$GitHubOrg/$Repo" $Target -- --recurse-submodules
    } catch {
        gh repo clone "$GitHubOrg/$Repo" $Target
    }
}

$installPs1 = Join-Path $Target "install.ps1"
if (Test-Path $installPs1) {
    Write-Host "[run]  $installPs1"
    Push-Location $Target
    try { & $installPs1 } finally { Pop-Location }
} else {
    Write-Host "[info] no install.ps1 in $Repo - clone only"
}

$line = "| ``apply $key`` | ``$((Join-Path $Target 'system-prompt.md') -replace '\\','/')`` |"
if (Test-Path $ClaudeMd) {
    $content = Get-Content $ClaudeMd -Raw
    if ($content -match [regex]::Escape("apply $key")) {
        Write-Host "[skip] apply $key already in $ClaudeMd"
    } else {
        Add-Content -Path $ClaudeMd -Value $line
        Write-Host "[add]  apply $key -> $ClaudeMd"
    }
} else {
    Set-Content -Path $ClaudeMd -Value "# Claude Code - Agent Routing`n`n| Command | System Prompt File |`n|---|---|`n$line" -Encoding UTF8
    Write-Host "[create] $ClaudeMd with apply $key"
}

Write-Host ""
Write-Host "Done. Try it in Claude Code:  apply $key" -ForegroundColor Green
