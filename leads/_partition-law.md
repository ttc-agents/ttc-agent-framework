# Partition Law (canonical — do not duplicate; link here)

When storing ANY knowledge, answer two questions:

1. **Ownership** — "specific to exactly THIS customer, or generally reusable?"
   - Customer-specific (facts, decisions, status, Belege, deliverables) → Customer plane: the Lead's stores (Team `AI-INFO/`, worklog) — and Restricted vault if sensitive.
   - Reusable (method, skill, framework code, template, tool idiom, domain knowledge) → Capability plane: `Agents/<Capability>/{memory,skills}` or `Knowledge Base/<domain>/`.
   - Technique done *on* a customer but not customer-specific → Capability plane **+ a one-line reuse-pointer in the customer worklog**.

2. **Confidentiality** — "Team / Restricted / Secret?"
   - Team → shared store (team-readable).
   - Restricted (rates, pricing, cost, contracts, legal positions, HR/salaries, PII) → Restricted vault (`Admin/Finance_Legal`, `Admin/HR*`, `Legal/`), shared per-folder with the circle only.
   - Secret (credentials/keys) → 1Password.

**If genuinely unsure where something belongs:** do NOT guess. Write it to the most likely place and add the marker `#curator-review` on its own line so the Curator escalates it.

**Restricted circle (2026-05-31):** Finance/Legal/Rates/Contracts/Cost = Alice, Janine, Christian, Joerg. HR (salaries/PII) = Alice, Janine, Joerg (NOT Christian).
