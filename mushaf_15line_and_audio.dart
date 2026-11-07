// mushaf_15line_and_audio.dart
// =============================================================================
// [OPSI 3] Modul Tampilan Mushaf Standar Madinah (15 Baris Proporsional Selembar
// Penuh + Zoom In/Out via Ctrl+Scroll Mouse di Desktop & Cubit 2 Jari / Pinch
// di Android Tanpa Mengganggu Scroll Halaman) serta Pemutar Audio Murattal Native
// Lintas Platform (Android MediaPlayer, Windows winmm.dll MCI, macOS afplay).
// =============================================================================

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:ui';
import 'package:ffi/ffi.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'quran_hifz_repository.dart';

// =============================================================================
// 0. WINDOWS NATIVE AUDIO BINDING (winmm.dll mciSendStringW)
// =============================================================================

typedef _MciSendStringWNative = ffi.Uint32 Function(
  ffi.Pointer<Utf16> lpszCommand,
  ffi.Pointer<Utf16> lpszReturnString,
  ffi.Uint32 cchReturn,
  ffi.IntPtr hwndCallback,
);
typedef _MciSendStringWDart = int Function(
  ffi.Pointer<Utf16> lpszCommand,
  ffi.Pointer<Utf16> lpszReturnString,
  int cchReturn,
  int hwndCallback,
);

class _WindowsMciAudioPlayer {
  static _MciSendStringWDart? _mciSendStringW;

  static _MciSendStringWDart? _getFn() {
    if (!Platform.isWindows) return null;
    if (_mciSendStringW != null) return _mciSendStringW;
    try {
      final winmm = ffi.DynamicLibrary.open('winmm.dll');
      _mciSendStringW = winmm.lookupFunction<_MciSendStringWNative, _MciSendStringWDart>('mciSendStringW');
      return _mciSendStringW;
    } catch (_) {
      return null;
    }
  }

  static int sendCommand(String cmd) {
    final fn = _getFn();
    if (fn == null) return -1;
    final cmdPtr = cmd.toNativeUtf16();
    try {
      return fn(cmdPtr, ffi.nullptr, 0, 0);
    } finally {
      calloc.free(cmdPtr);
    }
  }

  static String queryStatus(String cmd) {
    final fn = _getFn();
    if (fn == null) return '';
    final cmdPtr = cmd.toNativeUtf16();
    final bufPtr = calloc<ffi.Uint16>(256).cast<Utf16>();
    try {
      final err = fn(cmdPtr, bufPtr, 255, 0);
      if (err != 0) return '';
      return bufPtr.toDartString().trim();
    } finally {
      calloc.free(cmdPtr);
      calloc.free(bufPtr);
    }
  }

  static void playFile(String filePath) {
    sendCommand('close quran_murattal');
    sendCommand('open "$filePath" type mpegvideo alias quran_murattal');
    sendCommand('play quran_murattal from 0');
  }

  static void stop() {
    sendCommand('stop quran_murattal');
    sendCommand('close quran_murattal');
  }

  static bool isPlaying() {
    final mode = queryStatus('status quran_murattal mode').toLowerCase();
    return mode.contains('playing');
  }
}

// =============================================================================
// 0B. WIDGET PEMBUNGKUS GESTUR ZOOM MUSHAF LINTAS PLATFORM
//     - Desktop (Windows/macOS/Linux): Ctrl + Scroll Mouse (atau mode Scroll=Zoom)
//       & Trackpad Pinch tanpa mematikan scroll vertikal halaman normal.
//     - Android/Mobile: Cubit 2 Jari (Pinch-In / Pinch-Out) tanpa menghalangi
//       scroll halaman 1 jari.
// =============================================================================

class MushafZoomGestureWrapper extends StatefulWidget {
  final double zoomScale;
  final bool scrollWheelZoomWithoutCtrl;
  final ValueChanged<double> onZoomChanged;
  final Widget child;

  const MushafZoomGestureWrapper({
    super.key,
    required this.zoomScale,
    this.scrollWheelZoomWithoutCtrl = false,
    required this.onZoomChanged,
    required this.child,
  });

  @override
  State<MushafZoomGestureWrapper> createState() => _MushafZoomGestureWrapperState();
}

class _MushafZoomGestureWrapperState extends State<MushafZoomGestureWrapper> {
  final Map<int, Offset> _activePointers = <int, Offset>{};
  double? _initialPinchDistance;
  double _baseZoomOnPinchStart = 1.0;

  double _computeTwoFingerDistance() {
    if (_activePointers.length < 2) return 0.0;
    final values = _activePointers.values.toList();
    return (values[0] - values[1]).distance;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.position;
    if (_activePointers.length == 2) {
      final dist = _computeTwoFingerDistance();
      if (dist > 12.0) {
        _initialPinchDistance = dist;
        _baseZoomOnPinchStart = widget.zoomScale;
      }
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_activePointers.containsKey(event.pointer)) return;
    _activePointers[event.pointer] = event.position;

    if (_activePointers.length >= 2 && _initialPinchDistance != null && _initialPinchDistance! > 12.0) {
      final currentDist = _computeTwoFingerDistance();
      final ratio = currentDist / _initialPinchDistance!;
      final nextZoom = (_baseZoomOnPinchStart * ratio).clamp(0.60, 2.50);
      if ((nextZoom - widget.zoomScale).abs() > 0.01) {
        widget.onZoomChanged(nextZoom);
      }
    }
  }

  void _handlePointerUpOrCancel(PointerEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.length < 2) {
      _initialPinchDistance = null;
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScaleEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (PointerSignalEvent e) {
        final scaleEvt = e as PointerScaleEvent;
        final nextZoom = (widget.zoomScale * scaleEvt.scale).clamp(0.60, 2.50);
        widget.onZoomChanged(nextZoom);
      });
      return;
    }

    if (event is PointerScrollEvent) {
      final isCtrlOrCmdPressed = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;

      if (isCtrlOrCmdPressed || widget.scrollWheelZoomWithoutCtrl) {
        // Intercept event scroll agar halaman tidak ikut bergulir saat pengguna sedang melakukan Zoom
        GestureBinding.instance.pointerSignalResolver.register(event, (PointerSignalEvent e) {
          final scrollEvt = e as PointerScrollEvent;
          if (scrollEvt.scrollDelta.dy == 0) return;
          final delta = scrollEvt.scrollDelta.dy < 0 ? 0.10 : -0.10;
          final nextZoom = (widget.zoomScale + delta).clamp(0.60, 2.50);
          widget.onZoomChanged(nextZoom);
        });
      }
      // Jika Ctrl tidak ditekan dan mode Scroll=Zoom tidak aktif, biarkan event mengalir
      // ke SingleChildScrollView agar halaman bergulir naik/turun secara normal!
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUpOrCancel,
      onPointerCancel: _handlePointerUpOrCancel,
      onPointerSignal: _handlePointerSignal,
      child: widget.child,
    );
  }
}

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
// 2. SERVICE PEMUTAR AUDIO MURATTAL NATIVE & KOREKSI OTOMATIS TRAP JUMP
// =============================================================================

class QuranMurattalAudioService extends ChangeNotifier {
  static const MethodChannel _nativeChannel = MethodChannel('com.qurantarteelhifz/installer');

  QariReciter _selectedReciter = QariCatalog.supportedReciters.first;
  bool _isPlaying = false;
  bool _autoPlayOnTrapJump = true;
  int _repeatTargetCount = 1;
  int _currentRepeatIteration = 0;

  int? _playingSurahId;
  int? _playingVerseNumber;
  String? _playingSurahName;
  String? _currentAudioUrl;
  String? _cachedLocalFilePath;
  String? _statusCaption;
  Timer? _playbackPollTimer;
  Process? _macosAudioProcess;

  /// Callback opsional untuk pengujian unit test atau pemutar eksternal.
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

  /// Mengunduh (atau mengambil dari cache lokal) file MP3 murattal ayat.
  Future<String?> _downloadOrGetCachedMp3(String url, int surahId, int verseNumber) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory(p.join(tempDir.path, 'murattal_cache'));
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      final s = surahId.toString().padLeft(3, '0');
      final v = verseNumber.toString().padLeft(3, '0');
      final fileName = '${_selectedReciter.id}_$s$v.mp3';
      final file = File(p.join(cacheDir.path, fileName));

      if (await file.exists() && await file.length() > 1024) {
        return file.path;
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'QuranTarteelHifz-App'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes, flush: true);
        return file.path;
      }
    } catch (e) {
      debugPrint('[QuranMurattalAudioService] Gagal mengunduh MP3 murattal: $e');
    }
    return null;
  }

  /// Memutar audio murattal untuk ayat tertentu (dengan dukungan pengulangan / loop hafalan).
  Future<void> playVerse({
    required int surahId,
    required int verseNumber,
    String? surahName,
    String? customCaption,
  }) async {
    _stopNativePlaybackOnly();
    final url = _selectedReciter.getVerseAudioUrl(surahId, verseNumber);

    _isPlaying = true;
    _playingSurahId = surahId;
    _playingVerseNumber = verseNumber;
    _playingSurahName = surahName;
    _currentAudioUrl = url;
    _currentRepeatIteration = 1;
    _statusCaption = customCaption ??
        'Memuat audio QS. ${surahName ?? surahId}: $verseNumber • ${_selectedReciter.name}...';
    notifyListeners();

    if (externalAudioUrlPlayer != null) {
      await externalAudioUrlPlayer!(url);
      _scheduleFallbackLoopTimer(surahId: surahId, verseNumber: verseNumber, surahName: surahName);
      return;
    }

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _statusCaption = customCaption ??
          'Memutar QS. ${surahName ?? surahId}: $verseNumber • ${_selectedReciter.name} '
              '(${_repeatTargetCount > 1 ? "Ulang $_currentRepeatIteration/$_repeatTargetCount" : "1x"})';
      notifyListeners();
      _scheduleFallbackLoopTimer(surahId: surahId, verseNumber: verseNumber, surahName: surahName);
      return;
    }

    final localPath = await _downloadOrGetCachedMp3(url, surahId, verseNumber);
    if (!_isPlaying) return;

    if (localPath == null) {
      _isPlaying = false;
      _statusCaption = 'Gagal memuat audio murattal (periksa koneksi internet Anda).';
      notifyListeners();
      return;
    }

    _cachedLocalFilePath = localPath;
    _statusCaption = customCaption ??
        'Memutar QS. ${surahName ?? surahId}: $verseNumber • ${_selectedReciter.name} '
            '(${_repeatTargetCount > 1 ? "Ulang $_currentRepeatIteration/$_repeatTargetCount" : "1x"})';
    notifyListeners();

    await _playLocalFileOnPlatform(localPath);
  }

  Future<void> _playLocalFileOnPlatform(String filePath) async {
    try {
      if (Platform.isAndroid) {
        await _nativeChannel.invokeMethod('playAudio', {'filePath': filePath});
        _startCompletionPolling();
      } else if (Platform.isWindows) {
        _WindowsMciAudioPlayer.playFile(filePath);
        _startCompletionPolling();
      } else if (Platform.isMacOS) {
        _macosAudioProcess?.kill();
        _macosAudioProcess = await Process.start('afplay', [filePath]);
        _macosAudioProcess!.exitCode.then((_) {
          if (_isPlaying) {
            _onSingleIterationFinished();
          }
        });
      } else if (Platform.isLinux) {
        _macosAudioProcess?.kill();
        _macosAudioProcess = await Process.start('aplay', [filePath]);
        _macosAudioProcess!.exitCode.then((_) {
          if (_isPlaying) {
            _onSingleIterationFinished();
          }
        });
      }
    } catch (e) {
      debugPrint('[QuranMurattalAudioService] Gagal memutar file audio native: $e');
      _scheduleFallbackLoopTimer(
        surahId: _playingSurahId ?? 1,
        verseNumber: _playingVerseNumber ?? 1,
        surahName: _playingSurahName,
      );
    }
  }

  void _startCompletionPolling() {
    _playbackPollTimer?.cancel();
    _playbackPollTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }
      bool stillPlaying = false;
      try {
        if (Platform.isAndroid) {
          stillPlaying = await _nativeChannel.invokeMethod<bool>('isAudioPlaying') ?? false;
        } else if (Platform.isWindows) {
          stillPlaying = _WindowsMciAudioPlayer.isPlaying();
        }
      } catch (_) {
        stillPlaying = false;
      }

      if (!stillPlaying) {
        timer.cancel();
        await _onSingleIterationFinished();
      }
    });
  }

  Future<void> _onSingleIterationFinished() async {
    if (!_isPlaying) return;
    if (_currentRepeatIteration < _repeatTargetCount && _cachedLocalFilePath != null) {
      _currentRepeatIteration++;
      _statusCaption =
          'Memutar QS. ${_playingSurahName ?? _playingSurahId}: $_playingVerseNumber • ${_selectedReciter.name} '
          '(Ulang $_currentRepeatIteration/$_repeatTargetCount)';
      notifyListeners();
      await _playLocalFileOnPlatform(_cachedLocalFilePath!);
    } else {
      _isPlaying = false;
      _statusCaption =
          'Selesai memutar QS. ${_playingSurahName ?? _playingSurahId}: $_playingVerseNumber.';
      notifyListeners();
    }
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

  void _scheduleFallbackLoopTimer({
    required int surahId,
    required int verseNumber,
    String? surahName,
  }) {
    _playbackPollTimer?.cancel();
    _playbackPollTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
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

  void _stopNativePlaybackOnly() {
    _playbackPollTimer?.cancel();
    _macosAudioProcess?.kill();
    _macosAudioProcess = null;
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        if (Platform.isAndroid) {
          _nativeChannel.invokeMethod('stopAudio');
        } else if (Platform.isWindows) {
          _WindowsMciAudioPlayer.stop();
        }
      } catch (_) {}
    }
  }

  void stop() {
    _stopNativePlaybackOnly();
    _isPlaying = false;
    _statusCaption = 'Pemutaran murattal dihentikan.';
    notifyListeners();
  }

  @override
  void dispose() {
    _stopNativePlaybackOnly();
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
      if (verse.verseNumber == 1 && verse.surahId != lastSurahId) {
        lastSurahId = verse.surahId;
        rawSegments.add(
          MushafLineModel(
            lineNumber: 0,
            headerSurahId: verse.surahId,
            headerSurahName: verse.surahNameLatin ?? 'Surah ${verse.surahId}',
          ),
        );
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

    final wordsPerLine = (tokenPool.length / remainingTextLines).ceil() < 5
        ? 5
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
//    (ZOOM CTRL+SCROLL MOUSE DI DESKTOP & PINCH 2 JARI DI ANDROID TANPA BLOKIR SCROLL)
// =============================================================================

class Mushaf15LinePageWidget extends StatefulWidget {
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
  State<Mushaf15LinePageWidget> createState() => _Mushaf15LinePageWidgetState();
}

class _Mushaf15LinePageWidgetState extends State<Mushaf15LinePageWidget> {
  double _zoomScale = 1.0;
  bool _singleSheetFitMode = true;
  bool _scrollWheelZoomsDirectly = false;

  void _updateZoom(double newScale) {
    setState(() {
      _zoomScale = newScale.clamp(0.60, 2.50);
    });
  }

  void _resetZoom() {
    setState(() {
      _zoomScale = 1.0;
    });
  }

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
    final mutedColor = isDark ? const Color(0xFFA7B0AC) : const Color(0xFF525E58);

    final pageNumber = widget.verses.isNotEmpty ? widget.verses.first.pageNumber : 582;
    final juzNumber = widget.verses.isNotEmpty ? widget.verses.first.juzNumber : 30;
    final surahTitle = widget.surahArabicName != null && widget.surahArabicName!.isNotEmpty
        ? 'سُورَةُ ${widget.surahArabicName}'
        : (widget.verses.isNotEmpty ? 'سُورَةُ ${widget.verses.first.surahNameLatin ?? ''}' : '');
    final lines = Mushaf15LineLayoutEngine.build15LinesForPage(widget.verses);
    final visibleLines = lines.where((l) => l.isSurahHeader || l.isBismillahLine || l.tokens.isNotEmpty).toList();

    final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Toolbar Zoom In / Zoom Out & Petunjuk Gestur (Ctrl+Scroll / Pinch 2 Jari)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: pageBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isDark ? const Color(0xFF28302D) : const Color(0xFFE6DFD3)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.menu_book_rounded, size: 16, color: primaryColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      isDesktop
                          ? 'Lembar Mushaf Madinah • Ctrl + Scroll Mouse untuk Zoom (Scroll biasa untuk gulir halaman)'
                          : 'Lembar Mushaf Madinah • Cubit 2 Jari (Pinch) untuk Zoom In/Out',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: mutedColor),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (isDesktop)
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setState(() => _scrollWheelZoomsDirectly = !_scrollWheelZoomsDirectly),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: _scrollWheelZoomsDirectly
                              ? goldText.withOpacity(0.16)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _scrollWheelZoomsDirectly ? goldText : borderGold.withOpacity(0.45),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.mouse_rounded,
                              size: 13,
                              color: _scrollWheelZoomsDirectly ? goldText : mutedColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _scrollWheelZoomsDirectly ? 'Scroll = Zoom (Aktif)' : 'Ctrl+Scroll = Zoom',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _scrollWheelZoomsDirectly ? goldText : mutedColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Toggle Selembar Penuh vs Teks Mengalir
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(() => _singleSheetFitMode = !_singleSheetFitMode),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _singleSheetFitMode
                            ? primaryColor.withOpacity(0.14)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _singleSheetFitMode ? primaryColor : borderGold.withOpacity(0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.aspect_ratio_rounded,
                            size: 14,
                            color: _singleSheetFitMode ? primaryColor : mutedColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Selembar Mushaf',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _singleSheetFitMode ? primaryColor : mutedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Tombol Zoom Out (-)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Perkecil Mushaf (Zoom Out)',
                    onPressed: () => _updateZoom(_zoomScale - 0.15),
                    icon: Icon(Icons.remove_circle_outline_rounded, size: 20, color: mutedColor),
                  ),
                  // Indikator Persentase Zoom (Klik untuk Reset 100%)
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _resetZoom,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF242B28) : const Color(0xFFF2ECE1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${(_zoomScale * 100).round()}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: primaryColor,
                        ),
                      ),
                    ),
                  ),
                  // Tombol Zoom In (+)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Perbesar Mushaf (Zoom In)',
                    onPressed: () => _updateZoom(_zoomScale + 0.15),
                    icon: Icon(Icons.add_circle_outline_rounded, size: 20, color: mutedColor),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Area Lembaran Mushaf Madinah (Mendukung Ctrl+Scroll di Desktop & Pinch 2 Jari di Android
        // tanpa menghalangi scroll vertikal halaman 1 jari / roda mouse normal)
        MushafZoomGestureWrapper(
          zoomScale: _zoomScale,
          scrollWheelZoomWithoutCtrl: _scrollWheelZoomsDirectly,
          onZoomChanged: _updateZoom,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 680.0;
              final baseSheetWidth = _singleSheetFitMode
                  ? (availWidth < 680.0 ? availWidth : 680.0)
                  : availWidth;
              final scaledSheetWidth = baseSheetWidth * _zoomScale;

              final mushafCard = Container(
                width: _singleSheetFitMode ? scaledSheetWidth : availWidth,
                padding: EdgeInsets.symmetric(
                  horizontal: (22 * _zoomScale).clamp(12.0, 44.0),
                  vertical: (18 * _zoomScale).clamp(10.0, 36.0),
                ),
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
                    // Header Halaman Mushaf
                    Container(
                      padding: const EdgeInsets.only(bottom: 10),
                      margin: const EdgeInsets.only(bottom: 10),
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
                              fontSize: 15 * _zoomScale,
                              fontWeight: FontWeight.w700,
                              color: goldText,
                            ),
                          ),
                          Text(
                            surahTitle,
                            style: TextStyle(
                              fontSize: 17 * _zoomScale,
                              fontWeight: FontWeight.w700,
                              color: primaryColor,
                            ),
                          ),
                          Text(
                            Mushaf15LineLayoutEngine.toArabicDigits(pageNumber),
                            style: TextStyle(
                              fontSize: 15 * _zoomScale,
                              fontWeight: FontWeight.w700,
                              color: goldText,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 15 Baris Mushaf Madinah
                    ...visibleLines.map(
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

                    // Footer Navigasi Halaman Mushaf
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.only(top: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: borderGold, width: 1.0),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: widget.onPrevPage,
                            icon: const Icon(Icons.chevron_left_rounded, size: 18),
                            label: const Text('Sebelumnya'),
                            style: TextButton.styleFrom(foregroundColor: mutedColor),
                          ),
                          Text(
                            'Halaman $pageNumber',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: mutedColor,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: widget.onNextPage,
                            icon: const Text('Selanjutnya'),
                            label: const Icon(Icons.chevron_right_rounded, size: 18),
                            style: TextButton.styleFrom(foregroundColor: mutedColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );

              if (_singleSheetFitMode && scaledSheetWidth > availWidth) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: mushafCard,
                );
              }
              return Center(child: mushafCard);
            },
          ),
        ),
      ],
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
    final effectiveFontScale = _zoomScale;

    if (line.isSurahHeader) {
      final revArabic = (widget.revelationType?.toLowerCase() == 'madaniyah') ? 'مَدَنِيَّة' : 'مَكِّيَّة';
      final titleArabic = widget.surahArabicName != null && widget.surahArabicName!.isNotEmpty
          ? 'سُورَةُ ${widget.surahArabicName} • $revArabic'
          : 'سُورَةُ ${line.headerSurahName} • $revArabic';
      return Container(
        width: double.infinity,
        margin: EdgeInsets.symmetric(vertical: 4 * effectiveFontScale),
        padding: EdgeInsets.symmetric(vertical: 6 * effectiveFontScale, horizontal: 14),
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
              fontSize: 19 * effectiveFontScale,
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
        padding: EdgeInsets.symmetric(vertical: 5 * effectiveFontScale),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: lineRule, width: 1.0)),
        ),
        child: Center(
          child: Text(
            'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: 21 * effectiveFontScale,
              fontWeight: FontWeight.w600,
              color: arabicColor,
            ),
          ),
        ),
      );
    }

    final tokenWidgets = line.tokens.map((token) {
      final isVerseActive = token.verse.id == widget.activeVerseId;

      if (token.isVerseEndMarker) {
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            widget.onSelectVerse(token.verse);
            widget.onPlayVerseAudio(token.verse);
          },
          onLongPress: () => widget.onShowTafsir(token.verse),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              '۝${Mushaf15LineLayoutEngine.toArabicDigits(token.verse.verseNumber)}',
              style: TextStyle(
                fontSize: 21 * effectiveFontScale,
                fontWeight: FontWeight.w700,
                color: isVerseActive ? primaryColor : goldText,
              ),
            ),
          ),
        );
      }

      final word = token.word!;
      final isRevealed = !widget.hideVerseMode ||
          (isVerseActive && word.wordPosition <= widget.revealedWordPosition);

      return InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => widget.onSelectVerse(token.verse),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: (isVerseActive && isRevealed && widget.hideVerseMode)
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
                fontSize: 24 * effectiveFontScale,
                height: 1.75,
                fontWeight: isVerseActive ? FontWeight.w600 : FontWeight.w500,
                color: isVerseActive && isRevealed ? primaryColor : arabicColor,
              ),
            ),
          ),
        ),
      );
    }).toList();

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: 42 * effectiveFontScale),
      padding: EdgeInsets.symmetric(vertical: 3 * effectiveFontScale, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: lineRule, width: 1.0)),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: _singleSheetFitMode
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: 560 * effectiveFontScale),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: tokenWidgets,
                  ),
                ),
              )
            : Wrap(
                alignment: WrapAlignment.spaceEvenly,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: tokenWidgets,
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
                    color: Color(0xFF94A3B8),
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
