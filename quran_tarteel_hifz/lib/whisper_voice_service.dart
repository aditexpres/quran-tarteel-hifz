// whisper_voice_service.dart
// =============================================================================
// [OPSI 2 + FFI NATIVE BINDINGS] Modul Perekam Mikrofon Real-Time (PCM 16kHz + VAD),
// Pengunduh Otomatis Model AI Whisper Al-Qur'an, dan Binding Dart FFI Penuh ke
// `whisper_flutter_bridge.cpp` (`libwhisper.so`, `whisper.dll`, `libwhisper.dylib`).
//
// Dependensi pubspec.yaml:
//   ffi: ^2.1.3
//   record: ^5.1.2
//   path: ^1.9.0
//   path_provider: ^2.1.4
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'mushaf_15line_and_audio.dart';
import 'quran_hifz_repository.dart';

// =============================================================================
// 1. DEFINISI TYPEDEF C-ABI UNTUK `whisper_flutter_bridge.cpp`
// =============================================================================

// int64_t whisper_bridge_init(const char* model_path)
typedef _WhisperBridgeInitNative = ffi.Int64 Function(
  ffi.Pointer<Utf8> modelPath,
);
typedef _WhisperBridgeInitDart = int Function(
  ffi.Pointer<Utf8> modelPath,
);

// const char* whisper_bridge_transcribe_arabic(int64_t ctx, const float* pcm, int32_t n_samples, int32_t n_threads)
typedef _WhisperBridgeTranscribeNative = ffi.Pointer<Utf8> Function(
  ffi.Int64 ctxHandle,
  ffi.Pointer<ffi.Float> pcmF32,
  ffi.Int32 nSamples,
  ffi.Int32 nThreads,
);
typedef _WhisperBridgeTranscribeDart = ffi.Pointer<Utf8> Function(
  int ctxHandle,
  ffi.Pointer<ffi.Float> pcmF32,
  int nSamples,
  int nThreads,
);

// void whisper_bridge_free_string(const char* str_ptr)
typedef _WhisperBridgeFreeStringNative = ffi.Void Function(
  ffi.Pointer<Utf8> strPtr,
);
typedef _WhisperBridgeFreeStringDart = void Function(
  ffi.Pointer<Utf8> strPtr,
);

// void whisper_bridge_free(int64_t ctx_handle)
typedef _WhisperBridgeFreeNative = ffi.Void Function(
  ffi.Int64 ctxHandle,
);
typedef _WhisperBridgeFreeDart = void Function(
  int ctxHandle,
);

// =============================================================================
// 2. PENGUNDUH OTOMATIS MODEL AI WHISPER AL-QUR'AN (HUGGING FACE)
// =============================================================================

class WhisperQuranModelPreset {
  final String id;
  final String title;
  final String fileName;
  final String downloadUrl;
  final int approxSizeMB;

  const WhisperQuranModelPreset({
    required this.id,
    required this.title,
    required this.fileName,
    required this.downloadUrl,
    required this.approxSizeMB,
  });
}

class WhisperModelDownloadManager extends ChangeNotifier {
  static const List<WhisperQuranModelPreset> presets = [
    WhisperQuranModelPreset(
      id: 'tiny_ar_quran',
      title: 'Tarteel Whisper Tiny Arabic Qur\'an (Cepat & Ringan)',
      fileName: 'ggml-tarteel-whisper-tiny-ar-quran.bin',
      downloadUrl:
          'https://huggingface.co/tarteel-ai/whisper-tiny-ar-quran/resolve/main/pytorch_model.bin',
      approxSizeMB: 145,
    ),
    WhisperQuranModelPreset(
      id: 'base_ar_quran',
      title: 'Tarteel Whisper Base Arabic Qur\'an (Akurasi Tinggi)',
      fileName: 'ggml-tarteel-whisper-base-ar-quran.bin',
      downloadUrl:
          'https://huggingface.co/tarteel-ai/whisper-base-ar-quran/resolve/main/pytorch_model.bin',
      approxSizeMB: 278,
    ),
  ];

  WhisperQuranModelPreset _selectedPreset = presets.first;
  bool _isDownloading = false;
  bool _isModelReady = false;
  double _downloadProgress = 0.0;
  String? _localModelPath;
  String? _statusText;

  WhisperQuranModelPreset get selectedPreset => _selectedPreset;
  bool get isDownloading => _isDownloading;
  bool get isModelReady => _isModelReady;
  double get downloadProgress => _downloadProgress;
  String? get localModelPath => _localModelPath;
  String? get statusText => _statusText;

  Future<void> checkExistingModel([WhisperQuranModelPreset? preset]) async {
    if (preset != null) _selectedPreset = preset;
    final supportDir = await getApplicationSupportDirectory();
    final modelDir = Directory(p.join(supportDir.path, 'models'));
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    final filePath = p.join(modelDir.path, _selectedPreset.fileName);
    final file = File(filePath);
    final exists = await file.exists() && (await file.length()) > 1024 * 100;

    _localModelPath = filePath;
    _isModelReady = exists;
    _downloadProgress = exists ? 1.0 : 0.0;
    _statusText = exists
        ? 'Model offline siap digunakan (${_selectedPreset.title}).'
        : 'Model belum diunduh (~${_selectedPreset.approxSizeMB} MB).';
    notifyListeners();
  }

  Future<void> downloadSelectedModel() async {
    if (_isDownloading) return;
    await checkExistingModel();
    if (_localModelPath == null) return;

    _isDownloading = true;
    _downloadProgress = 0.0;
    _statusText = 'Menghubungkan ke Hugging Face (${_selectedPreset.title})...';
    notifyListeners();

    final client = HttpClient();
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(_selectedPreset.downloadUrl));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw HttpException(
          'Gagal mengunduh model (HTTP ${response.statusCode}).',
        );
      }

      final totalBytes = response.contentLength;
      var receivedBytes = 0;
      final outFile = File(_localModelPath!);
      sink = outFile.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          _downloadProgress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
          final pct = (_downloadProgress * 100).toStringAsFixed(1);
          _statusText = 'Mengunduh model AI Al-Qur\'an: $pct%';
          notifyListeners();
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      _isDownloading = false;
      _isModelReady = true;
      _downloadProgress = 1.0;
      _statusText = 'Model ${_selectedPreset.title} berhasil diunduh & siap!';
      notifyListeners();
    } catch (e) {
      await sink?.close();
      _isDownloading = false;
      _statusText = 'Unduhan terhenti: $e';
      notifyListeners();
    } finally {
      client.close();
    }
  }
}

// =============================================================================
// 3. SERVICE STREAMING MIKROFON LINTAS PLATFORM (PCM 16kHz + VAD + SLIDING WINDOW)
// =============================================================================

class CrossPlatformMicStreamService {
  static const int sampleRate = 16000;
  static const int bytesPerSample = 2;
  static const int windowDurationMs = 2000;
  static const int overlapDurationMs = 400;

  static const int _windowSizeBytes =
      (sampleRate * bytesPerSample * windowDurationMs) ~/ 1000;
  static const int _overlapSizeBytes =
      (sampleRate * bytesPerSample * overlapDurationMs) ~/ 1000;

  final List<int> _rollingBuffer = <int>[];
  StreamSubscription<Uint8List>? _micStreamSubscription;
  double _currentRmsLevel = 0.0;
  final double vadRmsThreshold;

  CrossPlatformMicStreamService({this.vadRmsThreshold = 0.018});

  double get currentRmsLevel => _currentRmsLevel;

  void attachPcm16Stream({
    required Stream<Uint8List> pcmStream,
    required void Function(Uint8List speechWindowPcm, double rmsLevel) onSpeechWindowReady,
    void Function(double rmsLevel)? onAmplitudeChanged,
  }) {
    _rollingBuffer.clear();
    _micStreamSubscription?.cancel();

    _micStreamSubscription = pcmStream.listen((chunk) {
      if (chunk.isEmpty) return;

      final rms = calculateNormalizedRms(chunk);
      _currentRmsLevel = rms;
      if (onAmplitudeChanged != null) {
        onAmplitudeChanged(rms);
      }

      _rollingBuffer.addAll(chunk);

      if (_rollingBuffer.length >= _windowSizeBytes) {
        final windowBytes = Uint8List.fromList(
          _rollingBuffer.sublist(0, _windowSizeBytes),
        );

        final retainStart = _windowSizeBytes - _overlapSizeBytes;
        final tail = _rollingBuffer.sublist(retainStart);
        _rollingBuffer
          ..clear()
          ..addAll(tail);

        final windowRms = calculateNormalizedRms(windowBytes);
        if (windowRms >= vadRmsThreshold) {
          onSpeechWindowReady(windowBytes, windowRms);
        }
      }
    });
  }

  static double calculateNormalizedRms(Uint8List pcm16Bytes) {
    final sampleCount = pcm16Bytes.length ~/ 2;
    if (sampleCount == 0) return 0.0;

    final byteData = ByteData.sublistView(pcm16Bytes);
    var sumSquares = 0.0;

    for (var i = 0; i < sampleCount; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little) / 32768.0;
      sumSquares += sample * sample;
    }
    return math.sqrt(sumSquares / sampleCount).clamp(0.0, 1.0);
  }

  Future<void> stop() async {
    await _micStreamSubscription?.cancel();
    _micStreamSubscription = null;
    _rollingBuffer.clear();
    _currentRmsLevel = 0.0;
  }
}

// =============================================================================
// 4. STATE & KONFIGURASI VOICE HIFZ
// =============================================================================

enum WhisperBackendMode {
  onDeviceWhisperCpp,
  cloudEndpoint,
  interactiveSimulator,
}

class VoiceHifzSessionState {
  final bool isListening;
  final int activeVerseId;
  final int activeSurahId;
  final int activeVerseNumber;
  final int revealedWordPosition;
  final int totalWordsInVerse;
  final double micRmsLevel;
  final String lastTranscript;
  final VoiceEvaluationResult? evaluationResult;
  final String? statusMessage;

  const VoiceHifzSessionState({
    required this.isListening,
    required this.activeVerseId,
    required this.activeSurahId,
    required this.activeVerseNumber,
    required this.revealedWordPosition,
    required this.totalWordsInVerse,
    this.micRmsLevel = 0.0,
    this.lastTranscript = '',
    this.evaluationResult,
    this.statusMessage,
  });

  bool get isVerseCompleted =>
      totalWordsInVerse > 0 && revealedWordPosition >= totalWordsInVerse;

  bool get hasTrapJumpAlert =>
      evaluationResult != null && evaluationResult!.isTrapJump;

  VoiceHifzSessionState copyWith({
    bool? isListening,
    int? activeVerseId,
    int? activeSurahId,
    int? activeVerseNumber,
    int? revealedWordPosition,
    int? totalWordsInVerse,
    double? micRmsLevel,
    String? lastTranscript,
    VoiceEvaluationResult? evaluationResult,
    bool clearEvaluation = false,
    String? statusMessage,
  }) {
    return VoiceHifzSessionState(
      isListening: isListening ?? this.isListening,
      activeVerseId: activeVerseId ?? this.activeVerseId,
      activeSurahId: activeSurahId ?? this.activeSurahId,
      activeVerseNumber: activeVerseNumber ?? this.activeVerseNumber,
      revealedWordPosition: revealedWordPosition ?? this.revealedWordPosition,
      totalWordsInVerse: totalWordsInVerse ?? this.totalWordsInVerse,
      micRmsLevel: micRmsLevel ?? this.micRmsLevel,
      lastTranscript: lastTranscript ?? this.lastTranscript,
      evaluationResult:
          clearEvaluation ? null : (evaluationResult ?? this.evaluationResult),
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

// =============================================================================
// 5. IMPLEMENTASI ENGINE TRANSKRIPSI WHISPER (FFI C++ BRIDGE & CLOUD)
// =============================================================================

abstract class WhisperTranscriberEngine {
  Future<void> initialize();
  Future<String> transcribePcm16kHz(Uint8List pcm16BitMonoBytes);
  Future<void> dispose();
}

/// Implementasi Penuh Dart FFI yang memanggil simbol C di `whisper_flutter_bridge.cpp`:
/// - `whisper_bridge_init`
/// - `whisper_bridge_transcribe_arabic` (dijalankan di background Isolate agar UI 60fps tetap mulus)
/// - `whisper_bridge_free_string`
/// - `whisper_bridge_free`
class WhisperCppFfiEngine implements WhisperTranscriberEngine {
  final String modelFilePath;
  final int threads;

  int _ctxHandle = 0;
  bool _isInitialized = false;

  WhisperCppFfiEngine({
    required this.modelFilePath,
    this.threads = 4,
  });

  static String _resolveDynamicLibraryName() {
    if (Platform.isAndroid || Platform.isLinux) {
      return 'libwhisper.so';
    } else if (Platform.isWindows) {
      return 'whisper.dll';
    } else if (Platform.isMacOS) {
      return 'libwhisper.dylib';
    }
    throw UnsupportedError('Platform tidak didukung untuk Whisper FFI.');
  }

  @override
  Future<void> initialize() async {
    if (_isInitialized && _ctxHandle != 0) return;

    final modelFile = File(modelFilePath);
    if (!await modelFile.exists()) {
      throw StateError(
        'File model GGML Al-Qur\'an belum ditemukan di: $modelFilePath. '
        'Jalankan `bash build_whisper_native.sh convert` atau gunakan pengunduh model di aplikasi.',
      );
    }

    final libName = _resolveDynamicLibraryName();
    final pathToLoad = modelFilePath;

    // Inisialisasi model di background Isolate agar UI tidak membeku saat memuat file ~145MB
    _ctxHandle = await Isolate.run<int>(() {
      final dylib = ffi.DynamicLibrary.open(libName);
      final initFn = dylib.lookupFunction<_WhisperBridgeInitNative,
          _WhisperBridgeInitDart>('whisper_bridge_init');

      final pathPtr = pathToLoad.toNativeUtf8();
      try {
        return initFn(pathPtr);
      } finally {
        calloc.free(pathPtr);
      }
    });

    if (_ctxHandle == 0) {
      throw StateError('Gagal menginisialisasi whisper_context dari $modelFilePath.');
    }
    _isInitialized = true;
  }

  @override
  Future<String> transcribePcm16kHz(Uint8List pcm16BitMonoBytes) async {
    if (!_isInitialized || _ctxHandle == 0) {
      throw StateError('WhisperCppFfiEngine belum diinisialisasi.');
    }
    final floatSamples = pcm16ToFloat32(pcm16BitMonoBytes);
    if (floatSamples.isEmpty) return '';

    final libName = _resolveDynamicLibraryName();
    final handle = _ctxHandle;
    final threadCount = threads;

    // Jalankan inferensi C++ `whisper_bridge_transcribe_arabic` di background Isolate
    return Isolate.run<String>(() {
      final dylib = ffi.DynamicLibrary.open(libName);
      final transcribeFn = dylib.lookupFunction<_WhisperBridgeTranscribeNative,
          _WhisperBridgeTranscribeDart>('whisper_bridge_transcribe_arabic');
      final freeStringFn = dylib.lookupFunction<_WhisperBridgeFreeStringNative,
          _WhisperBridgeFreeStringDart>('whisper_bridge_free_string');

      final sampleCount = floatSamples.length;
      final pcmPtr = calloc<ffi.Float>(sampleCount);
      try {
        final nativeFloatList = pcmPtr.asTypedList(sampleCount);
        nativeFloatList.setAll(0, floatSamples);

        final resPtr = transcribeFn(handle, pcmPtr, sampleCount, threadCount);
        if (resPtr == ffi.nullptr) {
          return '';
        }
        try {
          return resPtr.toDartString().trim();
        } finally {
          freeStringFn(resPtr);
        }
      } finally {
        calloc.free(pcmPtr);
      }
    });
  }

  static Float32List pcm16ToFloat32(Uint8List pcmBytes) {
    final sampleCount = pcmBytes.length ~/ 2;
    final floatSamples = Float32List(sampleCount);
    final byteData = ByteData.sublistView(pcmBytes);

    for (var i = 0; i < sampleCount; i++) {
      final int16Sample = byteData.getInt16(i * 2, Endian.little);
      floatSamples[i] = int16Sample / 32768.0;
    }
    return floatSamples;
  }

  @override
  Future<void> dispose() async {
    if (_ctxHandle != 0) {
      final libName = _resolveDynamicLibraryName();
      final handle = _ctxHandle;
      _ctxHandle = 0;
      _isInitialized = false;

      await Isolate.run<void>(() {
        final dylib = ffi.DynamicLibrary.open(libName);
        final freeCtxFn = dylib.lookupFunction<_WhisperBridgeFreeNative,
            _WhisperBridgeFreeDart>('whisper_bridge_free');
        freeCtxFn(handle);
      });
    }
  }
}

class CloudWhisperApiEngine implements WhisperTranscriberEngine {
  final Uri endpointUrl;
  final String apiKey;

  CloudWhisperApiEngine({
    required this.endpointUrl,
    required this.apiKey,
  });

  @override
  Future<void> initialize() async {}

  @override
  Future<String> transcribePcm16kHz(Uint8List pcm16BitMonoBytes) async {
    if (pcm16BitMonoBytes.isEmpty) return '';
    final wavBytes = buildWavHeader(pcm16BitMonoBytes, sampleRate: 16000);

    final client = HttpClient();
    try {
      final request = await client.postUrl(endpointUrl);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.set(HttpHeaders.contentTypeHeader, 'audio/wav');
      request.add(wavBytes);

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200) {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic> && decoded['text'] != null) {
          return decoded['text'].toString().trim();
        }
      }
      return '';
    } finally {
      client.close();
    }
  }

  static Uint8List buildWavHeader(
    Uint8List pcmBytes, {
    int sampleRate = 16000,
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final dataSize = pcmBytes.length;
    final totalFileSize = 36 + dataSize;

    final header = ByteData(44);
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    header.setUint32(4, totalFileSize, Endian.little);
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6D);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    header.setUint32(40, dataSize, Endian.little);

    final wavBuffer = BytesBuilder(copy: false);
    wavBuffer.add(header.buffer.asUint8List());
    wavBuffer.add(pcmBytes);
    return wavBuffer.toBytes();
  }

  @override
  Future<void> dispose() async {}
}

// =============================================================================
// 6. CONTROLLER UTAMA VOICE HIFZ (MIKROFON REAL-TIME + KOREKSI AUDIO MURATTAL)
// =============================================================================

class WhisperVoiceHifzController extends ChangeNotifier {
  final QuranHifzRepository repository;
  final QuranMurattalAudioService? murattalAudioService;
  final WhisperModelDownloadManager modelDownloadManager;
  final CrossPlatformMicStreamService micStreamService;

  WhisperBackendMode _backendMode;
  WhisperTranscriberEngine? transcriberEngine;

  Verse? _currentVerse;
  List<DualPathCandidate> _dualPathCandidates = const [];
  Timer? _simulationTimer;

  VoiceHifzSessionState _state = const VoiceHifzSessionState(
    isListening: false,
    activeVerseId: 0,
    activeSurahId: 0,
    activeVerseNumber: 0,
    revealedWordPosition: 0,
    totalWordsInVerse: 0,
  );

  VoiceHifzSessionState get state => _state;
  Verse? get currentVerse => _currentVerse;
  List<DualPathCandidate> get dualPathCandidates => _dualPathCandidates;
  WhisperBackendMode get backendMode => _backendMode;

  WhisperVoiceHifzController({
    required this.repository,
    this.murattalAudioService,
    WhisperModelDownloadManager? modelDownloadManager,
    CrossPlatformMicStreamService? micStreamService,
    WhisperBackendMode backendMode = WhisperBackendMode.interactiveSimulator,
    this.transcriberEngine,
  })  : _backendMode = backendMode,
        modelDownloadManager =
            modelDownloadManager ?? WhisperModelDownloadManager(),
        micStreamService = micStreamService ?? CrossPlatformMicStreamService();

  void setBackendMode(WhisperBackendMode mode) {
    _backendMode = mode;
    notifyListeners();
  }

  Future<void> setActiveVerse(Verse verse, {bool revealAllInitially = false}) async {
    _currentVerse = verse;
    final totalWords = _getEffectiveWordList(verse).length;

    _dualPathCandidates = await repository.getDualPathCandidates(verse.id);

    _state = VoiceHifzSessionState(
      isListening: _state.isListening,
      activeVerseId: verse.id,
      activeSurahId: verse.surahId,
      activeVerseNumber: verse.verseNumber,
      revealedWordPosition: revealAllInitially ? totalWords : 0,
      totalWordsInVerse: totalWords,
      lastTranscript: '',
      statusMessage: _dualPathCandidates.any((c) => c.isTrapJump)
          ? 'Radar Aktif: Ayat ini memiliki kembaran Mutasyabihat. Waspadai transisi ke ayat berikutnya!'
          : 'Siap menyimak bacaan QS. ${verse.surahNameLatin ?? verse.surahId}: ${verse.verseNumber}.',
    );
    notifyListeners();
  }

  void peekNextWord() {
    if (_currentVerse == null) return;
    if (_state.revealedWordPosition < _state.totalWordsInVerse) {
      HapticFeedback.selectionClick();
      _state = _state.copyWith(
        revealedWordPosition: _state.revealedWordPosition + 1,
        statusMessage:
            'Intip kata ke-${_state.revealedWordPosition + 1} dari ${_state.totalWordsInVerse}.',
      );
      notifyListeners();
    }
  }

  void hideAllWords() {
    if (_currentVerse == null) return;
    _state = _state.copyWith(
      revealedWordPosition: 0,
      lastTranscript: '',
      clearEvaluation: true,
      statusMessage: 'Seluruh kata disembunyikan. Silakan mulai membaca.',
    );
    notifyListeners();
  }

  void revealAllWords() {
    if (_currentVerse == null) return;
    _state = _state.copyWith(
      revealedWordPosition: _state.totalWordsInVerse,
      clearEvaluation: true,
    );
    notifyListeners();
  }

  Future<void> startListening({Stream<Uint8List>? liveMicPcmStream}) async {
    if (_currentVerse == null) return;
    if (transcriberEngine != null) {
      await transcriberEngine!.initialize();
    }

    if (liveMicPcmStream != null) {
      micStreamService.attachPcm16Stream(
        pcmStream: liveMicPcmStream,
        onAmplitudeChanged: (rms) {
          _state = _state.copyWith(micRmsLevel: rms);
          notifyListeners();
        },
        onSpeechWindowReady: (windowBytes, _) async {
          if (transcriberEngine != null) {
            final transcript =
                await transcriberEngine!.transcribePcm16kHz(windowBytes);
            if (transcript.isNotEmpty) {
              await processIncomingTranscript(transcript);
            }
          }
        },
      );
    }

    _state = _state.copyWith(
      isListening: true,
      clearEvaluation: true,
      statusMessage:
          'Mikrofon Aktif (16kHz Mono + VAD): Menyimak bacaan Anda secara real-time...',
    );
    notifyListeners();
  }

  Future<void> stopListening() async {
    _simulationTimer?.cancel();
    await micStreamService.stop();
    _state = _state.copyWith(
      isListening: false,
      micRmsLevel: 0.0,
      statusMessage: 'Sesi mikrofon dihentikan.',
    );
    notifyListeners();
  }

  Future<void> processIncomingTranscript(String transcript) async {
    final verse = _currentVerse;
    if (verse == null || transcript.trim().isEmpty) return;

    final cleanSpokenTokens = ArabicFuzzyMatcher.normalizeArabic(transcript)
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();

    final verseWords = _getEffectiveCleanWordList(verse);
    var matchedPos = _state.revealedWordPosition;

    for (final spokenWord in cleanSpokenTokens) {
      if (matchedPos >= verseWords.length) break;
      final targetWord = verseWords[matchedPos];
      final dist = ArabicFuzzyMatcher.levenshteinDistance(spokenWord, targetWord);
      final maxLen = targetWord.length > spokenWord.length
          ? targetWord.length
          : spokenWord.length;
      final similarity = maxLen == 0 ? 1.0 : 1.0 - (dist / maxLen);

      if (similarity >= 0.65) {
        matchedPos++;
      }
    }

    VoiceEvaluationResult? evalResult;
    if (_dualPathCandidates.isNotEmpty &&
        (matchedPos >= verseWords.length || cleanSpokenTokens.length >= 2)) {
      evalResult = ArabicFuzzyMatcher.evaluateNextVerseSpeech(
        spokenTranscript: transcript,
        candidates: _dualPathCandidates,
        threshold: 0.70,
      );

      if (evalResult != null && evalResult.isTrapJump) {
        await HapticFeedback.heavyImpact();
        final correctCandidate = _dualPathCandidates
            .where((c) => c.pathType == ListeningPathType.correctNext)
            .firstOrNull;
        if (correctCandidate != null) {
          await repository.logTrapJumpError(
            expectedVerseId: correctCandidate.verseId,
            jumpedToVerseId: evalResult.matchedCandidate.verseId,
          );
          await murattalAudioService?.playTrapJumpCorrection(correctCandidate);
        }
      }
    }

    _state = _state.copyWith(
      revealedWordPosition: matchedPos,
      lastTranscript: transcript,
      evaluationResult: evalResult,
      statusMessage: evalResult?.warningMessage,
    );
    notifyListeners();
  }

  Future<void> runInteractiveSimulation({required bool simulateTrapJump}) async {
    final verse = _currentVerse;
    if (verse == null) return;

    _simulationTimer?.cancel();
    hideAllWords();
    await startListening();

    final cleanWords = _getEffectiveCleanWordList(verse);
    var step = 0;

    _simulationTimer = Timer.periodic(const Duration(milliseconds: 550), (timer) async {
      if (step < cleanWords.length) {
        final partialTranscript = cleanWords.take(step + 1).join(' ');
        _state = _state.copyWith(micRmsLevel: 0.35 + (step % 3) * 0.15);
        await processIncomingTranscript(partialTranscript);
        step++;
      } else {
        timer.cancel();
        _state = _state.copyWith(micRmsLevel: 0.0);
        final targetType = simulateTrapJump
            ? ListeningPathType.trapJump
            : ListeningPathType.correctNext;
        final candidate = _dualPathCandidates
                .where((c) => c.pathType == targetType)
                .firstOrNull ??
            _dualPathCandidates.firstOrNull;

        if (candidate != null) {
          await processIncomingTranscript(candidate.expectedTextClean);
        }
      }
    });
  }

  List<String> _getEffectiveWordList(Verse verse) {
    if (verse.words.isNotEmpty) {
      return verse.words.map((w) => w.textUthmani).toList();
    }
    return verse.textUthmani.split(' ').where((w) => w.isNotEmpty).toList();
  }

  List<String> _getEffectiveCleanWordList(Verse verse) {
    if (verse.words.isNotEmpty) {
      return verse.words.map((w) => w.textClean).toList();
    }
    return verse.textClean.split(' ').where((w) => w.isNotEmpty).toList();
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    micStreamService.stop();
    transcriberEngine?.dispose();
    super.dispose();
  }
}
