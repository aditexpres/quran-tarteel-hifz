#!/usr/bin/env python3
"""
build_morphology_map.py
=======================
Membangun peta morfologi kata Al-Qur'an (LEMMA = bentuk kata baku, ROOT = akar kata)
dari Quranic Arabic Corpus (quran-morphology.txt).

Output: data/morphology_map.json
  {
    "by_verse": { "2:2:2": {"lemma": "كِتَاب", "root": "كتب"} },
    "by_word":  { "الكتاب": {"lemma": "كِتَاب", "root": "كتب"} }
  }

Peta ini dipakai oleh:
  - build_quran_db.py      -> mengisi kolom `lemma` & `root` di quran_master.db
  - build_full_30_juz.py   -> mengisi kolom `lemma` & `root` saat generate 30 juz
  - export_web_data.py     -> mengekspor `lemma` & `root` ke web/data/quran_data.json
  - patch_morphology.py    -> menambahkan kolom ke database & bundle web yang sudah ada

Sumber data (6,3 MB) diunduh otomatis bila belum tersedia.
"""
import json
import os
import re
import sys
import urllib.request
from collections import defaultdict

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SOURCE_PATH = os.path.join(SCRIPT_DIR, "data", "quran-morphology.txt")
OUT_PATH = os.path.join(SCRIPT_DIR, "data", "morphology_map.json")
SOURCE_URL = (
    "https://raw.githubusercontent.com/waliori/qurangraph/simple-graph/"
    "data/source/quran-morphology.txt"
)

# Sama persis dengan remove_diacritics() di build_quran_db.py / export_web_data.py
ARABIC_DIACRITICS_RE = re.compile(
    r"[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06DC\u06DF-\u06E8\u06EA-\u06ED\u0640]"
)


def remove_diacritics(text: str) -> str:
    if not text:
        return ""
    cleaned = ARABIC_DIACRITICS_RE.sub("", text)
    cleaned = re.sub(r"[أإآٱ]", "ا", cleaned)
    cleaned = cleaned.replace("ى", "ي").replace("ة", "ه").replace("ؤ", "و").replace("ئ", "ي")
    return re.sub(r"\s+", " ", cleaned).strip()


def ensure_source() -> None:
    if os.path.exists(SOURCE_PATH) and os.path.getsize(SOURCE_PATH) > 1000000:
        return
    os.makedirs(os.path.dirname(SOURCE_PATH), exist_ok=True)
    print(f"Mengunduh corpus morfologi dari {SOURCE_URL} ...", flush=True)
    req = urllib.request.Request(SOURCE_URL, headers={"User-Agent": "QuranTarteelHifz/1.0"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        payload = resp.read()
    with open(SOURCE_PATH, "wb") as f:
        f.write(payload)
    print(f"  -> {len(payload)} byte tersimpan di {SOURCE_PATH}", flush=True)


def parse_corpus():
    ensure_source()
    segments = defaultdict(list)
    order = []
    with open(SOURCE_PATH, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\r\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 4:
                continue
            loc, form, _pos, features = parts[0], parts[1], parts[2], parts[3]
            bits = loc.split(":")
            if len(bits) < 3:
                continue
            key = f"{bits[0]}:{bits[1]}:{bits[2]}"
            if key not in segments:
                order.append(key)
            segments[key].append((form, features))

    by_verse = {}
    tally = defaultdict(lambda: defaultdict(int))
    for key in order:
        rows = segments[key]
        surface = "".join(r[0] for r in rows).strip()
        root = ""
        lemma = ""
        # Lemma harus diambil dari segmen yang sama dengan ROOT (batang kata),
        # bukan dari prefiks seperti الـ yang juga punya tag LEM.
        stem = None
        for form, features in rows:
            if "ROOT:" in features:
                stem = (form, features)
                break
        if stem is None:
            # Tanpa ROOT (partikel / kata ganti): ambil segmen bukan prefiks terakhir.
            for form, features in rows:
                if "PREF" not in features:
                    stem = (form, features)
        candidates = [stem] if stem is not None else rows
        for _form, features in candidates:
            for tag in features.split("|"):
                if tag.startswith("ROOT:") and not root:
                    root = tag[5:].strip()
                elif tag.startswith("LEM:") and not lemma:
                    lemma = tag[4:].strip()
        if not (root or lemma):
            continue
        rec = {"lemma": lemma, "root": root}
        by_verse[key] = rec
        norm = remove_diacritics(surface)
        if len(norm) >= 2:
            tally[norm][lemma] += 1
            tally[norm][root] += 1

    by_word = {}
    for norm, counts in tally.items():
        lemma = max(counts, key=lambda k: counts[k]) if counts else ""
        by_word[norm] = {"lemma": lemma, "root": next(iter(counts), "")}
    # Vote terpisah agar lemma & root tidak saling menimpa
    lemma_tally = defaultdict(lambda: defaultdict(int))
    root_tally = defaultdict(lambda: defaultdict(int))
    for key in order:
        rec = by_verse.get(key)
        if not rec:
            continue
        surface = "".join(r[0] for r in segments[key]).strip()
        norm = remove_diacritics(surface)
        if len(norm) < 2:
            continue
        if rec["lemma"]:
            lemma_tally[norm][rec["lemma"]] += 1
        if rec["root"]:
            root_tally[norm][rec["root"]] += 1
    for norm in set(lemma_tally) | set(root_tally):
        lemma = max(lemma_tally[norm], key=lemma_tally[norm].get) if lemma_tally[norm] else ""
        root = max(root_tally[norm], key=root_tally[norm].get) if root_tally[norm] else ""
        by_word[norm] = {"lemma": lemma, "root": root}

    return by_verse, by_word


def main():
    by_verse, by_word = parse_corpus()
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump({"by_verse": by_verse, "by_word": by_word}, f, ensure_ascii=False, separators=(",", ":"))
    print(
        f"Morphology map selesai: {len(by_verse)} entri per-ayat, "
        f"{len(by_word)} entri per-kata -> {OUT_PATH}",
        flush=True,
    )


if __name__ == "__main__":
    main()
