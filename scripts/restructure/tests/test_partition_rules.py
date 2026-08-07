from scripts.restructure import _partition_rules as pr  # adjust import per runner

def test_detects_customer_name():
    assert pr.mentions_customer("BwBm regression on Q02", ["bwbm","bundeswehr"]) is True
    assert pr.mentions_customer("generic playwright tip", ["bwbm","bundeswehr"]) is False

def test_detects_sensitive_figures():
    assert pr.looks_sensitive("Day rate EUR 1,250 per consultant") is True
    assert pr.looks_sensitive("salary band 90k-110k") is True
    assert pr.looks_sensitive("the test passed in 1.4m") is False

def test_curator_marker():
    assert pr.has_review_marker("foo\n#curator-review\nbar") is True

# ── Deutsche Commercials (ergaenzt 2026-08-07) ────────────────────────────
# Vorher wurden diese Faelle NICHT erkannt: es griffen nur englische Begriffe.
def test_german_day_rate_without_currency():
    assert pr.looks_sensitive("Der Tagessatz betraegt 1450 pro Consultant") is True


def test_german_umlaut_and_ascii_variants():
    assert pr.looks_sensitive("Die Tagessätze wurden neu verhandelt") is True
    assert pr.looks_sensitive("Die Tagessaetze wurden neu verhandelt") is True
    assert pr.looks_sensitive("Die Vergütung wurde angepasst") is True
    assert pr.looks_sensitive("Die Verguetung wurde angepasst") is True


def test_german_contract_value_and_margin():
    assert pr.looks_sensitive("Der Auftragswert liegt ueber Plan") is True
    assert pr.looks_sensitive("Die Marge ist zu duenn") is True


def test_german_harmless_stays_harmless():
    assert pr.looks_sensitive("Der Testlauf dauerte 1,4 Minuten") is False
    assert pr.looks_sensitive("Die Teststrategie wurde abgestimmt") is False
