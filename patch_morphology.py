#!/usr/bin/env python3
"""
patch_morphology.py
===================
Menambahkan data morfologi (lemma / root) dari data/morphology_map.json ke:
  1. assets/db/quran_master.db
  2. quran_tarteel_hifz/assets/db/quran_master.db
  3. web/data/quran_data.json
  4. web/data/quran_data.js

Aman dijalankan berulang kali (idempoten).
"""
import json
import os
import sqlite3
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MAP_PATH = os.path.join(SCRIPT_DIR, "data", "morphology_map.json")
DB_PATHS = [
    os.path.join(SCRIPT_DIR, "assets", "db", "quran_master.db"),
    os.path.join(SCRIPT_DIR, "quran_tarteel_hifz", "assets", "db", "quran_master.db"),
]
JSON_PATH = os.path.join(SCRIPT_DIR, "web", "data", "quran_data.json")
JS_PATH = os.path.join(SCRIPT_DIR, "web", "data", "quran_data.js")


def load_map():
    with open(MAP_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data["by_verse"], data["by_word"]


def lookup(by_verse, by_word, surah_id, verse_number, position, text_clean):
    rec = by_verse.get(f"{surah_id}:{verse_number}:{position}")
    if rec and (rec.get("lemma") or rec.get("root")):
        return rec.get("lemma", ""), rec.get("root", "")
    rec = by_word.get(text_clean or "")
    if rec:
        return rec.get("lemma", ""), rec.get("root", "")
    return "", ""


def patch_db(path, by_verse, by_word):
    if not os.path.exists(path):
        print(f"[Skip] {path} tidak ada.")
        return
    conn = sqlite3.connect(path)
    cur = conn.cursor()
    cols = {row[1] for row in cur.execute("PRAGMA table_info(words)").fetchall()}
    for col in ("lemma", "root"):
        if col not in cols:
            cur.execute(f"ALTER TABLE words ADD COLUMN {col} TEXT NOT NULL DEFAULT ''")
    conn.commit()

    rows = cur.execute("""
        SELECT w.id, v.surah_id, v.verse_number, w.word_position, w.text_clean
        FROM words w JOIN verses v ON v.id = w.verse_id
    """).fetchall()
    updates = []
    for wid, sid, vnum, pos, clean in rows:
        lemma, root = lookup(by_verse, by_word, sid, vnum, pos, clean)
        updates.append((lemma, root, wid))
    cur.executemany("UPDATE words SET lemma = ?, root = ? WHERE id = ?", updates)
    conn.commit()
    filled = cur.execute("SELECT COUNT(*) FROM words WHERE lemma != '' OR root != ''").fetchone()[0]
    total = cur.execute("SELECT COUNT(*) FROM words").fetchone()[0]
    conn.close()
    print(f"[DB] {os.path.basename(path)}: {filled}/{total} kata memiliki lemma/root.")


def patch_words_in_payload(payload, by_verse, by_word):
    count = 0
    for v in payload.get("verses", []):
        sid = v.get("surah_id")
        vnum = v.get("verse_number")
        for w in v.get("words", []):
            lemma, root = lookup(
                by_verse, by_word, sid, vnum,
                w.get("position") or w.get("word_position"),
                w.get("text_clean"),
            )
            w["lemma"] = lemma
            w["root"] = root
            if lemma or root:
                count += 1
    return count


def patch_json(by_verse, by_word):
    if not os.path.exists(JSON_PATH):
        print("[Skip] quran_data.json tidak ada.")
        return
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        payload = json.load(f)
    count = patch_words_in_payload(payload, by_verse, by_word)
    with open(JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
    print(f"[Web] quran_data.json: {count} kata memiliki lemma/root.")


def patch_js(by_verse, by_word):
    if not os.path.exists(JS_PATH):
        print("[Skip] quran_data.js tidak ada.")
        return
    with open(JS_PATH, "r", encoding="utf-8") as f:
        src = f.read()
    marker = "window.QURAN_DATA = "
    payload = json.loads(src[len(marker):].strip().rstrip(";"))
    count = patch_words_in_payload(payload, by_verse, by_word)
    with open(JS_PATH, "w", encoding="utf-8") as f:
        f.write(marker + json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + ";\n")
    print(f"[Web] quran_data.js: {count} kata memiliki lemma/root.")


def main():
    by_verse, by_word = load_map()
    for db in DB_PATHS:
        patch_db(db, by_verse, by_word)
    patch_json(by_verse, by_word)
    patch_js(by_verse, by_word)


if __name__ == "__main__":
    main()
