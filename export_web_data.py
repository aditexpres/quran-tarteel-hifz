#!/usr/bin/env python3
"""
export_web_data.py
Mengekstrak data dari quran_master.db dan menambahkan data lengkap Juz 30
menjadi file JSON teroptimasi untuk Web App Qur'an Tarteel Hifz.
"""
import json
import os
import re
import sqlite3
import urllib.request
import urllib.error
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(SCRIPT_DIR, "quran_tarteel_hifz", "assets", "db", "quran_master.db")
WEB_DATA_DIR = os.path.join(SCRIPT_DIR, "web", "data")
os.makedirs(WEB_DATA_DIR, exist_ok=True)
OUT_JSON = os.path.join(WEB_DATA_DIR, "quran_data.json")

# Normalisasi teks Arab
ARABIC_DIACRITICS_RE = re.compile(r"[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06DC\u06DF-\u06E8\u06EA-\u06ED\u0640]")

def remove_diacritics(text: str) -> str:
    if not text:
        return ""
    cleaned = ARABIC_DIACRITICS_RE.sub("", text)
    cleaned = re.sub(r"[أإآٱ]", "ا", cleaned)
    cleaned = cleaned.replace("ى", "ي").replace("ة", "ه").replace("ؤ", "و").replace("ئ", "ي")
    return re.sub(r"\s+", " ", cleaned).strip()

def export_data():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    # 1. Ambil Surah
    cur.execute("SELECT id, name_arabic, name_latin, translation_id, total_verses, revelation_type FROM surahs ORDER BY id ASC")
    surahs = []
    for row in cur.fetchall():
        surahs.append({
            "id": row[0],
            "name_arabic": row[1],
            "name_latin": row[2],
            "translation_id": row[3],
            "total_verses": row[4],
            "revelation_type": row[5]
        })

    # 2. Ambil Ayat
    cur.execute("""
        SELECT v.id, v.surah_id, v.verse_number, v.page_number, v.juz_number, 
               v.text_uthmani, v.text_clean, v.translation_id, v.tafsir_wajiz, s.name_latin
        FROM verses v
        JOIN surahs s ON v.surah_id = s.id
        ORDER BY v.surah_id ASC, v.verse_number ASC
    """)
    verses = []
    verse_id_map = {}
    for row in cur.fetchall():
        v = {
            "id": row[0],
            "surah_id": row[1],
            "verse_number": row[2],
            "page_number": row[3],
            "juz_number": row[4],
            "text_uthmani": row[5],
            "text_clean": row[6],
            "translation_id": row[7],
            "tafsir_wajiz": row[8],
            "surah_name_latin": row[9],
            "words": []
        }
        verses.append(v)
        verse_id_map[row[0]] = v

    # 3. Ambil Kata
    cur.execute("""
        SELECT id, verse_id, word_position, text_uthmani, text_clean, translation_id, transliteration
        FROM words
        ORDER BY verse_id ASC, word_position ASC
    """)
    for row in cur.fetchall():
        vid = row[1]
        if vid in verse_id_map:
            verse_id_map[vid]["words"].append({
                "id": row[0],
                "position": row[2],
                "text_uthmani": row[3],
                "text_clean": row[4],
                "translation_id": row[5],
                "transliteration": row[6] or ""
            })

    # 4. Ambil Mutasyabihat
    cur.execute("""
        SELECT 
            g.id AS group_id,
            g.title,
            g.description,
            g.scope_juz,
            v1.id AS verse_id_1,
            v1.surah_id AS surah_1,
            s1.name_latin AS surah_name_1,
            v1.verse_number AS verse_num_1,
            v1.juz_number AS juz_1,
            v1.text_uthmani AS text_1,
            m1.diff_word_positions AS diff_1,
            m1.next_verse_start_words AS next_words_1,
            v2.id AS verse_id_2,
            v2.surah_id AS surah_2,
            s2.name_latin AS surah_name_2,
            v2.verse_number AS verse_num_2,
            v2.juz_number AS juz_2,
            v2.text_uthmani AS text_2,
            m2.diff_word_positions AS diff_2,
            m2.next_verse_start_words AS next_words_2
        FROM mutasyabihat_groups g
        JOIN mutasyabihat_items m1 ON g.id = m1.group_id
        JOIN verses v1 ON m1.verse_id = v1.id
        JOIN surahs s1 ON v1.surah_id = s1.id
        JOIN mutasyabihat_items m2 ON g.id = m2.group_id AND m1.id < m2.id
        JOIN verses v2 ON m2.verse_id = v2.id
        JOIN surahs s2 ON v2.surah_id = s2.id
    """)
    mutasyabihat_pairs = []
    for row in cur.fetchall():
        diff1 = json.loads(row[10]) if row[10] else []
        diff2 = json.loads(row[18]) if row[18] else []
        mutasyabihat_pairs.append({
            "group_id": row[0],
            "title": row[1],
            "description": row[2],
            "scope_juz": row[3],
            "verse_id_1": row[4],
            "surah_id_1": row[5],
            "surah_name_1": row[6],
            "verse_num_1": row[7],
            "juz_1": row[8],
            "text_1": row[9],
            "diff_1": diff1,
            "next_words_1": row[11],
            "verse_id_2": row[12],
            "surah_id_2": row[13],
            "surah_name_2": row[14],
            "verse_num_2": row[15],
            "juz_2": row[16],
            "text_2": row[17],
            "diff_2": diff2,
            "next_words_2": row[19]
        })

    conn.close()

    payload = {
        "surahs": surahs,
        "verses": verses,
        "mutasyabihat": mutasyabihat_pairs
    }

    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    print(f"Berhasil mengekspor data ke {OUT_JSON} ({len(surahs)} surah, {len(verses)} ayat, {len(mutasyabihat_pairs)} pasangan mutasyabihat).")

if __name__ == "__main__":
    export_data()
