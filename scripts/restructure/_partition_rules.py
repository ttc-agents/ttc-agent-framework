#!/usr/bin/env python3
"""Shared partition/leak heuristics (DRY: inventory + curator import these)."""
import re

_SENSITIVE = [
    re.compile(r"\b(rate|day ?rate|daily rate|price|pricing|cost)\b", re.I),
    re.compile(r"\b(salary|salaries|lohn|löhne|compensation|comp band)\b", re.I),
    re.compile(r"\b(EUR|USD|AED|GBP|CHF|€|\$)\s?\d", re.I),
    re.compile(r"\b\d{2,3}k\b", re.I),
    re.compile(r"\b(contract value|profit ?share|margin)\b", re.I),
]

def mentions_customer(text, names):
    t = text.lower()
    return any(n.lower() in t for n in names)


def _norm(s):
    """Lowercase, strip everything non-alphanumeric — so 'Qatar Energy', 'qatar-energy'
    and 'QatarEnergy_BC.pptx' all compare equal at the slug level."""
    return re.sub(r"[^a-z0-9]", "", s.lower())


def path_targets_customer(path_str, customers):
    """STRONG signal: the customer identity is in the file path/name itself, i.e. the
    file is *about* that customer (genuine scatter), not merely mentioning it.

    customers: list of {"label": str, "keys": [slug/display, ...], "aliases": [token, ...]}.
      - keys match as normalized substrings (>=3 chars) of the normalized path.
      - aliases (e.g. 'DH', 'DIB') match as whole path tokens only, so short
        abbreviations don't false-positive on substrings inside other words.

    Returns the matched label, or None.
    """
    norm = _norm(path_str)
    tokens = {t for t in re.split(r"[^a-z0-9]+", path_str.lower()) if t}
    for c in customers:
        for key in c.get("keys", []):
            n = _norm(key)
            if len(n) >= 3 and n in norm:
                return c["label"]
        for alias in c.get("aliases", []):
            if alias.lower() in tokens:
                return c["label"]
    return None

def looks_sensitive(text):
    return any(p.search(text) for p in _SENSITIVE)

def has_review_marker(text):
    return "#curator-review" in text
