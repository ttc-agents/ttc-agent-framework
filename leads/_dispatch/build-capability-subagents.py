#!/usr/bin/env python3
"""Generate the Customer-Lead capability DISPATCH sub-agent definitions — single source of truth.

These let a Customer Lead DISPATCH a capability (own fresh context, returns just the result) instead
of only LOADing it inline. Mirrors AutoLead's build-subagents.py: the generated defs DO NOT copy
persona text — each sub-agent READS the authoritative capability persona + the partition-law at
runtime, so there is no content drift and NO duplicate agent (one persona, two invocation styles:
interactive `apply <cap>` and dispatchable `cap-<cap>`).

Scope: cap-sap, cap-qa-tom, cap-tender, cap-contracts, cap-docs (all 5 customer-facing capabilities).
Test/TAF dispatch is already covered by AutoLead's test-designer/taf-author/taf-healer/triage.

Outputs:
  - canonical defs  -> Agents/Leads/_dispatch/subagents/<name>.md   (committed, source of truth)
  - installed defs  -> ~/.claude/agents/<name>.md                   (what Claude Code dispatches)

Usage:
    python3 build-capability-subagents.py            # generate + install
    python3 build-capability-subagents.py --check    # verify installed == generated (drift check); exit 1 on drift
"""
import os
import sys
import difflib

HOME = os.path.expanduser("~")
VAULT = "{{AI_VAULT}}"
SUBAGENT_SRC = os.path.join(VAULT, "Agents/Leads/_dispatch/subagents")
INSTALL_DIR = os.path.join(HOME, ".claude/agents")

# Authoritative persona sources (READ at runtime by the sub-agent, never copied here).
SAP_PROMPT = f"{VAULT}/Agents/SAP/system-prompt.md"
QA_TOM_PROMPT = f"{VAULT}/Agents/QA_TOM_Generator/system-prompt.md"
TENDER_PROMPT = f"{VAULT}/Agents/Tender/system-prompt.md"
CONTRACTS_PROMPT = f"{VAULT}/Agents/Contracts/system-prompt.md"
DOCS_PROMPT = f"{VAULT}/Agents/Docs/system-prompt.md"
PARTITION_LAW = f"{VAULT}/Agents/Leads/_partition-law.md"

DISPATCH_CONTRACT = """\
## Dispatch contract (all capability sub-agents)
- You are a customer-free CAPABILITY dispatched for ONE focused task. Your brief contains the task
  and a **customer slice** (only the context you need — not the whole customer record). You have no
  memory of the dispatching session; rely only on the brief + the files it points to + your persona.
- Obey `Agents/Leads/_partition-law.md`. Persist **NO** customer-specific facts (engagement state,
  client decisions, commercial figures) in your capability memory. You MAY record a reusable,
  customer-free learning's essence there with a reuse-pointer — never customer figures/decisions.
- Customer deliverables you produce go to the paths the brief specifies (the Lead's `working/` or the
  customer Team-tier), NEVER into capability memory.
- **Return a concise result as your FINAL message:** what you produced, where any files went, key
  decisions, open questions/blockers. The dispatching Lead owns integration + the customer worklog.
- **Verification discipline:** never claim a command/search succeeded unless you ran it and checked
  the output. If you couldn't (no live system, kb_search needs an MCP reconnect, …), say so plainly.
- **Autonomy:** try 2-3 approaches before escalating; flag for Joerg only for fundamental problems."""

SUBAGENTS = {
    "cap-sap": {
        "description": ("Dispatchable SAP capability — S/4HANA architecture, BPH/scope analysis, "
                        "effort/ROI estimation inputs, SAP testing guidance. Dispatch from a Customer "
                        "Lead (or for customer-free technical work) for a focused SAP task; you get a "
                        "customer slice, return the result, and persist no customer data."),
        "model": "opus",
        "tools": "Read, Write, Edit, Grep, Glob, Bash, mcp__knowledge-base",
        "read_at_start": [SAP_PROMPT, PARTITION_LAW],
        "role": """\
## Your role — dispatched SAP capability
Apply SAP S/4HANA expertise (read the SAP persona) to the ONE focused task in your brief:
architecture advice, BPH/scope analysis, effort/ROI estimation inputs, SAP testing guidance, or
landscape/implementation-pack questions. Use `kb_search` for the customer/project context the brief
points you to. Produce the requested artefact (analysis, estimate, recommendation) and return it —
do not sprawl beyond the task or re-open settled scope.""",
    },
    "cap-qa-tom": {
        "description": ("Dispatchable QA-TOM capability — consulting-grade QA Target Operating Models, "
                        "maturity/standards artefacts, ROI/business-case modelling, Phase-Zero "
                        "deliverables. Dispatch from a Customer Lead for a focused TOM/BC task; you get "
                        "a customer slice, return the artefact, and persist no customer data."),
        "model": "opus",
        "tools": "Read, Write, Edit, Grep, Glob, Bash, mcp__knowledge-base",
        "read_at_start": [QA_TOM_PROMPT, PARTITION_LAW],
        "role": """\
## Your role — dispatched QA-TOM capability
Build or refresh QA Target Operating Models and business cases (read the QA-TOM persona) for the ONE
focused task in your brief: a TOM section, a maturity/standards artefact, an ROI/BC model, or a
Phase-Zero deliverable. Apply the QA-TOM 6-phase method as far as the slice requires. Use `kb_search`
for the customer's existing context. Return the artefact + a concise summary; the dispatching Lead
owns integration and the customer-side worklog (incl. any commercial figures, which stay Lead-local).""",
    },
    "cap-tender": {
        "description": ("Dispatchable Tender capability — RFP/RFQ responses, proposals, qualification "
                        "statements, win themes, technical/commercial bid sections. Dispatch from a "
                        "Customer Lead for a focused proposal task; you get a customer slice, return "
                        "the draft, and persist no customer data."),
        "model": "opus",
        "tools": "Read, Write, Edit, Grep, Glob, Bash, mcp__knowledge-base",
        "read_at_start": [TENDER_PROMPT, PARTITION_LAW],
        "role": """\
## Your role — dispatched Tender capability
Produce persuasive, on-brand proposal content (read the Tender persona) for the ONE focused task in
your brief: an RFP/RFQ response section, a qualification statement, an executive briefing, win themes.
Use `kb_search` for the customer's existing context and TTC win material. Return the draft + a short
summary; the dispatching Lead owns where it ships (its `working/` until Joerg says "ship it").""",
    },
    "cap-contracts": {
        "description": ("Dispatchable Contracts capability — contract/NDA/SOW/MSA review, clause "
                        "analysis, redlines, risk flags, fallback positions. Dispatch from a Customer "
                        "Lead for a focused legal-review task; you get a customer slice, return the "
                        "analysis, and persist no customer data."),
        "model": "opus",
        "tools": "Read, Write, Edit, Grep, Glob, Bash, mcp__knowledge-base",
        "read_at_start": [CONTRACTS_PROMPT, PARTITION_LAW],
        "role": """\
## Your role — dispatched Contracts capability
Apply legal-review rigour (read the Contracts persona) to the ONE focused task in your brief: review a
contract/NDA/SOW/MSA, flag risks, propose redlines/fallbacks, analyse a clause. Use `kb_search` for
prior TTC positions. Return the analysis/redline + a concise risk summary. Executed/final commercial
docs belong in the Finance/Legal-circle stores — never in capability memory.""",
    },
    "cap-docs": {
        "description": ("Dispatchable Docs capability — TTC-branded PPTX/Word/Excel generation from a "
                        "brief or content. Dispatch from a Customer Lead for a focused document/deck "
                        "task; you get a customer slice + content, return the generated artefact, and "
                        "persist no customer data."),
        "model": "sonnet",
        "tools": "Read, Write, Edit, Grep, Glob, Bash, mcp__knowledge-base",
        "read_at_start": [DOCS_PROMPT, PARTITION_LAW],
        "role": """\
## Your role — dispatched Docs capability
Generate TTC-branded documents (read the Docs persona) for the ONE focused task in your brief: a PPTX
deck, a Word document, or an Excel workbook, from the content/brief provided. Use the Docs generators
(create_ttc_docx.py, the pptx builders, the excel helpers) via Bash — follow the catalogue-first +
brand-fidelity rules. Write the output to the path the brief specifies (the Lead's `working/`), and
return the path + a short build summary.""",
    },
}

GEN_HEADER = ("<!-- GENERATED by Agents/Leads/_dispatch/build-capability-subagents.py — DO NOT EDIT "
              "BY HAND. Edit the generator or the source personas instead, then re-run. -->")


def render(name, spec):
    read_list = "\n".join(f"- `{p}`" for p in spec["read_at_start"])
    parts = [
        "---",
        f"name: {name}",
        f"description: {spec['description']}",
        f"tools: {spec['tools']}",
        f"model: {spec['model']}",
        "---",
        "",
        GEN_HEADER,
        "",
        f"# {name} — Customer-Lead capability dispatch sub-agent",
        "",
        "## Read these at the start (authoritative source — not duplicated here)",
        read_list,
        "",
        spec["role"],
        "",
        DISPATCH_CONTRACT,
    ]
    return "\n".join(parts) + "\n"


def main(argv):
    generated = {name: render(name, spec) for name, spec in SUBAGENTS.items()}
    if "--check" in argv:
        drift = False
        for name, text in generated.items():
            for label, d in (("canonical", SUBAGENT_SRC), ("installed", INSTALL_DIR)):
                p = os.path.join(d, f"{name}.md")
                if not os.path.exists(p) or open(p, encoding="utf-8").read() != text:
                    print(f"DRIFT: {label} {name}.md differs from generator output")
                    drift = True
        print("DRIFT detected — re-run without --check." if drift else "OK — no drift.")
        sys.exit(1 if drift else 0)
    os.makedirs(SUBAGENT_SRC, exist_ok=True)
    os.makedirs(INSTALL_DIR, exist_ok=True)
    for name, text in generated.items():
        for d in (SUBAGENT_SRC, INSTALL_DIR):
            with open(os.path.join(d, f"{name}.md"), "w", encoding="utf-8") as fh:
                fh.write(text)
        print(f"generated + installed: {name}")


if __name__ == "__main__":
    main(sys.argv[1:])
