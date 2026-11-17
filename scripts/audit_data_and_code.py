import json
import sqlite3
import os
import sys

def audit_json():
    print('--- CHECKING web/data/quran_data.json ---')
    json_path = 'web/data/quran_data.json'
    if not os.path.exists(json_path):
        print(f"Error: {json_path} does not exist!")
        return
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    surahs = data.get('surahs', [])
    print(f'Total surahs: {len(surahs)}')
    if len(surahs) != 114:
        print(f"WARNING: Expected 114 surahs, got {len(surahs)}")

    verses = data.get('verses', [])
    print(f'Total verses: {len(verses)}')
    if len(verses) != 6236:
        print(f"WARNING: Expected 6236 verses, got {len(verses)}")

    total_words = 0
    words_with_lemma = 0
    words_with_root = 0
    all_verse_keys = set()
    pages = set()
    juzs = set()
    surah_verse_counts = {}

    for v in verses:
        s_id = v['surah_id']
        v_num = v['verse_number']
        key = f"{s_id}:{v_num}"
        if key in all_verse_keys:
            print(f"DUPLICATE VERSE: {key}")
        all_verse_keys.add(key)
        surah_verse_counts[s_id] = surah_verse_counts.get(s_id, 0) + 1
        
        pages.add(v.get('page_number'))
        juzs.add(v.get('juz_number'))

        words = v.get('words', [])
        total_words += len(words)
        for w in words:
            if w.get('lemma'):
                words_with_lemma += 1
            if w.get('root'):
                words_with_root += 1

    print(f'Total words: {total_words}')
    print(f'Words with lemma: {words_with_lemma} / {total_words} ({words_with_lemma/max(1,total_words)*100:.1f}%)')
    print(f'Words with root: {words_with_root} / {total_words} ({words_with_root/max(1,total_words)*100:.1f}%)')
    print(f'Pages range: min={min(pages) if pages else None}, max={max(pages) if pages else None}, total unique={len(pages)}')
    print(f'Juz range: min={min(juzs) if juzs else None}, max={max(juzs) if juzs else None}, total unique={len(juzs)}')

    # Verify surah counts
    mismatched_surahs = []
    for s in surahs:
        s_id = s['id']
        expected = s['total_verses']
        actual = surah_verse_counts.get(s_id, 0)
        if expected != actual:
            mismatched_surahs.append((s_id, s['name_latin'], expected, actual))
    if mismatched_surahs:
        print(f"MISMATCHED SURAH COUNTS: {mismatched_surahs}")
    else:
        print("All surah verse counts match perfectly (1..114).")

    mutasyabihat = data.get('mutasyabihat', [])
    print(f'Total mutasyabihat entries: {len(mutasyabihat)}')

    missing_refs = 0
    for m in mutasyabihat:
        s_key = f"{m.get('surah_id_1')}:{m.get('verse_num_1')}"
        t_key = f"{m.get('surah_id_2')}:{m.get('verse_num_2')}"
        if s_key not in all_verse_keys:
            print(f'Missing key 1 in mutasyabihat: {s_key}')
            missing_refs += 1
        if t_key not in all_verse_keys:
            print(f'Missing key 2 in mutasyabihat: {t_key}')
            missing_refs += 1

    print(f'Missing mutasyabihat verse references: {missing_refs}')

    # Check specific mutasyabihat pairs requested by user
    print('\n--- CHECKING USER-REQUESTED MUTASYABIHAT PAIRS ---')
    found_83 = []
    found_76_73 = []
    for m in mutasyabihat:
        s1, v1 = m.get('surah_id_1'), m.get('verse_num_1')
        s2, v2 = m.get('surah_id_2'), m.get('verse_num_2')
        if (s1 == 83 and v1 in [9, 20]) or (s2 == 83 and v2 in [9, 20]):
            found_83.append(m)
        if ((s1 == 76 and v1 == 29) or (s2 == 76 and v2 == 29)) and ((s1 == 73 and v1 == 19) or (s2 == 73 and v2 == 19)):
            found_76_73.append(m)

    print(f'Mutasyabihat 83:9 vs 83:20 matches found: {len(found_83)}')
    for m in found_83:
        print(f"  - {m.get('surah_name_1')}:{m.get('verse_num_1')} vs {m.get('surah_name_2')}:{m.get('verse_num_2')}: {m.get('title')}")

    print(f'Mutasyabihat 76:29 vs 73:19 matches found: {len(found_76_73)}')
    for m in found_76_73:
        print(f"  - {m.get('surah_name_1')}:{m.get('verse_num_1')} vs {m.get('surah_name_2')}:{m.get('verse_num_2')}: {m.get('title')}")

    js_path = 'web/data/quran_data.js'
    if os.path.exists(js_path):
        size_json = os.path.getsize(json_path)
        size_js = os.path.getsize(js_path)
        print(f"quran_data.json size: {size_json} bytes, quran_data.js size: {size_js} bytes")
        # Check prefix in js
        with open(js_path, 'r', encoding='utf-8') as f:
            start_js = f.read(50)
            print(f"quran_data.js start: {repr(start_js)}")

def audit_sqlite():
    print('\n--- CHECKING assets/db/quran_master.db ---')
    db_path = 'assets/db/quran_master.db'
    if not os.path.exists(db_path):
        print(f"Error: {db_path} does not exist!")
        return
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT name FROM sqlite_master WHERE type='table'")
    tables = [r[0] for r in c.fetchall()]
    print(f'Tables in SQLite: {tables}')
    for t in tables:
        c.execute(f"SELECT count(*) FROM {t}")
        print(f'  {t}: {c.fetchone()[0]} rows')
    
    # Check words table columns
    c.execute("PRAGMA table_info(words)")
    cols = [row[1] for row in c.fetchall()]
    print(f'Words table columns: {cols}')
    has_lemma = 'lemma' in cols
    has_root = 'root' in cols
    print(f'Words has lemma column: {has_lemma}, has root column: {has_root}')
    if has_lemma and has_root:
        c.execute("SELECT count(*) FROM words WHERE lemma IS NOT NULL AND lemma != ''")
        cnt_l = c.fetchone()[0]
        c.execute("SELECT count(*) FROM words WHERE root IS NOT NULL AND root != ''")
        cnt_r = c.fetchone()[0]
        print(f'SQLite words with non-empty lemma: {cnt_l}')
        print(f'SQLite words with non-empty root: {cnt_r}')

    conn.close()

def audit_web_dom():
    print('\n--- CHECKING WEB DOM IDS IN index.html VS app.js ---')
    with open('web/index.html', 'r', encoding='utf-8') as f:
        html = f.read()
    with open('web/app.js', 'r', encoding='utf-8') as f:
        js = f.read()

    import re
    # Find all getElementById in app.js
    get_by_id_calls = re.findall(r"getElementById\(['\"]([^'\"]+)['\"]\)", js)
    unique_ids = set(get_by_id_calls)
    print(f'Total unique getElementById in app.js: {len(unique_ids)}')

    missing_ids = []
    for elem_id in unique_ids:
        # Check if id="elem_id" exists in html
        pattern = f'id=["\']{re.escape(elem_id)}["\']'
        if not re.search(pattern, html):
            missing_ids.append(elem_id)

    if missing_ids:
        print(f'WARNING: {len(missing_ids)} DOM IDs requested in app.js are MISSING in index.html:')
        for m in sorted(missing_ids):
            print(f'  - {m}')
    else:
        print('All getElementById calls in app.js exist in index.html!')

def audit_assets():
    print('\n--- CHECKING ASSETS REFERENCED IN HTML & CSS ---')
    import re
    with open('web/index.html', 'r', encoding='utf-8') as f:
        html = f.read()

    srcs = re.findall(r'src=["\']([^"\']+)["\']', html)
    hrefs = re.findall(r'href=["\']([^"\']+)["\']', html)

    for path in srcs + hrefs:
        if path.startswith(('http://', 'https://', 'data:', '#')):
            continue
        full_path = os.path.normpath(os.path.join('web', path))
        exists = os.path.exists(full_path)
        print(f'  HTML {path} -> {full_path}: {"EXISTS" if exists else "MISSING!"}')

    with open('web/styles.css', 'r', encoding='utf-8') as f:
        css = f.read()

    urls = re.findall(r'url\([\'"]?([^\'"\)]+)[\'"]?\)', css)
    for path in set(urls):
        if path.startswith(('http://', 'https://', 'data:')):
            continue
        full_path = os.path.normpath(os.path.join('web', path))
        exists = os.path.exists(full_path)
        print(f'  CSS {path} -> {full_path}: {"EXISTS" if exists else "MISSING!"}')

def audit_pubspec_assets():
    print('\n--- CHECKING FLUTTER PUBSPEC ASSETS ---')
    import re
    for pub in ['pubspec.yaml', 'quran_tarteel_hifz/pubspec.yaml']:
        if not os.path.exists(pub):
            print(f'{pub} does not exist!')
            continue
        print(f'Checking {pub}:')
        with open(pub, 'r', encoding='utf-8') as f:
            content = f.read()
        assets = re.findall(r'-\s+([^\s\n#]+\.[a-zA-Z0-9]+)', content)
        base_dir = os.path.dirname(pub) if os.path.dirname(pub) else '.'
        for a in assets:
            p = os.path.normpath(os.path.join(base_dir, a))
            exists = os.path.exists(p)
            print(f'  {a} -> {p}: {"EXISTS" if exists else "MISSING!"}')

def test_15line_mushaf_pages():
    print('\n--- TESTING 15-LINE MUSHAF LAYOUT ON ALL 604 PAGES ---')
    with open('web/data/quran_data.json', 'r', encoding='utf-8') as f:
        data = json.load(f)

    pages = {}
    for v in data['verses']:
        pages.setdefault(v['page_number'], []).append(v)

    surah_map = {s['id']: s for s in data['surahs']}

    # Track how lines are allocated
    line_counts = []
    overflow_pages = []
    underflow_pages = []

    for p_num in range(1, 605):
        p_verses = pages.get(p_num, [])
        if not p_verses:
            print(f'Page {p_num} is EMPTY!')
            continue

        # Count header lines and bismillah lines
        header_lines_count = 0
        last_s_id = None
        for v in p_verses:
            if v['verse_number'] == 1 and v['surah_id'] != last_s_id:
                last_s_id = v['surah_id']
                header_lines_count += 1
                if v['surah_id'] != 1 and v['surah_id'] != 9:
                    header_lines_count += 1

        total_words = sum(len(v.get('words', [])) + 1 for v in p_verses) # +1 for ayah marker
        remaining_lines = 15 - header_lines_count

        if remaining_lines <= 0:
            overflow_pages.append((p_num, header_lines_count, remaining_lines))
        else:
            words_per_line = max(1, (total_words + remaining_lines - 1) // remaining_lines)

    print(f'Total pages tested: {len(pages)}')
    print(f'Overflow pages (headers >= 15): {overflow_pages}')

def simulate_pages():
    print('\n--- DETAILED SIMULATION OF PAGES 1, 582, 604 ---')
    with open('web/data/quran_data.json', 'r', encoding='utf-8') as f:
        data = json.load(f)

    surah_map = {s['id']: s for s in data['surahs']}
    pages = {}
    for v in data['verses']:
        pages.setdefault(v['page_number'], []).append(v)

    for p_num in [1, 582, 604]:
        p_verses = pages[p_num]
        sections = []
        curr_s_id = None
        curr_sec = []
        for v in p_verses:
            if v['surah_id'] != curr_s_id:
                if curr_sec:
                    sections.append((curr_s_id, curr_sec))
                curr_s_id = v['surah_id']
                curr_sec = [v]
            else:
                curr_sec.append(v)
        if curr_sec:
            sections.append((curr_s_id, curr_sec))

        total_headers = 0
        sec_info = []
        for s_id, verses in sections:
            has_v1 = verses[0]['verse_number'] == 1
            h_count = 0
            if has_v1:
                h_count += 1
                if s_id != 1 and s_id != 9:
                    h_count += 1
            total_headers += h_count
            tokens = sum(len(v.get('words', [])) + 1 for v in verses)
            sec_info.append({'s_id': s_id, 'verses': verses, 'has_v1': has_v1, 'h_count': h_count, 'tokens': tokens})

        remaining_lines = 15 - total_headers
        total_tokens = sum(s['tokens'] for s in sec_info)

        allocated = []
        lines_left = remaining_lines
        tokens_left = total_tokens
        for i, s in enumerate(sec_info):
            if i == len(sec_info) - 1:
                lines_for_sec = max(1, lines_left)
            else:
                prop = s['tokens'] / max(1, tokens_left)
                lines_for_sec = max(1, min(lines_left - (len(sec_info) - 1 - i), round(lines_left * prop)))
            allocated.append(lines_for_sec)
            lines_left -= lines_for_sec
            tokens_left -= s['tokens']

        print(f'\n=== Page {p_num} === (Total headers: {total_headers}, Total text lines: {sum(allocated)}, Sum: {total_headers + sum(allocated)})')
        line_no = 1
        for s, n_lines in zip(sec_info, allocated):
            surah = surah_map[s['s_id']]
            s_name = surah['name_latin']
            if s['has_v1']:
                print(f'  Line {line_no}: [HEADER: {s_name}]')
                line_no += 1
                if s['s_id'] != 1 and s['s_id'] != 9:
                    print(f'  Line {line_no}: [BISMILLAH]')
                    line_no += 1
            w_per_line = (s['tokens'] + n_lines - 1) // n_lines
            for l in range(n_lines):
                v_start = s['verses'][0]['verse_number']
                v_end = s['verses'][-1]['verse_number']
                print(f'  Line {line_no}: ({s_name} Ayat {v_start}-{v_end}, line {l+1}/{n_lines}, ~{w_per_line} words)')
                line_no += 1

def bundle_preview():
    print('\n--- REBUNDLING STANDALONE ARTIFACT PREVIEW ---')
    with open('web/index.html', 'r', encoding='utf-8') as f:
        html = f.read()

    with open('web/styles.css', 'r', encoding='utf-8') as f:
        css = f.read()

    with open('web/data/quran_data.js', 'r', encoding='utf-8') as f:
        data_js = f.read()

    with open('web/app.js', 'r', encoding='utf-8') as f:
        app_js = f.read()

    # Inline CSS
    html = html.replace('<link rel="stylesheet" href="styles.css">', f'<style>\n{css}\n</style>')

    # Inline Data JS and App JS
    html = html.replace('<script src="data/quran_data.js"></script>', f'<script>\n{data_js}\n</script>')
    html = html.replace('<script src="app.js"></script>', f'<script>\n{app_js}\n</script>')

    target = r'C:\Users\Aditya\.gemini\antigravity\brain\5b775501-1c50-42d5-89a2-fec93608357c\quran_ui_preview.html'
    with open(target, 'w', encoding='utf-8') as f:
        f.write(html)

    print(f'Generated standalone preview artifact: {target} ({os.path.getsize(target)} bytes)')

if __name__ == '__main__':
    audit_json()
    audit_sqlite()
    audit_web_dom()
    audit_assets()
    audit_pubspec_assets()
    test_15line_mushaf_pages()
    simulate_pages()
    bundle_preview()
