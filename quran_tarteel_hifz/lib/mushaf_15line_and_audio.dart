// mushaf_15line_and_audio.dart
// =============================================================================
// [OPSI 3] Modul Tampilan Mushaf Standar Madinah (15 Baris) & Audio Murattal Koreksi
// untuk Aplikasi Qur'an Tarteel Lintas Platform (Android, Windows, macOS).
//
// Fitur Utama:
// 1. Mushaf15LinePageWidget:
//    - Menyusun kata demi kata dari daftar ayat pada satu halaman Mushaf (1-604)
//      ke dalam tepat 15 baris proporsional ala Mushaf Madinah (QUL Tarteel).
//    - Mendukung penuh fitur Hide/Peek Verse (efek blur perkata yang terbuka
//      saat dibaca atau saat menekan tombol Spasi/Peek) langsung di atas halaman Mushaf.
//    - Menampilkan bingkai ornamen kepala Surah, البسملة, dan simbol akhir ayat (۝).
// 2. QuranMurattalAudioService & MurattalPlayerBar:
//    - Memutar audio murattal per ayat dari CDN EveryAyah / Quran.com API v4
//      dengan pilihan 4 Qari utama (Alafasy, Al-Husary Muallim, Abdul Basit, Al-Minshawi).
//    - Fitur "Auto-Correction on Trap Jump": Otomatis memutar bunyi ayat lanjutan
//      yang BENAR ketika pengguna terdeteksi melompat ke surah lain yang mirip.
//    - Fitur Loop A-B (Ulangi Ayat Transisi 3x/5x) untuk melatih bagian Mutasyabihat.
//
// Dependensi pubspec.yaml:
//   just_audio: ^0.9.39
// =============================================================================

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

import 'quran_hifz_repository.dart';

// =============================================================================
// 1. MODEL & KATALOG QARI MURATTAL (EVERYAYAH / QURAN.COM CDN)
// =============================================================================

class QariReciter {
  final String id;
  final String name;
  final String styleLabel;
  final String everyAyahSubfolder;

  const QariReciter({
    required this.id,
    required this.name,
    required this.styleLabel,
    required this.everyAyahSubfolder,
  });

  /// Menghasilkan URL MP3 per ayat (format standar 6 digit: SSSVVV.mp3, misal 079034.mp3).
  String getVerseAudioUrl(int surahId, int verseNumber) {
    final s = surahId.toString().padLeft(3, '0');
    final v = verseNumber.toString().padLeft(3, '0');
    return 'https://everyayah.com/data/$everyAyahSubfolder/$s$v.mp3';
  }
}

class QariCatalog {
  static const List<QariReciter> supportedReciters = [
    QariReciter(
      id: 'husary_muallim',
      name: 'Syaikh Mahmoud Khalil Al-Husary',
      styleLabel: 'Tartil Hifz (Rekomendasi Hafalan)',
      everyAyahSubfolder: 'Husary_128kbps',
    ),
    QariReciter(
      id: 'alafasy',
      name: 'Syaikh Mishary Rashid Alafasy',
      styleLabel: 'Murattal Jernih',
      everyAyahSubfolder: 'Alafasy_128kbps',
    ),
    QariReciter(
      id: 'minshawy',
      name: 'Syaikh Muhammad Siddiq Al-Minshawi',
      styleLabel: 'Murattal Klasik',
      everyAyahSubfolder: 'Minshawy_Murattal_128kbps',
    ),
    QariReciter(
      id: 'abdul_basit',
      name: 'Syaikh Abdul Basit Abdus Samad',
      styleLabel: 'Murattal Madinah',
      everyAyahSubfolder: 'Abdul_Basit_Murattal_192kbps',
    ),
  ];
}

// =============================================================================
// 2. SERVICE PEMUTAR AUDIO MURATTAL & KOREKSI OTOMATIS TRAP JUMP
// =============================================================================

class QuranMurattalAudioService extends ChangeNotifier {
  QariReciter _selectedReciter = QariCatalog.supportedReciters.first;
  bool _isPlaying = false;
  bool _autoPlayOnTrapJump = true;
  int _repeatTargetCount = 1;
  int _currentRepeatIteration = 0;

  int? _playingSurahId;
  int? _playingVerseNumber;
  String? _currentAudioUrl;
  String? _statusCaption;
  Timer? _playbackTimer;

  /// Callback opsional untuk menghubungkan ke instance `just_audio` (`AudioPlayer.setUrl`).
  final Future<void> Function(String url)? externalAudioUrlPlayer;

  QuranMurattalAudioService({this.externalAudioUrlPlayer});

  QariReciter get selectedReciter => _selectedReciter;
  bool get isPlaying => _isPlaying;
  bool get autoPlayOnTrapJump => _autoPlayOnTrapJump;
  int get repeatTargetCount => _repeatTargetCount;
  int? get playingSurahId => _playingSurahId;
  int? get playingVerseNumber => _playingVerseNumber;
  String? get currentAudioUrl => _currentAudioUrl;
  String? get statusCaption => _statusCaption;

  void setReciter(QariReciter reciter) {
    _selectedReciter = reciter;
    notifyListeners();
  }

  void setAutoPlayOnTrapJump(bool enabled) {
    _autoPlayOnTrapJump = enabled;
    notifyListeners();
  }

  void setRepeatTargetCount(int count) {
    _repeatTargetCount = count.clamp(1, 10);
    notifyListeners();
  }

  /// Memutar audio murattal untuk ayat tertentu (dengan dukungan pengulangan / loop hafalan).
  Future<void> playVerse({
    required int surahId,
    required int verseNumber,
    String? surahName,
    String? customCaption,
  }) async {
    _playbackTimer?.cancel();
    final url = _selectedReciter.getVerseAudioUrl(surahId, verseNumber);

    _isPlaying = true;
    _playingSurahId = surahId;
    _playingVerseNumber = verseNumber;
    _currentAudioUrl = url;
    _currentRepeatIteration = 1;
    _statusCaption = customCaption ??
        'Memutar QS. ${surahName ?? surahId}: $verseNumber • ${_selectedReciter.name} '
            '(${_repeatTargetCount > 1 ? "Ulang $_currentRepeatIteration/$_repeatTargetCount" : "1x"})';
    notifyListeners();

    if (externalAudioUrlPlayer != null) {
      await externalAudioUrlPlayer!(url);
    }

    // Pengatur siklus loop otomatis apabila pengguna memilih pengulangan (misal 3x untuk menguatkan mutasyabihat)
    _scheduleLoopCheck(surahId: surahId, verseNumber: verseNumber, surahName: surahName);
  }

  /// Dipanggil secara otomatis ketika pengguna terkena peringatan Trap Jump (lompat ke surah lain).
  Future<void> playTrapJumpCorrection(DualPathCandidate correctCandidate) async {
    if (!_autoPlayOnTrapJump) return;
    await playVerse(
      surahId: correctCandidate.surahId,
      verseNumber: correctCandidate.verseNumber,
      surahName: correctCandidate.surahName,
      customCaption:
          'Koreksi Otomatis Trap Jump: Memperdengarkan lanjutan yang benar '
          '(QS. ${correctCandidate.surahName}: ${correctCandidate.verseNumber}) — ${correctCandidate.textUthmani}',
    );
  }

  void _scheduleLoopCheck({
    required int surahId,
    required int verseNumber,
    String? surahName,
  }) {
    _playbackTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }
      if (_currentRepeatIteration < _repeatTargetCount) {
        _currentRepeatIteration++;
        _statusCaption =
            'Memutar QS. ${surahName ?? surahId}: $verseNumber • ${_selectedReciter.name} '
            '(Ulang $_currentRepeatIteration/$_repeatTargetCount)';
        notifyListeners();
        if (externalAudioUrlPlayer != null && _currentAudioUrl != null) {
          await externalAudioUrlPlayer!(_currentAudioUrl!);
        }
      } else {
        timer.cancel();
        _isPlaying = false;
        _statusCaption =
            'Selesai memutar QS. ${surahName ?? surahId}: $verseNumber.';
        notifyListeners();
      }
    });
  }

  void stop() {
    _playbackTimer?.cancel();
    _isPlaying = false;
    _statusCaption = 'Pemutaran murattal dihentikan.';
    notifyListeners();
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }
}

// =============================================================================
// 3. ENGINE TATA LETAK MUSHAF MADINAH 15 BARIS (MUSHAF PAGE LAYOUT)
// =============================================================================

/// Merepresentasikan satu token visual di dalam baris Mushaf 15 baris (kata ayat atau simbol nomor akhir ayat).
class MushafLineToken {
  final Verse verse;
  final QuranWord? word;
  final bool isVerseEndMarker;

  const MushafLineToken({
    required this.verse,
    this.word,
    this.isVerseEndMarker = false,
  });
}

/// Merepresentasikan 1 baris dari total 15 baris pada halaman Mushaf Madinah.
class MushafLineModel {
  final int lineNumber; // 1..15
  final int? headerSurahId;
  final String? headerSurahName;
  final bool isBismillahLine;
  final List<MushafLineToken> tokens;

  const MushafLineModel({
    required this.lineNumber,
    this.headerSurahId,
    this.headerSurahName,
    this.isBismillahLine = false,
    this.tokens = const [],
  });

  bool get isSurahHeader => headerSurahId != null;
}

class Mushaf15LineLayoutEngine {
  static const int standardLinesPerPage = 15;

  /// Membagi daftar ayat pada satu halaman Mushaf menjadi tepat 15 baris proporsional
  /// standar Mushaf Madinah, lengkap dengan bingkai nama Surah dan Basmalah pada awal Surah.
  static List<MushafLineModel> build15LinesForPage(List<Verse> pageVerses) {
    if (pageVerses.isEmpty) return const [];

    final rawSegments = <MushafLineModel>[];
    final tokenPool = <MushafLineToken>[];

    int? lastSurahId;
    for (final verse in pageVerses) {
      // Jika memasuki ayat ke-1 dari sebuah Surah baru, sisipkan header Surah & Basmalah
      if (verse.verseNumber == 1 && verse.surahId != lastSurahId) {
        lastSurahId = verse.surahId;
        rawSegments.add(
          MushafLineModel(
            lineNumber: 0,
            headerSurahId: verse.surahId,
            headerSurahName: verse.surahNameLatin ?? 'Surah ${verse.surahId}',
          ),
        );
        // Semua surah selain At-Taubah (9) dan Al-Fatihah (1) memiliki baris Basmalah tersendiri
        if (verse.surahId != 1 && verse.surahId != 9) {
          rawSegments.add(
            const MushafLineModel(
              lineNumber: 0,
              isBismillahLine: true,
            ),
          );
        }
      }

      final words = verse.words.isNotEmpty
          ? verse.words
          : verse.textUthmani
              .split(' ')
              .where((w) => w.isNotEmpty)
              .toList()
              .asMap()
              .entries
              .map(
                (e) => QuranWord(
                  id: e.key,
                  verseId: verse.id,
                  wordPosition: e.key + 1,
                  textUthmani: e.value,
                  textClean: e.value,
                  translationId: '',
                ),
              )
              .toList();

      for (final w in words) {
        tokenPool.add(MushafLineToken(verse: verse, word: w));
      }
      tokenPool.add(MushafLineToken(verse: verse, isVerseEndMarker: true));
    }

    // Hitung jumlah baris teks yang tersisa dari total 15 baris setelah dikurangi baris Header/Basmalah
    final remainingTextLines =
        (standardLinesPerPage - rawSegments.length).clamp(1, standardLinesPerPage);

    final resultLines = <MushafLineModel>[];
    var currentLineNum = 1;

    for (final headerSeg in rawSegments) {
      resultLines.add(
        MushafLineModel(
          lineNumber: currentLineNum++,
          headerSurahId: headerSeg.headerSurahId,
          headerSurahName: headerSeg.headerSurahName,
          isBismillahLine: headerSeg.isBismillahLine,
        ),
      );
    }

    if (tokenPool.isEmpty) {
      return resultLines;
    }

    // Distribusi kata secara proporsional seperti di versi Web (minimal 4 token per baris)
    final wordsPerLine = (tokenPool.length / remainingTextLines).ceil() < 4
        ? 4
        : (tokenPool.length / remainingTextLines).ceil();

    var cursor = 0;
    for (var i = 0; i < remainingTextLines; i++) {
      if (cursor >= tokenPool.length) {
        resultLines.add(
          MushafLineModel(
            lineNumber: currentLineNum++,
            tokens: const [],
          ),
        );
        continue;
      }
      final endIdx = (cursor + wordsPerLine).clamp(0, tokenPool.length);
      final slice = tokenPool.sublist(cursor, endIdx);
      cursor = endIdx;

      resultLines.add(
        MushafLineModel(
          lineNumber: currentLineNum++,
          tokens: slice,
        ),
      );
    }

    while (resultLines.length < standardLinesPerPage) {
      resultLines.add(
        MushafLineModel(
          lineNumber: currentLineNum++,
          tokens: const [],
        ),
      );
    }

    return resultLines;
  }

  /// Mengonversi angka integer ke angka Arab Timur (٠١٢٣٤٥٦٧٨٩) untuk medali akhir ayat.
  static String toArabicDigits(int number) {
    const arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number
        .toString()
        .split('')
        .map((ch) => arabicDigits[int.tryParse(ch) ?? 0])
        .join();
  }
}

// =============================================================================
// 4. WIDGET LEMBARAN MUSHAF MADINAH 15 BARIS INTERAKTIF
// =============================================================================

class Mushaf15LinePageWidget extends StatelessWidget {
  final List<Verse> verses;
  final int activeVerseId;
  final int revealedWordPosition;
  final bool hideVerseMode;
  final String? surahArabicName;
  final String? revelationType;
  final VoidCallback? onPrevPage;
  final VoidCallback? onNextPage;
  final void Function(Verse verse) onSelectVerse;
  final void Function(Verse verse) onPlayVerseAudio;
  final void Function(Verse verse) onShowTafsir;

  const Mushaf15LinePageWidget({
    super.key,
    required this.verses,
    required this.activeVerseId,
    required this.revealedWordPosition,
    required this.hideVerseMode,
    this.surahArabicName,
    this.revelationType,
    this.onPrevPage,
    this.onNextPage,
    required this.onSelectVerse,
    required this.onPlayVerseAudio,
    required this.onShowTafsir,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = isDark ? const Color(0xFF1A201E) : const Color(0xFFFCFAF6);
    final borderGold = isDark ? const Color(0xFF785E2B) : const Color(0xFFC8AA76);
    final lineRule = isDark ? const Color(0xFF28302D) : const Color(0xFFEBE5D8);
    final primaryColor = isDark ? const Color(0xFF34D399) : const Color(0xFF165B33);
    final goldText = isDark ? const Color(0xFFD9B36C) : const Color(0xFF9B7A38);
    final arabicColor = isDark ? const Color(0xFFF3F1EC) : const Color(0xFF141816);
    final bannerBg = isDark ? const Color(0xFF242B28) : const Color(0xFFF2ECE1);

    final pageNumber = verses.isNotEmpty ? verses.first.pageNumber : 582;
    final juzNumber = verses.isNotEmpty ? verses.first.juzNumber : 30;
    final surahTitle = surahArabicName != null && surahArabicName!.isNotEmpty
        ? 'سُورَةُ $surahArabicName'
        : (verses.isNotEmpty ? 'سُورَةُ ${verses.first.surahNameLatin ?? ''}' : '');
    final lines = Mushaf15LineLayoutEngine.build15LinesForPage(verses);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
      decoration: BoxDecoration(
        color: pageBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderGold, width: 2.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Halaman Mushaf (persis seperti .mushaf-page-header di Web)
          Container(
            padding: const EdgeInsets.only(bottom: 12),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: borderGold, width: 1.0),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'الجزء ${Mushaf15LineLayoutEngine.toArabicDigits(juzNumber)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: goldText,
                  ),
                ),
                Text(
                  surahTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: primaryColor,
                  ),
                ),
                Text(
                  Mushaf15LineLayoutEngine.toArabicDigits(pageNumber),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: goldText,
                  ),
                ),
              ],
            ),
          ),

          // 15 Baris Mushaf (tanpa angka 1..15 di tepi kiri, persis seperti Web)
          ...lines.where((l) => l.isSurahHeader || l.isBismillahLine || l.tokens.isNotEmpty).map(
                (line) => _buildMushafLineRow(
                  context,
                  line,
                  isDark: isDark,
                  primaryColor: primaryColor,
                  goldText: goldText,
                  borderGold: borderGold,
                  lineRule: lineRule,
                  arabicColor: arabicColor,
                  bannerBg: bannerBg,
                ),
              ),

          // Footer Navigasi Halaman Mushaf (persis seperti .mushaf-page-footer di Web)
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: borderGold, width: 1.0),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: onPrevPage,
                  icon: const Icon(Icons.chevron_left_rounded, size: 18),
                  label: const Text('Sebelumnya'),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark ? const Color(0xFFA7B0AC) : const Color(0xFF525E58),
                  ),
                ),
                Text(
                  'Halaman $pageNumber',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFFA7B0AC) : const Color(0xFF525E58),
                  ),
                ),
                TextButton.icon(
                  onPressed: onNextPage,
                  icon: const Text('Selanjutnya'),
                  label: const Icon(Icons.chevron_right_rounded, size: 18),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark ? const Color(0xFFA7B0AC) : const Color(0xFF525E58),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMushafLineRow(
    BuildContext context,
    MushafLineModel line, {
    required bool isDark,
    required Color primaryColor,
    required Color goldText,
    required Color borderGold,
    required Color lineRule,
    required Color arabicColor,
    required Color bannerBg,
  }) {
    if (line.isSurahHeader) {
      final revArabic = (revelationType?.toLowerCase() == 'madaniyah') ? 'مَدَنِيَّة' : 'مَكِّيَّة';
      final titleArabic = surahArabicName != null && surahArabicName!.isNotEmpty
          ? 'سُورَةُ $surahArabicName • $revArabic'
          : 'سُورَةُ ${line.headerSurahName} • $revArabic';
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
          color: bannerBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderGold),
        ),
        child: Center(
          child: Text(
            titleArabic,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: primaryColor,
            ),
          ),
        ),
      );
    }

    if (line.isBismillahLine) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: lineRule, width: 1.0)),
        ),
        child: Center(
          child: Text(
            'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: arabicColor,
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: lineRule, width: 1.0)),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Wrap(
          alignment: WrapAlignment.spaceEvenly,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: line.tokens.map((token) {
            final isVerseActive = token.verse.id == activeVerseId;

            if (token.isVerseEndMarker) {
              return InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  onSelectVerse(token.verse);
                  onPlayVerseAudio(token.verse);
                },
                onLongPress: () => onShowTafsir(token.verse),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    '۝${Mushaf15LineLayoutEngine.toArabicDigits(token.verse.verseNumber)}',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: isVerseActive ? primaryColor : goldText,
                    ),
                  ),
                ),
              );
            }

            final word = token.word!;
            final isRevealed = !hideVerseMode ||
                (isVerseActive && word.wordPosition <= revealedWordPosition);

            return InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onSelectVerse(token.verse),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: (isVerseActive && isRevealed && hideVerseMode)
                      ? primaryColor.withOpacity(0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: isRevealed ? 0.0 : 8.0,
                    sigmaY: isRevealed ? 0.0 : 8.0,
                  ),
                  child: Text(
                    word.textUthmani,
                    style: TextStyle(
                      fontSize: 25,
                      height: 1.85,
                      fontWeight: isVerseActive ? FontWeight.w600 : FontWeight.w500,
                      color: isVerseActive && isRevealed ? primaryColor : arabicColor,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// =============================================================================
// 5. MINI DOCK PEMUTAR AUDIO MURATTAL & KONTROL KOREKSI TRAP JUMP
// =============================================================================

class MurattalMiniPlayerDock extends StatelessWidget {
  final QuranMurattalAudioService audioService;
  final Verse? activeVerse;

  const MurattalMiniPlayerDock({
    super.key,
    required this.audioService,
    required this.activeVerse,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: audioService,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            border: Border(top: BorderSide(color: Color(0xFF334155))),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              // Pilihan Qari
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.spatial_audio_off_rounded,
                    color: Color(0xFF2DD4BF),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: audioService.selectedReciter.id,
                      dropdownColor: const Color(0xFF0F172A),
                      items: QariCatalog.supportedReciters
                          .map(
                            (q) => DropdownMenuItem<String>(
                              value: q.id,
                              child: Text(
                                '${q.name} (${q.styleLabel})',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (id) {
                        if (id == null) return;
                        final found = QariCatalog.supportedReciters.firstWhere(
                          (q) => q.id == id,
                        );
                        audioService.setReciter(found);
                      },
                    ),
                  ),
                ],
              ),

              // Kontrol Putar / Ulangi Loop / Auto-Koreksi Trap Jump
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: audioService.isPlaying
                        ? 'Hentikan Audio Murattal'
                        : 'Putar Murattal Ayat Aktif',
                    icon: Icon(
                      audioService.isPlaying
                          ? Icons.stop_circle_rounded
                          : Icons.play_circle_fill_rounded,
                      color: const Color(0xFF2DD4BF),
                      size: 28,
                    ),
                    onPressed: () {
                      if (audioService.isPlaying) {
                        audioService.stop();
                      } else if (activeVerse != null) {
                        audioService.playVerse(
                          surahId: activeVerse!.surahId,
                          verseNumber: activeVerse!.verseNumber,
                          surahName: activeVerse!.surahNameLatin,
                        );
                      }
                    },
                  ),
                  ChoiceChip(
                    label: Text('Loop ${audioService.repeatTargetCount}x'),
                    selected: audioService.repeatTargetCount > 1,
                    onSelected: (_) {
                      final next = audioService.repeatTargetCount == 1
                          ? 3
                          : (audioService.repeatTargetCount == 3 ? 5 : 1);
                      audioService.setRepeatTargetCount(next);
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Auto-Koreksi Audio saat Trap Jump'),
                    selected: audioService.autoPlayOnTrapJump,
                    onSelected: audioService.setAutoPlayOnTrapJump,
                  ),
                ],
              ),

              if (audioService.statusCaption != null)
                Text(
                  audioService.statusCaption!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFFBBF24),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
