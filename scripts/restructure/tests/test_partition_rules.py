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
