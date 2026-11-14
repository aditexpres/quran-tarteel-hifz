// lib/marked_mushaf_view.dart
// ==============================================================================
// Mode Tampilan: Mushaf Bertanda Mutasyabihat (Anti-Tertukar)
// Membaca Al-Qur'an secara full dengan fitur Zoom In/Out & Pinch-to-Zoom,
// dengan penanda warna khusus pada ayat mutasyabihat.
// ==============================================================================

import 'package:flutter/material.dart';
import 'mushaf_15line_and_audio.dart';
import 'quran_hifz_repository.dart';

class MarkedMushafMutasyabihatView extends StatefulWidget {
  final List<Verse> verses;
  final List<MutasyabihatComparisonPair> pairs;
  final QuranMurattalAudioService murattalAudioService;
  final List<Surah> surahs;
  final int currentSurahId;
  final void Function(int surahId)? onSelectSurah;
  final VoidCallback? onPrevSurah;
  final VoidCallback? onNextSurah;
  final String? prevSurahName;
  final String? nextSurahName;

  const MarkedMushafMutasyabihatView({
    super.key,
    required this.verses,
    required this.pairs,
    required this.murattalAudioService,
    this.surahs = const [],
    this.currentSurahId = 1,
    this.onSelectSurah,
    this.onPrevSurah,
    this.onNextSurah,
    this.prevSurahName,
    this.nextSurahName,
  });

  @override
  State<MarkedMushafMutasyabihatView> createState() =>
      _MarkedMushafMutasyabihatViewState();
}

class _MarkedMushafMutasyabihatViewState
    extends State<MarkedMushafMutasyabihatView> {
  Verse? _selectedVerse;
  MutasyabihatComparisonPair? _selectedPair;
  double _zoomScale = 1.0;
  bool _scrollWheelDirectZoom = false;

  void _updateZoom(double newScale) {
    final clamped = newScale.clamp(0.60, 2.50);
    setState(() {
      _zoomScale = clamped;
    });
  }

  void _resetZoom() {
    setState(() {
      _zoomScale = 1.0;
    });
  }

  MutasyabihatComparisonPair? _findPairForVerse(Verse verse) {
    for (final pair in widget.pairs) {
      if ((pair.surahId1 == verse.surahId &&
              pair.verseNumber1 == verse.verseNumber) ||
          (pair.surahId2 == verse.surahId &&
              pair.verseNumber2 == verse.verseNumber)) {
        return pair;
      }
    }
    return null;
  }

  void _selectMarkedVerse(Verse verse, MutasyabihatComparisonPair pair) {
    setState(() {
      _selectedVerse = verse;
      _selectedPair = pair;
    });
  }

  Surah? get _activeSurah {
    if (widget.surahs.isEmpty) return null;
    return widget.surahs.firstWhere(
      (s) => s.id == widget.currentSurahId,
      orElse: () => widget.surahs.first,
    );
  }

  void _showSurahPicker(BuildContext context) {
    if (widget.surahs.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SurahPickerSheet(
        surahs: widget.surahs,
        currentSurahId: widget.currentSurahId,
        onSelectSurah: (id) {
          Navigator.pop(ctx);
          widget.onSelectSurah?.call(id);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.verses.isEmpty) {
      return const Center(child: Text('Tidak ada data ayat.'));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final firstVerse = widget.verses.first;
    final primaryColor = isDark ? const Color(0xFF34D399) : const Color(0xFF165B33);
    final mutedColor = isDark ? const Color(0xFFA7B0AC) : const Color(0xFF525E58);
    final pageBg = isDark ? const Color(0xFF181D1A) : const Color(0xFFFCFAF6);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Banner Penjelasan Mode + Kontrol Zoom In / Zoom Out
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1B201D)
                  : const Color(0xFFFEF8ED),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF37423C)
                    : const Color(0xFFD6BD8A),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF9B7A38).withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Color(0xFF9B7A38),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mode Mushaf Bertanda Mutasyabihat',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Ayat dengan kembaran mutasyabihat diberi aksen emas. Klik/sentuh ayat bertanda untuk meneliti perbandingannya.',
                            style: TextStyle(fontSize: 11, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Toggle Scroll Mouse = Zoom langsung (Desktop)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _scrollWheelDirectZoom = !_scrollWheelDirectZoom),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _scrollWheelDirectZoom
                              ? const Color(0xFF9B7A38).withOpacity(0.18)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _scrollWheelDirectZoom
                                ? const Color(0xFF9B7A38)
                                : (isDark ? const Color(0xFF2E3834) : const Color(0xFFD8D0C0)),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.mouse_outlined,
                              size: 14,
                              color: _scrollWheelDirectZoom ? const Color(0xFF9B7A38) : mutedColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _scrollWheelDirectZoom ? 'Scroll = Zoom' : 'Ctrl+Scroll = Zoom',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: _scrollWheelDirectZoom ? const Color(0xFF9B7A38) : mutedColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Perkecil Mushaf (Zoom Out)',
                      onPressed: () => _updateZoom(_zoomScale - 0.15),
                      icon: Icon(Icons.remove_circle_outline_rounded, size: 20, color: mutedColor),
                    ),
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
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Perbesar Mushaf (Zoom In)',
                      onPressed: () => _updateZoom(_zoomScale + 0.15),
                      icon: Icon(Icons.add_circle_outline_rounded, size: 20, color: mutedColor),
                    ),
                    if (widget.surahs.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primaryColor,
                          side: BorderSide(
                            color: isDark ? const Color(0xFF37423C) : const Color(0xFFD6BD8A),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _showSurahPicker(context),
                        icon: const Icon(Icons.menu_book_rounded, size: 16),
                        label: Text(
                          'Pilih Surah: QS. ${_activeSurah?.nameLatin ?? firstVerse.surahNameLatin ?? ""} ▾',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Lembaran Mushaf Madinah Penuh (Mendukung Cubit 2 Jari, Scroll Mouse, dan Swipe Horisontal untuk Pindah Surah)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (DragEndDetails details) {
              final velocity = details.primaryVelocity;
              if (velocity != null) {
                if (velocity < -200) {
                  // Geser ke kiri (Swipe Left) -> Pindah ke Surah Selanjutnya
                  widget.onNextSurah?.call();
                } else if (velocity > 200) {
                  // Geser ke kanan (Swipe Right) -> Pindah ke Surah Sebelumnya
                  widget.onPrevSurah?.call();
                }
              }
            },
            child: MushafZoomGestureWrapper(
              zoomScale: _zoomScale,
              scrollWheelZoomWithoutCtrl: _scrollWheelDirectZoom,
              onZoomChanged: _updateZoom,
              child: Container(
                  decoration: BoxDecoration(
                    color: pageBg,
                    border: Border.all(
                      color: const Color(0xFFC8AA76),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Header Lembaran Mushaf
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'الجزء ${firstVerse.juzNumber}',
                            style: TextStyle(
                              fontFamily: 'kfgqpc_hafs',
                              fontSize: 16 * _zoomScale,
                              color: const Color(0xFF9B7A38),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          InkWell(
                            onTap: () => _showSurahPicker(context),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'سُورَةُ ${_activeSurah?.nameArabic ?? firstVerse.surahNameLatin ?? ''}',
                                    style: TextStyle(
                                      fontFamily: 'kfgqpc_hafs',
                                      fontSize: 20 * _zoomScale,
                                      color: primaryColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.arrow_drop_down_rounded,
                                    size: 22 * _zoomScale,
                                    color: primaryColor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Text(
                            '${firstVerse.pageNumber}',
                            style: TextStyle(
                              fontFamily: 'kfgqpc_hafs',
                              fontSize: 16 * _zoomScale,
                              color: const Color(0xFF9B7A38),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20, color: Color(0xFFC8AA76)),

                      // Basmalah (kecuali At-Taubah)
                      if (firstVerse.surahId != 9) ...[
                        Text(
                          'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'kfgqpc_hafs',
                            fontSize: 22 * _zoomScale,
                            height: 1.8,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Teks Ayat Mengalir Kontinyu
                      Directionality(
                        textDirection: TextDirection.rtl,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 10,
                          alignment: WrapAlignment.start,
                          children: widget.verses.map((v) {
                            final pair = _findPairForVerse(v);
                            final isMarked = pair != null;
                            final isSelected = _selectedVerse?.id == v.id;
                            final isSide1 = pair != null &&
                                pair.surahId1 == v.surahId &&
                                pair.verseNumber1 == v.verseNumber;
                            final twinLabel = pair == null
                                ? ''
                                : (isSide1
                                    ? '${pair.surahName2}:${pair.verseNumber2}'
                                    : '${pair.surahName1}:${pair.verseNumber1}');

                            return MouseRegion(
                              cursor: isMarked ? SystemMouseCursors.click : SystemMouseCursors.basic,
                              onEnter: isMarked ? (_) => _selectMarkedVerse(v, pair) : null,
                              child: GestureDetector(
                                onTap: isMarked ? () => _selectMarkedVerse(v, pair) : null,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 140),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isMarked ? 10 : 4,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? (isDark ? const Color(0xFF3E3018) : const Color(0xFFF6E7C8))
                                        : isMarked
                                            ? (isDark ? const Color(0xFF2B2418) : const Color(0xFFFBF5E8))
                                            : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: isMarked
                                        ? Border(
                                            bottom: BorderSide(
                                              color: const Color(0xFF9B7A38),
                                              width: isSelected ? 2.5 : 2.0,
                                            ),
                                          )
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          v.textUthmani,
                                          style: TextStyle(
                                            fontSize: 23 * _zoomScale,
                                            height: 1.9,
                                            color: isDark
                                                ? const Color(0xFFF3F1EC)
                                                : const Color(0xFF141816),
                                            fontWeight: isMarked ? FontWeight.w600 : FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      if (isMarked) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF9B7A38),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            '⇄ $twinLabel',
                                            textDirection: TextDirection.ltr,
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(width: 4),
                                      Text(
                                        '۝${_toArabicDigits(v.verseNumber)}',
                                        style: TextStyle(
                                          fontSize: 18 * _zoomScale,
                                          color: const Color(0xFF9B7A38),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      const SizedBox(height: 18),
                      Divider(height: 1, color: const Color(0xFFC8AA76).withOpacity(0.5)),
                      const SizedBox(height: 12),

                      // Footer Navigasi Pindah Surah & Indikator Gesture Swipe
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: widget.onPrevSurah,
                            icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
                            label: Text(
                              widget.prevSurahName != null
                                  ? '◄ QS. ${widget.prevSurahName}'
                                  : '◄ Sebelumnya',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                          InkWell(
                            onTap: () => _showSurahPicker(context),
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF242B28) : const Color(0xFFF1EDE4),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: isDark ? const Color(0xFF323B37) : const Color(0xFFDCD5C6),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.list_alt_rounded, size: 15, color: primaryColor),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Pilih Surah (1 - ${widget.surahs.isNotEmpty ? widget.surahs.length : 114}) ▾',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: primaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '| Swipe',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: mutedColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: widget.onNextSurah,
                            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                            label: Text(
                              widget.nextSurahName != null
                                  ? 'QS. ${widget.nextSurahName} ►'
                                  : 'Selanjutnya ►',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ),
          ),

          const SizedBox(height: 16),

          // Inspector Drawer (Persis seperti .mutasyabihat-inspector di Web)
          _buildInlineInspectorCard(context, isDark),
        ],
      ),
    );
  }

  Widget _buildInlineInspectorCard(BuildContext context, bool isDark) {
    final surfaceColor = isDark ? const Color(0xFF1B201E) : Colors.white;
    final subtleBg = isDark ? const Color(0xFF181D1A) : const Color(0xFFF1EDE4);
    final borderSubtle = isDark ? const Color(0xFF262D2A) : const Color(0xFFE6E1D6);
    final primaryColor = isDark ? const Color(0xFF34D399) : const Color(0xFF165B33);
    final goldColor = isDark ? const Color(0xFFD9B36C) : const Color(0xFF9B7A38);

    if (_selectedVerse == null || _selectedPair == null) {
      return Container(
        width: double.infinity,
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
                    color: goldColor.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: goldColor.withOpacity(0.45)),
                  ),
                  child: Text(
                    'Kembaran Mutasyabihat',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: goldColor,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Pilih ayat bertanda di atas',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ],
            ),
            const Divider(height: 20),
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Arahkan kursor atau sentuh ayat yang memiliki tanda emas di atas untuk melihat detail perbandingan ayat mirip, kata pembeda, dan sambungan surahnya.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final verse = _selectedVerse!;
    final pair = _selectedPair!;
    final isSide1 = pair.surahId1 == verse.surahId &&
        pair.verseNumber1 == verse.verseNumber;
    final twinSurahName = isSide1 ? pair.surahName2 : pair.surahName1;
    final twinVerseNum = isSide1 ? pair.verseNumber2 : pair.verseNumber1;
    final twinSurahId = isSide1 ? pair.surahId2 : pair.surahId1;
    final twinText = isSide1 ? pair.textUthmani2 : pair.textUthmani1;
    final nextCurrent = isSide1 ? pair.nextVerseStartWords1 : pair.nextVerseStartWords2;
    final nextTwin = isSide1 ? pair.nextVerseStartWords2 : pair.nextVerseStartWords1;

    final isIdentical = pair.diffWordPositions1.isEmpty && pair.diffWordPositions2.isEmpty;

    return Container(
      width: double.infinity,
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: goldColor.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: goldColor.withOpacity(0.45)),
                      ),
                      child: Text(
                        'Kembaran Mutasyabihat',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: goldColor,
                        ),
                      ),
                    ),
                    if (isIdentical)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: goldColor.withOpacity(0.20),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: goldColor.withOpacity(0.6)),
                        ),
                        child: Text(
                          'Kembar Identik (100%)',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: goldColor,
                          ),
                        ),
                      ),
                    Text(
                      'QS. ${verse.surahNameLatin ?? verse.surahId}:${verse.verseNumber} ⇄ QS. $twinSurahName:$twinVerseNum',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() {
                  _selectedVerse = null;
                  _selectedPair = null;
                }),
              ),
            ],
          ),
          const Divider(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final box1 = Container(
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
                          'Ayat Saat Ini: QS. ${verse.surahNameLatin}:${verse.verseNumber}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: primaryColor,
                          ),
                        ),
                        TextButton(
                          onPressed: () => widget.murattalAudioService.playVerse(
                            surahId: verse.surahId,
                            verseNumber: verse.verseNumber,
                            surahName: verse.surahNameLatin,
                          ),
                          child: const Text('▶ Putar', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    Text(
                      verse.textUthmani,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 21, height: 1.95),
                    ),
                    const Divider(height: 16),
                    Text(
                      'Awal ayat selanjutnya: $nextCurrent',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              );

              final box2 = Container(
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
                          'Kembaran Mirip: QS. $twinSurahName:$twinVerseNum',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: goldColor,
                          ),
                        ),
                        TextButton(
                          onPressed: () => widget.murattalAudioService.playVerse(
                            surahId: twinSurahId,
                            verseNumber: twinVerseNum,
                            surahName: twinSurahName,
                          ),
                          child: const Text('▶ Putar', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    Text(
                      twinText,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 21, height: 1.95),
                    ),
                    const Divider(height: 16),
                    Text(
                      'Awal ayat selanjutnya: $nextTwin',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
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
          if (pair.userMemoryNote != null && pair.userMemoryNote!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: goldColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: goldColor.withOpacity(0.4)),
              ),
              child: Text(
                'Jembatan Ingatan: ${pair.userMemoryNote}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _toArabicDigits(int num) {
    const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return num.toString().split('').map((d) => digits[int.parse(d)]).join();
  }
}

// ==============================================================================
// Bottom Sheet Pemilih Surah Al-Qur'an (1 - 114) dengan Pencarian & Scroll Mulus
// ==============================================================================

class _SurahPickerSheet extends StatefulWidget {
  final List<Surah> surahs;
  final int currentSurahId;
  final ValueChanged<int> onSelectSurah;

  const _SurahPickerSheet({
    required this.surahs,
    required this.currentSurahId,
    required this.onSelectSurah,
  });

  @override
  State<_SurahPickerSheet> createState() => _SurahPickerSheetState();
}

class _SurahPickerSheetState extends State<_SurahPickerSheet> {
  String _query = '';
  late final TextEditingController _searchController;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && widget.surahs.isNotEmpty) {
        final idx = widget.surahs.indexWhere((s) => s.id == widget.currentSurahId);
        if (idx > 0) {
          final target = (idx * 68.0).clamp(0.0, _scrollController.position.maxScrollExtent);
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? const Color(0xFF34D399) : const Color(0xFF165B33);
    final bgColor = isDark ? const Color(0xFF181D1A) : Colors.white;
    final cardBg = isDark ? const Color(0xFF222824) : const Color(0xFFFAF7F2);
    final borderColor = isDark ? const Color(0xFF323B37) : const Color(0xFFE2DDD3);

    final filtered = widget.surahs.where((s) {
      if (_query.trim().isEmpty) return true;
      final q = _query.toLowerCase().trim();
      return s.nameLatin.toLowerCase().contains(q) ||
          s.translationId.toLowerCase().contains(q) ||
          s.nameArabic.contains(q) ||
          s.id.toString() == q;
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: const Border(
          top: BorderSide(color: Color(0xFFC8AA76), width: 2),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: borderColor,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.menu_book_rounded, color: primaryColor, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Pilih Surah (1 - ${widget.surahs.length})',
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: 'Tutup',
                ),
              ],
            ),
          ),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Cari nama surah (Latin/Arab), terjemahan, atau nomor...',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: primaryColor, width: 1.6),
                ),
                filled: true,
                fillColor: cardBg,
                isDense: true,
              ),
            ),
          ),

          const SizedBox(height: 6),

          // Scrollable List of Surahs
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      'Tidak ada surah yang cocok.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final surah = filtered[index];
                      final isSelected = surah.id == widget.currentSurahId;

                      return InkWell(
                        onTap: () => widget.onSelectSurah(surah.id),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (isDark ? const Color(0xFF1D3528) : const Color(0xFFE9F3ED))
                                : cardBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? primaryColor
                                  : borderColor.withOpacity(0.6),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Nomor Surah
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: isSelected ? primaryColor : borderColor.withOpacity(0.5),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${surah.id}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.white : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Nama Latin & Terjemahan
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'QS. ${surah.nameLatin}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected ? primaryColor : null,
                                          ),
                                        ),
                                        if (isSelected) ...[
                                          const SizedBox(width: 6),
                                          Icon(Icons.check_circle_rounded, size: 16, color: primaryColor),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${surah.translationId} • ${surah.totalVerses} Ayat • ${surah.revelationType == 'madaniyah' ? 'Madaniyah' : 'Makkiyah'}',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: isDark ? const Color(0xFFA7B0AC) : const Color(0xFF525E58),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Nama Arab Surah
                              Text(
                                surah.nameArabic,
                                style: const TextStyle(
                                  fontFamily: 'kfgqpc_hafs',
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF9B7A38),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
