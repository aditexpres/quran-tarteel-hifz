// quran_hifz_app.dart
// =============================================================================
// UI/Widget Utama Aplikasi Qur'an Tarteel Lintas Platform (Android, Windows, macOS)
// Terintegrasi Penuh dengan:
// - [Opsi 3] Tampilan Mushaf Madinah 15 Baris & Pemutar Audio Murattal Auto-Koreksi
// - [Opsi 2] Perekam Mikrofon Real-Time (PCM 16kHz + VAD) & Pengunduh Model Whisper AI
// - [Opsi 1] Konfigurasi Lintas Platform Android, Windows, & macOS
// =============================================================================

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

class QuranTarteelHifzApp extends StatelessWidget {
  const QuranTarteelHifzApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Qur\'an Tarteel & Radar Mutasyabihat',
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
        dividerColor: const Color(0xFFE5DFD0),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: Color(0xFF22C55E),
          onPrimary: Color(0xFF052E16),
          secondary: Color(0xFFC7A356),
          onSecondary: Color(0xFF1C1608),
          error: Color(0xFFEF4444),
          onError: Colors.white,
          surface: Color(0xFF1B201D),
          onSurface: Color(0xFFECE7DE),
        ),
        scaffoldBackgroundColor: const Color(0xFF131615), // Tahajjud Stone
        cardColor: const Color(0xFF202623),
        dividerColor: const Color(0xFF2D3631),
      ),
      themeMode: ThemeMode.system,
      home: const QuranHifzHomeScreen(),
    );
  }
}

// =============================================================================
// 1. HOME SCREEN LINTAS PLATFORM (SPLIT-SCREEN DESKTOP & BOTTOM NAV ANDROID)
// =============================================================================

class QuranHifzHomeScreen extends StatefulWidget {
  const QuranHifzHomeScreen({super.key});

  @override
  State<QuranHifzHomeScreen> createState() => _QuranHifzHomeScreenState();
}

class _QuranHifzHomeScreenState extends State<QuranHifzHomeScreen> {
  final QuranHifzRepository _repository = QuranHifzRepository();
  late final QuranMurattalAudioService _murattalAudioService;
  late final WhisperVoiceHifzController _voiceController;
  final FocusNode _keyboardFocusNode = FocusNode();

  int _selectedNavIndex = 0;
  int _selectedJuz = 30;
  int _selectedSurahId = 79; // Default: QS. An-Nazi'at
  bool _hideVerseMode = true;
  bool _showWordByWord = true;
  bool _isMushaf15LineMode = true; // Default menampilkan Mushaf 15 Baris (Opsi 3)

  List<Surah> _surahs = const [];
  List<Verse> _verses = const [];
  List<MutasyabihatComparisonPair> _mutasyabihatPairs = const [];
  MutasyabihatScope _selectedScope = MutasyabihatScope.withinOneJuz;
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
        final defaultVerse = verses.firstWhere(
          (v) => v.verseNumber == 33,
          orElse: () => verses.first,
        );
        await _voiceController.setActiveVerse(
          defaultVerse,
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
      _isLoading = true;
    });
    final verses = await _repository.getVerses(
      surahId: newSurahId,
      includeWords: true,
    );
    if (!mounted) return;
    setState(() {
      _verses = verses;
      _isLoading = false;
    });
    if (verses.isNotEmpty) {
      await _voiceController.setActiveVerse(
        verses.first,
        revealAllInitially: !_hideVerseMode,
      );
    }
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

  @override
  void dispose() {
    _murattalAudioService.dispose();
    _voiceController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktopSplit = screenWidth >= 960;

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
        appBar: _buildTopAppBar(),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : isDesktopSplit
                ? _buildDesktopSplitLayout()
                : _buildMobileTabLayout(),
        bottomNavigationBar: isDesktopSplit
            ? null
            : NavigationBar(
                selectedIndex: _selectedNavIndex,
                onDestinationSelected: (idx) =>
                    setState(() => _selectedNavIndex = idx),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.menu_book_outlined),
                    selectedIcon: Icon(Icons.menu_book_rounded),
                    label: 'Mushaf 15 Baris',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.auto_awesome_outlined),
                    selectedIcon: Icon(Icons.auto_awesome_rounded),
                    label: 'Mushaf Bertanda',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.radar_outlined),
                    selectedIcon: Icon(Icons.radar_rounded),
                    label: 'Radar',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.quiz_outlined),
                    selectedIcon: Icon(Icons.quiz_rounded),
                    label: 'Drill',
                  ),
                ],
              ),
      ),
    );
  }

  PreferredSizeWidget _buildTopAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0F172A),
      title: Row(
        children: [
          const Icon(Icons.auto_stories_rounded, color: Color(0xFF2DD4BF)),
          const SizedBox(width: 10),
          const Text(
            'Qur\'an Tarteel Hifz',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(width: 16),
          if (_surahs.isNotEmpty)
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _surahs.any((s) => s.id == _selectedSurahId)
                    ? _selectedSurahId
                    : _surahs.first.id,
                dropdownColor: const Color(0xFF1E293B),
                items: _surahs
                    .map(
                      (s) => DropdownMenuItem<int>(
                        value: s.id,
                        child: Text(
                          '${s.id}. ${s.nameLatin} (${s.nameArabic})',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) _onSurahChanged(val);
                },
              ),
            ),
        ],
      ),
      actions: [
        FilterChip(
          label: const Text('Mushaf 15 Baris'),
          selected: _isMushaf15LineMode,
          onSelected: (val) => setState(() => _isMushaf15LineMode = val),
        ),
        const SizedBox(width: 8),
        FilterChip(
          label: const Text('Hide Verse'),
          selected: _hideVerseMode,
          onSelected: (val) {
            setState(() => _hideVerseMode = val);
            if (val) {
              _voiceController.hideAllWords();
            } else {
              _voiceController.revealAllWords();
            }
          },
        ),
        const SizedBox(width: 8),
        FilterChip(
          label: const Text('Perkata'),
          selected: _showWordByWord,
          onSelected: (val) => setState(() => _showWordByWord = val),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Periksa Pembaruan Aplikasi',
          icon: const Icon(Icons.system_update_rounded),
          onPressed: () => AppUpdateService.manualCheck(context),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Pengaturan Model AI Whisper & Mikrofon',
          icon: const Icon(Icons.downloading_rounded),
          onPressed: _showWhisperModelManagerDialog,
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _buildDesktopSplitLayout() {
    return Row(
      children: [
        NavigationRail(
          selectedIndex: _selectedNavIndex,
          onDestinationSelected: (idx) =>
              setState(() => _selectedNavIndex = idx),
          labelType: NavigationRailLabelType.all,
          destinations: const [
            NavigationRailDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book_rounded),
              label: Text('15 Baris'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome_rounded),
              label: Text('Bertanda'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.radar_outlined),
              selectedIcon: Icon(Icons.radar_rounded),
              label: Text('Mutasyabihat'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.quiz_outlined),
              selectedIcon: Icon(Icons.quiz_rounded),
              label: Text('Mode Drill'),
            ),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 6,
          child: _selectedNavIndex == 3
              ? MutasyabihatDrillView(
                  repository: _repository,
                  juzNumber: _selectedJuz,
                )
              : _selectedNavIndex == 1
                  ? MarkedMushafMutasyabihatView(
                      verses: _verses,
                      pairs: _mutasyabihatPairs,
                      murattalAudioService: _murattalAudioService,
                    )
                  : MushafVoiceHifzView(
                      verses: _verses,
                      voiceController: _voiceController,
                      murattalAudioService: _murattalAudioService,
                      hideVerseMode: _hideVerseMode,
                      showWordByWord: _showWordByWord,
                      isMushaf15LineMode: _isMushaf15LineMode,
                      onShowTafsir: _showTafsirBottomSheet,
                    ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 5,
          child: MutasyabihatRadarView(
            pairs: _mutasyabihatPairs,
            selectedScope: _selectedScope,
            selectedJuz: _selectedJuz,
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
      ],
    );
  }

  Widget _buildMobileTabLayout() {
    switch (_selectedNavIndex) {
      case 0:
        return MushafVoiceHifzView(
          verses: _verses,
          voiceController: _voiceController,
          murattalAudioService: _murattalAudioService,
          hideVerseMode: _hideVerseMode,
          showWordByWord: _showWordByWord,
          isMushaf15LineMode: _isMushaf15LineMode,
          onShowTafsir: _showTafsirBottomSheet,
        );
      case 1:
        return MarkedMushafMutasyabihatView(
          verses: _verses,
          pairs: _mutasyabihatPairs,
          murattalAudioService: _murattalAudioService,
        );
      case 2:
        return MutasyabihatRadarView(
          pairs: _mutasyabihatPairs,
          selectedScope: _selectedScope,
          selectedJuz: _selectedJuz,
          onScopeChanged: (scope) => _refreshMutasyabihatRadar(scope: scope),
          onJuzChanged: (juz) => _refreshMutasyabihatRadar(juzNumber: juz),
          onSaveMemoryAnchor: (groupId, note) async {
            await _repository.saveMemoryAnchor(
              groupId: groupId,
              userNote: note,
            );
            await _refreshMutasyabihatRadar();
          },
        );
      case 3:
      default:
        return MutasyabihatDrillView(
          repository: _repository,
          juzNumber: _selectedJuz,
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
              backgroundColor: const Color(0xFF1E293B),
              title: const Text('Model AI Whisper Al-Qur\'an & Mikrofon'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pilih Model On-Device (Hugging Face Tarteel AI):',
                      style: TextStyle(fontSize: 13, color: Colors.white70),
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
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF2DD4BF),
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
      backgroundColor: const Color(0xFF1E293B),
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
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2DD4BF),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                verse.textUthmani,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontSize: 24, height: 1.8),
              ),
              const Divider(height: 24, color: Color(0xFF334155)),
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
// 2. WIDGET MUSHAF (15 BARIS & LIST) + VOICE HIFZ + MURATTAL AUTO-KOREKSI
// =============================================================================

class MushafVoiceHifzView extends StatelessWidget {
  final List<Verse> verses;
  final WhisperVoiceHifzController voiceController;
  final QuranMurattalAudioService murattalAudioService;
  final bool hideVerseMode;
  final bool showWordByWord;
  final bool isMushaf15LineMode;
  final void Function(Verse verse) onShowTafsir;

  const MushafVoiceHifzView({
    super.key,
    required this.verses,
    required this.voiceController,
    required this.murattalAudioService,
    required this.hideVerseMode,
    required this.showWordByWord,
    required this.isMushaf15LineMode,
    required this.onShowTafsir,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: voiceController,
      builder: (context, _) {
        final state = voiceController.state;

        return Column(
          children: [
            // Banner peringatan merah jika terdeteksi Trap Jump
            if (state.evaluationResult != null)
              _buildEvaluationAlertBanner(state.evaluationResult!),

            // [Integrasi Opsi 3]: Beralih antara Mushaf Madinah 15 Baris vs Mode Kartu Ayat
            Expanded(
              child: isMushaf15LineMode
                  ? Mushaf15LinePageWidget(
                      verses: verses,
                      activeVerseId: state.activeVerseId,
                      revealedWordPosition: state.revealedWordPosition,
                      hideVerseMode: hideVerseMode,
                      onSelectVerse: (verse) => voiceController.setActiveVerse(
                        verse,
                        revealAllInitially: !hideVerseMode,
                      ),
                      onPlayVerseAudio: (verse) =>
                          murattalAudioService.playVerse(
                        surahId: verse.surahId,
                        verseNumber: verse.verseNumber,
                        surahName: verse.surahNameLatin,
                      ),
                      onShowTafsir: onShowTafsir,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: verses.length,
                      itemBuilder: (context, index) {
                        final verse = verses[index];
                        final isActive = verse.id == state.activeVerseId;
                        return _buildVerseCard(context, verse, isActive, state);
                      },
                    ),
            ),

            // [Integrasi Opsi 3]: Mini Player Audio Murattal & Auto-Koreksi Trap Jump
            MurattalMiniPlayerDock(
              audioService: murattalAudioService,
              activeVerse: voiceController.currentVerse,
            ),

            // Control Bar Voice Hifz & Indikator Level Suara VAD (Opsi 2)
            _buildVoiceControlDock(context, state),
          ],
        );
      },
    );
  }

  Widget _buildEvaluationAlertBanner(VoiceEvaluationResult result) {
    final isTrap = result.isTrapJump;
    final bgColor = isTrap ? const Color(0xFF7F1D1D) : const Color(0xFF064E3B);
    final borderColor =
        isTrap ? const Color(0xFFEF4444) : const Color(0xFF10B981);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(
            isTrap ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
            color: Colors.white,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isTrap
                      ? 'PERINGATAN JEBAKAN MUTASYABIHAT (LOMPAT SURAH)!'
                      : 'Transisi Ayat Tepat',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  result.warningMessage,
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerseCard(
    BuildContext context,
    Verse verse,
    bool isActive,
    VoiceHifzSessionState state,
  ) {
    final words = verse.words.isNotEmpty
        ? verse.words
        : verse.textUthmani
            .split(' ')
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

    return GestureDetector(
      onTap: () => voiceController.setActiveVerse(
        verse,
        revealAllInitially: !hideVerseMode,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? const Color(0xFF2DD4BF) : const Color(0xFF1E293B),
            width: isActive ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withOpacity(0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'QS. ${verse.surahNameLatin ?? verse.surahId} : ${verse.verseNumber}  •  Juz ${verse.juzNumber}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2DD4BF),
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Putar Murattal Ayat Ini',
                      icon: const Icon(Icons.volume_up_rounded, size: 18),
                      onPressed: () => murattalAudioService.playVerse(
                        surahId: verse.surahId,
                        verseNumber: verse.verseNumber,
                        surahName: verse.surahNameLatin,
                      ),
                    ),
                    if (isActive && hideVerseMode)
                      TextButton.icon(
                        onPressed: voiceController.peekNextWord,
                        icon: const Icon(Icons.visibility_outlined, size: 16),
                        label: const Text('Peek Kata (Spasi)'),
                      ),
                    IconButton(
                      tooltip: 'Lihat Tafsir Wajiz',
                      icon: const Icon(Icons.library_books_outlined, size: 18),
                      onPressed: () => onShowTafsir(verse),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Wrap(
                spacing: 10,
                runSpacing: 12,
                children: words.map((word) {
                  final isWordRevealed = !hideVerseMode ||
                      !isActive ||
                      word.wordPosition <= state.revealedWordPosition;
                  return _buildWordChip(word, isWordRevealed);
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              verse.translationId,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWordChip(QuranWord word, bool isRevealed) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1120),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isRevealed
              ? const Color(0xFF334155)
              : const Color(0xFF0F766E).withOpacity(0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: isRevealed ? 0.0 : 8.0,
              sigmaY: isRevealed ? 0.0 : 8.0,
            ),
            child: Text(
              word.textUthmani,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          if (showWordByWord && word.translationId.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              isRevealed ? word.translationId : '•••',
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVoiceControlDock(
    BuildContext context,
    VoiceHifzSessionState state,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.isListening)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: state.micRmsLevel,
                  minHeight: 5,
                  backgroundColor: const Color(0xFF1E293B),
                  color: const Color(0xFF2DD4BF),
                ),
              ),
            ),
          if (state.statusMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                state.statusMessage!,
                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                textAlign: TextAlign.center,
              ),
            ),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: state.isListening
                    ? voiceController.stopListening
                    : voiceController.startListening,
                icon: Icon(
                  state.isListening ? Icons.stop_rounded : Icons.mic_rounded,
                ),
                label: Text(
                  state.isListening ? 'Stop Menyimak' : 'Mulai Voice Hifz',
                ),
              ),
              OutlinedButton.icon(
                onPressed: voiceController.peekNextWord,
                icon: const Icon(Icons.visibility_rounded, size: 18),
                label: Text(
                  'Intip Kata (${state.revealedWordPosition}/${state.totalWordsInVerse})',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => voiceController.runInteractiveSimulation(
                  simulateTrapJump: false,
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Simulasi Baca Benar'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF87171),
                ),
                onPressed: () => voiceController.runInteractiveSimulation(
                  simulateTrapJump: true,
                ),
                icon: const Icon(Icons.warning_amber_rounded, size: 18),
                label: const Text('Simulasi Jebakan Lompat Surah'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 3. WIDGET RADAR MUTASYABIHAT & EDITOR MEMORY ANCHOR
// =============================================================================

class MutasyabihatRadarView extends StatelessWidget {
  final List<MutasyabihatComparisonPair> pairs;
  final MutasyabihatScope selectedScope;
  final int selectedJuz;
  final void Function(MutasyabihatScope scope) onScopeChanged;
  final void Function(int juz) onJuzChanged;
  final Future<void> Function(int groupId, String note) onSaveMemoryAnchor;

  const MutasyabihatRadarView({
    super.key,
    required this.pairs,
    required this.selectedScope,
    required this.selectedJuz,
    required this.onScopeChanged,
    required this.onJuzChanged,
    required this.onSaveMemoryAnchor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          color: const Color(0xFF0F172A),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('Dalam 1 Juz (Prioritas)'),
                selected: selectedScope == MutasyabihatScope.withinOneJuz,
                onSelected: (_) =>
                    onScopeChanged(MutasyabihatScope.withinOneJuz),
              ),
              ChoiceChip(
                label: const Text('Dalam 1 Surah'),
                selected: selectedScope == MutasyabihatScope.withinOneSurah,
                onSelected: (_) =>
                    onScopeChanged(MutasyabihatScope.withinOneSurah),
              ),
              ChoiceChip(
                label: const Text('Lintas Juz'),
                selected: selectedScope == MutasyabihatScope.crossJuz,
                onSelected: (_) => onScopeChanged(MutasyabihatScope.crossJuz),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: selectedJuz,
                dropdownColor: const Color(0xFF1E293B),
                items: List.generate(
                  30,
                  (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text('Juz ${i + 1}'),
                  ),
                ),
                onChanged: (val) {
                  if (val != null) onJuzChanged(val);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: pairs.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Tidak ditemukan pasangan ayat mirip pada filter ruang lingkup ini.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: pairs.length,
                  itemBuilder: (context, index) {
                    return _buildComparisonCard(context, pairs[index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildComparisonCard(
    BuildContext context,
    MutasyabihatComparisonPair pair,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            pair.title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Color(0xFF2DD4BF),
            ),
          ),
          const SizedBox(height: 12),
          _buildHighlightedVerseRow(
            surahLabel: 'QS. ${pair.surahName1}: ${pair.verseNumber1}',
            uthmaniText: pair.textUthmani1,
            diffPositions: pair.diffWordPositions1,
            nextVersePreview: pair.nextVerseStartWords1,
            accentColor: const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 10),
          _buildHighlightedVerseRow(
            surahLabel: 'QS. ${pair.surahName2}: ${pair.verseNumber2}',
            uthmaniText: pair.textUthmani2,
            diffPositions: pair.diffWordPositions2,
            nextVersePreview: pair.nextVerseStartWords2,
            accentColor: const Color(0xFFF43F5E),
          ),
          const Divider(height: 24, color: Color(0xFF334155)),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: Color(0xFFFBBF24),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    pair.userMemoryNote?.isNotEmpty == true
                        ? pair.userMemoryNote!
                        : 'Belum ada rumus Jembatan Ingatan. Ketuk tombol pensil untuk menambahkan rumus hafalan pribadi Anda.',
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
                IconButton(
                  tooltip: 'Ubah Jembatan Ingatan',
                  icon: const Icon(Icons.edit_note_rounded, size: 20),
                  onPressed: () => _showEditMemoryAnchorDialog(context, pair),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightedVerseRow({
    required String surahLabel,
    required String uthmaniText,
    required List<int> diffPositions,
    required String nextVersePreview,
    required Color accentColor,
  }) {
    final words = uthmaniText.split(' ').where((w) => w.isNotEmpty).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1120),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            surahLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 8),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(words.length, (idx) {
                final pos1Based = idx + 1;
                final isDiff = diffPositions.contains(pos1Based);
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDiff
                        ? accentColor.withOpacity(0.25)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: isDiff ? Border.all(color: accentColor) : null,
                  ),
                  child: Text(
                    words[idx],
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: isDiff ? FontWeight.bold : FontWeight.normal,
                      color: isDiff ? Colors.white : Colors.white60,
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.subdirectory_arrow_left_rounded,
                size: 15,
                color: Color(0xFF94A3B8),
              ),
              const SizedBox(width: 6),
              const Text(
                'Ayat selanjutnya: ',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
              Expanded(
                child: Text(
                  nextVersePreview,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
              ),
            ],
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
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Rumus Jembatan Ingatan (Memory Anchor)'),
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
                await onSaveMemoryAnchor(pair.groupId, controller.text);
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
// 4. WIDGET MODE DRILL "JEBAKAN MUTASYABIHAT" (KUIS SAMBUNG AYAT 1 JUZ)
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
        child: Text(
          'Belum ada soal Drill Mutasyabihat untuk Juz ini.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final q = _questions[_currentIndex];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Mode Drill Jebakan Mutasyabihat • Juz ${widget.juzNumber}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2DD4BF),
                ),
              ),
              Chip(
                label: Text(
                  'Skor: $_score / ${_questions.length}  (Soal ${_currentIndex + 1})',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  'Anda sedang membaca QS. ${q.promptSurahName} : ${q.promptVerseNumber}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFBBF24),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  q.promptVerseUthmani,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, height: 1.7),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Manakah awal ayat selanjutnya yang BENAR agar tidak melompat ke surah lain?',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildOptionButton(
            textUthmani: q.correctContinuationUthmani,
            onTap: () => _submitChoice(true),
          ),
          const SizedBox(height: 12),
          _buildOptionButton(
            textUthmani: q.trapContinuationUthmani,
            onTap: () => _submitChoice(false),
          ),
          if (_lastAnswerCorrect != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _lastAnswerCorrect!
                    ? const Color(0xFF064E3B)
                    : const Color(0xFF7F1D1D),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _lastAnswerCorrect!
                        ? 'Tepat! Anda tidak terjebak lompat surah.'
                        : 'Hati-hati! Itu adalah lanjutan milik QS. ${q.trapSurahName}: ${q.trapVerseNumber}.',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (q.memoryAnchorHint != null &&
                      q.memoryAnchorHint!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Jembatan Ingatan: ${q.memoryAnchorHint}',
                      style:
                          const TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _nextQuestion,
                      child: const Text('Soal Berikutnya'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionButton({
    required String textUthmani,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _lastAnswerCorrect == null ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Text(
          textUthmani,
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}