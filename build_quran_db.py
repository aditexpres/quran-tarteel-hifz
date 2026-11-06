#!/usr/bin/env python3
"""
build_quran_db.py
=================
Generator Database SQLite Dual-Architecture untuk Aplikasi Qur'an Tarteel Lintas Platform
(Android, Windows, macOS).

Fitur Utama:
1. Mengunduh data Surah, Ayat (Uthmani & Clean STT), Terjemahan Kemenag RI (ID: 33),
   Terjemahan Perkata (Word-by-Word), dan Tafsir dari Quran.com API v4 (dengan penanganan paginasi penuh).
2. Normalisasi teks Arab tanpa harakat/diakritik untuk pencocokan AI Speech-to-Text (Whisper/Fuzzy Matching).
3. Mesin Pemeta Otomatis Mutasyabihat (Ayat Mirip):
   - Mendeteksi pasangan ayat yang mirip di dalam 1 Juz, 1 Surah, maupun Lintas Juz menggunakan
     kombinasi kesamaan rasio token & karakter (SequenceMatcher).
   - Mengekstrak indeks kata pembeda (`diff_word_positions`) dalam format JSON array 1-based.
   - Menyimpan 3-4 kata pertama dari ayat selanjutnya (`next_verse_start_words`) untuk fitur
     Dual-Path Listening (deteksi jebakan lompat surah).
4. Mode `--offline-demo`: Menghasilkan database sampel Juz 30 secara instan tanpa koneksi internet
   untuk pengujian cepat di lingkungan lokal/CI.
"""

import argparse
import difflib
import html
import json
import os
import re
import sqlite3
import time
import urllib.error
import urllib.request
from typing import Dict, List, Optional, Tuple


# ==============================================================================
# 1. UTILITAS NORMALISASI TEKS ARAB & PEMBERSIH HTML
# ==============================================================================

# Rentang karakter harakat, tanda waqaf, dan simbol tajwid Unicode Arab
ARABIC_DIACRITICS_RE = re.compile(
    r"[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06DC\u06DF-\u06E8\u06EA-\u06ED\u0640]"
)
HTML_TAG_RE = re.compile(r"<[^>]+>")
FOOTNOTE_SUP_RE = re.compile(r"<sup[^>]*>.*?</sup>", flags=re.DOTALL)


def remove_diacritics(text: str) -> str:
    """
    Membersihkan harakat, tanda waqaf, tatweel, dan menormalisasi varian huruf Alif/Ya/Ta Marbuthah
    agar pencocokan kata Speech-to-Text (Whisper) dan deteksi Mutasyabihat akurat.
    """
    if not text:
        return ""
    cleaned = ARABIC_DIACRITICS_RE.sub("", text)
    # Normalisasi varian Alif (أ إ آ ٱ -> ا)
    cleaned = re.sub(r"[أإآٱ]", "ا", cleaned)
    # Normalisasi Alif Maqsurah (ى -> ي) dan Ta Marbuthah (ة -> ه) untuk konsistensi STT
    cleaned = cleaned.replace("ى", "ي").replace("ة", "ه").replace("ؤ", "و").replace("ئ", "ي")
    # Rapikan spasi berlebih
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return cleaned


def clean_html_translation(raw_text: str) -> str:
    """Membersihkan tag catatan kaki <sup> dan tag HTML dari teks terjemahan/tafsir API."""
    if not raw_text:
        return ""
    text = FOOTNOTE_SUP_RE.sub("", raw_text)
    text = HTML_TAG_RE.sub("", text)
    return html.unescape(text).strip()


# ==============================================================================
# 2. INISIALISASI SKEMA DUAL-DATABASE SQLITE
# ==============================================================================

MASTER_SCHEMA_SQL = """
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
"""

USER_SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS user_memory_anchors (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    group_id INTEGER NOT NULL UNIQUE,
    user_note TEXT NOT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS error_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    expected_verse_id INTEGER NOT NULL,
    jumped_to_verse_id INTEGER NOT NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_error_logs_expected ON error_logs(expected_verse_id);
"""


def init_databases(master_path: str, user_path: str) -> Tuple[sqlite3.Connection, sqlite3.Connection]:
    """Membuat koneksi dan mengeksekusi DDL skema untuk quran_master.db dan user_hifz.db."""
    os.makedirs(os.path.dirname(os.path.abspath(master_path)), exist_ok=True)
    os.makedirs(os.path.dirname(os.path.abspath(user_path)), exist_ok=True)

    if os.path.exists(master_path):
        os.remove(master_path)
    if os.path.exists(user_path):
        os.remove(user_path)

    master_conn = sqlite3.connect(master_path)
    user_conn = sqlite3.connect(user_path)

    master_conn.executescript(MASTER_SCHEMA_SQL)
    user_conn.executescript(USER_SCHEMA_SQL)

    return master_conn, user_conn


# ==============================================================================
# 3. PENGUNDUHAN DATA DARI QURAN.COM API V4 (ONLINE MODE)
# ==============================================================================

API_BASE_URL = "https://api.quran.com/api/v4"
KEMENAG_TRANSLATION_ID = 33  # Terjemahan Bahasa Indonesia Kemenag RI


def fetch_json(url: str, retries: int = 3, backoff: float = 1.5) -> dict:
    """Mengambil respons JSON dari URL dengan mekanisme retry otomatis."""
    headers = {
        "User-Agent": "QuranTarteelHifzBuilder/1.0",
        "Accept": "application/json",
    }
    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=20) as response:
                return json.loads(response.read().decode("utf-8"))
        except (urllib.error.URLError, TimeoutError) as exc:
            if attempt == retries:
                raise RuntimeError(f"Gagal mengunduh URL setelah {retries} percobaan: {url}") from exc
            time.sleep(backoff * attempt)
    return {}


def populate_surahs_online(master_conn: sqlite3.Connection) -> None:
    """Mengunduh daftar 114 Surah beserta terjemahan nama dalam Bahasa Indonesia."""
    print("[1/4] Mengunduh daftar 114 Surah dari Quran.com API v4...")
    data = fetch_json(f"{API_BASE_URL}/chapters?language=id")
    cur = master_conn.cursor()

    for ch in data.get("chapters", []):
        rev_place = (ch.get("revelation_place") or "makkah").lower()
        revelation_type = "madaniyah" if "madinah" in rev_place else "makkiyah"
        translated_name = ch.get("translated_name", {}).get("name", "")

        cur.execute(
            """
            INSERT OR REPLACE INTO surahs
            (id, name_arabic, name_latin, translation_id, total_verses, revelation_type)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                ch["id"],
                ch["name_arabic"],
                ch["name_simple"],
                translated_name,
                ch["verses_count"],
                revelation_type,
            ),
        )
    master_conn.commit()


def fetch_tafsir_for_chapter(chapter_id: int, tafsir_slug: str = "id-tafsir-kemenag") -> Dict[str, str]:
    """
    Mencoba mengambil tafsir per ayat jika tersedia di endpoint tafsir Quran.com API.
    Mengembalikan dictionary { 'surah:verse': 'teks tafsir' }.
    """
    tafsir_map: Dict[str, str] = {}
    try:
        url = f"{API_BASE_URL}/tafsirs/{tafsir_slug}/by_chapter/{chapter_id}?per_page=300"
        data = fetch_json(url, retries=1)
        for item in data.get("tafsirs", []):
            vkey = item.get("verse_key")
            if vkey and item.get("text"):
                tafsir_map[vkey] = clean_html_translation(item["text"])
    except Exception:
        # Jika endpoint tafsir spesifik tidak tersedia, biarkan kosong dan gunakan fallback ringkasan
        pass
    return tafsir_map


def populate_chapters_verses_online(
    master_conn: sqlite3.Connection,
    target_chapters: List[int],
    include_words: bool = True,
) -> None:
    """
    Mengunduh ayat demi ayat, terjemahan Kemenag RI, terjemahan perkata (words),
    dan tafsir dengan paginasi penuh (mengatasi batas default 10 ayat per halaman).
    """
    print(f"[2/4] Mengunduh ayat & kosakata perkata untuk {len(target_chapters)} Surah...")
    cur = master_conn.cursor()

    for idx, ch_id in enumerate(target_chapters, start=1):
        print(f"  -> Memproses Surah ke-{ch_id} ({idx}/{len(target_chapters)})...")
        tafsir_map = fetch_tafsir_for_chapter(ch_id)
        page = 1
        total_pages = 1

        while page <= total_pages:
            words_flag = "true" if include_words else "false"
            url = (
                f"{API_BASE_URL}/verses/by_chapter/{ch_id}"
                f"?language=id"
                f"&words={words_flag}"
                f"&word_fields=text_uthmani,location"
                f"&translations={KEMENAG_TRANSLATION_ID}"
                f"&fields=text_uthmani,page_number,juz_number"
                f"&per_page=50&page={page}"
            )
            data = fetch_json(url)
            pagination = data.get("pagination", {})
            total_pages = pagination.get("total_pages", 1)

            for v in data.get("verses", []):
                verse_key = v["verse_key"]
                surah_id, verse_num = map(int, verse_key.split(":"))
                text_uthmani = v.get("text_uthmani", "").strip()
                text_clean = remove_diacritics(text_uthmani)

                raw_trans = ""
                if v.get("translations"):
                    raw_trans = v["translations"][0].get("text", "")
                trans_id = clean_html_translation(raw_trans)
                tafsir_text = tafsir_map.get(
                    verse_key,
                    f"Tafsir Wajiz QS. {surah_id}:{verse_num} — {trans_id}",
                )

                cur.execute(
                    """
                    INSERT OR REPLACE INTO verses
                    (surah_id, verse_number, page_number, juz_number, text_uthmani, text_clean, translation_id, tafsir_wajiz)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        surah_id,
                        verse_num,
                        v.get("page_number", 1),
                        v.get("juz_number", 30),
                        text_uthmani,
                        text_clean,
                        trans_id,
                        tafsir_text,
                    ),
                )
                # Ambil verse_id yang baru saja disimpan
                cur.execute(
                    "SELECT id FROM verses WHERE surah_id = ? AND verse_number = ?",
                    (surah_id, verse_num),
                )
                verse_row = cur.fetchone()
                if not verse_row:
                    continue
                verse_db_id = verse_row[0]

                # Simpan terjemahan perkata (abaikan token bertipe 'end' atau nomor akhir ayat)
                if include_words and v.get("words"):
                    word_pos = 1
                    for w in v["words"]:
                        if w.get("char_type_name") == "end":
                            continue
                        w_uthmani = (w.get("text_uthmani") or w.get("text") or "").strip()
                        if not w_uthmani:
                            continue
                        w_clean = remove_diacritics(w_uthmani)
                        w_trans = clean_html_translation(
                            (w.get("translation") or {}).get("text") or ""
                        )
                        w_translit = (w.get("transliteration") or {}).get("text") or ""

                        cur.execute(
                            """
                            INSERT OR REPLACE INTO words
                            (verse_id, word_position, text_uthmani, text_clean, translation_id, transliteration)
                            VALUES (?, ?, ?, ?, ?, ?)
                            """,
                            (
                                verse_db_id,
                                word_pos,
                                w_uthmani,
                                w_clean,
                                w_trans,
                                w_translit,
                            ),
                        )
                        word_pos += 1

            page += 1
        master_conn.commit()


# ==============================================================================
# 4. MESIN PEMETA OTOMATIS MUTASYABIHAT & DETEKSI KATA PEMBEDA
# ==============================================================================

def compute_diff_word_positions(clean_words_a: List[str], clean_words_b: List[str]) -> Tuple[List[int], List[int]]:
    """
    Membandingkan dua daftar kata Arab tanpa harakat menggunakan SequenceMatcher
    dan mengembalikan indeks kata yang berbeda (1-based index) untuk masing-masing ayat.
    """
    matcher = difflib.SequenceMatcher(None, clean_words_a, clean_words_b)
    diff_a: List[int] = []
    diff_b: List[int] = []

    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag != "equal":
            diff_a.extend(range(i1 + 1, i2 + 1))
            diff_b.extend(range(j1 + 1, j2 + 1))

    # Jika ayat 100% identik secara teks, tandai kata terakhir sebagai titik fokus transisi ke ayat berikutnya
    if not diff_a and clean_words_a:
        diff_a = [len(clean_words_a)]
    if not diff_b and clean_words_b:
        diff_b = [len(clean_words_b)]

    return diff_a, diff_b


def get_next_verse_preview(cur: sqlite3.Cursor, surah_id: int, verse_number: int, max_words: int = 4) -> str:
    """Mengambil 3-4 kata pertama dari ayat selanjutnya untuk deteksi jebakan lompat surah."""
    cur.execute(
        "SELECT text_uthmani FROM verses WHERE surah_id = ? AND verse_number = ?",
        (surah_id, verse_number + 1),
    )
    row = cur.fetchone()
    if not row or not row[0]:
        return "[Akhir Surah]"
    words = row[0].split()
    return " ".join(words[:max_words])


def build_mutasyabihat_index(
    master_conn: sqlite3.Connection,
    similarity_threshold: float = 0.72,
    min_words: int = 2,
) -> int:
    """
    Memindai seluruh ayat di dalam database untuk menemukan pasangan ayat yang mirip
    (Mutasyabihat), menghitung indeks kata pembeda (`diff_word_positions`), dan
    mengekstrak awal ayat selanjutnya (`next_verse_start_words`).
    """
    print("[3/4] Membangun indeks Mutasyabihat (Ayat Mirip) & Kata Pembeda secara otomatis...")
    cur = master_conn.cursor()

    # Bersihkan indeks lama agar tidak duplikat saat dijalankan ulang
    cur.execute("DELETE FROM mutasyabihat_items")
    cur.execute("DELETE FROM mutasyabihat_groups")

    cur.execute(
        """
        SELECT v.id, v.surah_id, s.name_latin, v.verse_number, v.juz_number, v.text_uthmani, v.text_clean
        FROM verses v
        JOIN surahs s ON v.surah_id = s.id
        ORDER BY v.juz_number, v.surah_id, v.verse_number
        """
    )
    all_verses = cur.fetchall()

    # Kelompokkan per Juz untuk mempercepat pemindaian prioritas 1 Juz, serta simpan list global
    parsed_verses = []
    for row in all_verses:
        vid, sid, sname, vnum, juz, t_uth, t_clean = row
        clean_tokens = t_clean.split()
        if len(clean_tokens) >= min_words:
            parsed_verses.append(
                {
                    "id": vid,
                    "surah_id": sid,
                    "surah_name": sname,
                    "verse_number": vnum,
                    "juz_number": juz,
                    "text_uthmani": t_uth,
                    "text_clean": t_clean,
                    "tokens": clean_tokens,
                }
            )

    seen_pairs = set()
    groups_created = 0

    for i in range(len(parsed_verses)):
        v1 = parsed_verses[i]
        for j in range(i + 1, len(parsed_verses)):
            v2 = parsed_verses[j]

            # Lewati jika panjang kata terlalu jauh berbeda (> 60% selisih panjang)
            len1, len2 = len(v1["tokens"]), len(v2["tokens"])
            if abs(len1 - len2) > max(len1, len2) * 0.55:
                continue

            # Hitung rasio kemiripan berbasis token dan karakter
            token_ratio = difflib.SequenceMatcher(None, v1["tokens"], v2["tokens"]).ratio()
            char_ratio = difflib.SequenceMatcher(None, v1["text_clean"], v2["text_clean"]).ratio()
            combined_score = (token_ratio * 0.65) + (char_ratio * 0.35)

            # Deteksi juga apabila 2 kata pertama atau 2 kata terakhir sama persis pada ayat pendek
            same_opening = len1 >= 2 and len2 >= 2 and v1["tokens"][:2] == v2["tokens"][:2]
            is_match = combined_score >= similarity_threshold or (same_opening and combined_score >= 0.60)

            if not is_match:
                continue

            pair_key = (min(v1["id"], v2["id"]), max(v1["id"], v2["id"]))
            if pair_key in seen_pairs:
                continue
            seen_pairs.add(pair_key)

            diff_1, diff_2 = compute_diff_word_positions(v1["tokens"], v2["tokens"])
            next_1 = get_next_verse_preview(cur, v1["surah_id"], v1["verse_number"])
            next_2 = get_next_verse_preview(cur, v2["surah_id"], v2["verse_number"])

            scope_juz: Optional[int] = v1["juz_number"] if v1["juz_number"] == v2["juz_number"] else None
            scope_label = f"Juz {scope_juz}" if scope_juz is not None else "Lintas Juz"

            if v1["surah_id"] == v2["surah_id"]:
                title = f"Kemiripan Internal QS. {v1['surah_name']}: {v1['verse_number']} & {v2['verse_number']} ({scope_label})"
            else:
                title = (
                    f"Kemiripan QS. {v1['surah_name']}:{v1['verse_number']} vs "
                    f"QS. {v2['surah_name']}:{v2['verse_number']} ({scope_label})"
                )

            description = (
                f"Tingkat kemiripan {int(combined_score * 100)}%. "
                f"Waspadai transisi menuju ayat berikutnya: '{next_1}' vs '{next_2}'."
            )

            cur.execute(
                """
                INSERT INTO mutasyabihat_groups (title, description, scope_juz)
                VALUES (?, ?, ?)
                """,
                (title, description, scope_juz),
            )
            group_id = cur.lastrowid

            cur.execute(
                """
                INSERT INTO mutasyabihat_items
                (group_id, verse_id, diff_word_positions, next_verse_start_words)
                VALUES (?, ?, ?, ?)
                """,
                (group_id, v1["id"], json.dumps(diff_1), next_1),
            )
            cur.execute(
                """
                INSERT INTO mutasyabihat_items
                (group_id, verse_id, diff_word_positions, next_verse_start_words)
                VALUES (?, ?, ?, ?)
                """,
                (group_id, v2["id"], json.dumps(diff_2), next_2),
            )
            groups_created += 1

    master_conn.commit()
    print(f"  -> Berhasil memetakan {groups_created} grup pasangan ayat Mutasyabihat.")
    return groups_created


# ==============================================================================
# 5. SEED DATA OFFLINE DEMO (UNTUK PENGUJIAN TANPA INTERNET / CI)
# ==============================================================================

def populate_offline_demo_data(master_conn: sqlite3.Connection, user_conn: sqlite3.Connection) -> None:
    """
    Mengisi sampel data Juz 30 autentik (QS. An-Nazi'at, 'Abasa, Al-Infitar, Al-Mutaffifin, Al-Ma'un)
    lengkap dengan kosakata perkata dan catatan Jembatan Ingatan (Memory Anchor) bawaan.
    """
    print("[Offline Demo] Mengisi data sampel autentik Juz 30 ke dalam database...")
    cur = master_conn.cursor()

    sample_surahs = [
        (79, "النّازعات", "An-Nazi'at", "Malaikat yang Mencabut", 46, "makkiyah"),
        (80, "عبس", "'Abasa", "Ia Bermuka Masam", 42, "makkiyah"),
        (82, "الانفطار", "Al-Infitar", "Terbelah", 19, "makkiyah"),
        (83, "المطففين", "Al-Mutaffifin", "Orang-Orang yang Curang", 36, "makkiyah"),
        (107, "الماعون", "Al-Ma'un", "Barang yang Berguna", 7, "makkiyah"),
    ]
    cur.executemany(
        "INSERT OR REPLACE INTO surahs VALUES (?, ?, ?, ?, ?, ?)",
        sample_surahs,
    )

    sample_verses = [
        # QS. An-Nazi'at 32-34
        (
            79, 32, 584, 30,
            "وَالْجِبَالَ أَرْسَاهَا",
            "Designates mountains firmly",
            "Dan gunung-gunung Dia pancangkan dengan teguh,",
            "Gunung-gunung dipancangkan sebagai pasak bumi agar stabil.",
        ),
        (
            79, 33, 584, 30,
            "مَتَاعًا لَّكُمْ وَلِأَنْعَامِكُمْ",
            "",
            "(Semua itu) untuk kesenanganmu dan untuk hewan-hewan ternakmu.",
            "Seluruh nikmat bumi dan gunung diciptakan sebagai bekal hidup manusia dan ternak.",
        ),
        (
            79, 34, 584, 30,
            "فَإِذَا جَاءَتِ الطَّامَّةُ الْكُبْرَىٰ",
            "",
            "Maka apabila malapetaka yang sangat besar (hari Kiamat) telah datang,",
            "Ketika tiupan sangkakala kedua menghadirkan malapetaka besar yang mengalahkan segalanya.",
        ),
        # QS. 'Abasa 31-33
        (
            80, 31, 585, 30,
            "وَفَاكِهَةً وَأَبًّا",
            "",
            "dan buah-buahan serta rerumputan.",
            "Berbagai buah untuk manusia dan rerumputan untuk pakan ternak.",
        ),
        (
            80, 32, 585, 30,
            "مَّتَاعًا لَّكُمْ وَلِأَنْعَامِكُمْ",
            "",
            "(Semua itu) untuk kesenanganmu dan untuk hewan-hewan ternakmu.",
            "Nikmat tumbuh-tumbuhan tersebut menjadi bekal bagi manusia dan hewan ternaknya.",
        ),
        (
            80, 33, 585, 30,
            "فَإِذَا جَاءَتِ الصَّاخَّةُ",
            "",
            "Maka apabila datang suara yang memekakkan (tiupan sangkakala yang kedua),",
            "Suara teriakan kiamat yang sangat keras hingga memekakkan telinga.",
        ),
        # QS. Al-Infitar 13-15
        (
            82, 13, 587, 30,
            "إِنَّ الْأَبْرَارَ لَفِي نَعِيمٍ",
            "",
            "Sesungguhnya orang-orang yang berbakti benar-benar berada dalam (surga yang penuh) kenikmatan,",
            "Orang yang taat dan tulus beramal berada dalam kenikmatan abadi.",
        ),
        (
            82, 14, 587, 30,
            "وَإِنَّ الْفُجَّارَ لَفِي جَحِيمٍ",
            "",
            "dan sesungguhnya orang-orang yang durhaka benar-benar berada dalam neraka.",
            "Sebaliknya, orang-orang yang durhaka berada di dalam kobaran api neraka.",
        ),
        (
            82, 15, 587, 30,
            "يَصْلَوْنَهَا يَوْمَ الدِّينِ",
            "",
            "Mereka masuk ke dalamnya pada hari Pembalasan.",
            "Mereka merasakan panasnya api neraka pada hari perhitungan amal.",
        ),
        # QS. Al-Mutaffifin 22-23
        (
            83, 22, 588, 30,
            "إِنَّ الْأَبْرَارَ لَفِي نَعِيمٍ",
            "",
            "Sesungguhnya orang-orang yang berbakti benar-benar berada dalam (surga yang penuh) kenikmatan,",
            "Balasan bagi orang-orang jujur dan berbakti adalah kenikmatan surga.",
        ),
        (
            83, 23, 588, 30,
            "عَلَى الْأَرَائِكِ يَنْظُرُونَ",
            "",
            "mereka (duduk) di atas dipan-dipan melepas pandangan.",
            "Mereka duduk bersandar di atas singgasana sambil memandang karunia Allah.",
        ),
    ]

    for sid, vnum, page, juz, t_uth, _, trans, tafsir in sample_verses:
        t_clean = remove_diacritics(t_uth)
        cur.execute(
            """
            INSERT OR REPLACE INTO verses
            (surah_id, verse_number, page_number, juz_number, text_uthmani, text_clean, translation_id, tafsir_wajiz)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (sid, vnum, page, juz, t_uth, t_clean, trans, tafsir),
        )
        cur.execute(
            "SELECT id FROM verses WHERE surah_id = ? AND verse_number = ?",
            (sid, vnum),
        )
        verse_id = cur.fetchone()[0]

        # Pecah kosakata perkata otomatis untuk demo
        tokens_uth = t_uth.split()
        tokens_trans = trans.split()
        for pos, w_uth in enumerate(tokens_uth, start=1):
            w_clean = remove_diacritics(w_uth)
            approx_trans = tokens_trans[min(pos - 1, len(tokens_trans) - 1)] if tokens_trans else ""
            cur.execute(
                """
                INSERT OR REPLACE INTO words
                (verse_id, word_position, text_uthmani, text_clean, translation_id, transliteration)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (verse_id, pos, w_uth, w_clean, approx_trans, ""),
            )

    master_conn.commit()
    build_mutasyabihat_index(master_conn, similarity_threshold=0.70)

    # Tambahkan sampel catatan Jembatan Ingatan (Memory Anchor) di user_hifz.db
    user_cur = user_conn.cursor()
    user_cur.execute(
        """
        INSERT OR REPLACE INTO user_memory_anchors (group_id, user_note)
        VALUES (
            1,
            'Rumus Urutan Mushaf: An-Nazi''at (79) pakai huruf Tha (الطَّامَّةُ), sedangkan ''Abasa (80) pakai huruf Shad (الصَّاخَّةُ).'
        )
        """
    )
    user_conn.commit()


# ==============================================================================
# 6. ENTRY POINT CLI
# ==============================================================================

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generator Database SQLite Dual-Architecture untuk Aplikasi Qur'an Tarteel"
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Unduh seluruh 114 Surah / 30 Juz penuh (default: hanya Juz 30 / Surah 78-114)",
    )
    parser.add_argument(
        "--chapters",
        type=str,
        default="",
        help="Daftar nomor surah spesifik dipisahkan koma, misal: '78,79,80,82,83'",
    )
    parser.add_argument(
        "--no-words",
        action="store_true",
        help="Lewati pengunduhan terjemahan perkata untuk mempercepat proses build awal",
    )
    parser.add_argument(
        "--offline-demo",
        action="store_true",
        help="Gunakan data sampel offline Juz 30 tanpa koneksi internet",
    )
    parser.add_argument(
        "--similarity",
        type=float,
        default=0.72,
        help="Ambang batas kemiripan ayat Mutasyabihat (0.0 - 1.0, default: 0.72)",
    )
    parser.add_argument(
        "--master-out",
        default="quran_master.db",
        help="Path output untuk database master (read-only asset)",
    )
    parser.add_argument(
        "--user-out",
        default="user_hifz.db",
        help="Path output untuk database user (read-write memory anchors & logs)",
    )
    args = parser.parse_args()

    master_conn, user_conn = init_databases(args.master_out, args.user_out)
    try:
        if args.offline_demo:
            populate_offline_demo_data(master_conn, user_conn)
        else:
            populate_surahs_online(master_conn)
            if args.chapters.strip():
                target_chapters = [int(x.strip()) for x in args.chapters.split(",") if x.strip()]
            elif args.all:
                target_chapters = list(range(1, 115))
            else:
                target_chapters = list(range(78, 115))

            populate_chapters_verses_online(
                master_conn,
                target_chapters=target_chapters,
                include_words=not args.no_words,
            )
            build_mutasyabihat_index(master_conn, similarity_threshold=args.similarity)

        print(f"[4/4] Selesai! Database berhasil dibuat:")
        print(f"  - Master DB : {os.path.abspath(args.master_out)}")
        print(f"  - User DB   : {os.path.abspath(args.user_out)}")
    finally:
        master_conn.close()
        user_conn.close()


if __name__ == "__main__":
    main()
