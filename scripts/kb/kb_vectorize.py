#!/usr/bin/env python3
"""
Knowledge Base Vectorizer
Chunks text files from the Knowledge Base and stores them in ChromaDB
with sentence-transformer embeddings for semantic search.

Uses the same _index.json delta logic as convert_to_knowledge_base.py.

Usage:
    python3 kb_vectorize.py                   # delta run (only new/changed)
    python3 kb_vectorize.py --force           # re-vectorize everything
    python3 kb_vectorize.py --source /path    # specific source folder
"""

import os
import sys
import json
import hashlib
import argparse
from pathlib import Path
from datetime import datetime

import chromadb
from sentence_transformers import SentenceTransformer

# ── Configuration ─────────────────────────────────────────────────────────────

KB_ROOT = Path("/Users/joergpietzsch/AI-Vault/Claude Folder/Knowledge Base")
REGISTRY_FILE = KB_ROOT / "_customer_registry.json"
VECTOR_DB_PATH = KB_ROOT / "_vectordb"
VECTOR_INDEX_FILE = KB_ROOT / "_vector_index.json"

CHUNK_SIZE = 500       # words per chunk
CHUNK_OVERLAP = 50     # overlap words between chunks
EMBEDDING_MODEL = "all-MiniLM-L6-v2"
COLLECTION_NAME = "knowledge_base"

# ── Helpers ───────────────────────────────────────────────────────────────────

def load_vector_index() -> dict:
    if VECTOR_INDEX_FILE.exists():
        with open(VECTOR_INDEX_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_vector_index(index: dict):
    with open(VECTOR_INDEX_FILE, "w", encoding="utf-8") as f:
        json.dump(index, f, indent=2, ensure_ascii=False)


def file_checksum(path: Path) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def chunk_text(text: str, chunk_size: int = CHUNK_SIZE, overlap: int = CHUNK_OVERLAP) -> list[str]:
    """Split text into overlapping word-based chunks."""
    words = text.split()
    if not words:
        return []

    chunks = []
    start = 0
    while start < len(words):
        end = start + chunk_size
        chunk = " ".join(words[start:end])
        if chunk.strip():
            chunks.append(chunk)
        if end >= len(words):
            break
        start = end - overlap

    return chunks


def extract_metadata(txt_path: Path, kb_root: Path, override: dict = None) -> dict:
    """Extract region, customer, and other metadata from the file path."""
    if override:
        meta = dict(override)
        meta["filename"] = txt_path.name
        meta["source_path"] = str(txt_path)
        meta["doc_type"] = txt_path.suffix
        return meta

    try:
        rel = txt_path.relative_to(kb_root)
        parts = rel.parts
        region = parts[0] if len(parts) > 1 else "Unknown"
        customer = parts[1] if len(parts) > 2 else "Unknown"
    except ValueError:
        region = "Unknown"
        customer = "Unknown"

    return {
        "region": region,
        "customer": customer,
        "filename": txt_path.name,
        "source_path": str(txt_path),
        "doc_type": txt_path.suffix,
    }


def load_registry() -> dict:
    if REGISTRY_FILE.exists():
        with open(REGISTRY_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    return {"customers": {}}


def resolve_customer(name_or_slug: str) -> tuple[str, dict]:
    """Return (slug, entry) for a customer by display name or slug."""
    reg = load_registry()
    customers = reg.get("customers", {})
    if name_or_slug in customers:
        return name_or_slug, customers[name_or_slug]
    for slug, entry in customers.items():
        if entry.get("display_name", "").lower() == name_or_slug.lower():
            return slug, entry
    import re
    slug = re.sub(r"[^a-z0-9]+", "-", name_or_slug.lower()).strip("-")
    if slug in customers:
        return slug, customers[slug]
    raise KeyError(f"Customer not found in registry: {name_or_slug}")


# ── Main logic ────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Vectorize Knowledge Base text files into ChromaDB.")
    parser.add_argument("--force", action="store_true", help="Re-vectorize all files.")
    parser.add_argument("--source", type=Path, default=None, help="Override source folder.")
    parser.add_argument("--customer", type=str, default=None,
                        help="Customer name or slug — vectorize just that customer's AI-INFO/converted folder.")
    args = parser.parse_args()

    metadata_override = None
    if args.customer:
        try:
            slug, entry = resolve_customer(args.customer)
        except KeyError as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(2)
        source = Path(entry["ai_info_folder"]) / "converted"
        metadata_override = {
            "customer": entry.get("display_name", slug),
            "customer_slug": slug,
            "region": entry.get("region", "Unknown"),
        }
        print(f"Customer   : {entry['display_name']}  (slug: {slug})")
        print(f"Source     : {source}")
    else:
        source = args.source if args.source else KB_ROOT

    vector_index = load_vector_index()

    # Initialize ChromaDB
    print(f"Initializing ChromaDB at {VECTOR_DB_PATH}")
    client = chromadb.PersistentClient(path=str(VECTOR_DB_PATH))

    if args.force:
        # Delete and recreate collection on force
        try:
            client.delete_collection(COLLECTION_NAME)
            print("Deleted existing collection (--force)")
        except Exception:
            pass
        vector_index = {}

    collection = client.get_or_create_collection(
        name=COLLECTION_NAME,
        metadata={"hnsw:space": "cosine"},
    )

    # Load embedding model
    print(f"Loading embedding model: {EMBEDDING_MODEL}")
    model = SentenceTransformer(EMBEDDING_MODEL)

    # Discover all .txt files (skip index files, vector DBs, and AI-INFO notes/memory/README at top level)
    skip_names = {"_index.json", "_vector_index.json", "notes.md", "memory.md", "README.md"}
    all_files = [
        p for p in source.rglob("*.txt")
        if p.is_file()
        and "_vectordb" not in str(p)
        and p.name not in skip_names
    ]

    print(f"Found {len(all_files)} text files in {source}")
    print(f"Vector index has {len(vector_index)} previously vectorized entries\n")

    vectorized = 0
    skipped = 0
    errors = []
    total_chunks = 0

    for i, txt_path in enumerate(all_files, start=1):
        src_key = str(txt_path)
        checksum = file_checksum(txt_path)

        # Delta check
        if not args.force and src_key in vector_index:
            if vector_index[src_key].get("checksum") == checksum:
                skipped += 1
                continue

        try:
            text = txt_path.read_text(encoding="utf-8", errors="replace")
            if not text.strip():
                skipped += 1
                continue

            chunks = chunk_text(text)
            if not chunks:
                skipped += 1
                continue

            metadata = extract_metadata(txt_path, KB_ROOT, override=metadata_override)

            # Remove old chunks for this file if re-processing
            old_ids = [f"{src_key}::chunk_{j}" for j in range(1000)]
            try:
                collection.delete(ids=old_ids)
            except Exception:
                pass

            # Embed chunks
            embeddings = model.encode(chunks, show_progress_bar=False).tolist()

            # Prepare batch data
            ids = [f"{src_key}::chunk_{j}" for j in range(len(chunks))]
            metadatas = [
                {**metadata, "chunk_index": j, "total_chunks": len(chunks)}
                for j in range(len(chunks))
            ]

            # Upsert into ChromaDB (batch if needed — max 5000 per call)
            BATCH = 5000
            for b_start in range(0, len(ids), BATCH):
                b_end = b_start + BATCH
                collection.upsert(
                    ids=ids[b_start:b_end],
                    embeddings=embeddings[b_start:b_end],
                    documents=chunks[b_start:b_end],
                    metadatas=metadatas[b_start:b_end],
                )

            total_chunks += len(chunks)
            vectorized += 1

            # Update vector index
            vector_index[src_key] = {
                "checksum": checksum,
                "chunks": len(chunks),
                "vectorized_at": datetime.now().isoformat(),
            }

            try:
                display_rel = txt_path.relative_to(KB_ROOT)
            except ValueError:
                display_rel = txt_path
            print(f"[{i}/{len(all_files)}] VECTORIZED {display_rel} ({len(chunks)} chunks)")

        except Exception as e:
            errors.append((txt_path, str(e)))
            print(f"[{i}/{len(all_files)}] ERROR      {txt_path.relative_to(KB_ROOT)} — {e}")

        # Save index periodically
        if i % 50 == 0:
            save_vector_index(vector_index)

    # Final save
    save_vector_index(vector_index)

    print(f"\n── Summary ───────────────────────────────")
    print(f"  Vectorized : {vectorized} files ({total_chunks} chunks)")
    print(f"  Skipped    : {skipped} (unchanged or empty)")
    print(f"  Errors     : {len(errors)}")
    print(f"  Collection : {collection.count()} total chunks in DB")
    print(f"  Index      : {VECTOR_INDEX_FILE}")
    if errors:
        print(f"\n── Errors ────────────────────────────────")
        for src, msg in errors[:20]:
            print(f"  {src.name}: {msg}")
        if len(errors) > 20:
            print(f"  ... and {len(errors) - 20} more")


if __name__ == "__main__":
    main()
