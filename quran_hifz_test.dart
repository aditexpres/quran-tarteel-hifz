// quran_hifz_test.dart
// =============================================================================
// Unit & Integration Test Suite untuk Aplikasi Qur'an Tarteel Lintas Platform
//
// Mencakup pengujian otomatis untuk:
// 1. Akurasi Normalisasi Arab & `ArabicFuzzyMatcher` (Levenshtein, Prefix Similarity,
//    serta Deteksi `CORRECT_NEXT` vs `TRAP_JUMP` pada QS. An-Nazi'at: 33-34 & 'Abasa: 32-33).
// 2. Query SQLite Dual-Database (`ATTACH DATABASE user_hifz`), Radar Mutasyabihat (Query A),
//    Dual-Path Listening (Query B), penyimpanan Memory Anchor, & pencatatan Error Logs.
// 3. Mesin Tata Letak Mushaf Madinah 15 Baris (`Mushaf15LineLayoutEngine`) & Utilitas
//    Konversi Audio PCM 16kHz / WAV / VAD RMS.
//
// Cara Menjalankan:
//   flutter test test/quran_hifz_test.dart
// =============================================================================

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'mushaf_15line_and_audio.dart';
import 'quran_hifz_repository.dart';
import 'whisper_voice_service.dart';

void main() {
  // Inisialisasi SQLite FFI agar pengujian database dapat berjalan di Windows, macOS, & Linux CI
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // ===========================================================================
  // GROUP 1: PENGUJIAN AKURASI ARABIC FUZZY MATCHER & DETEKSI LOMPAT SURAH
  // ===========================================================================
  group('1. ArabicFuzzyMatcher & Deteksi Trap Jump Mutasyabihat', () {
    test('normalizeArabic membersihkan harakat, tatweel, dan menyatukan varian Alif/Ya/Ta', () {
      const rawUthmani = 'فَإِذَا جَاءَتِ الطَّامَّةُ الْكُبْرَىٰ';
      final normalized = ArabicFuzzyMatcher.normalizeArabic(rawUthmani);

      expect(normalized, equals('فاذا جاءت الطامه الكبري'));
      expect(
        ArabicFuzzyMatcher.normalizeArabic('مَّتَاعًا لَّكُمْ وَلِأَنْعَامِكُمْ'),
        equals('متاعا لكم ولانعامكم'),
      );
    });

    test('calculatePrefixSimilarity akurat meskipun pengguna baru mengucapkan 2 kata pertama', () {
      const candidateClean = 'فاذا جاءت الطامه الكبري';
      // Simulasi transkripsi STT saat pengguna baru membaca "Fa idza jaa'atit..."
      const partialSpoken = 'فاذا جاءت';

      final score = ArabicFuzzyMatcher.calculatePrefixSimilarity(
        partialSpoken,
        candidateClean,
      );
      expect(score, equals(1.0));
    });

    test('evaluateNextVerseSpeech mendeteksi CORRECT_NEXT saat menyambung ke QS. An-Nazi\'at: 34', () {
      final candidates = [
        const DualPathCandidate(
          pathType: ListeningPathType.correctNext,
          verseId: 3,
          surahId: 79,
          surahName: 'An-Nazi\'at',
          verseNumber: 34,
          expectedTextClean: 'فاذا جاءت الطامه الكبري',
          textUthmani: 'فَإِذَا جَاءَتِ الطَّامَّةُ الْكُبْرَىٰ',
        ),
        const DualPathCandidate(
          pathType: ListeningPathType.trapJump,
          verseId: 6,
          surahId: 80,
          surahName: '\'Abasa',
          verseNumber: 33,
          expectedTextClean: 'فاذا جاءت الصاخه',
          textUthmani: 'فَإِذَا جَاءَتِ الصَّاخَّةُ',
        ),
      ];

      final result = ArabicFuzzyMatcher.evaluateNextVerseSpeech(
        spokenTranscript: 'فَإِذَا جَاءَتِ الطَّامَّةُ',
        candidates: candidates,
      );

      expect(result, isNotNull);
      expect(result!.isTrapJump, isFalse);
      expect(result.detectedPath, equals(ListeningPathType.correctNext));
      expect(result.matchedCandidate.surahId, equals(79));
      expect(result.matchedCandidate.verseNumber, equals(34));
      expect(result.similarityScore, greaterThanOrEqualTo(0.90));
    });

    test('evaluateNextVerseSpeech memicu peringatan TRAP_JUMP saat terpeleset ke QS. \'Abasa: 33', () {
      final candidates = [
        const DualPathCandidate(
          pathType: ListeningPathType.correctNext,
          verseId: 3,
          surahId: 79,
          surahName: 'An-Nazi\'at',
          verseNumber: 34,
          expectedTextClean: 'فاذا جاءت الطامه الكبري',
          textUthmani: 'فَإِذَا جَاءَتِ الطَّامَّةُ الْكُبْرَىٰ',
        ),
        const DualPathCandidate(
          pathType: ListeningPathType.trapJump,
          verseId: 6,
          surahId: 80,
          surahName: '\'Abasa',
          verseNumber: 33,
          expectedTextClean: 'فاذا جاءت الصاخه',
          textUthmani: 'فَإِذَا جَاءَتِ الصَّاخَّةُ',
        ),
      ];

      // Pengguna sedang di An-Nazi'at: 33 tetapi lidahnya terpeleset membaca lanjutan 'Abasa: 33
      final result = ArabicFuzzyMatcher.evaluateNextVerseSpeech(
        spokenTranscript: 'فَإِذَا جَاءَتِ الصَّاخَّةُ',
        candidates: candidates,
      );

      expect(result, isNotNull);
      expect(result!.isTrapJump, isTrue);
      expect(result.detectedPath, equals(ListeningPathType.trapJump));
      expect(result.matchedCandidate.surahId, equals(80));
      expect(result.matchedCandidate.verseNumber, equals(33));
      expect(result.warningMessage, contains('Terdeteksi lompat surah!'));
      expect(result.warningMessage, contains('An-Nazi\'at: 34'));
    });

    test('evaluateNextVerseSpeech mengembalikan null jika bacaan sama sekali berbeda (di bawah threshold)', () {
      final candidates = [
        const DualPathCandidate(
          pathType: ListeningPathType.correctNext,
          verseId: 3,
          surahId: 79,
          surahName: 'An-Nazi\'at',
          verseNumber: 34,
          expectedTextClean: 'فاذا جاءت الطامه الكبري',
          textUthmani: 'فَإِذَا جَاءَتِ الطَّامَّةُ الْكُبْرَىٰ',
        ),
      ];

      final result = ArabicFuzzyMatcher.evaluateNextVerseSpeech(
        spokenTranscript: 'قل هو الله احد',
        candidates: candidates,
        threshold: 0.72,
      );

      expect(result, isNull);
    });
  });

  // ===========================================================================
  // GROUP 2: PENGUJIAN SQLITE DUAL-DATABASE & QUERY MUTASYABIHAT / DUAL-PATH
  // ===========================================================================
  group('2. SQLite Dual-Database (Radar Mutasyabihat & Dual-Path Listening)', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

      // Buat skema master & skema user_hifz (simulasi ATTACH DATABASE in-memory)
      await db.execute("ATTACH DATABASE ':memory:' AS user_hifz;");

      await db.execute('''
        CREATE TABLE surahs (
          id INTEGER PRIMARY KEY,
          name_arabic TEXT NOT NULL,
          name_latin TEXT NOT NULL,
          translation_id TEXT NOT NULL,
          total_verses INTEGER NOT NULL,
          revelation_type TEXT
        );
      ''');

      await db.execute('''
        CREATE TABLE verses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          surah_id INTEGER NOT NULL,
          verse_number INTEGER NOT NULL,
          page_number INTEGER NOT NULL,
          juz_number INTEGER NOT NULL,
          text_uthmani TEXT NOT NULL,
          text_clean TEXT NOT NULL,
          translation_id TEXT NOT NULL,
          tafsir_wajiz TEXT
        );
      ''');

      await db.execute('''
        CREATE TABLE mutasyabihat_groups (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          description TEXT,
          scope_juz INTEGER
        );
      ''');

      await db.execute('''
        CREATE TABLE mutasyabihat_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          group_id INTEGER NOT NULL,
          verse_id INTEGER NOT NULL,
          diff_word_positions TEXT NOT NULL,
          next_verse_start_words TEXT NOT NULL
        );
      ''');

      await db.execute('''
        CREATE TABLE user_hifz.user_memory_anchors (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          group_id INTEGER NOT NULL UNIQUE,
          user_note TEXT NOT NULL,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
      ''');

      // Seed data QS. An-Nazi'at (79:33-34) & QS. 'Abasa (80:32-33)
      await db.insert('surahs', {
        'id': 79,
        'name_arabic': 'النّازعات',
        'name_latin': 'An-Nazi\'at',
        'translation_id': 'Malaikat yang Mencabut',
        'total_verses': 46,
        'revelation_type': 'makkiyah',
      });
      await db.insert('surahs', {
        'id': 80,
        'name_arabic': 'عبس',
        'name_latin': '\'Abasa',
        'translation_id': 'Ia Bermuka Masam',
        'total_verses': 42,
        'revelation_type': 'makkiyah',
      });

      final v79_33 = await db.insert('verses', {
        'surah_id': 79,
        'verse_number': 33,
        'page_number': 584,
        'juz_number': 30,
        'text_uthmani': 'مَتَاعًا لَّكُمْ وَلِأَنْعَامِكُمْ',
        'text_clean': 'متاعا لكم ولانعامكم',
        'translation_id': 'Untuk kesenanganmu dan hewan ternakmu.',
      });
      await db.insert('verses', {
        'surah_id': 79,
        'verse_number': 34,
        'page_number': 584,
        'juz_number': 30,
        'text_uthmani': 'فَإِذَا جَاءَتِ الطَّامَّةُ الْكُبْرَىٰ',
        'text_clean': 'فاذا جاءت الطامه الكبري',
        'translation_id': 'Maka apabila malapetaka besar telah datang.',
      });

      final v80_32 = await db.insert('verses', {
        'surah_id': 80,
        'verse_number': 32,
        'page_number': 585,
        'juz_number': 30,
        'text_uthmani': 'مَّتَاعًا لَّكُمْ وَلِأَنْعَامِكُمْ',
        'text_clean': 'متاعا لكم ولانعامكم',
        'translation_id': 'Untuk kesenanganmu dan hewan ternakmu.',
      });
      await db.insert('verses', {
        'surah_id': 80,
        'verse_number': 33,
        'page_number': 585,
        'juz_number': 30,
        'text_uthmani': 'فَإِذَا جَاءَتِ الصَّاخَّةُ',
        'text_clean': 'فاذا جاءت الصاخه',
        'translation_id': 'Maka apabila datang suara yang memekakkan.',
      });

      final gid = await db.insert('mutasyabihat_groups', {
        'title': 'Kemiripan QS. An-Nazi\'at:33 vs QS. \'Abasa:32 (Juz 30)',
        'description': 'Ayat identik di Juz 30',
        'scope_juz': 30,
      });

      await db.insert('mutasyabihat_items', {
        'group_id': gid,
        'verse_id': v79_33,
        'diff_word_positions': '[3]',
        'next_verse_start_words': 'فَإِذَا جَاءَتِ الطَّامَّةُ الْكُبْرَىٰ',
      });
      await db.insert('mutasyabihat_items', {
        'group_id': gid,
        'verse_id': v80_32,
        'diff_word_positions': '[3]',
        'next_verse_start_words': 'فَإِذَا جَاءَتِ الصَّاخَّةُ',
      });

      await db.rawInsert('''
        INSERT INTO user_hifz.user_memory_anchors (group_id, user_note)
        VALUES (?, ?)
      ''', [gid, 'An-Nazi\'at pakai huruf Tha, \'Abasa pakai huruf Shad.']);
    });

    tearDown(() async {
      await db.close();
    });

    test('Query A (Radar Mutasyabihat) berhasil menggabungkan data master & catatan Memory Anchor', () async {
      final rows = await db.rawQuery('''
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
          m2.next_verse_start_words AS next_words_2,
          uma.user_note
        FROM mutasyabihat_groups g
        JOIN mutasyabihat_items m1 ON g.id = m1.group_id
        JOIN verses v1 ON m1.verse_id = v1.id
        JOIN surahs s1 ON v1.surah_id = s1.id
        JOIN mutasyabihat_items m2 ON g.id = m2.group_id AND m1.id < m2.id
        JOIN verses v2 ON m2.verse_id = v2.id
        JOIN surahs s2 ON v2.surah_id = s2.id
        LEFT JOIN user_hifz.user_memory_anchors uma ON g.id = uma.group_id
        WHERE v1.juz_number = 30 AND v2.juz_number = 30
      ''');

      expect(rows.length, equals(1));
      final pair = MutasyabihatComparisonPair.fromMap(rows.first);
      expect(pair.surahId1, equals(79));
      expect(pair.surahId2, equals(80));
      expect(pair.diffWordPositions1, equals([3]));
      expect(pair.userMemoryNote, contains('huruf Tha'));
    });

    test('Query B (Dual-Path Listening) mengembalikan jalur CORRECT_NEXT dan TRAP_JUMP', () async {
      final v79Row = await db.query(
        'verses',
        where: 'surah_id = ? AND verse_number = ?',
        whereArgs: [79, 33],
      );
      final currentVerseId = v79Row.first['id'] as int;

      final rows = await db.rawQuery('''
        SELECT 
          'CORRECT_NEXT' AS path_type,
          v_next.id AS verse_id,
          v_next.surah_id,
          s.name_latin AS surah_name,
          v_next.verse_number,
          v_next.text_clean AS expected_text,
          v_next.text_uthmani
        FROM verses v_curr
        JOIN verses v_next
          ON v_curr.surah_id = v_next.surah_id
         AND v_next.verse_number = v_curr.verse_number + 1
        JOIN surahs s ON v_next.surah_id = s.id
        WHERE v_curr.id = ?

        UNION ALL

        SELECT 
          'TRAP_JUMP' AS path_type,
          v_trap_next.id AS verse_id,
          v_trap_next.surah_id,
          s_trap.name_latin AS surah_name,
          v_trap_next.verse_number,
          v_trap_next.text_clean AS expected_text,
          v_trap_next.text_uthmani
        FROM mutasyabihat_items m_curr
        JOIN mutasyabihat_items m_twin
          ON m_curr.group_id = m_twin.group_id
         AND m_curr.id != m_twin.id
        JOIN verses v_twin ON m_twin.verse_id = v_twin.id
        JOIN verses v_trap_next
          ON v_twin.surah_id = v_trap_next.surah_id
         AND v_trap_next.verse_number = v_twin.verse_number + 1
        JOIN surahs s_trap ON v_trap_next.surah_id = s_trap.id
        WHERE m_curr.verse_id = ?
      ''', [currentVerseId, currentVerseId]);

      final candidates = rows.map(DualPathCandidate.fromMap).toList();
      expect(candidates.length, equals(2));

      final correct = candidates.firstWhere((c) => !c.isTrapJump);
      final trap = candidates.firstWhere((c) => c.isTrapJump);

      expect(correct.surahId, equals(79));
      expect(correct.verseNumber, equals(34));
      expect(trap.surahId, equals(80));
      expect(trap.verseNumber, equals(33));
    });
  });

  // ===========================================================================
  // GROUP 3: PENGUJIAN TATA LETAK MUSHAF 15 BARIS & PEMROSESAN AUDIO PCM/WAV
  // ===========================================================================
  group('3. Mushaf15LineLayoutEngine & Konversi Audio PCM 16kHz', () {
    test('build15LinesForPage selalu menghasilkan tepat 15 baris beserta Header Surah & Basmalah', () {
      final sampleVerses = [
        const Verse(
          id: 1,
          surahId: 79,
          surahNameLatin: 'An-Nazi\'at',
          verseNumber: 1,
          pageNumber: 583,
          juzNumber: 30,
          textUthmani: 'وَالنَّازِعَاتِ غَرْقًا',
          textClean: 'والنازعات غرقا',
          translationId: 'Demi (malaikat) yang mencabut (nyawa) dengan keras.',
        ),
        const Verse(
          id: 2,
          surahId: 79,
          surahNameLatin: 'An-Nazi\'at',
          verseNumber: 2,
          pageNumber: 583,
          juzNumber: 30,
          textUthmani: 'وَالنَّاشِطَاتِ نَشْطًا',
          textClean: 'والناشطات نشطا',
          translationId: 'Demi (malaikat) yang mencabut (nyawa) dengan lemah lembut.',
        ),
      ];

      final lines = Mushaf15LineLayoutEngine.build15LinesForPage(sampleVerses);

      expect(lines.length, equals(15));
      expect(lines[0].isSurahHeader, isTrue);
      expect(lines[0].headerSurahName, equals('An-Nazi\'at'));
      expect(lines[1].isBismillahLine, isTrue);
    });

    test('toArabicDigits mengonversi nomor halaman dan ayat ke angka Arab Timur dengan benar', () {
      expect(Mushaf15LineLayoutEngine.toArabicDigits(1), equals('١'));
      expect(Mushaf15LineLayoutEngine.toArabicDigits(33), equals('٣٣'));
      expect(Mushaf15LineLayoutEngine.toArabicDigits(584), equals('٥٨٤'));
    });

    test('pcm16ToFloat32 dan buildWavHeader memproses sampel audio 16kHz secara akurat', () {
      // Buat 2 sampel PCM 16-bit Little-Endian: 0 dan 16384 (+0.5 amplitudo penuh)
      final byteData = ByteData(4);
      byteData.setInt16(0, 0, Endian.little);
      byteData.setInt16(2, 16384, Endian.little);
      final pcmBytes = byteData.buffer.asUint8List();

      final floatSamples = WhisperCppFfiEngine.pcm16ToFloat32(pcmBytes);
      expect(floatSamples.length, equals(2));
      expect(floatSamples[0], closeTo(0.0, 1e-5));
      expect(floatSamples[1], closeTo(0.5, 1e-4));

      final wavFileBytes = CloudWhisperApiEngine.buildWavHeader(pcmBytes);
      // Header WAV standar 44 byte + 4 byte data = 48 byte
      expect(wavFileBytes.length, equals(48));
      // Pastikan 4 karakter pertama adalah "RIFF"
      expect(String.fromCharCodes(wavFileBytes.sublist(0, 4)), equals('RIFF'));
      expect(String.fromCharCodes(wavFileBytes.sublist(8, 12)), equals('WAVE'));
    });
  });
}