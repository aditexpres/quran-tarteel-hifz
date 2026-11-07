// quran_hifz_app.dart
// =============================================================================
// UI/Widget Utama Aplikasi Qur'an Tarteel Hifz Lintas Platform
// (Android APK, Windows EXE, macOS DMG) — Desain Identik 100% dengan Versi Web
// (Palet Mushaf Madinah Ivory #F8F6F0, Madinah Emerald #165B33, Antique Gold #9B7A38,
//  serta Mode Malam Tahajjud #131615).
//
// Mencakup 5 Menu Utama:
// 1. Mushaf 15 Baris (Voice Hifz Panel + Lembaran Mushaf 15 Baris + Detail Perkata)
// 2. Mushaf Bertanda Mutasyabihat (Hover/Sentuh Ayat Mirip + Inline Inspector)
// 3. Koreksi Bacaan Per Kata (Per-Word Mistake Analyzer ala Tarteel: Hijau/Kuning/Merah)
// 4. Radar Mutasyabihat (Pencarian, Filter, Diff Kata Pembeda, & Memory Anchor)
// 5. Drill Sambung Ayat (Kuis Interaktif Anti-Lompat Surah)
// =============================================================================

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_update_service.dart';
import 'marked_mushaf_view.dart';
import 'mushaf_15line_and_audio.dart';
import 'quran_hifz_repository.dart';
import 'whisper_voice_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QuranTarteelHifzApp());
}

class QuranTarteelHifzApp extends StatefulWidget {
  const QuranTarteelHifzApp({super.key});

  @override
  State<QuranTarteelHifzApp> createState() => _QuranTarteelHifzAppState();
}

class _QuranTarteelHifzAppState extends State<QuranTarteelHifzApp> {
  ThemeMode _themeMode = ThemeMode.light; // Default: Mushaf Madinah Ivory seperti di Web

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Qur\'an Tarteel Hifz & Radar Mutasyabihat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          primary: Color(0xFF165B33), // Madinah Emerald
          onPrimary: Colors.white,
          secondary: Color(0xFF9B7A38), // Antique Gold
          onSecondary: Colors.white,
          error: Color(0xFFB91C1C),
          onError: Colors.white,
          surface: Color(0xFFFFFFFF),
          onSurface: Color(0xFF1C221F),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F6F0), // Madinah Ivory
        cardColor: const Color(0xFFFFFFFF),
        dividerColor: const Color(0xFFE6E1D6),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: Color(0xFF34D399),
          onPrimary: Color(0xFF062E1B),
          secondary: Color(0xFFD9B36C),
          onSecondary: Color(0xFF1C1608),
          error: Color(0xFFEF4444),
          onError: Colors.white,
          surface: Color(0xFF1B201E),
          onSurface: Color(0xFFECEAE4),
        ),
        scaffoldBackgroundColor: const Color(0xFF131615), // Tahajjud Dark
        cardColor: const Color(0xFF1B201E),
        dividerColor: const Color(0xFF262D2A),
      ),
      themeMode: _themeMode,
      home: QuranHifzHomeScreen(
        isDarkMode: _themeMode == ThemeMode.dark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

// =============================================================================
// 1. HOME SCREEN (LAYOUT IDENTIK VERSI WEB: HEADER + HORIZONTAL TABS + CONTENT)
// =============================================================================

class QuranHifzHomeScreen extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback? onToggleTheme;

  const QuranHifzHomeScreen({
    super.key,
    this.isDarkMode = false,
    this.onToggleTheme,
  });

  @override
  State<QuranHifzHomeScreen> createState() => _QuranHifzHomeScreenState();
}

class _QuranHifzHomeScreenState extends State<QuranHifzHomeScreen> {
  final QuranHifzRepository _repository = QuranHifzRepository();
  late final QuranMurattalAudioService _murattalAudioService;
  late final WhisperVoiceHifzController _voiceController;
  final FocusNode _keyboardFocusNode = FocusNode();

  int _selectedNavIndex = 0; // 0: Mushaf 15 Baris, 1: Mushaf Bertanda, 2: Koreksi Bacaan, 3: Radar, 4: Drill
  int _selectedJuz = 30;
  int _selectedSurahId = 78; // Default: QS. An-Naba' (seperti di Web)
  bool _hideVerseMode = true;

  List<Surah> _surahs = const [];
  List<Verse> _verses = const [];
  List<MutasyabihatComparisonPair> _mutasyabihatPairs = const [];
  MutasyabihatScope _selectedScope = MutasyabihatScope.all;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _murattalAudioService = QuranMurattalAudioService();
    _voiceController = WhisperVoiceHifzController(
      repository: _repository,
      murattalAudioService: _murattalAudioService,
    );
    _voiceController.modelDownloadManager.checkExistingModel();
    _loadInitialData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppUpdateService.checkUpdateSilently(context);
    });
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final surahs = await _repository.getAllSurahs();
      if (surahs.isNotEmpty && !surahs.any((s) => s.id == _selectedSurahId)) {
        _selectedSurahId = surahs.first.id;
      }
      final verses = await _repository.getVerses(
        surahId: _selectedSurahId,
        includeWords: true,
      );
      final pairs = await _repository.getMutasyabihatRadar(
        scope: _selectedScope,
        juzNumber: _selectedJuz,
        surahId: _selectedSurahId,
      );

      if (!mounted) return;
      setState(() {
        _surahs = surahs;
        _verses = verses;
        _mutasyabihatPairs = pairs;
        _isLoading = false;
      });

      if (verses.isNotEmpty) {
        await _voiceController.setActiveVerse(
          verses.first,
          revealAllInitially: !_hideVerseMode,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _onSurahChanged(int newSurahId) async {
    setState(() {
      _selectedSurahId = newSurahId;
      if (_verses.isEmpty) {
        _isLoading = true;
      }
    });
    final verses = await _repository.getVerses(
      surahId: newSurahId,
      includeWords: true,
    );
    final pairs = await _repository.getMutasyabihatRadar(
      scope: _selectedScope,
      juzNumber: _selectedJuz,
      surahId: newSurahId,
    );
    if (!mounted) return;
    setState(() {
      _verses = verses;
      _mutasyabihatPairs = pairs;
      _isLoading = false;
    });
    if (verses.isNotEmpty) {
      await _voiceController.setActiveVerse(
        verses.first,
        revealAllInitially: !_hideVerseMode,
      );
    }
  }

  Future<Surah?> _advanceToNextSurah() async {
    if (_surahs.isEmpty) return null;
    final idx = _surahs.indexWhere((s) => s.id == _selectedSurahId);
    if (idx < 0) return null;
    final nextIdx = (idx + 1) < _surahs.length ? (idx + 1) : 0;
    final nextSurah = _surahs[nextIdx];
    await _onSurahChanged(nextSurah.id);
    return nextSurah;
  }

  Future<void> _refreshMutasyabihatRadar({
    MutasyabihatScope? scope,
    int? juzNumber,
  }) async {
    final targetScope = scope ?? _selectedScope;
    final targetJuz = juzNumber ?? _selectedJuz;
    setState(() {
      _selectedScope = targetScope;
      _selectedJuz = targetJuz;
    });

    final pairs = await _repository.getMutasyabihatRadar(
      scope: targetScope,
      juzNumber: targetJuz,
      surahId: _selectedSurahId,
    );
    if (!mounted) return;
    setState(() => _mutasyabihatPairs = pairs);
  }

  void _stepSurah(int delta) {
    if (_surahs.isEmpty) return;
    final idx = _surahs.indexWhere((s) => s.id == _selectedSurahId);
    if (idx < 0) return;
    final nextIdx = (idx + delta).clamp(0, _surahs.length - 1);
    if (nextIdx != idx) {
      _onSurahChanged(_surahs[nextIdx].id);
    }
  }

  Surah? get _activeSurah {
    if (_surahs.isEmpty) return null;
    return _surahs.firstWhere(
      (s) => s.id == _selectedSurahId,
      orElse: () => _surahs.first,
    );
  }

  @override
  void dispose() {
    _murattalAudioService.dispose();
    _voiceController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.space) {
          _voiceController.peekNextWord();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // 1. Header Aplikasi (Identik .app-header di Web)
              _buildWebStyleHeader(context, isDark),

              // 2. Baris Tab Navigasi Horizontal (Identik .nav-tabs di Web)
              _buildWebStyleNavTabs(context, isDark),

              // 3. Area Konten Utama Terpusat (max-width: 1140px)
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildActiveTabBody(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebStyleHeader(BuildContext context, bool isDark) {
    final surfaceColor = isDark ? const Color(0xFF1B201E) : Colors.white;
    final borderSubtle = isDark ? const Color(0xFF262D2A) : const Color(0xFFE6E1D6);
    final borderCard = isDark ? const Color(0xFF323B37) : const Color(0xFFDCD5C6);
    final primaryColor = isDark ? const Color(0xFF34D399) : const Color(0xFF165B33);
    final primarySubtle = isDark ? const Color(0xFF132A20) : const Color(0xFFEBF4EE);
    final textPrimary = isDark ? const Color(0xFFECEAE4) : const Color(0xFF1C221F);
    final textSecondary = isDark ? const Color(0xFFA7B0AC) : const Color(0xFF525E58);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(bottom: BorderSide(color: borderSubtle)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1140),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              // Brand Kiri
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: primarySubtle,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: primaryColor.withOpacity(0.25)),
                    ),
                    child: Icon(
                      Icons.menu_book_rounded,
                      color: primaryColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Qur\'an Tarteel Hifz',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        'Mushaf Madinah 15 Baris & Radar Mutasyabihat',
                        style: TextStyle(
                          fontSize: 12,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Kontrol Kanan (Dropdown Surah + Tombol Intip Kata + Tema + Update + Whisper)
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_surahs.isNotEmpty)
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: surfaceColor,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderCard),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _surahs.any((s) => s.id == _selectedSurahId)
                              ? _selectedSurahId
                              : _surahs.first.id,
                          dropdownColor: surfaceColor,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                          items: _surahs
                              .map(
                                (s) => DropdownMenuItem<int>(
                                  value: s.id,
                                  child: Text(
                                    '${s.id}. QS. ${s.nameLatin} (${s.nameArabic})',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) _onSurahChanged(val);
                          },
                        ),
                      ),
                    ),

                  // Tombol Intip Kata (Persis seperti #btn-hide-mode di Web)
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      setState(() => _hideVerseMode = !_hideVerseMode);
                      if (_hideVerseMode) {
                        _voiceController.hideAllWords();
                      } else {
                        _voiceController.revealAllWords();
                      }
                    },
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: _hideVerseMode ? primarySubtle : surfaceColor,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _hideVerseMode ? primaryColor : borderCard,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.remove_red_eye_outlined,
                            size: 16,
                            color: _hideVerseMode ? primaryColor : textPrimary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Intip Kata',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: _hideVerseMode ? primaryColor : textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Tombol Ganti Tema (Madinah Ivory / Malam Tahajjud)
                  IconButton(
                    tooltip: 'Ganti Tema (Madinah Terang / Malam Tahajjud)',
                    onPressed: widget.onToggleTheme,
                    icon: Icon(
                      isDark ? Icons.dark_mode_outlined : Icons.wb_sunny_outlined,
                      size: 20,
                      color: textSecondary,
                    ),
                  ),

                  // Tombol Periksa Auto-Update
                  IconButton(
                    tooltip: 'Periksa Pembaruan Aplikasi (Auto-Update)',
                    onPressed: () => AppUpdateService.manualCheck(context),
                    icon: Icon(
                      Icons.system_update_alt_rounded,
                      size: 20,
                      color: textSecondary,
                    ),
                  ),

                  // Tombol Pengaturan Model Whisper AI
                  IconButton(
                    tooltip: 'Pengaturan Model Suara Whisper AI Offline',
                    onPressed: _showWhisperModelManagerDialog,
                    icon: Icon(
                      Icons.tune_rounded,
                      size: 20,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebStyleNavTabs(BuildContext context, bool isDark) {
    final surfaceColor = isDark ? const Color(0xFF1B201E) : Colors.white;
    final borderSubtle = isDark ? const Color(0xFF262D2A) : const Color(0xFFE6E1D6);
    final primaryColor = isDark ? const Color(0xFF34D399) : const Color(0xFF165B33);
    final textSecondary = isDark ? const Color(0xFFA7B0AC) : const Color(0xFF525E58);
    final goldColor = isDark ? const Color(0xFFD9B36C) : const Color(0xFF9B7A38);

    final tabs = [
      (index: 0, icon: Icons.menu_book_outlined, label: 'Mushaf 15 Baris', badge: null),
      (index: 1, icon: Icons.star_outline_rounded, label: 'Mushaf Bertanda', badge: null),
      (index: 2, icon: Icons.mic_none_rounded, label: 'Koreksi Bacaan', badge: null),
      (
        index: 3,
        icon: Icons.explore_outlined,
        label: 'Radar Mutasyabihat',
        badge: '${_mutasyabihatPairs.length}'
      ),
      (index: 4, icon: Icons.check_circle_outline_rounded, label: 'Drill Sambung Ayat', badge: null),
    ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(bottom: BorderSide(color: borderSubtle)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1140),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: tabs.map((t) {
                final isActive = _selectedNavIndex == t.index;
                return InkWell(
                  onTap: () => setState(() => _selectedNavIndex = t.index),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isActive ? primaryColor : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          t.icon,
                          size: 18,
                          color: isActive ? primaryColor : textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          t.label,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: isActive ? primaryColor : textSecondary,
                          ),
                        ),
                        if (t.badge != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                            decoration: BoxDecoration(
                              color: goldColor.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: goldColor.withOpacity(0.45)),
                            ),
                            child: Text(
                              t.badge!,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: goldColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTabBody(BuildContext context) {
    final surah = _activeSurah;
    switch (_selectedNavIndex) {
      case 0:
        return MushafVoiceHifzView(
          verses: _verses,
          surah: surah,
          voiceController: _voiceController,
          murattalAudioService: _murattalAudioService,
          hideVerseMode: _hideVerseMode,
          onPrevSurahPage: () => _stepSurah(-1),
          onNextSurahPage: () => _stepSurah(1),
          onShowTafsir: _showTafsirBottomSheet,
        );
      case 1:
        final surahs = _surahs;
        final currIdx = surahs.indexWhere((s) => s.id == _selectedSurahId);
        final prevSurah = currIdx > 0 ? surahs[currIdx - 1] : null;
        final nextSurah =
            (currIdx >= 0 && currIdx + 1 < surahs.length) ? surahs[currIdx + 1] : null;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1140),
            child: MarkedMushafMutasyabihatView(
              verses: _verses,
              pairs: _mutasyabihatPairs,
              murattalAudioService: _murattalAudioService,
              onPrevSurah: () => _stepSurah(-1),
              onNextSurah: () => _stepSurah(1),
              prevSurahName: prevSurah?.nameLatin,
              nextSurahName: nextSurah?.nameLatin,
            ),
          ),
        );
      case 2:
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1140),
            child: RecitationCorrectionView(
              verses: _verses,
              surah: surah,
              allSurahs: _surahs,
              voiceController: _voiceController,
              murattalAudioService: _murattalAudioService,
              onAdvanceToNextSurah: _advanceToNextSurah,
              onSelectSurah: _onSurahChanged,
            ),
          ),
        );
      case 3:
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1140),
            child: MutasyabihatRadarView(
              pairs: _mutasyabihatPairs,
              selectedScope: _selectedScope,
              selectedJuz: _selectedJuz,
              murattalAudioService: _murattalAudioService,
              onScopeChanged: (scope) => _refreshMutasyabihatRadar(scope: scope),
              onJuzChanged: (juz) => _refreshMutasyabihatRadar(juzNumber: juz),
              onSaveMemoryAnchor: (groupId, note) async {
                await _repository.saveMemoryAnchor(
                  groupId: groupId,
                  userNote: note,
                );
                await _refreshMutasyabihatRadar();
              },
            ),
          ),
        );
      case 4:
      default:
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: MutasyabihatDrillView(
              repository: _repository,
              juzNumber: _selectedJuz,
            ),
          ),
        );
    }
  }

  void _showWhisperModelManagerDialog() {
    final manager = _voiceController.modelDownloadManager;
    showDialog<void>(
      context: context,
      builder: (context) {
        return ListenableBuilder(
          listenable: manager,
          builder: (context, _) {
            return AlertDialog(
              title: const Text('Model AI Whisper Al-Qur\'an & Mikrofon'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pilih Model On-Device (Hugging Face Tarteel AI):',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    ...WhisperModelDownloadManager.presets.map((preset) {
                      return RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          preset.title,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text('Ukuran ~${preset.approxSizeMB} MB'),
                        value: preset.id,
                        groupValue: manager.selectedPreset.id,
                        onChanged: (val) {
                          if (val != null) {
                            manager.checkExistingModel(preset);
                          }
                        },
                      );
                    }),
                    const SizedBox(height: 12),
                    if (manager.isDownloading) ...[
                      LinearProgressIndicator(value: manager.downloadProgress),
                      const SizedBox(height: 8),
                    ],
                    if (manager.statusText != null)
                      Text(
                        manager.statusText!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Tutup'),
                ),
                FilledButton.icon(
                  onPressed: manager.isDownloading
                      ? null
                      : manager.downloadSelectedModel,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    manager.isModelReady ? 'Unduh Ulang Model' : 'Unduh Model',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showTafsirBottomSheet(Verse verse) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tafsir Wajiz — QS. ${verse.surahNameLatin ?? verse.surahId}: ${verse.verseNumber}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                verse.textUthmani,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontSize: 24, height: 1.8),
              ),
              const Divider(height: 24),
              Text(
                verse.tafsirWajiz ?? verse.translationId,
                style: const TextStyle(fontSize: 15, height: 1.6),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// 2. TAB 1: MUSHAF 15 BARIS + PANEL VOICE HIFZ + DETAIL AYAT PERKATA (IDENTIK WEB)
// =============================================================================

class MushafVoiceHifzView extends StatelessWidget {
  final List<Verse> verses;
  final Surah? surah;
  final WhisperVoiceHifzController voiceController;
  final QuranMurattalAudioService murattalAudioService;
  final bool hideVerseMode;
  final VoidCallback? onPrevSurahPage;
  final VoidCallback? onNextSurahPage;
  final void Function(Verse verse) onShowTafsir;

  const MushafVoiceHifzView({
    super.key,
    required this.verses,
    this.surah,
    required this.voiceController,
    required this.murattalAudioService,
    required this.hideVerseMode,
    this.onPrevSurahPage,
    this.onNextSurahPage,
    required this.onShowTafsir,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: Listenable.merge([voiceController, murattalAudioService]),
      builder: (context, _) {
        final state = voiceController.state;
        final activeVerse = voiceController.currentVerse ??
            (verses.isNotEmpty ? verses.first : null);

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Panel Simak Suara & Kontrol Audio (Persis .voice-hifz-panel di Web)
                  _buildWebVoiceHifzPanel(context, state, activeVerse, isDark),

                  const SizedBox(height: 18),

                  // 2. Lembaran Mushaf Madinah 15 Baris (Persis .mushaf-page-card di Web)
                  Mushaf15LinePageWidget(
                    verses: verses,
                    activeVerseId: state.activeVerseId,
                    revealedWordPosition: state.revealedWordPosition,
                    hideVerseMode: hideVerseMode,
                    surahArabicName: surah?.nameArabic,
                    revelationType: surah?.revelationType,
                    onPrevPage: onPrevSurahPage,
                    onNextPage: onNextSurahPage,
                    onSelectVerse: (verse) => voiceController.setActiveVerse(
                      verse,
                      revealAllInitially: !hideVerseMode,
                    ),
                    onPlayVerseAudio: (verse) => murattalAudioService.playVerse(
                      surahId: verse.surahId,
                      verseNumber: verse.verseNumber,
                      surahName: verse.surahNameLatin,
                    ),
                    onShowTafsir: onShowTafsir,
                  ),

                  const SizedBox(height: 18),

                  // 3. Kartu Detail Ayat & Terjemahan Perkata (Persis .verse-detail-card di Web)
                  if (activeVerse != null)
                    _buildWebVerseDetailCard(context, activeVerse, isDark),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWebVoiceHifzPanel(
    BuildContext context,
    VoiceHifzSessionState state,
    Verse? activeVerse,
    bool isDark,
  ) {
    final surfaceColor = isDark ? const Color(0xFF1B201E) : Colors.white;
    final subtleBg = isDark ? const Color(0xFF1E2422) : const Color(0xFFF1EDE4);
    final borderCard = isDark ? const Color(0xFF323B37) : const Color(0xFFDCD5C6);
    final borderSubtle = isDark ? const Color(0xFF262D2A) : const Color(0xFFE6E1D6);
    final primaryColor = isDark ? const Color(0xFF34D399) : const Color(0xFF165B33);
    final textPrimary = isDark ? const Color(0xFFECEAE4) : const Color(0xFF1C221F);
    final textSecondary = isDark ? const Color(0xFFA7B0AC) : const Color(0xFF525E58);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderCard),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Baris Atas: Tombol Mikrofon Bulat + Status & Kotak Transkrip
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: state.isListening
                    ? voiceController.stopListening
                    : () => voiceController.startListening(resetWordsOnStart: true),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: state.isListening
                        ? const Color(0xFFDC2626)
                        : primaryColor,
                  ),
                  child: Icon(
                    state.isListening ? Icons.stop_rounded : Icons.mic_none_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: state.isListening
                                ? const Color(0xFF15803D)
                                : const Color(0xFF84928B),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state.statusMessage ?? 'Siap menyimak bacaan hafalan',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: subtleBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderSubtle),
                      ),
                      child: Text(
                        state.lastTranscript.isNotEmpty
                            ? 'Suara: "${state.lastTranscript}"'
                            : 'Tekan tombol mikrofon untuk menyimak otomatis, atau tekan Spasi untuk membuka kata demi kata.',
                        style: TextStyle(
                          fontSize: 13,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Kotak Peringatan Trap Jump (Jika Terdeteksi)
          if (state.evaluationResult != null) ...[
            const SizedBox(height: 12),
            _buildTrapAlertBox(context, state.evaluationResult!, isDark),
          ],

          const SizedBox(height: 14),
          Divider(height: 1, color: borderSubtle),
          const SizedBox(height: 12),

          // Murattal Bar (Persis .murattal-bar di Web: Dropdown Qari | Putar Audio + Ulangi 1x | Hint Spasi)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              // Dropdown Qari
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderCard),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: murattalAudioService.selectedReciter.id,
                    dropdownColor: surfaceColor,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: textPrimary,
                    ),
                    items: QariCatalog.supportedReciters
                        .map(
                          (q) => DropdownMenuItem<String>(
                            value: q.id,
                            child: Text('${q.name} (${q.styleLabel})'),
                          ),
                        )
                        .toList(),
                    onChanged: (id) {
                      if (id == null) return;
                      final found = QariCatalog.supportedReciters
                          .firstWhere((q) => q.id == id);
                      murattalAudioService.setReciter(found);
                    },
                  ),
                ),
              ),

              // Tombol Putar Audio + Ulangi + Simulasi Cepat
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () {
                      if (murattalAudioService.isPlaying) {
                        murattalAudioService.stop();
                      } else if (activeVerse != null) {
                        murattalAudioService.playVerse(
                          surahId: activeVerse.surahId,
                          verseNumber: activeVerse.verseNumber,
                          surahName: activeVerse.surahNameLatin,
                        );
                      }
                    },
                    icon: Icon(
                      murattalAudioService.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 16,
                    ),
                    label: Text(
                      murattalAudioService.isPlaying ? 'Jeda Audio' : 'Putar Audio',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textPrimary,
                      side: BorderSide(color: borderCard),
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () {
                      final next = murattalAudioService.repeatTargetCount == 1
                          ? 3
                          : (murattalAudioService.repeatTargetCount == 3 ? 5 : 1);
                      murattalAudioService.setRepeatTargetCount(next);
                    },
                    icon: const Icon(Icons.repeat_rounded, size: 15),
                    label: Text(
                      'Ulangi ${murattalAudioService.repeatTargetCount}x',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textSecondary,
                      side: BorderSide(color: borderSubtle),
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => voiceController.runInteractiveSimulation(
                      simulateTrapJump: true,
                    ),
                    child: const Text(
                      'Uji Deteksi Lompat Surah',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),

              // Hint Navigasi Spasi
              Text(
                'Navigasi: Spasi untuk intip kata berikutnya',
                style: TextStyle(
                  fontSize: 12,
                  color: textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrapAlertBox(
    BuildContext context,
    VoiceEvaluationResult result,
    bool isDark,
  ) {
    final isTrap = result.isTrapJump;
    final bg = isTrap
        ? (isDark ? const Color(0xFF2D1618) : const Color(0xFFFEF2F2))
        : (isDark ? const Color(0xFF0E291E) : const Color(0xFFECFDF5));
    final border = isTrap ? const Color(0xFFFECACA) : const Color(0xFF6EE7B7);
    final accent = isTrap ? const Color(0xFFB91C1C) : const Color(0xFF15803D);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isTrap ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
            color: accent,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isTrap
                      ? 'Peringatan: Potensi Lompat Surah'
                      : 'Bacaan Tepat Sesuai Urutan',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  result.warningMessage,
                  style: const TextStyle(fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebVerseDetailCard(
    BuildContext context,
    Verse verse,
    bool isDark,
  ) {
    final surfaceColor = isDark ? const Color(0xFF1B201E) : Colors.white;
    final subtleBg = isDark ? const Color(0xFF1E2422) : const Color(0xFFF1EDE4);
    final borderCard = isDark ? const Color(0xFF323B37) : const Color(0xFFDCD5C6);
    final borderSubtle = isDark ? const Color(0xFF262D2A) : const Color(0xFFE6E1D6);
    final primaryColor = isDark ? const Color(0xFF34D399) : const Color(0xFF165B33);
    final primarySubtle = isDark ? const Color(0xFF132A20) : const Color(0xFFEBF4EE);
    final arabicColor = isDark ? const Color(0xFFF3F1EC) : const Color(0xFF141816);
    final textSecondary = isDark ? const Color(0xFFA7B0AC) : const Color(0xFF525E58);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderCard),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: primarySubtle,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderSubtle),
                ),
                child: Text(
                  'QS. ${verse.surahNameLatin ?? verse.surahId} : Ayat ${verse.verseNumber}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: primaryColor,
                  ),
                ),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => onShowTafsir(verse),
                    icon: const Icon(Icons.menu_book_outlined, size: 15),
                    label: const Text('Tafsir', style: TextStyle(fontSize: 12.5)),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(
                          text: '${verse.textUthmani}\n${verse.translationId}',
                        ),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ayat & terjemahan disalin ke clipboard.'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text('Salin', style: TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            verse.textUthmani,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 27,
              height: 2.0,
              color: arabicColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            verse.translationId,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.6,
              color: textSecondary,
            ),
          ),
          if (verse.words.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: borderSubtle),
            const SizedBox(height: 14),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: verse.words.map((w) {
                  return Container(
                    constraints: const BoxConstraints(minWidth: 64),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: subtleBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderSubtle),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          w.textUthmani,
                          style: TextStyle(
                            fontSize: 20,
                            height: 1.5,
                            color: arabicColor,
                          ),
                        ),
                        if (w.translationId.isNotEmpty)
                          Text(
                            w.translationId,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: textSecondary,
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// 3. TAB 3: MODE LATIHAN & KOREKSI BACAAN PER KATA (ALA TARTEEL - IDENTIK WEB)
// =============================================================================

class _EvaluatedVerseHistoryItem {
  final int surahId;
  final String surahNameLatin;
  final int verseNumber;
  final String textUthmani;
  final VerseMistakeAnalysisResult result;
  final bool isAllCorrect;

  const _EvaluatedVerseHistoryItem({
    required this.surahId,
    required this.surahNameLatin,
    required this.verseNumber,
    required this.textUthmani,
    required this.result,
    required this.isAllCorrect,
  });
}

class RecitationCorrectionView extends StatefulWidget {
  final List<Verse> verses;
  final Surah? surah;
  final List<Surah> allSurahs;
  final WhisperVoiceHifzController voiceController;
  final QuranMurattalAudioService murattalAudioService;
  final Future<Surah?> Function()? onAdvanceToNextSurah;
  final Future<void> Function(int surahId)? onSelectSurah;

  const RecitationCorrectionView({
    super.key,
    required this.verses,
    this.surah,
    this.allSurahs = const [],
    required this.voiceController,
    required this.murattalAudioService,
    this.onAdvanceToNextSurah,
    this.onSelectSurah,
  });

  @override
  State<RecitationCorrectionView> createState() =>
      _RecitationCorrectionViewState();
}

class _RecitationCorrectionViewState extends State<RecitationCorrectionView> {
  int _selectedVerseNumber = 1;
  bool _blindMode = false;
  bool _autoAdvanceEnabled = true;
  bool _autoPlayQariOnMistake = false;
  bool _isContinuousSimulating = false;
  int _selectedWordIdx = 0;
  VerseMistakeAnalysisResult? _analysisResult;
  String? _autoAdvanceBannerText;
  bool _autoAdvanceBannerIsCorrect = true;
  Timer? _autoAdvanceTimer;
  Timer? _continuousSimTimer;
  int? _pendingJumpVerseNumber;
  String? _lastFinalizedVerseKey;
  final List<_EvaluatedVerseHistoryItem> _sessionHistory = <_EvaluatedVerseHistoryItem>[];
  final TextEditingController _transcriptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.voiceController.onLiveTranscriptDetailedCallback =
        (String liveText, bool isFinal) {
      if (!mounted) return;
      _handleIncomingLiveSpeech(liveText, isFinal: isFinal);
    };
  }

  @override
  void didUpdateWidget(covariant RecitationCorrectionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.verses != widget.verses) {
      final targetVerseNum = _pendingJumpVerseNumber ??
          (widget.verses.isNotEmpty ? widget.verses.first.verseNumber : 1);
      _pendingJumpVerseNumber = null;
      setState(() {
        _selectedVerseNumber = targetVerseNum;
        _analysisResult = null;
        _autoAdvanceBannerText = null;
        _lastFinalizedVerseKey = null;
        _selectedWordIdx = 0;
        _transcriptController.clear();
      });
      final v = _activeVerse;
      if (v != null) {
        widget.voiceController.setActiveVerse(v);
      }
      if (_isContinuousSimulating) {
        _scheduleNextSimulatedVerse();
      }
    }
  }

  Verse? get _activeVerse {
    if (widget.verses.isEmpty) return null;
    return widget.verses.firstWhere(
      (v) => v.verseNumber == _selectedVerseNumber,
      orElse: () => widget.verses.first,
    );
  }

  Surah? get _nextSurahPreview {
    if (widget.allSurahs.isEmpty) return null;
    final currId = widget.surah?.id ??
        (widget.verses.isNotEmpty ? widget.verses.first.surahId : 0);
    final idx = widget.allSurahs.indexWhere((s) => s.id == currId);
    if (idx < 0) return null;
    final nextIdx = (idx + 1) < widget.allSurahs.length ? (idx + 1) : 0;
    return widget.allSurahs[nextIdx];
  }

  void _handleIncomingLiveSpeech(String liveText, {required bool isFinal}) {
    final verse = _activeVerse;
    if (verse == null) return;
    final verseKey = '${verse.surahId}:${verse.verseNumber}';
    // Jika ayat saat ini sudah difinalisasi dan sedang menunggu transisi otomatis, abaikan event ganda
    if (_lastFinalizedVerseKey == verseKey) {
      return;
    }

    _transcriptController.text = liveText;
    final res = ArabicFuzzyMatcher.analyzeVerseWordMistakes(
      targetVerse: verse,
      spokenTranscript: liveText,
    );
    final firstIssueIdx = res.wordItems.indexWhere(
      (w) => w.status != WordMistakeStatus.correct,
    );
    setState(() {
      _analysisResult = res;
      _selectedWordIdx = firstIssueIdx >= 0 ? firstIssueIdx : 0;
    });

    final cleanTokens = ArabicFuzzyMatcher.normalizeArabic(liveText)
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    final totalExpectedWords = res.wordItems.length;

    // Deteksi apakah pembacaan ayat saat ini telah selesai (seluruh kata telah diucapkan atau kalimat selesai/final)
    final hasReachedAllWords =
        totalExpectedWords > 0 && cleanTokens.length >= totalExpectedWords;
    if (cleanTokens.isNotEmpty && (isFinal || hasReachedAllWords)) {
      _lastFinalizedVerseKey = verseKey;
      _finalizeAndMaybeAutoAdvance(
        verse,
        res,
        resetLiveMicBufferOnAdvance: !isFinal,
      );
    }
  }

  void _runEvaluation(String transcript, {bool triggerAutoAdvance = true}) {
    final verse = _activeVerse;
    if (verse == null) return;
    _autoAdvanceTimer?.cancel();
    _lastFinalizedVerseKey = null;
    final res = ArabicFuzzyMatcher.analyzeVerseWordMistakes(
      targetVerse: verse,
      spokenTranscript: transcript,
    );
    final firstIssueIdx = res.wordItems.indexWhere(
      (w) => w.status != WordMistakeStatus.correct,
    );
    setState(() {
      _analysisResult = res;
      _selectedWordIdx = firstIssueIdx >= 0 ? firstIssueIdx : 0;
    });
    if (triggerAutoAdvance) {
      _finalizeAndMaybeAutoAdvance(verse, res);
    }
  }

  void _finalizeAndMaybeAutoAdvance(
    Verse verse,
    VerseMistakeAnalysisResult res, {
    bool resetLiveMicBufferOnAdvance = false,
  }) {
    final isAllCorrect = res.wrongCount == 0 && res.nearMissCount == 0;
    final surahName = verse.surahNameLatin ??
        widget.surah?.nameLatin ??
        'Surah ${verse.surahId}';

    final historyItem = _EvaluatedVerseHistoryItem(
      surahId: verse.surahId,
      surahNameLatin: surahName,
      verseNumber: verse.verseNumber,
      textUthmani: verse.textUthmani,
      result: res,
      isAllCorrect: isAllCorrect,
    );

    setState(() {
      final existingIdx = _sessionHistory.indexWhere(
        (h) => h.surahId == verse.surahId && h.verseNumber == verse.verseNumber,
      );
      if (existingIdx >= 0) {
        _sessionHistory[existingIdx] = historyItem;
      } else {
        _sessionHistory.insert(0, historyItem);
      }
    });

    if (_autoPlayQariOnMistake && !isAllCorrect) {
      widget.murattalAudioService.playVerse(
        surahId: verse.surahId,
        verseNumber: verse.verseNumber,
        surahName: surahName,
      );
    }

    if (!_autoAdvanceEnabled) return;

    _autoAdvanceTimer?.cancel();
    final isLastVerseInSurah = _selectedVerseNumber >= widget.verses.length;
    final nextSurah = _nextSurahPreview;
    final nextTargetLabel = !isLastVerseInSurah
        ? 'QS. $surahName : Ayat ${_selectedVerseNumber + 1}'
        : (nextSurah != null
            ? 'Surah Selanjutnya — QS. ${nextSurah.nameLatin} (${nextSurah.nameArabic}) : Ayat 1'
            : 'Surah Selanjutnya : Ayat 1');

    final accPct = (res.accuracyScore * 100).round();
    final issueCount = res.wrongCount + res.nearMissCount;

    setState(() {
      _autoAdvanceBannerIsCorrect = isAllCorrect;
      _autoAdvanceBannerText = isAllCorrect
          ? '✓ Bacaan Tepat ($accPct%)! Menyambung otomatis ke $nextTargetLabel...'
          : '⚠️ Terdeteksi $issueCount kata perlu koreksi ($accPct%). Menyambung otomatis ke $nextTargetLabel...';
    });

    final delayMs = isAllCorrect
        ? 1500
        : (_autoPlayQariOnMistake ? 3400 : 2200);

    _autoAdvanceTimer = Timer(Duration(milliseconds: delayMs), () {
      _advanceToNextVerseOrSurah(
        resetLiveMicBuffer: resetLiveMicBufferOnAdvance,
      );
    });
  }

  Future<void> _advanceToNextVerseOrSurah({bool resetLiveMicBuffer = false}) async {
    if (!mounted) return;
    _autoAdvanceTimer?.cancel();
    _lastFinalizedVerseKey = null;

    if (resetLiveMicBuffer) {
      await widget.voiceController.resetRecognitionBufferForNextVerse();
    }

    if (_selectedVerseNumber < widget.verses.length) {
      setState(() {
        _selectedVerseNumber++;
        _analysisResult = null;
        _autoAdvanceBannerText = null;
        _selectedWordIdx = 0;
        _transcriptController.clear();
      });
      final nextV = _activeVerse;
      if (nextV != null) {
        await widget.voiceController.setActiveVerse(nextV);
      }
      if (_isContinuousSimulating) {
        _scheduleNextSimulatedVerse();
      }
    } else {
      // Sudah di ayat terakhir surah ini -> otomatis pindah ke Surah Selanjutnya Ayat 1!
      if (widget.onAdvanceToNextSurah != null) {
        await widget.onAdvanceToNextSurah!();
      }
    }
  }

  void _cancelPendingAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    _continuousSimTimer?.cancel();
    setState(() {
      _autoAdvanceBannerText = null;
      _isContinuousSimulating = false;
    });
  }

  void _toggleContinuousSimulation() {
    if (_isContinuousSimulating) {
      _cancelPendingAutoAdvance();
      return;
    }
    setState(() {
      _isContinuousSimulating = true;
      _autoAdvanceEnabled = true;
    });
    _runSingleSimulatedStep();
  }

  void _scheduleNextSimulatedVerse() {
    _continuousSimTimer?.cancel();
    if (!_isContinuousSimulating || !mounted) return;
    _continuousSimTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || !_isContinuousSimulating) return;
      _runSingleSimulatedStep();
    });
  }

  void _runSingleSimulatedStep() {
    final verse = _activeVerse;
    if (verse == null) return;
    // Setiap ayat ke-3 disimulasikan ada 1 kata kurang tepat agar terlihat proses koreksi benar & salah secara nyata
    if (verse.verseNumber % 3 == 0) {
      _simulateMistake();
    } else {
      _simulatePerfect();
    }
  }

  void _simulatePerfect() {
    final verse = _activeVerse;
    if (verse == null) return;
    _transcriptController.text = verse.textUthmani;
    _runEvaluation(verse.textUthmani, triggerAutoAdvance: true);
  }

  void _simulateMistake() {
    final verse = _activeVerse;
    if (verse == null) return;
    final tokens = verse.textUthmani
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final mutated = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      final tok = tokens[i];
      if (tokens.length >= 3 && i == 1) {
        mutated.add(tok.substring(0, (tok.length - 2).clamp(1, tok.length)));
      } else if (i == tokens.length - 1) {
        mutated.add('ٱلصَّاخَّةُ');
      } else {
        mutated.add(tok);
      }
    }
    final text = mutated.join(' ');
    _transcriptController.text = text;
    _runEvaluation(text, triggerAutoAdvance: true);
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _continuousSimTimer?.cancel();
    if (widget.voiceController.onLiveTranscriptDetailedCallback != null) {
      widget.voiceController.onLiveTranscriptDetailedCallback = null;
    }
    _transcriptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final verse = _activeVerse;
    if (verse == null) {
      return const Center(child: Text('Tidak ada data ayat.'));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1B201E) : Colors.white;
    final pageBg = isDark ? const Color(0xFF1A201E) : const Color(0xFFFCFAF6);
    final borderCard = isDark ? const Color(0xFF323B37) : const Color(0xFFDCD5C6);
    final borderGold = isDark ? const Color(0xFF785E2B) : const Color(0xFFC8AA76);
    final primaryColor = isDark ? const Color(0xFF34D399) : const Color(0xFF165B33);
    final goldColor = isDark ? const Color(0xFFD9B36C) : const Color(0xFF9B7A38);
    final textSecondary = isDark ? const Color(0xFFA7B0AC) : const Color(0xFF525E58);

    final words = verse.words.isNotEmpty
        ? verse.words
        : verse.textUthmani
            .split(RegExp(r'\s+'))
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
                textClean: ArabicFuzzyMatcher.normalizeArabic(e.value),
                translationId: '',
              ),
            )
            .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner Penjelasan Mode Koreksi Bacaan
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E221A) : const Color(0xFFFBF5E8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? const Color(0xFF4B3D22) : const Color(0xFFE6D0A3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: goldColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.mic_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mode Latihan & Koreksi Bacaan Per Kata (Tasmi\' & Tashih)',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Uji ketepatan bacaan ayat demi ayat. Setiap kata dianalisis secara otomatis: Hijau (Tepat), Kuning (Kurang Tepat/Mirip), dan Merah (Salah Ucap/Terlewat) disertai koreksi audio Qari.',
                        style: TextStyle(fontSize: 12.5, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Kartu Kontrol Pilihan Ayat, Mikrofon, Simulasi, & Skor
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderCard),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton(
                          onPressed: _selectedVerseNumber > 1
                              ? () {
                                  _cancelPendingAutoAdvance();
                                  setState(() {
                                    _selectedVerseNumber--;
                                    _analysisResult = null;
                                    _lastFinalizedVerseKey = null;
                                    _transcriptController.clear();
                                  });
                                }
                              : null,
                          child: const Text('◄ Ayat Sebelumnya'),
                        ),
                        Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: borderCard),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: _selectedVerseNumber,
                              items: widget.verses
                                  .map(
                                    (v) => DropdownMenuItem<int>(
                                      value: v.verseNumber,
                                      child: Text(
                                        'QS. ${v.surahNameLatin ?? v.surahId} : Ayat ${v.verseNumber}',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  _cancelPendingAutoAdvance();
                                  setState(() {
                                    _selectedVerseNumber = val;
                                    _analysisResult = null;
                                    _lastFinalizedVerseKey = null;
                                    _transcriptController.clear();
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            _cancelPendingAutoAdvance();
                            _lastFinalizedVerseKey = null;
                            if (_selectedVerseNumber < widget.verses.length) {
                              setState(() {
                                _selectedVerseNumber++;
                                _analysisResult = null;
                                _transcriptController.clear();
                              });
                            } else if (widget.onAdvanceToNextSurah != null) {
                              widget.onAdvanceToNextSurah!();
                            }
                          },
                          child: Text(
                            _selectedVerseNumber < widget.verses.length
                                ? 'Ayat Selanjutnya ►'
                                : 'Surah Selanjutnya ►',
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _autoAdvanceEnabled
                                ? primaryColor.withOpacity(0.14)
                                : null,
                            side: BorderSide(
                              color: _autoAdvanceEnabled ? primaryColor : borderCard,
                              width: _autoAdvanceEnabled ? 1.5 : 1.0,
                            ),
                          ),
                          onPressed: () => setState(
                            () => _autoAdvanceEnabled = !_autoAdvanceEnabled,
                          ),
                          icon: Icon(
                            _autoAdvanceEnabled
                                ? Icons.autorenew_rounded
                                : Icons.pause_circle_outline_rounded,
                            size: 16,
                            color: _autoAdvanceEnabled ? primaryColor : textSecondary,
                          ),
                          label: Text(
                            _autoAdvanceEnabled
                                ? 'Sambung Otomatis (Ayat & Surah): ON'
                                : 'Sambung Otomatis: OFF',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _autoAdvanceEnabled ? primaryColor : null,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _autoPlayQariOnMistake
                                ? goldColor.withOpacity(0.16)
                                : null,
                            side: BorderSide(
                              color: _autoPlayQariOnMistake ? goldColor : borderCard,
                            ),
                          ),
                          onPressed: () => setState(
                            () => _autoPlayQariOnMistake = !_autoPlayQariOnMistake,
                          ),
                          icon: Icon(
                            Icons.record_voice_over_outlined,
                            size: 15,
                            color: _autoPlayQariOnMistake ? goldColor : textSecondary,
                          ),
                          label: Text(
                            _autoPlayQariOnMistake
                                ? 'Putar Qari Saat Salah: ON'
                                : 'Putar Qari Saat Salah: OFF',
                            style: TextStyle(
                              color: _autoPlayQariOnMistake ? goldColor : null,
                            ),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () =>
                              setState(() => _blindMode = !_blindMode),
                          child: Text(
                            _blindMode
                                ? 'Tampilkan Lafal (Mode Terbuka)'
                                : 'Sembunyikan Lafal (Uji Hafalan)',
                          ),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: primaryColor),
                          onPressed: () => widget.murattalAudioService.playVerse(
                            surahId: verse.surahId,
                            verseNumber: verse.verseNumber,
                            surahName: verse.surahNameLatin,
                          ),
                          child: const Text('Dengarkan Contoh Qari'),
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.voiceController.state.isListening
                            ? const Color(0xFFDC2626)
                            : primaryColor,
                      ),
                      onPressed: () async {
                        _cancelPendingAutoAdvance();
                        await widget.voiceController.setActiveVerse(verse);
                        if (widget.voiceController.state.isListening) {
                          await widget.voiceController.stopListening();
                          final sp = widget.voiceController.state.lastTranscript;
                          if (sp.isNotEmpty) {
                            _transcriptController.text = sp;
                            _runEvaluation(sp);
                          }
                        } else {
                          await widget.voiceController.startListening();
                        }
                        setState(() {});
                      },
                      icon: Icon(
                        widget.voiceController.state.isListening
                            ? Icons.stop_rounded
                            : Icons.mic_rounded,
                        size: 18,
                      ),
                      label: Text(
                        widget.voiceController.state.isListening
                            ? 'Hentikan & Evaluasi Suara'
                            : 'Mulai Rekam & Koreksi Bersambung',
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _isContinuousSimulating
                            ? const Color(0xFFDC2626).withOpacity(0.12)
                            : null,
                        side: BorderSide(
                          color: _isContinuousSimulating
                              ? const Color(0xFFDC2626)
                              : primaryColor,
                        ),
                      ),
                      onPressed: _toggleContinuousSimulation,
                      icon: Icon(
                        _isContinuousSimulating
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outline_rounded,
                        size: 17,
                        color: _isContinuousSimulating
                            ? const Color(0xFFDC2626)
                            : primaryColor,
                      ),
                      label: Text(
                        _isContinuousSimulating
                            ? 'Hentikan Tasmi\' Otomatis'
                            : 'Simulasi Tasmi\' Bersambung (Lintas Ayat & Surah)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _isContinuousSimulating
                              ? const Color(0xFFDC2626)
                              : primaryColor,
                        ),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _simulatePerfect,
                      child: const Text('Simulasi Bacaan Tepat (100%)'),
                    ),
                    OutlinedButton(
                      onPressed: _simulateMistake,
                      child: const Text('Simulasi Ada Kata Salah / Terlewat'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _transcriptController,
                        textDirection: TextDirection.rtl,
                        decoration: InputDecoration(
                          hintText:
                              'Transkripsi suara Arab Anda akan muncul di sini (atau ketik untuk uji koreksi per kata)...',
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: primaryColor),
                      onPressed: () => _runEvaluation(_transcriptController.text),
                      child: const Text('Evaluasi Per Kata'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildMetricPill(
                      label: _analysisResult == null
                          ? 'Akurasi: —'
                          : 'Akurasi: ${(_analysisResult!.accuracyScore * 100).round()}%',
                      bgColor: isDark ? const Color(0xFF242B28) : const Color(0xFFF1EDE4),
                      textColor: isDark ? Colors.white : const Color(0xFF1C221F),
                      borderColor: borderCard,
                    ),
                    _buildMetricPill(
                      label: 'Tepat: ${_analysisResult?.correctCount ?? 0} kata',
                      bgColor: const Color(0xFFECFDF5),
                      textColor: const Color(0xFF065F46),
                      borderColor: const Color(0xFF6EE7B7),
                    ),
                    _buildMetricPill(
                      label:
                          'Perlu Perbaikan: ${_analysisResult?.nearMissCount ?? 0} kata',
                      bgColor: const Color(0xFFFEF3C7),
                      textColor: const Color(0xFF92400E),
                      borderColor: const Color(0xFFF59E0B),
                    ),
                    _buildMetricPill(
                      label:
                          'Salah / Terlewat: ${_analysisResult?.wrongCount ?? 0} kata',
                      bgColor: const Color(0xFFFEF2F2),
                      textColor: const Color(0xFF991B1B),
                      borderColor: const Color(0xFFF87171),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Banner Transisi Otomatis ke Ayat / Surah Selanjutnya (Ala Tarteel)
          if (_autoAdvanceBannerText != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _autoAdvanceBannerIsCorrect
                    ? (isDark ? const Color(0xFF0E291E) : const Color(0xFFECFDF5))
                    : (isDark ? const Color(0xFF2E2410) : const Color(0xFFFFFBEB)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _autoAdvanceBannerIsCorrect
                      ? const Color(0xFF34D399)
                      : const Color(0xFFF59E0B),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _autoAdvanceBannerIsCorrect
                        ? Icons.check_circle_rounded
                        : Icons.info_outline_rounded,
                    color: _autoAdvanceBannerIsCorrect
                        ? const Color(0xFF059669)
                        : const Color(0xFFD97706),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _autoAdvanceBannerText!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _autoAdvanceBannerIsCorrect
                            ? (isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46))
                            : (isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _cancelPendingAutoAdvance,
                    child: const Text(
                      'Tahan di Ayat Ini',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Lembaran Mushaf Evaluasi Per Kata
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: pageBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderGold, width: 2.0),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'QS. ${verse.surahNameLatin ?? verse.surahId} : Ayat ${verse.verseNumber}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: primaryColor,
                      ),
                    ),
                    Text(
                      'Klik kata berwarna merah/kuning untuk melihat detail koreksi',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                  ],
                ),
                Divider(height: 22, color: borderGold),
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: List.generate(words.length, (idx) {
                      final w = words[idx];
                      final item = (_analysisResult != null &&
                              idx < _analysisResult!.wordItems.length)
                          ? _analysisResult!.wordItems[idx]
                          : null;
                      final isSelected = _selectedWordIdx == idx;

                      Color chipBg = surfaceColor;
                      Color chipBorder = borderCard;
                      Color tagBg = isDark ? const Color(0xFF242B28) : const Color(0xFFF1EDE4);
                      Color tagColor = textSecondary;
                      var tagText = 'Kata #${idx + 1}';

                      if (item != null) {
                        if (item.status == WordMistakeStatus.correct) {
                          chipBg = isDark
                              ? const Color(0xFF0E291E)
                              : const Color(0xFFECFDF5);
                          chipBorder = const Color(0xFF34D399);
                          tagBg = const Color(0xFFD1FAE5);
                          tagColor = const Color(0xFF065F46);
                          tagText = '✓ Tepat';
                        } else if (item.status == WordMistakeStatus.nearMiss) {
                          chipBg = isDark
                              ? const Color(0xFF2E2410)
                              : const Color(0xFFFFFBEB);
                          chipBorder = const Color(0xFFF59E0B);
                          tagBg = const Color(0xFFFEF3C7);
                          tagColor = const Color(0xFF92400E);
                          tagText = '~ Kurang Tepat';
                        } else {
                          chipBg = isDark
                              ? const Color(0xFF2D1618)
                              : const Color(0xFFFEF2F2);
                          chipBorder = const Color(0xFFF87171);
                          tagBg = const Color(0xFFFEE2E2);
                          tagColor = const Color(0xFF991B1B);
                          tagText = '✕ Salah / Terlewat';
                        }
                      }

                      final revealThis = !_blindMode ||
                          (item != null &&
                              item.status != WordMistakeStatus.wrongOrSkipped);

                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => _selectedWordIdx = idx),
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 78),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: chipBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? primaryColor : chipBorder,
                              width: isSelected ? 2.4 : 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ImageFiltered(
                                imageFilter: ImageFilter.blur(
                                  sigmaX: revealThis ? 0.0 : 8.0,
                                  sigmaY: revealThis ? 0.0 : 8.0,
                                ),
                                child: Text(
                                  w.textUthmani,
                                  style: const TextStyle(
                                    fontSize: 26,
                                    height: 1.65,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: tagBg,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  tagText,
                                  textDirection: TextDirection.ltr,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: tagColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: borderGold.withOpacity(0.5)),
                const SizedBox(height: 12),
                Text(
                  '"${verse.translationId}"',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: textSecondary),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Riwayat Hasil Bacaan Bersambung (Sesi Ini) — Memudahkan pantau ayat Benar/Salah lintas ayat & surah
          if (_sessionHistory.isNotEmpty) ...[
            _buildSessionHistoryCard(context, isDark),
            const SizedBox(height: 16),
          ],

          // Kartu Inspector Koreksi Kata Terpilih
          _buildWordInspectorCard(context, verse, words, isDark),
        ],
      ),
    );
  }

  Widget _buildSessionHistoryCard(BuildContext context, bool isDark) {
    final surfaceColor = isDark ? const Color(0xFF1B201E) : Colors.white;
    final borderCard = isDark ? const Color(0xFF323B37) : const Color(0xFFDCD5C6);
    final primaryColor = isDark ? const Color(0xFF34D399) : const Color(0xFF165B33);
    final textSecondary = isDark ? const Color(0xFFA7B0AC) : const Color(0xFF525E58);

    final correctVerses = _sessionHistory.where((h) => h.isAllCorrect).length;
    final mistakeVerses = _sessionHistory.length - correctVerses;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_edu_rounded, size: 18, color: primaryColor),
                  const SizedBox(width: 8),
                  const Text(
                    'Riwayat Tasmi\' Bersambung (Sesi Ini)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildMetricPill(
                    label: 'Total: ${_sessionHistory.length} Ayat',
                    bgColor: isDark ? const Color(0xFF242B28) : const Color(0xFFF1EDE4),
                    textColor: isDark ? Colors.white : const Color(0xFF1C221F),
                    borderColor: borderCard,
                  ),
                  _buildMetricPill(
                    label: '✓ Lancar: $correctVerses Ayat',
                    bgColor: const Color(0xFFECFDF5),
                    textColor: const Color(0xFF065F46),
                    borderColor: const Color(0xFF6EE7B7),
                  ),
                  _buildMetricPill(
                    label: '⚠️ Perlu Koreksi: $mistakeVerses Ayat',
                    bgColor: const Color(0xFFFEF2F2),
                    textColor: const Color(0xFF991B1B),
                    borderColor: const Color(0xFFF87171),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _sessionHistory.clear()),
                    child: const Text('Reset Riwayat', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Klik salah satu ayat di bawah untuk meninjau kembali detail kata yang benar/salah:',
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _sessionHistory.take(18).map((item) {
              final acc = (item.result.accuracyScore * 100).round();
              final issues = item.result.wrongCount + item.result.nearMissCount;
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  _cancelPendingAutoAdvance();
                  final currentSurahId = widget.surah?.id ??
                      (widget.verses.isNotEmpty ? widget.verses.first.surahId : 0);
                  if (item.surahId != currentSurahId && widget.onSelectSurah != null) {
                    _pendingJumpVerseNumber = item.verseNumber;
                    await widget.onSelectSurah!(item.surahId);
                  }
                  if (!mounted) return;
                  setState(() {
                    _selectedVerseNumber = item.verseNumber;
                    _analysisResult = item.result;
                    final firstIssue = item.result.wordItems.indexWhere(
                      (w) => w.status != WordMistakeStatus.correct,
                    );
                    _selectedWordIdx = firstIssue >= 0 ? firstIssue : 0;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: item.isAllCorrect
                        ? (isDark ? const Color(0xFF0E291E) : const Color(0xFFECFDF5))
                        : (isDark ? const Color(0xFF2D1618) : const Color(0xFFFEF2F2)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: item.isAllCorrect
                          ? const Color(0xFF34D399)
                          : const Color(0xFFF87171),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.isAllCorrect
                            ? Icons.check_circle_rounded
                            : Icons.warning_amber_rounded,
                        size: 14,
                        color: item.isAllCorrect
                            ? const Color(0xFF059669)
                            : const Color(0xFFDC2626),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'QS. ${item.surahNameLatin}:${item.verseNumber} • ${item.isAllCorrect ? "100% Tepat" : "$acc% ($issues koreksi)"}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: item.isAllCorrect
                              ? (isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46))
                              : (isDark ? const Color(0xFFFECACA) : const Color(0xFF991B1B)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricPill({
    required String label,
    required Color bgColor,
    required Color textColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildWordInspectorCard(
    BuildContext context,
    Verse verse,
    List<QuranWord> words,
    bool isDark,
  ) {
    final surfaceColor = isDark ? const Color(0xFF1B201E) : Colors.white;
    final subtleBg = isDark ? const Color(0xFF181D1A) : const Color(0xFFF1EDE4);
    final goldColor = isDark ? const Color(0xFFD9B36C) : const Color(0xFF9B7A38);
    final primaryColor = isDark ? const Color(0xFF34D399) : const Color(0xFF165B33);

    final safeIdx = _selectedWordIdx.clamp(0, words.length - 1);
    final word = words[safeIdx];
    final evalItem = (_analysisResult != null &&
            safeIdx < _analysisResult!.wordItems.length)
        ? _analysisResult!.wordItems[safeIdx]
        : null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: goldColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: goldColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: goldColor.withOpacity(0.45)),
                ),
                child: Text(
                  evalItem == null
                      ? 'Detail Kosakata'
                      : (evalItem.status == WordMistakeStatus.correct
                          ? '✓ Bacaan Tepat'
                          : evalItem.status == WordMistakeStatus.nearMiss
                              ? '~ Perlu Perbaikan Makhraj'
                              : '✕ Koreksi Kata Salah / Terlewat'),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: goldColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Kata ke-${safeIdx + 1} pada QS. ${verse.surahNameLatin ?? verse.surahId}:${verse.verseNumber}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: subtleBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Lafal Mushaf yang Benar (Kata #${safeIdx + 1})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        word.textUthmani,
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 24, height: 1.8),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Transliterasi: ${word.transliteration ?? "-"} • Arti: "${word.translationId.isEmpty ? "-" : word.translationId}"',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: subtleBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Hasil Simak Bacaan Anda (${evalItem != null ? "${(evalItem.similarityScore * 100).round()}% kecocokan" : "Belum diuji"})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: goldColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        evalItem?.spokenWord ?? '—',
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 24, height: 1.8),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        evalItem?.feedbackNote ??
                            'Tekan tombol Mulai Rekam atau Simulasi di atas untuk mengevaluasi ketepatan pelafalan kata ini.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: primaryColor),
            onPressed: () => widget.murattalAudioService.playVerse(
              surahId: verse.surahId,
              verseNumber: verse.verseNumber,
              surahName: verse.surahNameLatin,
            ),
            icon: const Icon(Icons.volume_up_rounded, size: 17),
            label: Text(
              'Dengarkan Contoh Lafal Qari (QS. ${verse.surahNameLatin ?? verse.surahId}:${verse.verseNumber})',
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 4. TAB 4: RADAR MUTASYABIHAT & EDITOR MEMORY ANCHOR (IDENTIK WEB)
// =============================================================================

class MutasyabihatRadarView extends StatefulWidget {
  final List<MutasyabihatComparisonPair> pairs;
  final MutasyabihatScope selectedScope;
  final int selectedJuz;
  final QuranMurattalAudioService murattalAudioService;
  final void Function(MutasyabihatScope scope) onScopeChanged;
  final void Function(int juz) onJuzChanged;
  final Future<void> Function(int groupId, String note) onSaveMemoryAnchor;

  const MutasyabihatRadarView({
    super.key,
    required this.pairs,
    required this.selectedScope,
    required this.selectedJuz,
    required this.murattalAudioService,
    required this.onScopeChanged,
    required this.onJuzChanged,
    required this.onSaveMemoryAnchor,
  });

  @override
  State<MutasyabihatRadarView> createState() => _MutasyabihatRadarViewState();
}

class _MutasyabihatRadarViewState extends State<MutasyabihatRadarView> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1B201E) : Colors.white;
    final borderCard = isDark ? const Color(0xFF323B37) : const Color(0xFFDCD5C6);
    final primaryColor = isDark ? const Color(0xFF34D399) : const Color(0xFF165B33);
    final textSecondary = isDark ? const Color(0xFFA7B0AC) : const Color(0xFF525E58);

    final filtered = widget.pairs.where((p) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return p.title.toLowerCase().contains(q) ||
          p.surahName1.toLowerCase().contains(q) ||
          p.surahName2.toLowerCase().contains(q) ||
          p.textUthmani1.contains(q) ||
          p.textUthmani2.contains(q);
    }).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      children: [
        // Header Radar Mutasyabihat (Persis .radar-header-card di Web)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Radar Mutasyabihat',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Memetakan pasangan ayat serupa di Juz 28, 29, dan 30 agar hafalan Anda tidak tertukar atau melompat surah.',
                style: TextStyle(fontSize: 13.5, color: textSecondary),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 420,
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        hintText: 'Cari nama surah atau potongan ayat...',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Semua (Juz 28-30)'),
                        selected:
                            widget.selectedScope == MutasyabihatScope.all,
                        onSelected: (_) =>
                            widget.onScopeChanged(MutasyabihatScope.all),
                      ),
                      ChoiceChip(
                        label: const Text('Juz 30'),
                        selected:
                            widget.selectedScope == MutasyabihatScope.withinOneJuz &&
                                widget.selectedJuz == 30,
                        onSelected: (_) {
                          widget.onJuzChanged(30);
                          widget.onScopeChanged(MutasyabihatScope.withinOneJuz);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Juz 29'),
                        selected:
                            widget.selectedScope == MutasyabihatScope.withinOneJuz &&
                                widget.selectedJuz == 29,
                        onSelected: (_) {
                          widget.onJuzChanged(29);
                          widget.onScopeChanged(MutasyabihatScope.withinOneJuz);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Juz 28'),
                        selected:
                            widget.selectedScope == MutasyabihatScope.withinOneJuz &&
                                widget.selectedJuz == 28,
                        onSelected: (_) {
                          widget.onJuzChanged(28);
                          widget.onScopeChanged(MutasyabihatScope.withinOneJuz);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Surah Ini'),
                        selected:
                            widget.selectedScope == MutasyabihatScope.withinOneSurah,
                        onSelected: (_) =>
                            widget.onScopeChanged(MutasyabihatScope.withinOneSurah),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderCard),
            ),
            child: Center(
              child: Text(
                'Tidak ditemukan pasangan ayat mirip untuk filter ini.',
                style: TextStyle(color: textSecondary),
              ),
            ),
          )
        else
          ...filtered.map(
            (pair) => _buildWebComparisonCard(
              context,
              pair,
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderCard: borderCard,
              primaryColor: primaryColor,
              textSecondary: textSecondary,
            ),
          ),
      ],
    );
  }

  Widget _buildWebComparisonCard(
    BuildContext context,
    MutasyabihatComparisonPair pair, {
    required bool isDark,
    required Color surfaceColor,
    required Color borderCard,
    required Color primaryColor,
    required Color textSecondary,
  }) {
    final goldColor = isDark ? const Color(0xFFD9B36C) : const Color(0xFF9B7A38);
    final subtleBg = isDark ? const Color(0xFF181D1A) : const Color(0xFFF1EDE4);
    final borderSubtle = isDark ? const Color(0xFF262D2A) : const Color(0xFFE6E1D6);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  pair.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: goldColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: goldColor.withOpacity(0.45)),
                ),
                child: Text(
                  'Juz ${pair.juzNumber1}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: goldColor,
                  ),
                ),
              ),
            ],
          ),
          Divider(height: 22, color: borderSubtle),
          LayoutBuilder(
            builder: (context, constraints) {
              final box1 = _buildWebVerseBox(
                surahId: pair.surahId1,
                surahName: pair.surahName1,
                verseNumber: pair.verseNumber1,
                uthmaniText: pair.textUthmani1,
                diffPositions: pair.diffWordPositions1,
                nextVersePreview: pair.nextVerseStartWords1,
                isDark: isDark,
                subtleBg: subtleBg,
                borderSubtle: borderSubtle,
                primaryColor: primaryColor,
                goldColor: goldColor,
                textSecondary: textSecondary,
              );
              final box2 = _buildWebVerseBox(
                surahId: pair.surahId2,
                surahName: pair.surahName2,
                verseNumber: pair.verseNumber2,
                uthmaniText: pair.textUthmani2,
                diffPositions: pair.diffWordPositions2,
                nextVersePreview: pair.nextVerseStartWords2,
                isDark: isDark,
                subtleBg: subtleBg,
                borderSubtle: borderSubtle,
                primaryColor: primaryColor,
                goldColor: goldColor,
                textSecondary: textSecondary,
              );
              if (constraints.maxWidth >= 680) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: box1),
                    const SizedBox(width: 14),
                    Expanded(child: box2),
                  ],
                );
              }
              return Column(
                children: [
                  box1,
                  const SizedBox(height: 12),
                  box2,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: goldColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: goldColor.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'JEMBATAN INGATAN (MEMORY ANCHOR)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: goldColor,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pair.userMemoryNote?.isNotEmpty == true
                            ? pair.userMemoryNote!
                            : 'Belum ada rumus catatan. Klik Ubah Rumus untuk menambahkan pengingat pribadi.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: () => _showEditMemoryAnchorDialog(context, pair),
                  child: const Text('Ubah Rumus', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebVerseBox({
    required int surahId,
    required String surahName,
    required int verseNumber,
    required String uthmaniText,
    required List<int> diffPositions,
    required String nextVersePreview,
    required bool isDark,
    required Color subtleBg,
    required Color borderSubtle,
    required Color primaryColor,
    required Color goldColor,
    required Color textSecondary,
  }) {
    final words = uthmaniText.split(' ').where((w) => w.isNotEmpty).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: subtleBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'QS. $surahName : Ayat $verseNumber',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: primaryColor,
                ),
              ),
              TextButton(
                onPressed: () => widget.murattalAudioService.playVerse(
                  surahId: surahId,
                  verseNumber: verseNumber,
                  surahName: surahName,
                ),
                child: const Text('▶ Putar', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(words.length, (idx) {
                final isDiff = diffPositions.contains(idx + 1);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDiff ? goldColor.withOpacity(0.18) : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: isDiff
                        ? Border(bottom: BorderSide(color: goldColor, width: 2))
                        : null,
                  ),
                  child: Text(
                    words[idx],
                    style: TextStyle(
                      fontSize: 22,
                      height: 1.85,
                      fontWeight: isDiff ? FontWeight.w700 : FontWeight.w500,
                      color: isDiff ? goldColor : null,
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: borderSubtle),
          const SizedBox(height: 8),
          Text(
            'Ayat selanjutnya: $nextVersePreview',
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditMemoryAnchorDialog(
    BuildContext context,
    MutasyabihatComparisonPair pair,
  ) async {
    final controller = TextEditingController(text: pair.userMemoryNote ?? '');
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Jembatan Ingatan (Rumus Anti-Tertukar)'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText:
                  'Contoh: An-Nazi\'at (79) pakai huruf Tha (الطَّامَّةُ), sedangkan \'Abasa (80) pakai huruf Shad (الصَّاخَّةُ)...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                await widget.onSaveMemoryAnchor(pair.groupId, controller.text);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Simpan Rumus'),
            ),
          ],
        );
      },
    );
  }
}

// =============================================================================
// 5. TAB 5: MODE DRILL SAMBUNG AYAT (IDENTIK .drill-card DI WEB)
// =============================================================================

class MutasyabihatDrillView extends StatefulWidget {
  final QuranHifzRepository repository;
  final int juzNumber;

  const MutasyabihatDrillView({
    super.key,
    required this.repository,
    required this.juzNumber,
  });

  @override
  State<MutasyabihatDrillView> createState() => _MutasyabihatDrillViewState();
}

class _MutasyabihatDrillViewState extends State<MutasyabihatDrillView> {
  List<MutasyabihatDrillQuestion> _questions = const [];
  int _currentIndex = 0;
  int _score = 0;
  bool? _lastAnswerCorrect;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    setState(() => _isLoading = true);
    final q = await widget.repository.generateDrillQuestions(
      juzNumber: widget.juzNumber,
      limit: 30,
    );
    if (!mounted) return;
    setState(() {
      _questions = q;
      _currentIndex = 0;
      _score = 0;
      _lastAnswerCorrect = null;
      _isLoading = false;
    });
  }

  void _submitChoice(bool choseCorrectContinuation) {
    HapticFeedback.mediumImpact();
    setState(() {
      _lastAnswerCorrect = choseCorrectContinuation;
      if (choseCorrectContinuation) _score++;
    });
  }

  void _nextQuestion() {
    setState(() {
      _lastAnswerCorrect = null;
      if (_currentIndex + 1 < _questions.length) {
        _currentIndex++;
      } else {
        _currentIndex = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_questions.isEmpty) {
      return const Center(
        child: Text('Belum ada soal Drill Mutasyabihat untuk Juz ini.'),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1B201E) : Colors.white;
    final pageBg = isDark ? const Color(0xFF1A201E) : const Color(0xFFFCFAF6);
    final borderCard = isDark ? const Color(0xFF323B37) : const Color(0xFFDCD5C6);
    final borderGold = isDark ? const Color(0xFF785E2B) : const Color(0xFFC8AA76);
    final primaryColor = isDark ? const Color(0xFF34D399) : const Color(0xFF165B33);
    final primarySubtle = isDark ? const Color(0xFF132A20) : const Color(0xFFEBF4EE);
    final textSecondary = isDark ? const Color(0xFFA7B0AC) : const Color(0xFF525E58);

    final q = _questions[_currentIndex];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: primarySubtle,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Latihan Sambung Ayat',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: primaryColor,
                    ),
                  ),
                ),
                Text(
                  'Skor: $_score / ${_currentIndex + (_lastAnswerCorrect != null ? 1 : 0)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: pageBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderGold),
              ),
              child: Column(
                children: [
                  Text(
                    'Anda sedang membaca QS. ${q.promptSurahName} : Ayat ${q.promptVerseNumber}',
                    style: TextStyle(fontSize: 13, color: textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    q.promptVerseUthmani,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, height: 1.9),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Pilihlah awal ayat selanjutnya yang tepat:',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildDrillOptionBtn(
                    tag: 'A',
                    textUthmani: q.correctContinuationUthmani,
                    onTap: () => _submitChoice(true),
                    surfaceColor: surfaceColor,
                    borderCard: borderCard,
                    primaryColor: primaryColor,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildDrillOptionBtn(
                    tag: 'B',
                    textUthmani: q.trapContinuationUthmani,
                    onTap: () => _submitChoice(false),
                    surfaceColor: surfaceColor,
                    borderCard: borderCard,
                    primaryColor: primaryColor,
                  ),
                ),
              ],
            ),
            if (_lastAnswerCorrect != null) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _lastAnswerCorrect!
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _lastAnswerCorrect!
                        ? const Color(0xFF6EE7B7)
                        : const Color(0xFFFECACA),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _lastAnswerCorrect!
                          ? 'Jawaban Tepat'
                          : 'Perhatian: Pilihan Keliru',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: _lastAnswerCorrect!
                            ? const Color(0xFF15803D)
                            : const Color(0xFFB91C1C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _lastAnswerCorrect!
                          ? 'Anda berhasil melanjutkan ayat tanpa terjebak ke surah ${q.trapSurahName}.'
                          : 'Itu adalah lanjutan milik QS. ${q.trapSurahName} : ${q.trapVerseNumber}.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1C221F),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: primaryColor),
                      onPressed: _nextQuestion,
                      child: const Text('Soal Selanjutnya'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDrillOptionBtn({
    required String tag,
    required String textUthmani,
    required VoidCallback onTap,
    required Color surfaceColor,
    required Color borderCard,
    required Color primaryColor,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _lastAnswerCorrect == null ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderCard, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: borderCard),
                ),
                child: Text(
                  tag,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              textUthmani,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 22, height: 1.8),
            ),
          ],
        ),
      ),
    );
  }
}
