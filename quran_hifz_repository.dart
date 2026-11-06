// quran_hifz_repository.dart
// =============================================================================
// Data Layer, Dual-Database SQLite Service, Repository, & Voice Hifz Matcher
// untuk Aplikasi Qur'an Tarteel Lintas Platform (Android, Windows, macOS).
//
// Dependensi pubspec.yaml yang dibutuhkan:
//   dependencies:
//     flutter:
//       sdk: flutter
//     sqflite: ^2.3.3
//     sqflite_common_ffi: ^2.3.3
//     path: ^1.9.0
//     path_provider: ^2.1.3
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// =============================================================================
// 1. DATA MODELS (ENTITAS MUSHAF, MUTASYABIHAT, & VOICE HIFZ)
// =============================================================================

enum MutasyabihatScope {
  withinOneJuz,
  withinOneSurah,
  crossJuz,
}

enum ListeningPathType {
  correctNext,
  trapJump,
}

class Surah {
  final int id;
  final String nameArabic;
  final String nameLatin;
  final String translationId;
  final int totalVerses;
  final String revelationType;

  const Surah({
    required this.id,
    required this.nameArabic,
    required this.nameLatin,
    required this.translationId,
    required this.totalVerses,
    required this.revelationType,
  });

  factory Surah.fromMap(Map<String, dynamic> map) {
    return Surah(
      id: map['id'] as int,
      nameArabic: map['name_arabic'] as String,
      nameLatin: map['name_latin'] as String,
      translationId: map['translation_id'] as String,
      totalVerses: map['total_verses'] as int,
      revelationType: map['revelation_type'] as String,
    );
  }
}

class QuranWord {
  final int id;
  final int verseId;
  final int wordPosition; // 1-based position
  final String textUthmani;
  final String textClean;
  final String translationId;
  final String? transliteration;

  const QuranWord({
    required this.id,
    required this.verseId,
    required this.wordPosition,
    required this.textUthmani,
    required this.textClean,
    required this.translationId,
    this.transliteration,
  });

  factory QuranWord.fromMap(Map<String, dynamic> map) {
    return QuranWord(
      id: map['id'] as int,
      verseId: map['verse_id'] as int,
      wordPosition: map['word_position'] as int,
      textUthmani: map['text_uthmani'] as String,
      textClean: map['text_clean'] as String,
      translationId: map['translation_id'] as String,
      transliteration: map['transliteration'] as String?,
    );
  }
}

class Verse {
  final int id;
  final int surahId;
  final String? surahNameLatin;
  final int verseNumber;
  final int pageNumber;
  final int juzNumber;
  final String textUthmani;
  final String textClean;
  final String translationId;
  final String? tafsirWajiz;
  final List<QuranWord> words;

  const Verse({
    required this.id,
    required this.surahId,
    this.surahNameLatin,
    required this.verseNumber,
    required this.pageNumber,
    required this.juzNumber,
    required this.textUthmani,
    required this.textClean,
    required this.translationId,
    this.tafsirWajiz,
    this.words = const [],
  });

  Verse copyWith({List<QuranWord>? words}) {
    return Verse(
      id: id,
      surahId: surahId,
      surahNameLatin: surahNameLatin,
      verseNumber: verseNumber,
      pageNumber: pageNumber,
      juzNumber: juzNumber,
      textUthmani: textUthmani,
      textClean: textClean,
      translationId: translationId,
      tafsirWajiz: tafsirWajiz,
      words: words ?? this.words,
    );
  }

  factory Verse.fromMap(Map<String, dynamic> map, {List<QuranWord> words = const []}) {
    return Verse(
      id: map['id'] as int,
      surahId: map['surah_id'] as int,
      surahNameLatin: map['surah_name_latin'] as String?,
      verseNumber: map['verse_number'] as int,
      pageNumber: map['page_number'] as int,
      juzNumber: map['juz_number'] as int,
      textUthmani: map['text_uthmani'] as String,
      textClean: map['text_clean'] as String,
      translationId: map['translation_id'] as String,
      tafsirWajiz: map['tafsir_wajiz'] as String?,
      words: words,
    );
  }
}

class MutasyabihatComparisonPair {
  final int groupId;
  final String title;
  final String? description;
  final int? scopeJuz;

  final int verseId1;
  final int surahId1;
  final String surahName1;
  final int verseNumber1;
  final int juzNumber1;
  final String textUthmani1;
  final List<int> diffWordPositions1;
  final String nextVerseStartWords1;

  final int verseId2;
  final int surahId2;
  final String surahName2;
  final int verseNumber2;
  final int juzNumber2;
  final String textUthmani2;
  final List<int> diffWordPositions2;
  final String nextVerseStartWords2;

  final String? userMemoryNote;

  const MutasyabihatComparisonPair({
    required this.groupId,
    required this.title,
    this.description,
    this.scopeJuz,
    required this.verseId1,
    required this.surahId1,
    required this.surahName1,
    required this.verseNumber1,
    required this.juzNumber1,
    required this.textUthmani1,
    required this.diffWordPositions1,
    required this.nextVerseStartWords1,
    required this.verseId2,
    required this.surahId2,
    required this.surahName2,
    required this.verseNumber2,
    required this.juzNumber2,
    required this.textUthmani2,
    required this.diffWordPositions2,
    required this.nextVerseStartWords2,
    this.userMemoryNote,
  });

  static List<int> _parseIntList(dynamic rawJson) {
    if (rawJson == null || rawJson.toString().isEmpty) return const [];
    try {
      final decoded = jsonDecode(rawJson.toString()) as List<dynamic>;
      return decoded.map((e) => (e as num).toInt()).toList();
    } catch (_) {
      return const [];
    }
  }

  factory MutasyabihatComparisonPair.fromMap(Map<String, dynamic> map) {
    return MutasyabihatComparisonPair(
      groupId: map['group_id'] as int,
      title: map['title'] as String,
      description: map['description'] as String?,
      scopeJuz: map['scope_juz'] as int?,
      verseId1: map['verse_id_1'] as int,
      surahId1: map['surah_1'] as int,
      surahName1: map['surah_name_1'] as String,
      verseNumber1: map['verse_num_1'] as int,
      juzNumber1: map['juz_1'] as int,
      textUthmani1: map['text_1'] as String,
      diffWordPositions1: _parseIntList(map['diff_1']),
      nextVerseStartWords1: map['next_words_1'] as String,
      verseId2: map['verse_id_2'] as int,
      surahId2: map['surah_2'] as int,
      surahName2: map['surah_name_2'] as String,
      verseNumber2: map['verse_num_2'] as int,
      juzNumber2: map['juz_2'] as int,
      textUthmani2: map['text_2'] as String,
      diffWordPositions2: _parseIntList(map['diff_2']),
      nextVerseStartWords2: map['next_words_2'] as String,
      userMemoryNote: map['user_note'] as String?,
    );
  }
}

class DualPathCandidate {
  final ListeningPathType pathType;
  final int verseId;
  final int surahId;
  final String surahName;
  final int verseNumber;
  final String expectedTextClean;
  final String textUthmani;

  const DualPathCandidate({
    required this.pathType,
    required this.verseId,
    required this.surahId,
    required this.surahName,
    required this.verseNumber,
    required this.expectedTextClean,
    required this.textUthmani,
  });

  bool get isTrapJump => pathType == ListeningPathType.trapJump;

  factory DualPathCandidate.fromMap(Map<String, dynamic> map) {
    final rawType = map['path_type'] as String;
    return DualPathCandidate(
      pathType: rawType == 'CORRECT_NEXT'
          ? ListeningPathType.correctNext
          : ListeningPathType.trapJump,
      verseId: map['verse_id'] as int,
      surahId: map['surah_id'] as int,
      surahName: map['surah_name'] as String,
      verseNumber: map['verse_number'] as int,
      expectedTextClean: map['expected_text'] as String,
      textUthmani: map['text_uthmani'] as String,
    );
  }
}

class MutasyabihatDrillQuestion {
  final int groupId;
  final String promptSurahName;
  final int promptSurahId;
  final int promptVerseNumber;
  final String promptVerseUthmani;
  final String correctContinuationUthmani;
  final String trapContinuationUthmani;
  final String trapSurahName;
  final int trapVerseNumber;
  final String? memoryAnchorHint;

  const MutasyabihatDrillQuestion({
    required this.groupId,
    required this.promptSurahName,
    required this.promptSurahId,
    required this.promptVerseNumber,
    required this.promptVerseUthmani,
    required this.correctContinuationUthmani,
    required this.trapContinuationUthmani,
    required this.trapSurahName,
    required this.trapVerseNumber,
    this.memoryAnchorHint,
  });
}

// =============================================================================
// 2. DUAL-DATABASE SERVICE (ANDROID + WINDOWS + MACOS)
// =============================================================================

class QuranDatabaseService {
  static final QuranDatabaseService instance = QuranDatabaseService._internal();
  QuranDatabaseService._internal();

  Database? _db;

  /// Mengambil instance database utama yang sudah di-attach dengan `user_hifz.db`.
  Future<Database> get database async {
    if (_db != null && _db!.isOpen) {
      return _db!;
    }
    _db = await _initDualDatabases();
    return _db!;
  }

  Future<Database> _initDualDatabases() async {
    // Gunakan sqflite_common_ffi untuk Desktop (Windows, macOS, Linux)
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final supportDir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(supportDir.path, 'databases'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    final masterDbPath = p.join(dbDir.path, 'quran_master.db');
    final userDbPath = p.join(dbDir.path, 'user_hifz.db');

    // 1. Salin aset quran_master.db jika belum ada di penyimpanan lokal perangkat
    final masterFile = File(masterDbPath);
    if (!await masterFile.exists()) {
      final byteData = await rootBundle.load('assets/db/quran_master.db');
      final bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      await masterFile.writeAsBytes(bytes, flush: true);
    }

    // 2. Pastikan user_hifz.db beserta tabelnya sudah diinisialisasi
    final userDb = await openDatabase(
      userDbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS user_memory_anchors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            group_id INTEGER NOT NULL UNIQUE,
            user_note TEXT NOT NULL,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
          );
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS error_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            expected_verse_id INTEGER NOT NULL,
            jumped_to_verse_id INTEGER NOT NULL,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
          );
        ''');
      },
    );
    await userDb.close();

    // 3. Buka quran_master.db dan ATTACH user_hifz.db sebagai schema `user_hifz`
    final masterDb = await openDatabase(masterDbPath, readOnly: false);
    final escapedUserPath = userDbPath.replaceAll("'", "''");
    await masterDb.execute("ATTACH DATABASE '$escapedUserPath' AS user_hifz;");

    return masterDb;
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}

// =============================================================================
// 3. REPOSITORY UTAMA (MUSHAF, RADAR MUTASYABIHAT, & DUAL-PATH LISTENING)
// =============================================================================

class QuranHifzRepository {
  final QuranDatabaseService _dbService;

  QuranHifzRepository({QuranDatabaseService? dbService})
      : _dbService = dbService ?? QuranDatabaseService.instance;

  /// Mengambil daftar seluruh Surah.
  Future<List<Surah>> getAllSurahs() async {
    final db = await _dbService.database;
    final rows = await db.query('surahs', orderBy: 'id ASC');
    return rows.map(Surah.fromMap).toList();
  }

  /// Mengambil daftar ayat berdasarkan Surah atau Halaman Mushaf, lengkap dengan kata perkata.
  Future<List<Verse>> getVerses({
    int? surahId,
    int? pageNumber,
    int? juzNumber,
    bool includeWords = true,
  }) async {
    final db = await _dbService.database;
    final whereClauses = <String>[];
    final whereArgs = <Object?>[];

    if (surahId != null) {
      whereClauses.add('v.surah_id = ?');
      whereArgs.add(surahId);
    }
    if (pageNumber != null) {
      whereClauses.add('v.page_number = ?');
      whereArgs.add(pageNumber);
    }
    if (juzNumber != null) {
      whereClauses.add('v.juz_number = ?');
      whereArgs.add(juzNumber);
    }

    final whereSql =
        whereClauses.isEmpty ? '' : 'WHERE ${whereClauses.join(' AND ')}';

    final verseRows = await db.rawQuery('''
      SELECT v.*, s.name_latin AS surah_name_latin
      FROM verses v
      JOIN surahs s ON v.surah_id = s.id
      $whereSql
      ORDER BY v.surah_id ASC, v.verse_number ASC
    ''', whereArgs);

    final verses = verseRows.map((r) => Verse.fromMap(r)).toList();
    if (!includeWords || verses.isEmpty) {
      return verses;
    }

    // Ambil seluruh kosakata perkata dalam satu batch query untuk performa tinggi
    final verseIds = verses.map((v) => v.id).toList();
    final placeholders = List.filled(verseIds.length, '?').join(',');
    final wordRows = await db.rawQuery('''
      SELECT *
      FROM words
      WHERE verse_id IN ($placeholders)
      ORDER BY verse_id ASC, word_position ASC
    ''', verseIds);

    final wordsByVerse = <int, List<QuranWord>>{};
    for (final row in wordRows) {
      final word = QuranWord.fromMap(row);
      wordsByVerse.putIfAbsent(word.verseId, () => []).add(word);
    }

    return verses
        .map((v) => v.copyWith(words: wordsByVerse[v.id] ?? const []))
        .toList();
  }

  /// SQL Query A: Mengambil pasangan ayat mirip (Radar Mutasyabihat) sesuai filter Scope:
  /// - `withinOneJuz`  : Pasangan ayat berada dalam 1 Juz yang sama (prioritas utama).
  /// - `withinOneSurah`: Pasangan ayat berada dalam 1 Surah yang sama.
  /// - `crossJuz`      : Pasangan ayat berada di Juz yang berbeda (Lintas Juz).
  Future<List<MutasyabihatComparisonPair>> getMutasyabihatRadar({
    required MutasyabihatScope scope,
    int? juzNumber,
    int? surahId,
  }) async {
    final db = await _dbService.database;
    final filterClauses = <String>[];
    final args = <Object?>[];

    switch (scope) {
      case MutasyabihatScope.withinOneJuz:
        filterClauses.add('v1.juz_number = v2.juz_number');
        if (juzNumber != null) {
          filterClauses.add('v1.juz_number = ?');
          args.add(juzNumber);
        }
        break;
      case MutasyabihatScope.withinOneSurah:
        filterClauses.add('v1.surah_id = v2.surah_id');
        if (surahId != null) {
          filterClauses.add('v1.surah_id = ?');
          args.add(surahId);
        }
        break;
      case MutasyabihatScope.crossJuz:
        filterClauses.add('v1.juz_number != v2.juz_number');
        if (juzNumber != null) {
          filterClauses.add('(v1.juz_number = ? OR v2.juz_number = ?)');
          args.addAll([juzNumber, juzNumber]);
        }
        break;
    }

    final whereClause =
        filterClauses.isEmpty ? '' : 'WHERE ${filterClauses.join(' AND ')}';

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
      $whereClause
      ORDER BY v1.juz_number DESC, v1.surah_id ASC, v1.verse_number ASC
    ''', args);

    return rows.map(MutasyabihatComparisonPair.fromMap).toList();
  }

  /// SQL Query B: Dual-Path Listening untuk mendeteksi apakah pengguna membaca
  /// ayat selanjutnya yang benar (`CORRECT_NEXT`) atau justru terpeleset ke lanjutan
  /// surah lain karena kemiripan ayat (`TRAP_JUMP`).
  Future<List<DualPathCandidate>> getDualPathCandidates(int currentVerseId) async {
    final db = await _dbService.database;
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

    return rows.map(DualPathCandidate.fromMap).toList();
  }

  /// Menyimpan atau memperbarui catatan Jembatan Ingatan (Memory Anchor) di `user_hifz.db`.
  Future<void> saveMemoryAnchor({
    required int groupId,
    required String userNote,
  }) async {
    final db = await _dbService.database;
    await db.rawInsert('''
      INSERT INTO user_hifz.user_memory_anchors (group_id, user_note, updated_at)
      VALUES (?, ?, CURRENT_TIMESTAMP)
      ON CONFLICT(group_id) DO UPDATE SET
        user_note = excluded.user_note,
        updated_at = CURRENT_TIMESTAMP
    ''', [groupId, userNote.trim()]);
  }

  /// Mencatat insiden kesalahan lompat surah ke tabel `user_hifz.error_logs`.
  Future<void> logTrapJumpError({
    required int expectedVerseId,
    required int jumpedToVerseId,
  }) async {
    final db = await _dbService.database;
    await db.rawInsert('''
      INSERT INTO user_hifz.error_logs (expected_verse_id, jumped_to_verse_id)
      VALUES (?, ?)
    ''', [expectedVerseId, jumpedToVerseId]);
  }

  /// Menghasilkan soal latihan untuk Mode Drill "Jebakan Mutasyabihat" dalam 1 Juz.
  Future<List<MutasyabihatDrillQuestion>> generateDrillQuestions({
    required int juzNumber,
    int limit = 10,
  }) async {
    final pairs = await getMutasyabihatRadar(
      scope: MutasyabihatScope.withinOneJuz,
      juzNumber: juzNumber,
    );

    final questions = <MutasyabihatDrillQuestion>[];
    for (final pair in pairs.take(limit)) {
      if (pair.nextVerseStartWords1 == '[Akhir Surah]' ||
          pair.nextVerseStartWords2 == '[Akhir Surah]') {
        continue;
      }
      questions.add(
        MutasyabihatDrillQuestion(
          groupId: pair.groupId,
          promptSurahName: pair.surahName1,
          promptSurahId: pair.surahId1,
          promptVerseNumber: pair.verseNumber1,
          promptVerseUthmani: pair.textUthmani1,
          correctContinuationUthmani: pair.nextVerseStartWords1,
          trapContinuationUthmani: pair.nextVerseStartWords2,
          trapSurahName: pair.surahName2,
          trapVerseNumber: pair.verseNumber2 + 1,
          memoryAnchorHint: pair.userMemoryNote,
        ),
      );
    }
    return questions;
  }
}

// =============================================================================
// 4. ENGINE VOICE HIFZ & FUZZY MATCHING (DETEKSI LOMPAT SURAH REAL-TIME)
// =============================================================================

class VoiceEvaluationResult {
  final ListeningPathType detectedPath;
  final DualPathCandidate matchedCandidate;
  final double similarityScore;
  final String warningMessage;

  const VoiceEvaluationResult({
    required this.detectedPath,
    required this.matchedCandidate,
    required this.similarityScore,
    required this.warningMessage,
  });

  bool get isTrapJump => detectedPath == ListeningPathType.trapJump;
}

class ArabicFuzzyMatcher {
  static final RegExp _diacriticsRegExp = RegExp(
    r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06DC\u06DF-\u06E8\u06EA-\u06ED\u0640]',
  );

  /// Menormalisasi transkripsi suara Arab dari Whisper / STT agar setara dengan kolom `text_clean`.
  static String normalizeArabic(String input) {
    if (input.isEmpty) return '';
    var cleaned = input.replaceAll(_diacriticsRegExp, '');
    cleaned = cleaned.replaceAll(RegExp(r'[أإآٱ]'), 'ا');
    cleaned = cleaned
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Menghitung Levenshtein Distance antara dua string.
  static int levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    final v0 = List<int>.generate(s2.length + 1, (i) => i);
    final v1 = List<int>.filled(s2.length + 1, 0);

    for (var i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (var j = 0; j < s2.length; j++) {
        final cost = (s1.codeUnitAt(i) == s2.codeUnitAt(j)) ? 0 : 1;
        v1[j + 1] = math.min(
          v1[j] + 1,
          math.min(v0[j + 1] + 1, v0[j] + cost),
        );
      }
      for (var j = 0; j <= s2.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[s2.length];
  }

  /// Menghitung skor kemiripan (0.0 - 1.0) antara transkripsi pengguna dan potongan awal ayat kandidat.
  static double calculatePrefixSimilarity(String spokenTranscript, String candidateCleanText) {
    final spokenWords = normalizeArabic(spokenTranscript).split(' ');
    final candidateWords = normalizeArabic(candidateCleanText).split(' ');
    if (spokenWords.isEmpty || candidateWords.isEmpty) return 0.0;

    // Bandingkan sebanyak jumlah kata yang baru diucapkan pengguna (maksimal panjang kandidat)
    final compareCount = math.min(spokenWords.length, candidateWords.length);
    final spokenPrefix = spokenWords.take(compareCount).join(' ');
    final candidatePrefix = candidateWords.take(compareCount).join(' ');

    final maxLen = math.max(spokenPrefix.length, candidatePrefix.length);
    if (maxLen == 0) return 1.0;

    final dist = levenshteinDistance(spokenPrefix, candidatePrefix);
    return 1.0 - (dist / maxLen);
  }

  /// Mengevaluasi transkripsi STT terhadap seluruh kandidat Dual-Path Listening.
  static VoiceEvaluationResult? evaluateNextVerseSpeech({
    required String spokenTranscript,
    required List<DualPathCandidate> candidates,
    double threshold = 0.72,
  }) {
    if (spokenTranscript.trim().isEmpty || candidates.isEmpty) return null;

    DualPathCandidate? bestCandidate;
    var bestScore = 0.0;

    for (final candidate in candidates) {
      final score = calculatePrefixSimilarity(
        spokenTranscript,
        candidate.expectedTextClean,
      );
      if (score > bestScore) {
        bestScore = score;
        bestCandidate = candidate;
      }
    }

    if (bestCandidate == null || bestScore < threshold) {
      return null;
    }

    final correctCandidate = candidates
        .where((c) => c.pathType == ListeningPathType.correctNext)
        .firstOrNull;

    final warning = bestCandidate.isTrapJump
        ? 'Terdeteksi lompat surah! Anda membaca lanjutan QS. ${bestCandidate.surahName}: ${bestCandidate.verseNumber}. '
          'Seharusnya melanjutkan ke QS. ${correctCandidate?.surahName ?? "-"}: ${correctCandidate?.verseNumber ?? "-"} '
          '(${correctCandidate?.textUthmani ?? ""}).'
        : 'Bacaan tepat sesuai urutan QS. ${bestCandidate.surahName}: ${bestCandidate.verseNumber}.';

    return VoiceEvaluationResult(
      detectedPath: bestCandidate.pathType,
      matchedCandidate: bestCandidate,
      similarityScore: bestScore,
      warningMessage: warning,
    );
  }
}