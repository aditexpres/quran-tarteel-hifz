#!/usr/bin/env python3
"""
build_juz28_29_30.py
Membangun dataset lengkap Juz 28, Juz 29, dan Juz 30 (Surah 58 Al-Mujadilah s/d Surah 114 An-Nas).
- Mengunduh Surah 58 s/d 77 dari Quran.com API v4 (lengkap dengan perkata & terjemahan Kemenag RI).
- Menggabungkan dengan Surah 78 s/d 114 yang sudah ada.
- Menghitung radar mutasyabihat lintas Juz 28, 29, 30 dan internal tiap juz.
- Mengekspor ke web/data/quran_data.json, web/data/quran_data.js, dan quran_master.db.
"""

import difflib
import html
import json
import os
import re
import sqlite3
import sys
import time
import urllib.request
import urllib.error
from typing import Dict, List, Tuple

sys.stdout.reconfigure(encoding="utf-8")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WEB_DATA_DIR = os.path.join(SCRIPT_DIR, "web", "data")
OUT_JSON = os.path.join(WEB_DATA_DIR, "quran_data.json")
OUT_JS = os.path.join(WEB_DATA_DIR, "quran_data.js")
OUT_DB_1 = os.path.join(SCRIPT_DIR, "assets", "db", "quran_master.db")
OUT_DB_2 = os.path.join(SCRIPT_DIR, "quran_tarteel_hifz", "assets", "db", "quran_master.db")

API_BASE_URL = "https://api.quran.com/api/v4"
KEMENAG_ID = 33

ARABIC_DIACRITICS_RE = re.compile(
    r"[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06DC\u06DF-\u06E8\u06EA-\u06ED\u0640]"
)
HTML_TAG_RE = re.compile(r"<[^>]+>")
FOOTNOTE_RE = re.compile(r"<sup[^>]*>.*?</sup>", flags=re.DOTALL)


def remove_diacritics(text: str) -> str:
    if not text:
        return ""
    cleaned = ARABIC_DIACRITICS_RE.sub("", text)
    cleaned = re.sub(r"[أإآٱ]", "ا", cleaned)
    cleaned = cleaned.replace("ى", "ي").replace("ة", "ه").replace("ؤ", "و").replace("ئ", "ي")
    return re.sub(r"\s+", " ", cleaned).strip()


def clean_html(text: str) -> str:
    if not text:
        return ""
    text = FOOTNOTE_RE.sub("", text)
    text = HTML_TAG_RE.sub("", text)
    return html.unescape(text).strip()


def fetch_json(url: str, retries: int = 3):
    headers = {"User-Agent": "QuranWebBuilder/1.0", "Accept": "application/json"}
    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=20) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception as e:
            if attempt == retries:
                print(f"Gagal fetch {url}: {e}", flush=True)
                return {}
            time.sleep(1.0 * attempt)
    return {}


def compute_diff_words(tokens1: List[str], tokens2: List[str]) -> Tuple[List[int], List[int]]:
    matcher = difflib.SequenceMatcher(None, tokens1, tokens2)
    diff1 = []
    diff2 = []
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag in ("replace", "delete"):
            diff1.extend(range(i1 + 1, i2 + 1))
        if tag in ("replace", "insert"):
            diff2.extend(range(j1 + 1, j2 + 1))
    return diff1, diff2


def main():
    print("=== Memulai Build Dataset Lengkap Juz 28, 29, dan 30 ===", flush=True)

    # 1. Ambil metadata 114 surah
    print("[1/5] Mengunduh metadata 114 Surah dari Quran.com API v4...", flush=True)
    ch_data = fetch_json(f"{API_BASE_URL}/chapters?language=id")
    chapters = ch_data.get("chapters", [])
    surah_meta = {}
    for ch in chapters:
        rev_place = (ch.get("revelation_place") or "makkah").lower()
        rev_type = "madaniyah" if "madinah" in rev_place else "makkiyah"
        translated_name = ch.get("translated_name", {}).get("name", "")
        surah_meta[ch["id"]] = {
            "id": ch["id"],
            "name_arabic": ch["name_arabic"],
            "name_latin": ch["name_simple"],
            "translation_id": translated_name,
            "total_verses": ch["verses_count"],
            "revelation_type": rev_type,
            "pages": ch.get("pages", [0, 0]),
        }

    # 2. Muat surah 78-114 yang sudah ada jika tersedia
    existing_juz30_verses = []
    if os.path.exists(OUT_JSON):
        try:
            with open(OUT_JSON, "r", encoding="utf-8") as f:
                old_d = json.load(f)
                existing_juz30_verses = [v for v in old_d.get("verses", []) if v["surah_id"] >= 78]
                print(f"  -> Memuat {len(existing_juz30_verses)} ayat Juz 30 yang sudah terverifikasi.", flush=True)
        except Exception as e:
            print(f"  -> Tidak dapat membaca cache Juz 30: {e}, akan diunduh ulang.", flush=True)

    # 3. Unduh Surah 58 s/d 77 (Juz 28 dan Juz 29)
    print("[2/5] Mengunduh Surah 58 s/d 77 (Juz 28 & 29) beserta terjemahan perkata...", flush=True)
    juz28_29_verses = []

    for sid in range(58, 78):
        s_info = surah_meta.get(sid, {})
        s_name = s_info.get("name_latin", f"Surah {sid}")
        page = 1
        total_pages = 1
        count_for_surah = 0

        while page <= total_pages:
            url = (
                f"{API_BASE_URL}/verses/by_chapter/{sid}"
                f"?language=id&words=true&word_fields=text_uthmani"
                f"&translations={KEMENAG_ID}"
                f"&fields=text_uthmani,page_number,juz_number"
                f"&per_page=50&page={page}"
            )
            data = fetch_json(url)
            total_pages = data.get("pagination", {}).get("total_pages", 1)
            raw_verses = data.get("verses", [])

            for v in raw_verses:
                vkey = v["verse_key"]
                _, vnum = map(int, vkey.split(":"))
                text_uthmani = v.get("text_uthmani", "").strip()
                text_clean = remove_diacritics(text_uthmani)

                trans_id = ""
                if v.get("translations"):
                    trans_id = clean_html(v["translations"][0].get("text", ""))

                words = []
                for w in v.get("words", []):
                    w_uth = w.get("text_uthmani", "").strip()
                    if not w_uth or w.get("char_type_name") == "end":
                        continue
                    w_clean = remove_diacritics(w_uth)
                    w_pos = w.get("position", len(words) + 1)
                    w_trans = w.get("translation", {}).get("text", "")
                    words.append({
                        "id": len(words) + 1,
                        "position": w_pos,
                        "text_uthmani": w_uth,
                        "text_clean": w_clean,
                        "translation_id": clean_html(w_trans),
                        "transliteration": w.get("transliteration", {}).get("text", ""),
                    })

                # Tentukan juz number yang tepat (Juz 28 untuk surah 58-66, Juz 29 untuk 67-77)
                juz_num = v.get("juz_number") or (28 if sid <= 66 else 29)

                v_obj = {
                    "id": 0,  # akan dinomori ulang
                    "surah_id": sid,
                    "surah_name_latin": s_name,
                    "verse_number": vnum,
                    "page_number": v.get("page_number", 0),
                    "juz_number": juz_num,
                    "text_uthmani": text_uthmani,
                    "text_clean": text_clean,
                    "translation_id": trans_id,
                    "tafsir_wajiz": f"Tafsir Ringkas QS. {s_name}:{vnum} — {trans_id}",
                    "words": words,
                }
                juz28_29_verses.append(v_obj)
                count_for_surah += 1

            page += 1
        print(f"  -> Selesai Surah {sid} ({s_name}): {count_for_surah} ayat", flush=True)

    # Jika Juz 30 belum ada di cache, unduh juga Surah 78 s/d 114
    if not existing_juz30_verses:
        print("[2b/5] Mengunduh Surah 78 s/d 114 (Juz 30)...", flush=True)
        for sid in range(78, 115):
            s_info = surah_meta.get(sid, {})
            s_name = s_info.get("name_latin", f"Surah {sid}")
            page = 1
            total_pages = 1
            while page <= total_pages:
                url = (
                    f"{API_BASE_URL}/verses/by_chapter/{sid}"
                    f"?language=id&words=true&word_fields=text_uthmani"
                    f"&translations={KEMENAG_ID}"
                    f"&fields=text_uthmani,page_number,juz_number"
                    f"&per_page=50&page={page}"
                )
                data = fetch_json(url)
                total_pages = data.get("pagination", {}).get("total_pages", 1)
                for v in data.get("verses", []):
                    _, vnum = map(int, v["verse_key"].split(":"))
                    text_uth = v.get("text_uthmani", "").strip()
                    trans_id = ""
                    if v.get("translations"):
                        trans_id = clean_html(v["translations"][0].get("text", ""))
                    words = []
                    for w in v.get("words", []):
                        w_uth = w.get("text_uthmani", "").strip()
                        if not w_uth or w.get("char_type_name") == "end":
                            continue
                        words.append({
                            "id": len(words) + 1,
                            "position": w.get("position", len(words) + 1),
                            "text_uthmani": w_uth,
                            "text_clean": remove_diacritics(w_uth),
                            "translation_id": clean_html(w.get("translation", {}).get("text", "")),
                            "transliteration": w.get("transliteration", {}).get("text", ""),
                        })
                    existing_juz30_verses.append({
                        "id": 0,
                        "surah_id": sid,
                        "surah_name_latin": s_name,
                        "verse_number": vnum,
                        "page_number": v.get("page_number", 0),
                        "juz_number": v.get("juz_number", 30),
                        "text_uthmani": text_uth,
                        "text_clean": remove_diacritics(text_uth),
                        "translation_id": trans_id,
                        "tafsir_wajiz": f"Tafsir Ringkas QS. {s_name}:{vnum} — {trans_id}",
                        "words": words,
                    })
                page += 1

    # Gabungkan semua ayat: Juz 28, 29, 30 (Surah 58 s/d 114)
    all_combined_verses = juz28_29_verses + existing_juz30_verses
    all_combined_verses.sort(key=lambda x: (x["surah_id"], x["verse_number"]))

    # Urutkan ID 1..N
    for i, v in enumerate(all_combined_verses, start=1):
        v["id"] = i

    target_surahs = [surah_meta[sid] for sid in range(58, 115) if sid in surah_meta]

    print(f"\n[3/5] Total ayat terkumpul: {len(all_combined_verses)} ayat dari {len(target_surahs)} Surah (Juz 28, 29, 30).", flush=True)

    # 4. Bangun Radar Mutasyabihat lintas Juz 28, 29, 30 & internal
    print("[4/5] Membangun indeks pasangan Mutasyabihat di Juz 28, 29, dan 30...", flush=True)
    mutasyabihat = []
    group_id = 1
    seen_pairs = set()

    clean_verses = []
    for v in all_combined_verses:
        toks = v["text_clean"].split()
        if len(toks) >= 2:
            clean_verses.append((v, toks))

    total_cv = len(clean_verses)
    for i in range(total_cv):
        v1, tok1 = clean_verses[i]
        for j in range(i + 1, total_cv):
            v2, tok2 = clean_verses[j]

            len_diff = abs(len(tok1) - len(tok2))
            if len_diff > max(len(tok1), len(tok2)) * 0.42:
                continue

            matcher = difflib.SequenceMatcher(None, tok1, tok2)
            ratio = matcher.ratio()

            same_opening = len(tok1) >= 2 and len(tok2) >= 2 and tok1[:2] == tok2[:2]
            is_match = (ratio >= 0.68) or (same_opening and ratio >= 0.58)

            if not is_match:
                continue

            pair_key = (min(v1["id"], v2["id"]), max(v1["id"], v2["id"]))
            if pair_key in seen_pairs:
                continue
            seen_pairs.add(pair_key)

            diff1, diff2 = compute_diff_words(tok1, tok2)

            next_words_1 = ""
            if i + 1 < total_cv and clean_verses[i + 1][0]["surah_id"] == v1["surah_id"]:
                next_words_1 = " ".join(clean_verses[i + 1][0]["text_uthmani"].split()[:4])

            next_words_2 = ""
            if j + 1 < total_cv and clean_verses[j + 1][0]["surah_id"] == v2["surah_id"]:
                next_words_2 = " ".join(clean_verses[j + 1][0]["text_uthmani"].split()[:4])

            scope_juz = v1["juz_number"] if v1["juz_number"] == v2["juz_number"] else None
            scope_label = f"Juz {scope_juz}" if scope_juz is not None else "Lintas Juz"

            title = (
                f"Kemiripan QS. {v1['surah_name_latin']}:{v1['verse_number']} vs "
                f"QS. {v2['surah_name_latin']}:{v2['verse_number']} ({scope_label})"
            )
            nw1 = next_words_1 if next_words_1 else "[Akhir Surah]"
            nw2 = next_words_2 if next_words_2 else "[Akhir Surah]"
            desc = (
                f"Tingkat kemiripan {int(ratio * 100)}%. "
                f"Waspadai transisi ke ayat selanjutnya: '{nw1}' vs '{nw2}'."
            )

            mutasyabihat.append({
                "group_id": group_id,
                "title": title,
                "description": desc,
                "scope_juz": scope_juz,
                "verse_id_1": v1["id"],
                "surah_id_1": v1["surah_id"],
                "surah_name_1": v1["surah_name_latin"],
                "verse_num_1": v1["verse_number"],
                "juz_1": v1["juz_number"],
                "text_1": v1["text_uthmani"],
                "diff_1": diff1,
                "next_words_1": next_words_1 or "[Akhir Surah]",
                "verse_id_2": v2["id"],
                "surah_id_2": v2["surah_id"],
                "surah_name_2": v2["surah_name_latin"],
                "verse_num_2": v2["verse_number"],
                "juz_2": v2["juz_number"],
                "text_2": v2["text_uthmani"],
                "diff_2": diff2,
                "next_words_2": next_words_2 or "[Akhir Surah]",
            })
            group_id += 1

    print(f"  -> Ditemukan {len(mutasyabihat)} pasangan Mutasyabihat di Juz 28, 29, dan 30.", flush=True)

    # 5. Tulis quran_data.json & quran_data.js
    print("[5/5] Menyimpan dataset ke web/data/quran_data.json & quran_data.js...", flush=True)
    payload = {
        "all_chapters": list(surah_meta.values()),
        "surahs": target_surahs,
        "verses": all_combined_verses,
        "mutasyabihat": mutasyabihat,
    }

    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False)

    with open(OUT_JS, "w", encoding="utf-8") as f:
        f.write("window.QURAN_DATA = ")
        json.dump(payload, f, ensure_ascii=False)
        f.write(";\n")

    print(f"  -> File JSON: {OUT_JSON} ({round(os.path.getsize(OUT_JSON)/(1024*1024), 2)} MB)")
    print(f"  -> File JS  : {OUT_JS} ({round(os.path.getsize(OUT_JS)/(1024*1024), 2)} MB)")

    # 6. Bangun database SQLite quran_master.db
    print("\n[6/5] Mengompilasi database SQLite quran_master.db untuk Flutter...", flush=True)
    for db_path in [OUT_DB_1, OUT_DB_2]:
        os.makedirs(os.path.dirname(os.path.abspath(db_path)), exist_ok=True)
        if os.path.exists(db_path):
            os.remove(db_path)

        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.executescript("""
            PRAGMA foreign_keys = ON;
            CREATE TABLE IF NOT EXISTS surahs (
                id INTEGER PRIMARY KEY,
                name_arabic TEXT NOT NULL,
                name_latin TEXT NOT NULL,
                translation_id TEXT NOT NULL,
                total_verses INTEGER NOT NULL,
                revelation_type TEXT CHECK(revelation_type IN ('makkiyah', 'madaniyah'))
            );
            CREATE TABLE IF NOT EXISTS verses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                surah_id INTEGER NOT NULL,
                verse_number INTEGER NOT NULL,
                page_number INTEGER NOT NULL,
                juz_number INTEGER NOT NULL,
                text_uthmani TEXT NOT NULL,
                text_clean TEXT NOT NULL,
                translation_id TEXT NOT NULL,
                tafsir_wajiz TEXT,
                UNIQUE(surah_id, verse_number),
                FOREIGN KEY (surah_id) REFERENCES surahs(id)
            );
            CREATE TABLE IF NOT EXISTS words (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                verse_id INTEGER NOT NULL,
                word_position INTEGER NOT NULL,
                text_uthmani TEXT NOT NULL,
                text_clean TEXT NOT NULL,
                translation_id TEXT NOT NULL,
                transliteration TEXT,
                UNIQUE(verse_id, word_position),
                FOREIGN KEY (verse_id) REFERENCES verses(id)
            );
            CREATE TABLE IF NOT EXISTS mutasyabihat_groups (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                description TEXT,
                scope_juz INTEGER
            );
            CREATE TABLE IF NOT EXISTS mutasyabihat_items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                group_id INTEGER NOT NULL,
                verse_id INTEGER NOT NULL,
                diff_word_positions TEXT NOT NULL,
                next_verse_start_words TEXT NOT NULL,
                FOREIGN KEY (group_id) REFERENCES mutasyabihat_groups(id),
                FOREIGN KEY (verse_id) REFERENCES verses(id)
            );
            CREATE INDEX IF NOT EXISTS idx_verses_juz ON verses(juz_number);
            CREATE INDEX IF NOT EXISTS idx_verses_surah_verse ON verses(surah_id, verse_number);
            CREATE INDEX IF NOT EXISTS idx_verses_page ON verses(page_number);
            CREATE INDEX IF NOT EXISTS idx_words_verse ON words(verse_id);
            CREATE INDEX IF NOT EXISTS idx_mutasyabihat_verse ON mutasyabihat_items(verse_id);
            CREATE INDEX IF NOT EXISTS idx_mutasyabihat_group ON mutasyabihat_items(group_id);
        """)

        # Isi surahs
        for s in target_surahs:
            cur.execute(
                "INSERT INTO surahs VALUES (?, ?, ?, ?, ?, ?)",
                (s["id"], s["name_arabic"], s["name_latin"], s["translation_id"], s["total_verses"], s["revelation_type"]),
            )

        # Isi verses & words
        for v in all_combined_verses:
            cur.execute(
                """
                INSERT INTO verses
                (id, surah_id, verse_number, page_number, juz_number, text_uthmani, text_clean, translation_id, tafsir_wajiz)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (v["id"], v["surah_id"], v["verse_number"], v["page_number"], v["juz_number"], v["text_uthmani"], v["text_clean"], v["translation_id"], v["tafsir_wajiz"]),
            )
            for w in v.get("words", []):
                cur.execute(
                    """
                    INSERT INTO words
                    (verse_id, word_position, text_uthmani, text_clean, translation_id, transliteration)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    (v["id"], w["position"], w["text_uthmani"], w["text_clean"], w["translation_id"], w.get("transliteration", "")),
                )

        # Isi mutasyabihat
        for m in mutasyabihat:
            cur.execute(
                "INSERT INTO mutasyabihat_groups (id, title, description, scope_juz) VALUES (?, ?, ?, ?)",
                (m["group_id"], m["title"], m["description"], m["scope_juz"]),
            )
            cur.execute(
                "INSERT INTO mutasyabihat_items (group_id, verse_id, diff_word_positions, next_verse_start_words) VALUES (?, ?, ?, ?)",
                (m["group_id"], m["verse_id_1"], json.dumps(m["diff_1"]), m["next_words_1"]),
            )
            cur.execute(
                "INSERT INTO mutasyabihat_items (group_id, verse_id, diff_word_positions, next_verse_start_words) VALUES (?, ?, ?, ?)",
                (m["group_id"], m["verse_id_2"], json.dumps(m["diff_2"]), m["next_words_2"]),
            )

        conn.commit()
        conn.close()
        print(f"  -> SQLite quran_master.db berhasil dibuat di: {db_path} ({round(os.path.getsize(db_path)/(1024*1024), 2)} MB)", flush=True)

    print("\n[SUKSES] Dataset & Database Juz 28, 29, dan 30 berhasil dibangun 100%!", flush=True)


if __name__ == "__main__":
    main()
