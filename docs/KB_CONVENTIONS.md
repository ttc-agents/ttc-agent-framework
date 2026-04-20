# Knowledge Base Conventions — TTC Agent Framework

**Authoritative rules for all TTC agents. Link to this doc from every agent system-prompt.**
Last updated: 2026-04-20 | Owner: Joerg Pietzsch (Infrastructure Agent)

---

## 1. Two-tier KB model

### General KB — `AI-Vault/Claude Folder/Knowledge Base/`
**Per-user, TTC-internal. Not shared with colleagues.**

| Scope | Path | Contents |
|---|---|---|
| BwBm (internal) | `KB/BwBm/` | BwBm project reference — own source vault |
| Finance | `KB/Finance/` | TTC contract templates, internal pricing, partner contracts |
| Personal | `KB/Personal/` | Joerg's personal notes and preferences |
| TTC general | `KB/ttc-general/` | Brand, sales playbooks, service offerings, win themes, pricing baselines |
| Archive | `KB/Archive/` | Historical, read-only |
| Vector DB | `KB/_vectordb/` | chromadb indexes (per-user, never sync) |
| Registry | `KB/_customer_registry.json` | Maps customer → primary OneDrive folder (per-user copy; edited by `kb_bootstrap_customer.sh`) |

### Customer KB — `<OneDrive customer folder>/AI-INFO - DO NOT DELETE/`
**Shared across TTC users via OneDrive. Every customer we actively work with gets one.**

```
<Customer primary folder>/AI-INFO - DO NOT DELETE/
├── README.md              (explains folder, forbids deletion)
├── converted/             (.txt KB chunks — agent reads from here)
├── notes.md               (collaborative customer notes — humans edit)
├── memory.md              (agent session highlights — what was decided, when)
└── _index.json            (customer KB manifest)
```

**Why `AI-INFO - DO NOT DELETE`?** Name is deliberately awkward so nobody confuses it with deliverables or accidentally cleans it up. OneDrive restores deletions up to 93 days anyway.

---

## 2. Primary customer folder — selection rules

For a new customer, determine the primary folder in this order:

1. **Active sales pursuit** → `OneDrive-TTCGlobal/Sales/Customer/<Region>/<Customer>/`
2. **Active delivery** → `OneDrive-TTCGlobal/Delivery/<Practice>/<Customer>/`
3. **Both** → Sales folder is authoritative. Place a one-line `README.md` pointer in the Delivery folder.
4. **Contracts-only** → `OneDrive-TTCGlobal/Admin/Finance_Legal/Customer Contracts/<Customer>/` — Contracts agent only; general KB still in Sales/Delivery.

The registry stores which rule was applied; change it there if the customer's status changes.

---

## 3. Multi-user access — what works, what doesn't

| Artefact | Shared? | Mechanism |
|---|---|---|
| Source docs (.docx/.pptx/.pdf) | ✅ Yes | OneDrive native sync |
| Converted `.txt` chunks | ✅ Yes | OneDrive native sync |
| `notes.md`, `memory.md` | ✅ Yes | OneDrive native sync; conflict copies if simultaneous |
| `_index.json` (customer manifest) | ✅ Yes | OneDrive native sync; small file |
| Vector index (chromadb) | ❌ **No — per-user only** | Each user rebuilds locally from synced `.txt` via `kb_refresh_customer.sh` |

**Golden rule:** anything derived (vector DB, chroma shards) stays local. Anything authored (text, notes) syncs via OneDrive.

---

## 4. Storage rules for all customer-facing agents

Every customer-facing agent must follow this table:

| Artefact type | Location |
|---|---|
| Source docs (read-only input) | `OneDrive-TTCGlobal/<root>/...` (as-is) |
| Searchable KB — **general** | `AI-Vault/Claude Folder/Knowledge Base/<domain>/` |
| Searchable KB — **customer-specific** | `<primary>/AI-INFO - DO NOT DELETE/converted/` |
| Drafts, in-progress output | `AI-Vault/Agents/<Agent>/working/` |
| Final client-facing deliverable | `<primary>/<deliverable-subfolder>/` — **only after Joerg says "ship it"** |
| Session memory | `AI-Vault/Agents/<Agent>/memory/` |
| Collaborative customer notes | `<primary>/AI-INFO - DO NOT DELETE/notes.md` |
| Agent decisions on a customer | `<primary>/AI-INFO - DO NOT DELETE/memory.md` |
| Templates | `AI-Vault/Agents/<Agent>/templates/` |
| Scripts/tools | `AI-Vault/Agents/<Agent>/tools/` |

---

## 5. How an agent handles a new customer

First time an agent works for customer X that isn't in the registry:

1. Run `kb_bootstrap_customer.sh "<Customer Name>"` — idempotent; creates the `AI-INFO` folder structure, adds to registry.
2. Continue the task — save drafts to `working/`, customer notes to the new `notes.md`.
3. When ready, run `kb_refresh_customer.sh "<Customer Name>"` to build the vector index.

**Never create the `AI-INFO` folder manually** — always go through the bootstrap script so the registry stays in sync.

---

## 6. Customer registry

File: `AI-Vault/Claude Folder/Knowledge Base/_customer_registry.json`

Schema:
```json
{
  "customers": {
    "<slug>": {
      "display_name": "Customer Display Name",
      "region": "Middle East|DACH Region|UK|South Africa|...",
      "primary_folder": "/absolute/path/to/primary/folder",
      "ai_info_folder": "/absolute/path/to/AI-INFO - DO NOT DELETE",
      "created": "YYYY-MM-DD",
      "active_agents": ["tender", "contracts", "test", "taf"],
      "status": "active|paused|archived"
    }
  }
}
```

Slug rule: lowercase, hyphenated, no spaces. e.g. `dubai-holdings-leapwork`, `central-bank-uae`, `adnoc`.

---

## 7. Which agents consume which KB

| Agent | General KB | Customer KB |
|---|---|---|
| Tender | `KB/ttc-general/`, `KB/Finance/` | ✅ all customers in scope |
| Contracts | `KB/Finance/Contract Templates TTC/` | ✅ all customers in scope |
| Test | `KB/ttc-general/`, `KB/BwBm/` | ✅ all customers in scope |
| TAF | `KB/ttc-general/` | ✅ all customers in scope |
| BwBm | `KB/BwBm/` | only if customer KB exists for BwBm (unlikely) |
| Finance | `KB/Finance/` | ❌ (internal TTC finance) |
| HR | `KB/ttc-general/` + OneDrive HR folder | ❌ (internal) |
| Personal, Private, Infrastructure, PPTX, SAP, Oracle, Odoo, QA_TOM_Generator | per their prompts | ❌ |

---

## 8. Forbidden patterns

- ❌ Copying customer KB content into `AI-Vault/Claude Folder/Knowledge Base/` root or region folders
- ❌ Sharing the `_vectordb/` directory via Syncthing/OneDrive (will corrupt)
- ❌ Creating the `AI-INFO` folder manually without the bootstrap script
- ❌ Saving drafts directly into `AI-INFO - DO NOT DELETE/` (that's for indexed KB only; drafts go in `working/`)
- ❌ Renaming the `AI-INFO - DO NOT DELETE/` folder (breaks all agent lookups)

---

## 9. Change log

- **2026-04-20** — Initial version. Plan: `AI-Vault/docs/plans/2026-04-20-kb-split-customer-ai-info.md`
