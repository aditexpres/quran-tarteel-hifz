#!/usr/bin/env python3
"""
build_full_juz30_web.py
Mengunduh data lengkap Juz 30 (Surah 78 An-Naba' s/d 114 An-Nas) dari Quran.com API v4,
menghitung pasangan Mutasyabihat (ayat mirip) secara otomatis,
dan mengekspornya ke web/data/quran_data.js & web/data/quran_data.json.
"""
import difflib
import html
import json
import os
import re
import time
import urllib.request
import urllib.error
from typing import Dict, List, Tuple

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WEB_DATA_DIR = os.path.join(SCRIPT_DIR, "web", "data")
os.makedirs(WEB_DATA_DIR, exist_ok=True)
OUT_JS = os.path.join(WEB_DATA_DIR, "quran_data.js")
OUT_JSON = os.path.join(WEB_DATA_DIR, "quran_data.json")

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
                print(f"Gagal fetch {url}: {e}")
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
    print("[1/3] Mengunduh daftar 114 Surah...")
    chapters_data = fetch_json(f"{API_BASE_URL}/chapters?language=id")
    chapters = chapters_data.get("chapters", [])
    
    surahs_list = []
    surah_dict = {}
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
            "pages": ch.get("pages", [0, 0])
        }
        surah_dict[ch["id"]] = item
        if ch["id"] >= 78:
            surahs_list.append(item)

    print(f"[2/3] Mengunduh seluruh ayat Juz 30 (Surah 78 s/d 114)...")
    all_verses = []
    verse_counter = 1

    for ch_id in range(78, 115):
        s_meta = surah_dict.get(ch_id, {})
        s_name = s_meta.get("name_latin", f"Surah {ch_id}")
        page = 1
        total_pages = 1

        while page <= total_pages:
            url = (
                f"{API_BASE_URL}/verses/by_chapter/{ch_id}"
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
                        "transliteration": w.get("transliteration", {}).get("text", "")
                    })

                v_obj = {
                    "id": verse_counter,
                    "surah_id": ch_id,
                    "surah_name_latin": s_name,
                    "verse_number": vnum,
                    "page_number": v.get("page_number", 0),
                    "juz_number": v.get("juz_number", 30),
                    "text_uthmani": text_uthmani,
                    "text_clean": text_clean,
                    "translation_id": trans_id,
                    "tafsir_wajiz": f"Tafsir Ringkas QS. {s_name}:{vnum} — {trans_id}",
                    "words": words
                }
                all_verses.append(v_obj)
                verse_counter += 1

            page += 1
        print(f"  -> Selesai Surah {ch_id} ({s_name})")

    print(f"[3/3] Memetakan pasangan ayat Mutasyabihat di Juz 30...")
    mutasyabihat = []
    group_id = 1
    seen_pairs = set()

    # Pre-tokenize
    clean_verses = []
    for v in all_verses:
        tokens = v["text_clean"].split()
        if len(tokens) >= 3:
            clean_verses.append((v, tokens))

    total_cv = len(clean_verses)
    for i in range(total_cv):
        v1, tok1 = clean_verses[i]
        for j in range(i + 1, total_cv):
            v2, tok2 = clean_verses[j]

            # Hitung skor token
            len_diff = abs(len(tok1) - len(tok2))
            if len_diff > max(len(tok1), len(tok2)) * 0.40:
                continue

            matcher = difflib.SequenceMatcher(None, tok1, tok2)
            ratio = matcher.ratio()
            if ratio < 0.65:
                continue

            pair_key = (min(v1["id"], v2["id"]), max(v1["id"], v2["id"]))
            if pair_key in seen_pairs:
                continue
            seen_pairs.add(pair_key)

            diff1, diff2 = compute_diff_words(tok1, tok2)

            # Cari 3-4 kata awal ayat berikutnya
            next_words_1 = ""
            if i + 1 < total_cv and clean_verses[i+1][0]["surah_id"] == v1["surah_id"]:
                next_v1 = clean_verses[i+1][0]
                next_words_1 = " ".join(next_v1["text_uthmani"].split()[:4])

            next_words_2 = ""
            if j + 1 < total_cv and clean_verses[j+1][0]["surah_id"] == v2["surah_id"]:
                next_v2 = clean_verses[j+1][0]
                next_words_2 = " ".join(next_v2["text_uthmani"].split()[:4])

            title = f"Kemiripan QS. {v1['surah_name_latin']}:{v1['verse_number']} vs QS. {v2['surah_name_latin']}:{v2['verse_number']}"
            desc = f"Tingkat kemiripan {int(ratio * 100)}%. Waspadai transisi ke ayat selanjutnya: '{next_words_1}' vs '{next_words_2}'."

            mutasyabihat.append({
                "group_id": group_id,
                "title": title,
                "description": desc,
                "scope_juz": 30,
                "verse_id_1": v1["id"],
                "surah_id_1": v1["surah_id"],
                "surah_name_1": v1["surah_name_latin"],
                "verse_num_1": v1["verse_number"],
                "juz_1": v1["juz_number"],
                "text_1": v1["text_uthmani"],
                "diff_1": diff1,
                "next_words_1": next_words_1,
                "verse_id_2": v2["id"],
                "surah_id_2": v2["surah_id"],
                "surah_name_2": v2["surah_name_latin"],
                "verse_num_2": v2["verse_number"],
                "juz_2": v2["juz_number"],
                "text_2": v2["text_uthmani"],
                "diff_2": diff2,
                "next_words_2": next_words_2
            })
            group_id += 1

    payload = {
        "all_chapters": list(surah_dict.values()),
        "surahs": surahs_list,
        "verses": all_verses,
        "mutasyabihat": mutasyabihat
    }

    # Tulis file JSON
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False)

    # Tulis file JS (window.QURAN_DATA)
    with open(OUT_JS, "w", encoding="utf-8") as f:
        f.write("window.QURAN_DATA = ")
        json.dump(payload, f, ensure_ascii=False)
        f.write(";\n")

    print(f"\n[SELESAI] Data Juz 30 berhasil diunduh:")
    print(f"  - Surah       : {len(surahs_list)}")
    print(f"  - Total Ayat  : {len(all_verses)}")
    print(f"  - Mutasyabihat: {len(mutasyabihat)} pasangan")
    print(f"  - Output JS   : {OUT_JS} ({round(os.path.getsize(OUT_JS) / (1024*1024), 2)} MB)")
    print(f"  - Output JSON : {OUT_JSON}")

if __name__ == "__main__":
    main()
