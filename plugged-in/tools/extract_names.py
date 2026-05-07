"""
extract_names.py — one-time tool
Pulls top names from the names-dataset library and writes
  res://data/names.json
which NameDB.gd loads at runtime.

Usage (from repo root or the plugged-in folder):
    python tools/extract_names.py

Requires:
    pip install names-dataset
"""

import json
import os
import sys

try:
    from names_dataset import NameDataset
except ImportError:
    print("ERROR: names-dataset is not installed.  Run:  pip install names-dataset")
    sys.exit(1)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Countries chosen for cultural diversity matching a multicultural city.
COUNTRIES = ["US", "GB", "BR", "FR", "DE", "JP", "NG", "MX", "IN", "KR"]
TOP_N     = 60   # top N male + top N female first names per country
TOP_LAST  = 60   # top N last names per country

# ---------------------------------------------------------------------------
# Extract
# ---------------------------------------------------------------------------

print("Loading NameDataset (this may take a moment)…")
nd = NameDataset()
print("Dataset loaded.")

first_set: set[str] = set()
last_set:  set[str] = set()

for cc in COUNTRIES:
    try:
        # First names — returns {'CC': {'M': [...], 'F': [...]}}
        top    = nd.get_top_names(n=TOP_N, country_alpha2=cc)
        d_top  = top.get(cc, {})
        m_names: list[str] = d_top.get("M", []) if isinstance(d_top, dict) else []
        f_names: list[str] = d_top.get("F", []) if isinstance(d_top, dict) else []

        # Last names — returns {'CC': ['Smith', ...]}  (plain list, no gender)
        lasts  = nd.get_top_names(n=TOP_LAST, use_first_names=False, country_alpha2=cc)
        d_last = lasts.get(cc, [])
        l_names: list[str] = d_last if isinstance(d_last, list) else []

        for name in m_names + f_names:
            if name and name.isascii():
                first_set.add(name.strip().title())
        for name in l_names:
            if name and name.isascii():
                last_set.add(name.strip().title())

        print(f"  {cc}: {len(m_names)} male, {len(f_names)} female first names; "
              f"{len(l_names)} last names")
    except Exception as e:
        print(f"  {cc}: skipped ({e})")

first_names = sorted(first_set)
last_names  = sorted(last_set)

print(f"\nTotal unique first names : {len(first_names)}")
print(f"Total unique last names  : {len(last_names)}")

# ---------------------------------------------------------------------------
# Write output
# ---------------------------------------------------------------------------

out_path = os.path.join(os.path.dirname(__file__), "..", "data", "names.json")
out_path = os.path.normpath(out_path)
os.makedirs(os.path.dirname(out_path), exist_ok=True)

with open(out_path, "w", encoding="utf-8") as f:
    json.dump({"first_names": first_names, "last_names": last_names},
              f, ensure_ascii=False, indent=1)

print(f"\nWritten to: {out_path}")
