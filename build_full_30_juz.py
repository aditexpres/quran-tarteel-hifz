#!/usr/bin/env python3
"""
build_full_30_juz.py
====================
Membangun Database Lengkap 30 Juz (114 Surah, 6.236 Ayat)
- Mengunduh Surah 1 s/d 57 dari Quran.com API v4 (secara multi-threading).
- Menggabungkan dengan Surah 58 s/d 114 yang telah tersedia di web/data/quran_data.json.
- Mengindeks pasangan ayat mutasyabihat (anti-tertukar) di seluruh 30 Juz.
- Menghasilkan:
  1. assets/db/quran_master.db (SQLite)
  2. quran_tarteel_hifz/assets/db/quran_master.db (SQLite)
  3. web/data/quran_data.json
  4. web/data/quran_data.js
"""

import concurrent.futures
from collections import defaultdict
import difflib
import html
import json
import os
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from typing import Dict, List, Tuple, Any

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


def fetch_json(url: str, retries: int = 4, backoff: float = 1.0) -> dict:
    headers = {"User-Agent": "Quran30JuzBuilder/1.0", "Accept": "application/json"}
    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=25) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception as e:
            if attempt == retries:
                print(f"[Warn] Gagal fetch {url} setelah {retries}x: {e}", flush=True)
                return {}
            time.sleep(backoff * attempt)
    return {}


def fetch_single_chapter(sid: int, surah_meta: Dict[int, Any]) -> List[dict]:
    s_info = surah_meta.get(sid, {})
    s_name = s_info.get("name_latin", f"Surah {sid}")
    page = 1
    total_pages = 1
    chapter_verses = []

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

            juz_num = v.get("juz_number") or 1
            page_num = v.get("page_number") or 1

            v_obj = {
                "id": 0,
                "surah_id": sid,
                "surah_name_latin": s_name,
                "verse_number": vnum,
                "page_number": page_num,
                "juz_number": juz_num,
                "text_uthmani": text_uthmani,
                "text_clean": text_clean,
                "translation_id": trans_id,
                "tafsir_wajiz": f"Tafsir Ringkas QS. {s_name}:{vnum} — {trans_id}",
                "words": words,
            }
            chapter_verses.append(v_obj)

        page += 1

    return chapter_verses


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


def build_full_30_juz():
    print("==================================================================", flush=True)
    print(" MEMBANGUN DATABASE PENUH 30 JUZ AL-QUR'AN (114 SURAH, 6.236 AYAT)", flush=True)
    print("==================================================================", flush=True)

    # 1. Unduh metadata 114 Surah
    print("[1/5] Mengunduh metadata 114 Surah dari Quran.com API v4...", flush=True)
    ch_data = fetch_json(f"{API_BASE_URL}/chapters?language=id")
    chapters = ch_data.get("chapters", [])
    if not chapters:
        print("[Error] Tidak dapat mengambil metadata Surah dari Quran.com!", flush=True)
        return

    surah_meta = {}
    surahs_list = []
    for ch in chapters:
        rev_place = (ch.get("revelation_place") or "makkah").lower()
        rev_type = "madaniyah" if "madinah" in rev_place else "makkiyah"
        translated_name = ch.get("translated_name", {}).get("name", "")
        item = {
            "id": ch["id"],
            "name_arabic": ch["name_arabic"],
            "name_latin": ch["name_simple"],
            "translation_id": translated_name,
            "total_verses": ch["verses_count"],
            "revelation_type": rev_type,
            "pages": ch.get("pages", [1, 604]),
        }
        surah_meta[ch["id"]] = item
        surahs_list.append(item)

    print(f"  -> Berhasil memuat metadata {len(surahs_list)} Surah.", flush=True)

    # 2. Muat surah 58-114 yang sudah tersimpan
    existing_verses_by_surah = defaultdict(list)
    if os.path.exists(OUT_JSON):
        try:
            with open(OUT_JSON, "r", encoding="utf-8") as f:
                old_d = json.load(f)
                for v in old_d.get("verses", []):
                    existing_verses_by_surah[v["surah_id"]].append(v)
            print(f"  -> Cache lokal terdeteksi untuk Surah {min(existing_verses_by_surah.keys())} s/d {max(existing_verses_by_surah.keys())} ({sum(len(v) for v in existing_verses_by_surah.values())} ayat).", flush=True)
        except Exception as e:
            print(f"  -> Tidak dapat membaca cache lokal: {e}", flush=True)

    # 3. Identifikasi Surah yang perlu diunduh
    surahs_to_fetch = []
    for sid in range(1, 115):
        expected_count = surah_meta[sid]["total_verses"]
        existing = existing_verses_by_surah.get(sid, [])
        if len(existing) != expected_count:
            surahs_to_fetch.append(sid)

    print(f"[2/5] Perlu mengunduh {len(surahs_to_fetch)} Surah yang belum lengkap...", flush=True)

    # Unduh secara paralel menggunakan ThreadPoolExecutor
    fetched_verses_by_surah = {}
    if surahs_to_fetch:
        print(f"  -> Memulai unduhan paralel (6 worker threads)...", flush=True)
        t_start = time.time()
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
            future_to_sid = {
                executor.submit(fetch_single_chapter, sid, surah_meta): sid
                for sid in surahs_to_fetch
            }
            completed = 0
            for future in concurrent.futures.as_completed(future_to_sid):
                sid = future_to_sid[future]
                try:
                    res = future.result()
                    fetched_verses_by_surah[sid] = res
                    completed += 1
                    s_name = surah_meta[sid]["name_latin"]
                    print(f"     [{completed}/{len(surahs_to_fetch)}] QS. {sid} {s_name}: {len(res)} ayat selesai.", flush=True)
                except Exception as exc:
                    print(f"     [Error] Gagal mengunduh Surah {sid}: {exc}", flush=True)

        print(f"  -> Seluruh {len(surahs_to_fetch)} Surah selesai diunduh dalam {time.time()-t_start:.1f} detik.", flush=True)

    # 4. Gabungkan dan urutkan seluruh ayat (1..114)
    print("[3/5] Menggabungkan dan menomori ulang seluruh 114 Surah...", flush=True)
    all_verses = []
    global_verse_id = 1
    for sid in range(1, 115):
        if sid in fetched_verses_by_surah:
            v_list = fetched_verses_by_surah[sid]
        else:
            v_list = existing_verses_by_surah[sid]

        # Urutkan berdasarkan verse_number
        v_list.sort(key=lambda x: x["verse_number"])

        for v in v_list:
            v["id"] = global_verse_id
            v["surah_name_latin"] = surah_meta[sid]["name_latin"]
            # Pastikan kata-kata memiliki verse_id yang tepat
            for w in v.get("words", []):
                w["verse_id"] = global_verse_id
            all_verses.append(v)
            global_verse_id += 1

    print(f"  -> Total ayat gabungan: {len(all_verses)} ayat dari 114 Surah.", flush=True)

    # Buat peta ayat selanjutnya untuk fitur deteksi lompat surah (Dual-Path)
    verse_next_words_map = {}
    for i in range(len(all_verses) - 1):
        curr = all_verses[i]
        nxt = all_verses[i + 1]
        if curr["surah_id"] == nxt["surah_id"]:
            nxt_words = nxt["text_uthmani"].split()[:4]
            verse_next_words_map[curr["id"]] = " ".join(nxt_words)

    # 5. Algoritma Pencocokan Mutasyabihat Cepat (Inverted Index)
    print("[4/5] Memetakan pasangan ayat mutasyabihat di seluruh 30 Juz...", flush=True)
    t_mut_start = time.time()

    # Index kata-kata pembeda
    word_to_vindices = defaultdict(list)
    v_tokens = []
    for idx, v in enumerate(all_verses):
        words = v["text_clean"].split()
        v_tokens.append(words)
        for w in set(words):
            if len(w) >= 3:
                word_to_vindices[w].append(idx)

    # Bangun kandidat pasangan ayat (yang memiliki kata-kata berbobot sama)
    candidate_pairs = set()
    for w, vids in word_to_vindices.items():
        if len(vids) < 2 or len(vids) > 120:  # Abaikan kata penghubung yang terlalu sering muncul
            continue
        for i in range(len(vids)):
            for j in range(i + 1, len(vids)):
                candidate_pairs.add((vids[i], vids[j]))

    print(f"  -> Kandidat pasangan untuk diverifikasi: {len(candidate_pairs)} pasangan.", flush=True)

    mutasyabihat = []
    group_id = 1
    SIMILARITY_THRESHOLD = 0.72

    for (i, j) in candidate_pairs:
        v1 = all_verses[i]
        v2 = all_verses[j]

        # Kecualikan perbandingan ayat yang sama
        if v1["id"] == v2["id"]:
            continue

        tok1 = v_tokens[i]
        tok2 = v_tokens[j]
        if not tok1 or not tok2:
            continue

        # Filter cepat rasio panjang kata
        len_ratio = min(len(tok1), len(tok2)) / max(len(tok1), len(tok2))
        if len_ratio < 0.55:
            continue

        # Jaccard overlap kata
        s1, s2 = set(tok1), set(tok2)
        jaccard = len(s1 & s2) / len(s1 | s2)
        if jaccard < 0.45:
            continue

        # Hitung rasio SequenceMatcher token
        ratio = difflib.SequenceMatcher(None, tok1, tok2).ratio()
        if ratio >= SIMILARITY_THRESHOLD and ratio < 1.0:
            diff1, diff2 = compute_diff_words(tok1, tok2)
            next_words_1 = verse_next_words_map.get(v1["id"], "")
            next_words_2 = verse_next_words_map.get(v2["id"], "")

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
                "next_words_1": nw1,
                "verse_id_2": v2["id"],
                "surah_id_2": v2["surah_id"],
                "surah_name_2": v2["surah_name_latin"],
                "verse_num_2": v2["verse_number"],
                "juz_2": v2["juz_number"],
                "text_2": v2["text_uthmani"],
                "diff_2": diff2,
                "next_words_2": nw2,
            })
            group_id += 1

    print(f"  -> Ditemukan {len(mutasyabihat)} pasangan Mutasyabihat dalam {time.time()-t_mut_start:.2f} detik.", flush=True)

    # 6. Simpan ke web/data/quran_data.json & quran_data.js
    print("[5/5] Menyimpan dataset ke web/data/quran_data.json & quran_data.js...", flush=True)
    payload = {
        "all_chapters": surahs_list,
        "surahs": surahs_list,
        "verses": all_verses,
        "mutasyabihat": mutasyabihat,
    }

    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False)

    with open(OUT_JS, "w", encoding="utf-8") as f:
        f.write("window.QURAN_DATA = ")
        json.dump(payload, f, ensure_ascii=False)
        f.write(";\n")

    print(f"  -> File JSON: {OUT_JSON} ({round(os.path.getsize(OUT_JSON)/(1024*1024), 2)} MB)", flush=True)
    print(f"  -> File JS  : {OUT_JS} ({round(os.path.getsize(OUT_JS)/(1024*1024), 2)} MB)", flush=True)

    # 7. Bangun database SQLite quran_master.db
    print("\n[6/5] Mengompilasi database SQLite quran_master.db (114 Surah, 6.236 Ayat)...", flush=True)
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

        # Insert surahs
        cur.executemany(
            "INSERT INTO surahs VALUES (?, ?, ?, ?, ?, ?)",
            [
                (
                    s["id"],
                    s["name_arabic"],
                    s["name_latin"],
                    s["translation_id"],
                    s["total_verses"],
                    s["revelation_type"],
                )
                for s in surahs_list
            ],
        )

        # Insert verses and words
        word_rows = []
        for v in all_verses:
            cur.execute(
                """
                INSERT INTO verses
                (id, surah_id, verse_number, page_number, juz_number, text_uthmani, text_clean, translation_id, tafsir_wajiz)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    v["id"],
                    v["surah_id"],
                    v["verse_number"],
                    v["page_number"],
                    v["juz_number"],
                    v["text_uthmani"],
                    v["text_clean"],
                    v["translation_id"],
                    v.get("tafsir_wajiz", ""),
                ),
            )
            for w in v.get("words", []):
                word_rows.append((
                    v["id"],
                    w["position"],
                    w["text_uthmani"],
                    w["text_clean"],
                    w["translation_id"],
                    w.get("transliteration", ""),
                ))

        cur.executemany(
            """
            INSERT INTO words
            (verse_id, word_position, text_uthmani, text_clean, translation_id, transliteration)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            word_rows,
        )

        # Insert mutasyabihat
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
        print(f"  -> Berhasil membuat SQLite: {db_path} ({round(os.path.getsize(db_path)/(1024*1024), 2)} MB)", flush=True)

    print("\n=== SEMUA PROSES BERHASIL DISELESAIKAN (FULL 30 JUZ) ===", flush=True)


if __name__ == "__main__":
    build_full_30_juz()
