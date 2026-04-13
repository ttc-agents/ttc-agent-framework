import SwiftUI
import AppKit

// MARK: - Agent Model

struct Agent: Identifiable {
    let id: String
    let label: String
    let icon: String
}

// Define your agents here. Group them as needed.
// id = the name passed to `apply <id>` in Claude Code
// label = display name in the menu
// icon = SF Symbols icon name

let workAgents: [Agent] = [
    Agent(id: "example",  label: "Example Agent",  icon: "person.circle"),
    // Add more agents here:
    // Agent(id: "finance",  label: "Finance",  icon: "banknote"),
]

// Optional: agents grouped under a submenu (e.g. private/sensitive agents)
let privateAgents: [Agent] = [
    // Agent(id: "private",  label: "Private",  icon: "lock"),
]

enum LaunchTarget: String, CaseIterable {
    case warp = "Warp"
    case terminal = "Terminal"
}

// MARK: - Launch Logic

let claudeBin = "/opt/homebrew/bin/claude"
let claudeFlags = "--dangerously-skip-permissions"

func launchAgent(_ name: String, target: LaunchTarget) {
    let cmd = "\(claudeBin) \(claudeFlags) \"apply \(name)\""

    switch target {
    case .warp:
        let scriptPath = "/tmp/agent-\(name).command"
        let scriptContent = "#!/bin/zsh\ncd ~\n\(cmd)\n"
        try? scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", scriptPath]
        try? chmod.run()
        chmod.waitUntilExit()
        let warpURL = URL(fileURLWithPath: "/Applications/Warp.app")
        let fileURL = URL(fileURLWithPath: scriptPath)
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([fileURL], withApplicationAt: warpURL, configuration: config)

    case .terminal:
        let scriptPath = "/tmp/agent-\(name).command"
        let scriptContent = "#!/bin/zsh\ncd ~\nWIN_ID=$(osascript -e 'tell application \"Terminal\" to get id of front window' 2>/dev/null)\n\(cmd)\n[[ -n \"$WIN_ID\" ]] && osascript -e \"tell application \\\"Terminal\\\" to close (every window whose id is $WIN_ID)\" 2>/dev/null\n"
        try? scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", scriptPath]
        try? chmod.run()
        chmod.waitUntilExit()
        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let fileURL = URL(fileURLWithPath: scriptPath)
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([fileURL], withApplicationAt: terminalURL, configuration: config)
    }
}

// MARK: - App

@main
struct AgentLauncherApp: App {
    @AppStorage("launchTarget") private var launchTarget: String = LaunchTarget.warp.rawValue

    var body: some Scene {
        MenuBarExtra("Agents", systemImage: "play.laptopcomputer") {
            Text("Agent Launcher")
                .font(.headline)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            Divider()

            ForEach(workAgents) { agent in
                Button {
                    launchAgent(agent.id, target: LaunchTarget(rawValue: launchTarget) ?? .warp)
                } label: {
                    Label(agent.label, systemImage: agent.icon)
                }
            }

            if !privateAgents.isEmpty {
                Divider()

                Menu {
                    ForEach(privateAgents) { agent in
                        Button {
                            launchAgent(agent.id, target: LaunchTarget(rawValue: launchTarget) ?? .warp)
                        } label: {
                            Label(agent.label, systemImage: agent.icon)
                        }
                    }
                } label: {
                    Label("Private", systemImage: "lock.shield")
                }
            }

            Divider()

            // Target picker
            Menu("Launch in: \(launchTarget)") {
                ForEach(LaunchTarget.allCases, id: \.self) { target in
                    Button {
                        launchTarget = target.rawValue
                    } label: {
                        if target.rawValue == launchTarget {
                            Label(target.rawValue, systemImage: "checkmark")
                        } else {
                            Text(target.rawValue)
                        }
                    }
                }
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
