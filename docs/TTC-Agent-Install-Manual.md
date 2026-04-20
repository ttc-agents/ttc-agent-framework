# TTC AI Agents — Self-Install Manual

**Audience:** TTC colleagues who want to run the TTC AI agents on their own work laptop.
**Time required:** about 20 minutes.
**Skill level:** no coding experience needed — you just copy and paste a few commands.

If you get stuck at any step, send a screenshot to Joerg and we will get you unblocked.

> **Already installed?** Skip to [Updating to the latest version](#updating-to-the-latest-version) — one command and you're current. The [Knowledge Base section](#knowledge-base--how-its-organised) covers the new two-tier (general + shared customer) model.

---

## What you will end up with

- **Claude Desktop** — the familiar Claude chat app (same as claude.ai, but on your laptop). This is the easier day-to-day interface — great for regular conversations, drafting, research, and letting Claude control your local tools (Word, PowerPoint, PDFs, your browser, your inbox). **Highly recommended.**
- **Claude Code** — a command-line version of Claude that runs the TTC agents. This is where the specialised TTC personas live (tender writing, test management, SAP engineering, proposal decks, etc.). You switch agent by typing `apply tender`, `apply test`, `apply sap`, and so on.
- **The TTC agents themselves** — each one has its own knowledge and instructions. You only see the agents you have been given access to.

Most TTC colleagues end up using both apps side by side: Claude Desktop for quick chats and tool control, Claude Code when they need a specific agent persona.

---

## The 7 steps (recommended order)

1. **Activate your Claude account** — follow the invite email Joerg sent you
2. **Create a GitHub account** (if you do not already have one)
3. **Send Joerg your GitHub username** so he can grant you access to the right agents
4. **Install Claude Desktop** (highly recommended — the easier UI, and what you will use to let Claude control your local tools)
5. **Run the one-line TTC installer** — this installs everything else automatically
6. **Start Claude Code and try an agent**
7. **Set up 1Password and your Claude Desktop connectors** (recommended)

Do them in this order. If you run the installer before step 3 is done, it will fail at the GitHub login step.

---

## Step 1 — Activate your Claude account

Before you can use the agents, your Anthropic (Claude) account must be active. Joerg sends each TTC colleague an **invitation email from Anthropic** when onboarding — it contains a personal activation link.

1. Open the invitation email with the subject line *"You've been invited to join TTC on Claude"* (or similar). Check your Junk / Clutter folder if you don't see it — Anthropic emails sometimes land there.
2. Click the **Accept invitation** button in the email. It takes you to claude.ai.
3. **Create or sign in to your Anthropic account** using your TTC work email address. If you already have a personal Anthropic account on your work email, it will link; otherwise create a new one and set a password.
4. Accept the workspace invitation when prompted — you should now see "TTC" (or the TTC workspace name) in your account.
5. Try sending a test message at **https://claude.ai** — if Claude replies, your account is active. Done.

If:
- **The email expired** or you cannot find it → ask Joerg to resend.
- **You already had a personal Claude account** on a different email → that's fine; the TTC invite will link your TTC workspace to the existing account. Use whichever email the invite was sent to.
- **Claude.ai asks you to pay** → you are not yet in the TTC workspace; re-open the invite link or ask Joerg.

Once you can log into claude.ai and reply to a test prompt, carry on with step 2.

---

## Step 2 — Create a GitHub account

GitHub is where the TTC agents are stored. You need a (free) personal GitHub account to download them.

1. Go to **https://github.com/signup**
2. Use **your TTC work email** as the account email.
3. Pick a username. Something simple like `firstname-lastname-ttc` works well.
4. Choose the **Free** plan.
5. Verify your email address using the code GitHub sends you.

You do **not** need to create any repositories, add a profile picture, or anything else. Just get the account created.

---

## Step 3 — Send Joerg your GitHub username

Email or message Joerg with:

- Your GitHub username (for example `alex-smith-ttc`)
- Which part of TTC you work in (Sales, Delivery, SAP, Test, HR, Finance, Legal, etc.)

Joerg will then add you to the right teams inside the TTC GitHub organisation. You will receive an email from GitHub asking you to accept the invitation — click the link and accept.

Only after you have accepted the invitation should you move on to step 5.

---

## Step 4 — Install Claude Desktop (highly recommended)

Claude Desktop is the normal Claude chat app — the same experience as claude.ai, running natively on your laptop. It is the **easier day-to-day interface** for most work: drafting, research, long conversations, and — crucially — the place where Claude can reach out into your tools (Word, PowerPoint, Outlook, your browser) and **do** things for you, not just talk about them.

It is **not** where the TTC agents live (those run in Claude Code, step 5). But most TTC colleagues end up using both apps side by side, and Claude Desktop is the one you will open first thing in the morning.

- **Mac:** https://claude.ai/download — click the macOS download button, open the downloaded file, drag Claude into Applications.
- **Windows:** https://claude.ai/download — click the Windows download button, run the installer.

Sign in with the Anthropic account you activated in step 1 (same credentials you will use in step 6 for Claude Code).

Once signed in, come back here and carry on with step 5. We will add the useful extensions and connectors to Claude Desktop in step 7.

---

## Step 5 — Install the TTC Framework (one-line command)

This is the magic step. One command installs everything: Git, GitHub CLI, Node.js, Python, the TTC framework, and the four base agents (SAP, Test, TAF, Tender). Total time about 10 minutes depending on your internet speed.

### On Mac

1. Press **Cmd + Space**, type **Terminal**, press Enter.
2. Copy the line below and paste it into the Terminal, then press Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.sh | bash
```

3. The first thing it asks for is your Mac admin password (this is so it can install Homebrew, the Mac software manager). Type your Mac login password (characters will not appear — that is normal) and press Enter.
4. It will then install about a dozen tools. You will see a lot of text scroll past. This is normal.
5. At some point it will say:

    > A short one-time code will be displayed.
    > Open https://github.com/login/device in any browser and paste the code.

    Copy the 8-character code it shows you, open **https://github.com/login/device** in any browser, paste the code, and sign in with your GitHub account. This authorises the installer to download the private agent repositories for you.

6. After that it keeps running on its own. When it is finished you will see:

    > === Install complete ===

### On Windows

1. Click the **Start** menu, type **PowerShell**, **right-click "Windows PowerShell"** and choose **"Run as administrator"**. Running as admin avoids repeated User Account Control pop-ups and lets the installer do its work without interruption.
2. Copy the line below and paste it into the PowerShell window (right-click to paste), then press Enter:

```powershell
iwr https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.ps1 | iex
```

3. **Windows security will ask for permission** a few times while the installer runs — this is normal. Whenever Windows (User Account Control) asks whether you want to allow an installer to make changes to your device, click **Yes**.
4. **If PowerShell asks "Do you want to run software from this untrusted publisher?"** or any similar confirmation with a list of choices like `[Y] Yes  [A] Yes to All  [N] No  [L] No to All`, type **`A`** and press Enter. This confirms all script-based steps in one go. If a plain `[Y]/[N]` prompt appears, answer `Y`.
5. The installer will install Git, GitHub CLI, Node.js, Python and the 1Password CLI using the built-in Windows package manager (`winget`).
6. When it asks for GitHub authentication, copy the 8-character code, open **https://github.com/login/device** in any browser, paste the code, and sign in with your GitHub account.
7. **Known quirk on Windows:** after GitHub authentication succeeds, the installer sometimes stops or shows an error instead of continuing. If that happens:
    - Close the PowerShell window.
    - Open a **new** PowerShell window (again right-click "Run as administrator").
    - Paste and run the same one-line command again:

    ```powershell
    iwr https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.ps1 | iex
    ```

    The installer is designed to be run again — it skips whatever is already done and picks up where it stopped. The second run usually finishes without any further interaction because you are already authenticated with GitHub.
8. When you see `=== Install complete ===` the setup is done.

### What the installer does, in plain language

- Checks whether each required tool is already on your machine — skips any that are already installed.
- Installs the missing tools using the standard software manager for your operating system.
- Installs **Claude Code** — a command-line version of Claude that knows how to run the agents.
- Asks you to log into GitHub so it can download the agent repositories you have been granted access to.
- **Asks GitHub which TTC agent repositories you have read access to**, and downloads every single one. You do not have to know which agents exist — the installer figures it out based on your team memberships. A pre-sales consultant ends up with Tender, TOM, PPTX, Test and SAP; a test engineer gets Test, TAF and PPTX; and so on.
- Writes a small configuration file called `CLAUDE.md` in your home directory so Claude Code knows about the agents.

---

## Step 6 — Start Claude Code and try an agent

1. Open a new Terminal (Mac) or PowerShell (Windows) window. Closing and reopening is important — it makes your laptop pick up the new tools in the search path.

2. Type:

```
claude
```

The first time you run this, it will ask you to sign in to Anthropic. Follow the prompts — it opens a browser window where you sign in with your Anthropic account (same credentials as Claude Desktop if you installed it).

3. Once signed in, you are at the Claude Code prompt. Type:

```
apply tender
```

and press Enter. You should see a message saying the Tender agent is ready, along with its role (something like *"I am the Tender & Proposal agent for TTC…"*). That means it worked.

4. The installer prints the list of agents you have installed, with one `apply <name>` line each. Try whichever of them matches the work you do today.

---

## Step 7 — Set up 1Password and Claude Desktop connectors

Now that the agents run, these recommended extras make them genuinely useful in your daily work.

### 1Password (strongly recommended)

The TTC agents are designed to pull authentication secrets — Microsoft 365 tokens, API keys, database passwords — from **1Password**, rather than storing them in plaintext configuration files. That way your credentials stay encrypted at rest and you never accidentally commit one to a repository.

The installer in step 5 already put the **1Password command-line tool** on your machine. You still need the 1Password **desktop app** and an account.

1. Download and install the 1Password desktop app from **https://1password.com/downloads/**
2. Sign in to your 1Password account. If you would like access to the TTC shared "AI Vault" (where the MS365 app registration and similar shared credentials live), ask Joerg to invite you.
3. In the 1Password app, open **Settings → Developer** and switch on **Connect with 1Password CLI** and **Integrate with SSH Agent** if offered.
4. The first time a Claude agent reads a secret from 1Password, the app will pop up and ask you to approve the read. Approve it — you can tick "remember this session" to avoid repeated prompts.

**Why this matters:** when an agent needs to call Microsoft 365 on your behalf, it asks 1Password for the token at the moment of use. You never have to paste the token into a config file, and if you ever need to revoke access, you revoke it in one place.

### If you prefer a different password manager

Bitwarden, Dashlane, LastPass, KeePass, Apple Keychain — all of them can work, but the TTC agents are not pre-wired for them. If that is your situation:

1. Finish the installation first and get at least one agent running (`apply tender` or similar)
2. Start a Claude Code session and simply say:

    > "Please help me configure Bitwarden (or whichever tool you use) as the secret source for my MCP servers on this machine."

    Claude Code will look at your setup, figure out what needs to change, and guide you through it step by step — including creating the right wrapper script and testing it. You do not need any command-line experience for this.

### Claude Desktop — recommended connectors

Claude Desktop (the chat app from step 4) supports the same kind of integrations as Claude Code. Here is the setup used on the reference TTC laptop — you can mirror the whole thing or pick and choose.

**MCP servers** (advanced — open Claude Desktop → Settings → Developer → Edit Config):

| Server | What it does | Needs |
|---|---|---|
| `filesystem` | Read and edit files in folders you choose | None |
| `ms365` | Microsoft 365 email, calendar, tasks, Teams | Azure tenant + app registration (ask Joerg to share the TTC one) |
| `proton` | Proton Mail (personal mail) | Proton Bridge running locally — optional |
| `knowledge-base` | Semantic search over local documents | None (it is a local Python service the installer configures) |

All secrets in these MCP configurations **should come from 1Password** via the wrapper (`op-mcp-wrapper.sh` on Mac — the installer places it under `~/AI-Vault/ttc-agent-framework/scripts/`). Never paste plaintext credentials into the config file.

**Desktop Extensions** (easier — open Claude Desktop → Settings → Extensions → browse, click *Install*):

| Extension | Purpose | Mac | Windows |
|---|---|---|---|
| Filesystem | File access from chat | ✓ | ✓ |
| PDF Server (by Anthropic) | Read and extract from PDFs | ✓ | ✓ |
| PDF Filler | Fill PDF forms | ✓ | ✓ |
| Word (Microsoft Office) | Create / read / edit `.docx` | ✓ | ✓ |
| PowerPoint (Microsoft Office) | Create / read / edit `.pptx` | ✓ | ✓ |
| Chrome Control | Control the Chrome browser | ✓ | ✓ |
| osascript | Run AppleScript to control Mac apps | ✓ | — |
| iMessage | Send and read iMessages | ✓ | — |
| Apple Notes | Read and write Apple Notes | ✓ | — |

If you are unsure where to start, install **Filesystem**, **PDF Server**, **Word** and **PowerPoint**. Add the others later as you discover use cases.

> **Note for Windows users:** the Word and PowerPoint extensions require the real Microsoft 365 apps to be installed on your machine. If you only have Office on the web, those extensions will not do anything useful.

### Let Claude Code configure things for you

Any time you hit a configuration task that feels fiddly — authenticating an MCP server, wiring up a new tool, setting up SSH keys, connecting a different password manager, or just making sense of an error message — **ask Claude Code itself to help**. Open a terminal, type `claude`, and describe what you want to achieve in plain English, for example:

> "Help me connect the Microsoft 365 MCP server — I have the Azure tenant ID and client ID, but I need a client secret and I do not know where to store it safely."

> "I get an error when I run `apply taf` about Playwright browsers not being installed. Please fix it."

> "Set up my Bitwarden as the secret source for the Claude Desktop MCP servers on this Mac."

> "Walk me through enabling Proton Mail Bridge so the `proton` MCP works."

Claude Code will look at your machine, figure out what is needed, and give you a **step-by-step manual tailored to your exact setup** — often running the fixes itself when you approve them. You do not need command-line experience. If you can describe the problem, Claude can almost always walk you through the solution.

If the fix involves a secret (password, API key, token), Claude will ask where you keep it (1Password, another manager, paste it into the chat) and handle storage appropriately — never hard-coding it into a config file unless you explicitly ask for that.

---

## Adding more agents later

If Joerg grants you access to an additional agent **after** you have run the installer, you have two options:

1. **Just run the one-line installer again.** It is idempotent — it will discover the new permission and clone the new repo, leaving the rest alone. This is the easiest path.
2. **Install the single agent** with the `add-agent` helper:

### On Mac

```bash
~/AI-Vault/ttc-agent-framework/scripts/add-agent.sh hr
```

### On Windows

```powershell
& "$env:USERPROFILE\AI-Vault\ttc-agent-framework\scripts\add-agent.ps1" hr
```

Replace `hr` with the agent name you want. The known agents are:

| Command | What it is |
|---|---|
| `hr` | CV screening and candidate tracking |
| `contracts` | NDAs, MSAs, SOWs, legal review |
| `finance` | Pricing, invoicing, commercial analysis |
| `pptx` | PowerPoint deck builder |
| `bwbm` | Bundeswehr SAP programme (restricted) |
| `odoo` | TTC Odoo ERP admin knowledge |
| `tom` | QA Target Operating Model generator |
| `personal-template` | Starter for your own Personal Assistant agent |

If a command says *unknown agent* it means either you have mistyped the name or you have not been granted access yet — check with Joerg.

---

## Personalising your own Personal Assistant

If you installed the `personal-template`, open the folder at

- Mac: `~/AI-Vault/Agents/Personal/`
- Windows: `%USERPROFILE%\AI-Vault\Agents\Personal\`

and edit:

1. `system-prompt.md` — replace every `{{PLACEHOLDER}}` with your details (name, role, email, timezone, etc.)
2. `memory/contacts.md` — people you correspond with regularly
3. `memory/email-preferences.md` — your tone of voice and regional etiquette
4. `memory/timezone-context.md` — your timezone and those of your main contacts

Once saved, the next time you type `apply personal` in Claude Code the agent picks up your customisations.

---

## Knowledge Base — how it's organised

The agents read from **two kinds of knowledge base**. Understanding the split helps you know where to put things and what your colleagues will and won't see.

### Tier 1 — General KB (local, private to you)

Location: `~/AI-Vault/Claude Folder/Knowledge Base/`

Contains TTC-internal reference material that every installation keeps its own copy of:

| Folder | What's in it |
|---|---|
| `BwBm/` | Bundeswehr SAP programme (restricted — only if you have bwbm agent access) |
| `Finance/` | TTC contract templates, pricing baselines, partner agreements |
| `Personal/` | Your own personal notes |
| `ttc-general/` | Brand assets, sales methodology, service offerings |
| `Archive/` | Historical, read-only |

This tier is **local to your machine**. Your colleagues have their own copies. Refreshing one doesn't touch anyone else's.

### Tier 2 — Customer KB (shared via OneDrive)

Location: every active customer has a hidden folder called `AI-INFO - DO NOT DELETE/` directly under their OneDrive folder. Examples:

```
OneDrive-TTCGlobal/Sales/Customer/Middle East/ADNOC/AI-INFO - DO NOT DELETE/
OneDrive-TTCGlobal/Sales/Customer/Middle East/ENOC/AI-INFO - DO NOT DELETE/
OneDrive-TTCGlobal/Delivery/Leapwork/VKB/AI-INFO - DO NOT DELETE/
```

Inside each folder:

| File / folder | Purpose |
|---|---|
| `README.md` | Explains rules, names the responsible owner |
| `notes.md` | **Human-editable** running notes on the customer — anyone with folder access can contribute |
| `memory.md` | Agent session highlights — what AI has learned or decided |
| `converted/` | Generated `.txt` files agents read for semantic search — don't edit by hand |
| `_index.json` | Delta manifest (auto-generated) |

**Why this matters:**
- **Multi-user collaboration** — when you work on ADNOC, your agent picks up notes your colleague added last week. When you add something, it syncs to them via OneDrive.
- **One source of truth per customer** — no more duplicate customer KBs on different machines.
- **Folder is hidden** on macOS / Windows — press `Cmd+Shift+.` (Mac) or enable "Show hidden items" (Windows) to see it. OneDrive Web always shows it.
- **Name is deliberately awkward** (`AI-INFO - DO NOT DELETE`) so no one mistakes it for deliverables. OneDrive restores deletions within 93 days anyway.

### Which agents use which tier

| Agent | General KB | Customer KB |
|---|---|---|
| **Tender** | `ttc-general/`, `Finance/` | ✅ scoped per customer |
| **Contracts** | `Finance/Contract Templates TTC/` | ✅ scoped per customer |
| **Test** | `BwBm/`, `ttc-general/` | ✅ scoped per customer |
| **TAF** | `ttc-general/` | ✅ reads customer context for test scope |
| **QA TOM Generator** | `ttc-general/`, methodology | ✅ scoped per customer |
| **SAP** | `BwBm/` | ✅ when working on customer SAP landscape |
| **BwBm** | `BwBm/` (internal project — stays Tier 1) | rarely |
| **Infrastructure** | documents the framework itself | — |
| Finance, HR, Odoo, Personal, Private, PPTX | their own reference | — (don't touch customer KBs) |

The agents know the split — you don't have to think about it. Just tell them the customer name and they'll look in the right place.

### Working with a customer — three scenarios

**Scenario 1 — A colleague already has a KB for this customer**
Nothing special to do. Every customer-facing agent runs a **silent discovery** at session start that scans OneDrive for `AI-INFO - DO NOT DELETE/` folders and adds any new ones to your local registry. Next time you say "apply tender" and mention that customer, the agent already knows the KB exists.

**Scenario 2 — You're the first person working on a brand-new customer**
When you ask the agent to save something for a customer it doesn't recognise, it will run:

```bash
~/AI-Vault/Claude\ Folder/kb_bootstrap_customer.sh "Customer Name"
```

This creates the hidden `AI-INFO - DO NOT DELETE/` folder inside their OneDrive customer folder, seeds `README.md`, `notes.md`, `memory.md`, adds the customer to the registry, and applies the hidden flag. It's idempotent — running it again is safe.

**Scenario 3 — Someone added new documents to a customer folder**
Rebuild the searchable index:

```bash
~/AI-Vault/Claude\ Folder/kb_refresh_customer.sh "Customer Name"
```

This re-converts only the new/changed source docs and updates your local vector index. Takes seconds.

The full rule book lives in `~/AI-Vault/docs/KB_CONVENTIONS.md`.

### Storage rules cheat sheet

| What you're producing | Where it goes |
|---|---|
| Drafts, in-progress work | `~/AI-Vault/Agents/<Agent>/working/` |
| Collaborative customer notes | `<customer>/AI-INFO - DO NOT DELETE/notes.md` |
| Agent session highlights | `<customer>/AI-INFO - DO NOT DELETE/memory.md` |
| Session memory (cross-customer) | `~/AI-Vault/Agents/<Agent>/memory/` |
| **Final client deliverable** | `<customer>/` proper — only after Joerg confirms "ship it" |

Never create an `AI-INFO` folder manually — always use the bootstrap script so the registry stays in sync.

---

## Updating to the latest version

The framework and agents are under active development. To pull the latest version of everything — framework, all agents, KB scripts, and conventions — run **one command**:

### On Mac

```bash
~/AI-Vault/ttc-agent-framework/scripts/update-all.sh
```

### On Windows

```powershell
& "$env:USERPROFILE\AI-Vault\ttc-agent-framework\scripts\update-all.sh"
```
*(Windows support via Git Bash; a native `update-all.ps1` may be added later.)*

What it does:
- Pulls the framework repo
- Pulls every agent repo you have installed (fast-forward only)
- **Skips any repo with uncommitted local changes** (safe — nothing overwritten)
- Refreshes the runtime KB scripts (`kb_bootstrap_customer.sh`, `kb_refresh_customer.sh`, the converter, the vectorizer) and `KB_CONVENTIONS.md`

System-prompt changes take effect in your **next** Claude Code conversation. No reload or restart needed.

When to run it:
- When Joerg says "I pushed an update"
- Once a week to stay current
- Before starting a big customer engagement

When **not** to run it (use the one-line installer from Step 5 instead):
- First install on a new machine
- When a new tool or Python dependency has been added (rare — usually mentioned in release notes)

---

## What if something goes wrong

### The installer failed halfway through

Just run the same one-line command again. The installer is safe to re-run — it will skip anything that is already installed and carry on where it stopped.

### The installer stopped right after I signed in to GitHub (Windows)

This is the most common hiccup on Windows. PowerShell sometimes loses track of newly-installed tools mid-script. Close PowerShell, open a fresh window, and run the one-liner again — the second run usually completes without any further interaction because your GitHub sign-in is already saved.

### "gh: command not found" after the installer finished

Close the Terminal / PowerShell window and open a **new** one. The newly installed tools only appear in freshly opened windows.

### "Repository not found" when GitHub tries to clone

This means your GitHub account does not have access to that repository yet. Check with Joerg that you were added to the right team and that you accepted the GitHub invitation email.

### The device-flow code expired

If you were slow to paste the 8-character code, it may expire. Just type the install command again — a new code is generated each time.

### Windows says "execution of scripts is disabled"

Run the one-liner via:

```powershell
powershell -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.ps1 | iex"
```

### I installed Claude Code but `apply tender` does not work

Check that your `CLAUDE.md` file exists in your home folder and contains an `apply tender` line. If it is missing, run the base-agent installer again:

- Mac: `~/AI-Vault/ttc-agent-framework/scripts/add-agent.sh tender`
- Windows: `& "$env:USERPROFILE\AI-Vault\ttc-agent-framework\scripts\add-agent.ps1" tender`

---

## A note on keeping things tidy

- **Do not commit your work inside the agent folders back to GitHub.** The installer creates a `working/` subfolder in every agent — anything in there is ignored by Git by design. Put drafts, exports, and scratch files in `working/`.
- **Do not share the contents of your `AI-Vault` folder** outside TTC. Some of the agent memory contains internal client context.
- **Passwords, API keys, credentials**: never paste them into a memory file. Use 1Password and reference them through the `op://` system — ask Joerg if you need that set up.

---

## Getting help

- Walk-through: **Joerg Pietzsch** — joerg.pietzsch@ttcglobal.com
- Technical issues: send a screenshot of the Terminal / PowerShell output. 90% of the time the fix is obvious from the error message.
- Feature requests or agent suggestions: reply to Joerg — new agents are added regularly.

Welcome to the TTC agent family. Happy prompting.
