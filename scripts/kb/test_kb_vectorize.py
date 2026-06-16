import importlib.util
import pathlib

import chromadb
import numpy as np

KBV_PATH = pathlib.Path(__file__).parent / "kb_vectorize.py"
_spec = importlib.util.spec_from_file_location("kb_vectorize", KBV_PATH)
kbv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(kbv)


class StubModel:
    """Deterministic stand-in for SentenceTransformer — avoids loading model weights."""
    def encode(self, chunks, show_progress_bar=False):
        return np.zeros((len(chunks), 8), dtype="float32")


def _collection(tmp_path):
    client = chromadb.PersistentClient(path=str(tmp_path / "_vectordb"))
    return client.get_or_create_collection(name="knowledge_base", metadata={"hnsw:space": "cosine"})


def _registry(tmp_path):
    """alpha = team-tier worklog (indexable); beta = only a restricted vault, no worklog."""
    wl = tmp_path / "alpha_ai_info" / "worklog.md"
    wl.parent.mkdir(parents=True, exist_ok=True)
    wl.write_text("# Alpha worklog\n## 2026-06-15 — did a thing\n- detail one\n- detail two\n", encoding="utf-8")

    beta_ai = tmp_path / "beta_ai_info"
    beta_ai.mkdir(parents=True, exist_ok=True)
    restricted = tmp_path / "beta_restricted" / "worklog.md"
    restricted.parent.mkdir(parents=True, exist_ok=True)
    restricted.write_text("SENTINEL_RESTRICTED_MUST_NOT_BE_INDEXED\n", encoding="utf-8")

    reg = {"customers": {
        "alpha": {"display_name": "Alpha Corp", "region": "Test Region", "status": "active",
                  "worklog": str(wl), "ai_info_folder": str(wl.parent)},
        "beta": {"display_name": "Beta Ltd", "region": "Test Region", "status": "active",
                 "restricted_ai_info": str(restricted.parent), "ai_info_folder": str(beta_ai)},
    }}
    return reg, wl


def test_worklog_happy_path_indexed_with_doc_type(tmp_path):
    coll = _collection(tmp_path)
    reg, wl = _registry(tmp_path)
    vidx = {}
    v, s, c = kbv.vectorize_worklogs(reg, coll, StubModel(), vidx, force=False)
    assert v == 1 and c >= 1
    metas = coll.get(include=["metadatas"])["metadatas"]
    assert len(metas) >= 1
    assert all(m["doc_type"] == "worklog" for m in metas)
    assert all(m["customer"] == "Alpha Corp" for m in metas)
    assert all(m["customer_slug"] == "alpha" for m in metas)
    assert all(m["region"] == "Test Region" for m in metas)
    assert str(wl) in vidx


def test_restricted_path_never_read(tmp_path):
    coll = _collection(tmp_path)
    reg, wl = _registry(tmp_path)
    kbv.vectorize_worklogs(reg, coll, StubModel(), {}, force=False)
    joined = "\n".join(coll.get(include=["documents"])["documents"])
    assert "SENTINEL_RESTRICTED_MUST_NOT_BE_INDEXED" not in joined


def test_delta_noop_on_unchanged(tmp_path):
    coll = _collection(tmp_path)
    reg, wl = _registry(tmp_path)
    vidx = {}
    kbv.vectorize_worklogs(reg, coll, StubModel(), vidx, force=False)
    v2, s2, c2 = kbv.vectorize_worklogs(reg, coll, StubModel(), vidx, force=False)
    assert v2 == 0 and s2 == 1


def test_delta_rechunk_no_duplicates_on_change(tmp_path):
    coll = _collection(tmp_path)
    reg, wl = _registry(tmp_path)
    vidx = {}
    kbv.vectorize_worklogs(reg, coll, StubModel(), vidx, force=False)
    wl.write_text("# Alpha worklog\n## 2026-06-16 — new entry\n- changed content entirely\n", encoding="utf-8")
    kbv.vectorize_worklogs(reg, coll, StubModel(), vidx, force=False)
    got = coll.get()
    assert len(got["ids"]) == len(set(got["ids"]))
    assert all(str(wl) in i for i in got["ids"])


def test_missing_worklog_file_not_included(tmp_path):
    coll = _collection(tmp_path)
    reg, wl = _registry(tmp_path)
    reg["customers"]["spar"] = {"display_name": "SPAR", "region": "DACH",
                                "worklog": str(tmp_path / "nonexistent" / "worklog.md")}
    v, s, c = kbv.vectorize_worklogs(reg, coll, StubModel(), {}, force=False)
    assert v == 1
    assert coll.count() == c  # only alpha's chunks; beta + spar contributed nothing


def test_archived_customer_excluded(tmp_path):
    coll = _collection(tmp_path)
    reg, wl = _registry(tmp_path)
    reg["customers"]["alpha"]["status"] = "archived"
    v, s, c = kbv.vectorize_worklogs(reg, coll, StubModel(), {}, force=False)
    assert v == 0
    assert coll.count() == 0


def test_worklogs_force_preserves_other_docs(tmp_path):
    coll = _collection(tmp_path)
    coll.add(ids=["other::chunk_0"], embeddings=[[0.0] * 8],
             documents=["unrelated KB content"],
             metadatas=[{"doc_type": ".txt", "customer": "X", "region": "Y"}])
    reg, wl = _registry(tmp_path)
    kbv.vectorize_worklogs(reg, coll, StubModel(), {}, force=True)
    assert coll.get(ids=["other::chunk_0"])["ids"] == ["other::chunk_0"]
