# Team Onboarding — Copy-Paste Templates

Snippets to send to a new teammate once they have accepted their GitHub invitation and been added to the right TTC teams.

---

## Email version

**Subject:** Getting set up with the TTC AI agents

Hi [Name],

You've been added to the TTC GitHub organisation and granted access to the agents matching your role. Setup takes about 20 minutes.

### One command installs everything

Open a terminal and paste the line below. It installs Git, Node.js, Python, 1Password CLI, Claude Code, the TTC framework and **every AI agent you have been granted access to** — you don't need to know any agent names in advance, it figures that out from your GitHub team memberships.

**Windows (PowerShell):**
```powershell
iwr https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.ps1 | iex
```

**Mac:**
```bash
curl -fsSL https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.sh | bash
```

During the install you'll see a short 8-character device code. Open **https://github.com/login/device** in any browser, paste the code, and sign in with your GitHub account. That's the only interactive step.

### After install

When it finishes, the installer prints the list of agents that were installed for you, each with an `apply <name>` command. To try one:

```
claude
apply tender     # or whichever agent name it showed you
```

### Highly recommended extras

- **Claude Desktop** — https://claude.ai/download (the chat UI, great for day-to-day work)
- **1Password** — we use it to keep Microsoft 365 tokens and other secrets encrypted. Ask me for access to the shared "AI Vault" if you need it.

The full install manual (with screenshots-worth of detail and troubleshooting) is at
`ttc-agent-framework/docs/TTC-Agent-Install-Manual.docx` — I can send you the PDF / Word copy if useful.

If you get stuck, send me a screenshot of the error.

Welcome aboard.

[Your signature]

---

## Slack / Teams version (short)

> Hi [Name] — you're set up on GitHub. To install the TTC AI agents on your laptop, paste this into a terminal:
>
> **Windows:** `iwr https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.ps1 | iex`
> **Mac:** `curl -fsSL https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.sh | bash`
>
> It auto-installs every agent you have access to based on your team membership — no list to remember. Full guide: `TTC-Agent-Install-Manual.docx`. Shout if stuck.

---

## Notes for the sender (you)

1. **Grant the teams first, then send the message.** Teams can be edited later, but the first install picks up whatever grants existed at `gh auth login` time. If they get access to a new repo later, re-running the one-liner installs it automatically.
2. **Each team maps to a role profile** — see `install-config.json` + the team layout in your audit notes. Quick reference:
    - `sales` → tender, contracts, pptx
    - `pre-sales` → tender, tom, pptx, test, sap
    - `legal` → contracts
    - `finance` → finance
    - `hr` → hr, pptx
    - `test-team` → test, taf, pptx
    - `sap-team` → sap, test, taf, pptx
    - `bwbm-team` → sap, bwbm, test, taf, pptx
    - `all-staff` → pptx, personal-template
3. **Personal Assistant:** the `all-staff` team gets the **public sanitized template**. Teammates run `add-agent personal-template` to install it and fill in their own placeholders — they never see your personal data.
4. **If a teammate changes role,** update their team membership in https://github.com/orgs/ttc-agents/teams — next time they run the installer they get the new agents.
