# Windows Support — Future

This document will contain the Windows setup guide when Windows support is added.

## Platform Differences

| Component | Mac (current) | Windows (planned) |
|---|---|---|
| Terminal | Warp | Windows Terminal |
| Agent Launcher | SwiftUI menu bar app | System tray app (PowerShell or Electron) |
| Scheduled tasks | LaunchAgents (plist) | Task Scheduler (XML / schtasks) |
| Package manager | Homebrew | winget / scoop |
| Paths | `/Users/x/AI-Vault/` | `C:\Users\x\AI-Vault\` |
| Install script | `install.sh` (bash) | `install.ps1` (PowerShell) |
