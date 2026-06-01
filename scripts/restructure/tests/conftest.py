"""Put the AI-Vault root on sys.path so `from scripts.restructure import ...` resolves
no matter which directory pytest is invoked from (repo root, scripts/restructure, or here)."""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[3]))
