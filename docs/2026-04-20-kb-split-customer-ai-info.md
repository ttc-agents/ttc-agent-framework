# Plan — KB Split: General + Customer-shared `AI-INFO - DO NOT DELETE`

**Date:** 2026-04-20
**Scope:** Migrate customer-specific KB content out of `AI-Vault/Claude Folder/Knowledge Base/` into per-customer OneDrive folders so multiple TTC users can collaborate on the same customer context.
**Agents affected:** Tender, Contracts, Test, TAF (direct) + BwBm (reference update)
**Deferred:** SharePoint migration (current decision: keep OneDrive; re-plan later)

---

## 1. Target architecture

### 1.1 Storage split

```
# GENERAL — stays per-user, TTC-internal
AI-Vault/Claude Folder/Knowledge Base/
├── BwBm/                       (TTC-internal project; stays because BwBm source is separate vault)
├── Finance/                    (TTC contracts, templates, internal financials)
├── Personal/
├── ttc-general/                ← NEW consolidation target for TTC brand/sales methodology
│   ├── sales-playbooks/
│   ├── service-offerings/
│   ├── win-themes/
│   └── pricing-baselines/
├── _index.json
└── _vectordb/

# CUSTOMER — shared via OneDrive, multi-user
<OneDrive customer root>/<Customer>/AI-INFO - DO NOT DELETE/
├── source/                     (symlinks/pointers to originals — optional; or left blank)
├── converted/                  (.txt KB chunks — committed)
├── notes.md                    (collaborative running notes)
├── memory.md                   (AI agent session highlights — what was decided, when)
├── _index.json                 (customer-scoped manifest)
└── README.md                   (explains folder, forbids deletion, names responsible user)
```

### 1.2 Primary customer folder rules (where `AI-INFO - DO NOT DELETE` lives)

| Customer type | Primary folder |
|---|---|
| Active sales pursuit | `OneDrive-TTCGlobal/Sales/Customer/<Region>/<Customer>/` |
| Active delivery | `OneDrive-TTCGlobal/Delivery/<Practice>/<Customer>/` |
| Both sales + delivery | Sales folder is authoritative; delivery folder gets a `README.md` pointer |
| Contracts-only | `OneDrive-TTCGlobal/Admin/Finance_Legal/Customer Contracts/<Customer>/` — only contracts agent writes here; main KB still in sales/delivery |

### 1.3 Initial customer scope (6 customers, all manual first pass)

| # | Customer | Primary folder (confirmed) | Region |
|---|---|---|---|
| 1 | VKB | `Delivery/Leapwork/VKB/` | South Africa (Leapwork delivery) |
| 2 | Dubai Holdings Leapwork | `Sales/Customer/Middle East/Dubai Holdings Leapwork/` | ME |
| 3 | ENOC | `Sales/Customer/Middle East/ENOC/` | ME |
| 4 | Central Bank UAE | `Sales/Customer/Middle East/Central Bank UAE/` | ME |
| 5 | Dubai Islamic Bank (Oracle) | `Sales/Customer/Middle East/Dubai Islamic Bank (Oracle)/` | ME |
| 6 | ADNOC | `Sales/Customer/Middle East/ADNOC/` | ME |

---

## 2. Multi-user access mechanics (confirmed)

**Files (source + `.txt` + notes) → OneDrive handles it.**
- Concurrent edits → OneDrive conflict copies (rare for generated `.txt`)
- Version history (90 days) is automatic
- Permissions via share link per customer folder (no org-wide exposure)

**Vector index (chromadb) → per-user local, never shared.**
- Each user runs `kb_refresh_customer.py <customer>` locally
- Index stored in `~/AI-Vault/Claude Folder/Knowledge Base/_vectordb/<customer>/`
- Rebuild time: seconds for most customer KBs

---

## 3. Implementation plan — phased

### Phase 1 — Design, tooling, conventions (foundation)

| Task | Output | Risk |
|---|---|---|
| 1.1 Write `AI-Vault/docs/KB_CONVENTIONS.md` (single source of truth for all agents) | doc | — |
| 1.2 Extend `convert_to_knowledge_base.py` with `--customer <name>` and `--scope customer\|general` flags; derive customer AI-INFO path from a registry | updated script | medium — don't break existing calls |
| 1.3 Create `AI-Vault/Claude Folder/Knowledge Base/_customer_registry.json` — maps customer → primary OneDrive folder, region, active agents | file | low |
| 1.4 Add `kb_refresh_customer.sh` helper (takes customer name → runs converter → rebuilds chromadb for that customer) | shell script | low |
| 1.5 Add `kb_bootstrap_customer.sh` helper (creates `AI-INFO - DO NOT DELETE/` skeleton + README for new customer) | shell script | low |

### Phase 2 — Migrate 6 existing customers (manual, one at a time)

For each customer in scope:

| Sub-step | Action |
|---|---|
| 2.x.1 | Run `kb_bootstrap_customer.sh <customer>` — creates `AI-INFO - DO NOT DELETE/` + README in primary folder |
| 2.x.2 | Move customer-specific `.txt` from `AI-Vault/Claude Folder/Knowledge Base/` → `<customer>/AI-INFO - DO NOT DELETE/converted/` |
| 2.x.3 | Run `kb_refresh_customer.sh <customer>` — rebuild chromadb scoped to this customer |
| 2.x.4 | Verify via `kb_search` MCP with `customer="<name>"` filter |
| 2.x.5 | If current memory references the old path, update it |

**Order (lowest risk first):**
1. ADNOC (new; nothing to migrate — pure bootstrap)
2. ENOC (recently done; files known, small set)
3. DIB/Dubai Islamic Bank (clean, single RFQ)
4. CBUAE (won tender, finite set)
5. VKB (active delivery; bigger set; validate carefully)
6. Dubai Holdings Leapwork (biggest — many v1/v2/v3 drafts)

### Phase 3 — Agent system-prompt updates

| Agent | Change |
|---|---|
| **Tender** | Add KB Conventions table + `kb_search(customer=...)` guidance; point deliverables at working/ first, customer folder only after confirmation |
| **Contracts** | Add dual-search rule (general Finance KB + customer AI-INFO); add storage rules table |
| **Test** | Add customer KB lookup; clarify memory vs. deliverable location |
| **TAF** | Already has good dual-path rule — extend to also read customer AI-INFO for context |
| **BwBm** | Add pointer note — "if a customer KB exists under OneDrive AI-INFO, prefer it over the general BwBm KB for customer-specific queries" |

All system-prompts link to the new `AI-Vault/docs/KB_CONVENTIONS.md`.

### Phase 4 — Auto-generation for new customers

Goal: when an agent works with a new customer for the first time, the `AI-INFO - DO NOT DELETE` folder is auto-created.

**Approach — explicit, not magic:**
- Add a one-liner helper invocation pattern to agent system-prompts:
  > *"Before saving a new customer's deliverable, run `kb_bootstrap_customer.sh <customer>` if the AI-INFO folder doesn't exist."*
- Bootstrap script is idempotent (skip if exists).
- Registry updates happen inside the bootstrap script.

**Why not a hook?** Filesystem hooks add brittleness; explicit bootstrap is visible in conversation and auditable.

### Phase 5 — Cleanup

| Target | Action |
|---|---|
| Loose `[DubaiHolding]*.txt` at KB root | Move to DH AI-INFO, delete originals after verification |
| Loose Dubai-Holding strategic drafts | Move to DH AI-INFO |
| `Central Bank UAE Proposal.txt` | Move to CBUAE AI-INFO |
| `Middle East/` region folder contents | Per-customer split → respective AI-INFO folders; keep `Middle East/` for unassigned snippets only |
| `Archive/` folder | Leave as-is (audit only); document in KB_CONVENTIONS |
| `_index.json` + `_vector_index.json` | Regenerate after migration |
| `_vectordb/` | Rebuild once all customers migrated (667 MB reclaim) |

---

## 4. Files to create / modify / move

### New files

```
AI-Vault/docs/KB_CONVENTIONS.md                                     ← authoritative rules
AI-Vault/docs/plans/2026-04-20-kb-split-customer-ai-info.md         ← THIS plan
AI-Vault/Claude Folder/Knowledge Base/_customer_registry.json       ← customer → path map
AI-Vault/Claude Folder/kb_bootstrap_customer.sh                     ← scaffold new customer
AI-Vault/Claude Folder/kb_refresh_customer.sh                       ← refresh one customer KB
AI-Vault/Claude Folder/kb_migrate_customer.py                       ← one-shot migrator (Phase 2 only)
```

### Modified files

```
AI-Vault/Claude Folder/convert_to_knowledge_base.py                 ← add --customer, --scope flags
AI-Vault/Agents/Tender/system-prompt.md                             ← storage + KB rules
AI-Vault/Agents/Contracts/system-prompt.md                          ← storage + KB rules
AI-Vault/Agents/Test/system-prompt.md                               ← storage + KB rules
AI-Vault/Agents/TAF/system-prompt.md                                ← add customer KB reading
AI-Vault/Agents/BwBm/system-prompt.md                               ← pointer to customer KB
```

### Moved files (Phase 2 + 5)

Approx. 14 loose `.txt` at KB root → respective customer AI-INFO folders. No deletions until verification step passes.

### New OneDrive folders (per customer)

```
<Customer primary folder>/AI-INFO - DO NOT DELETE/
├── README.md
├── converted/
├── notes.md
└── memory.md
```

---

## 5. `kb_bootstrap_customer.sh` — shape

```bash
kb_bootstrap_customer.sh <customer-name> [--region <region>] [--primary-folder <path>]
```

- Idempotent. If `AI-INFO - DO NOT DELETE/` exists → exit 0 with notice.
- Writes `README.md` with:
  - "AI reference data — do not delete or rename."
  - Created-by, date, customer name
  - Pointer to `AI-Vault/docs/KB_CONVENTIONS.md`
- Updates `_customer_registry.json`
- Prints next steps (run `kb_refresh_customer.sh`)

---

## 6. `kb_refresh_customer.sh` — shape

```bash
kb_refresh_customer.sh <customer-name>
```

1. Read primary folder from `_customer_registry.json`
2. Run `convert_to_knowledge_base.py --customer <name> --source <primary> --dest "<primary>/AI-INFO - DO NOT DELETE/converted"`
3. Rebuild chromadb shard for this customer
4. Report counts (files processed, size, duration)

---

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Colleague accidentally deletes the folder | Name `AI-INFO - DO NOT DELETE` + README warning; OneDrive restore from Recycle Bin within 93 days |
| OneDrive sync delay hides new content from colleague | Document in README: "allow 1-2 min after push"; kb_refresh only reads local filesystem so no cross-device delay for the author |
| Chromadb corruption on shared filesystem | Per-user local indexes only — explicitly documented in KB_CONVENTIONS |
| Plan abandoned halfway (hybrid state) | Registry drives all agents — if a customer isn't in registry, agents fall back to central KB. Safe to migrate one customer at a time |
| Customer ambiguity (same customer, multiple regions) | Registry keys by canonical slug (e.g. `dubai-holdings-leapwork`); multiple OneDrive paths allowed per entry |
| Converter overwrites on conflict | `.txt` files are derived — always reproducible. Worst case: rerun refresh |

---

## 8. Success criteria (Phase-by-phase)

- **Phase 1 done:** KB_CONVENTIONS.md exists, converter supports `--customer`, registry file in place.
- **Phase 2 done:** all 6 customers have populated `AI-INFO - DO NOT DELETE/` folders; `kb_search(customer=...)` returns scoped results.
- **Phase 3 done:** 5 agent prompts updated + committed (ttc-agents repos).
- **Phase 4 done:** Running `apply tender` and saying "I worked on customer Foo today" triggers auto-bootstrap on first save.
- **Phase 5 done:** KB root directory contains zero customer-specific loose files; `_vectordb/` rebuilt; size reduction logged.

---

## 9. Execution order (today, if approved)

1. Write KB_CONVENTIONS.md ← **start here**
2. Build registry JSON with 6 customers
3. Build `kb_bootstrap_customer.sh` (idempotent)
4. Bootstrap ADNOC (smallest, safest first trial)
5. Verify folder + README on Mac Mini via Syncthing (confirms OneDrive path works across machines)
6. Extend `convert_to_knowledge_base.py` — `--customer` flag
7. Build `kb_refresh_customer.sh`
8. Migrate ENOC (second smallest) as full end-to-end trial
9. If ENOC passes → migrate remaining 4 customers
10. Patch agent system-prompts
11. Cleanup loose KB root files
12. Commit all framework + agent changes to their ttc-agents repos

Estimated elapsed time: 2–3 hours of focused work, spread over one or two sessions.

---

## 10. Out of scope (explicitly deferred)

- SharePoint migration (you said later)
- Central chromadb server on Mac Mini / NAS (revisit only if 4+ heavy KB users emerge)
- Automated permission provisioning (AAD groups) — manual share-link grants for now
- KB versioning/snapshots beyond OneDrive's built-in history
- Auto-detection of "customer is new" via LLM parsing of user messages — stay explicit
