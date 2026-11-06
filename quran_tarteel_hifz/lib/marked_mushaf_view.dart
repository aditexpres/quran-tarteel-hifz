// lib/marked_mushaf_view.dart
// ==============================================================================
// Mode Tampilan: Mushaf Bertanda Mutasyabihat (Anti-Tertukar)
// Membaca Al-Qur'an secara full, dengan penanda warna khusus pada ayat mutasyabihat.
// Ketika disentuh/diklik, menyorot ayat dan menampilkan perbandingan ayat kembarannya.
// ==============================================================================

import 'package:flutter/material.dart';
import 'mushaf_15line_and_audio.dart';
import 'quran_hifz_repository.dart';

class MarkedMushafMutasyabihatView extends StatefulWidget {
  final List<Verse> verses;
  final List<MutasyabihatComparisonPair> pairs;
  final QuranMurattalAudioService murattalAudioService;

  const MarkedMushafMutasyabihatView({
    super.key,
    required this.verses,
    required this.pairs,
    required this.murattalAudioService,
  });

  @override
  State<MarkedMushafMutasyabihatView> createState() =>
      _MarkedMushafMutasyabihatViewState();
}

class _MarkedMushafMutasyabihatViewState
    extends State<MarkedMushafMutasyabihatView> {
  int? _highlightedVerseId;

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

  void _inspectMutasyabihat(Verse verse, MutasyabihatComparisonPair pair) {
    setState(() => _highlightedVerseId = verse.id);
    final isSide1 = pair.surahId1 == verse.surahId &&
        pair.verseNumber1 == verse.verseNumber;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final twinSurahName = isSide1 ? pair.surahName2 : pair.surahName1;
        final twinVerseNum = isSide1 ? pair.verseNumber2 : pair.verseNumber1;
        final twinSurahId = isSide1 ? pair.surahId2 : pair.surahId1;
        final twinText = isSide1 ? pair.textUthmani2 : pair.textUthmani1;
        final twinDiff = isSide1 ? pair.diffWordPositions2 : pair.diffWordPositions1;
        final currentDiff = isSide1 ? pair.diffWordPositions1 : pair.diffWordPositions2;
        final nextCurrent = isSide1 ? pair.nextVerseStartWords1 : pair.nextVerseStartWords2;
        final nextTwin = isSide1 ? pair.nextVerseStartWords2 : pair.nextVerseStartWords1;

        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.4,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollCtrl) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: ListView(
                controller: scrollCtrl,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF9B7A38).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFC8AA76)),
                        ),
                        child: const Text(
                          'Radar Mutasyabihat',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF9B7A38),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'QS. ${verse.surahNameLatin ?? verse.surahId} : ${verse.verseNumber}  ⇄  QS. $twinSurahName : $twinVerseNum',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Kotak 1: Ayat Aktif
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF181D1A) : const Color(0xFFF8F6F0),
                      border: Border.all(color: const Color(0xFF165B33).withOpacity(0.4)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Ayat Yang Sedang Dibaca (${verse.surahNameLatin} : ${verse.verseNumber})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF165B33),
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => widget.murattalAudioService.playVerse(
                                surahId: verse.surahId,
                                verseNumber: verse.verseNumber,
                              ),
                              icon: const Icon(Icons.play_arrow_rounded, size: 16),
                              label: const Text('Audio', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          verse.textUthmani,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontFamily: 'Amiri',
                            fontSize: 20,
                            height: 2.1,
                          ),
                        ),
                        const Divider(height: 16),
                        Text(
                          'Awal ayat kelanjutan yang benar: "$nextCurrent"',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Kotak 2: Ayat Kembaran
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF181D1A) : const Color(0xFFF8F6F0),
                      border: Border.all(color: const Color(0xFF9B7A38).withOpacity(0.5)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Ayat Kembaran Serupa ($twinSurahName : $twinVerseNum)',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF9B7A38),
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => widget.murattalAudioService.playVerse(
                                surahId: twinSurahId,
                                verseNumber: twinVerseNum,
                              ),
                              icon: const Icon(Icons.play_arrow_rounded, size: 16),
                              label: const Text('Audio', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          twinText,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontFamily: 'Amiri',
                            fontSize: 20,
                            height: 2.1,
                          ),
                        ),
                        const Divider(height: 16),
                        Text(
                          'Awal ayat kelanjutan kembarannya: "$nextTwin"',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (pair.userMemoryNote != null && pair.userMemoryNote!.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF9B7A38).withOpacity(0.1),
                        border: Border.all(color: const Color(0xFF9B7A38).withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lightbulb_outline_rounded,
                              size: 18, color: Color(0xFF9B7A38)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Jembatan Ingatan: ${pair.userMemoryNote}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.verses.isEmpty) {
      return const Center(child: Text('Tidak ada data ayat.'));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final firstVerse = widget.verses.first;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Banner Penjelasan Mode
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
            child: Row(
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
                const Expanded(
                  child: Column(
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
                        'Ayat dengan kembaran mutasyabihat diberi aksen emas. Klik atau ketuk ayat bertanda untuk meneliti perbandingannya.',
                        style: TextStyle(fontSize: 11, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Lembaran Mushaf Madinah Penuh
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF181D1A)
                  : const Color(0xFFFCFAF6),
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
                      style: const TextStyle(
                        fontFamily: 'Amiri',
                        fontSize: 16,
                        color: Color(0xFF9B7A38),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'سُورَةُ ${firstVerse.surahNameLatin ?? ''}',
                      style: const TextStyle(
                        fontFamily: 'Amiri',
                        fontSize: 20,
                        color: Color(0xFF165B33),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${firstVerse.pageNumber}',
                      style: const TextStyle(
                        fontFamily: 'Amiri',
                        fontSize: 16,
                        color: Color(0xFF9B7A38),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20, color: Color(0xFFC8AA76)),

                // Basmalah (kecuali At-Taubah)
                if (firstVerse.surahId != 9) ...[
                  const Text(
                    'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Amiri',
                      fontSize: 22,
                      height: 1.8,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Teks Ayat Mengalir Kontinyu
                SelectableText.rich(
                  TextSpan(
                    children: widget.verses.map((v) {
                      final pair = _findPairForVerse(v);
                      final isMarked = pair != null;
                      final isSelected = _highlightedVerseId == v.id;

                      return WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: InkWell(
                          onTap: isMarked
                              ? () => _inspectMutasyabihat(v, pair)
                              : null,
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                            padding: EdgeInsets.symmetric(
                              horizontal: isMarked ? 4 : 1,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7))
                                  : isMarked
                                      ? (isDark
                                          ? const Color(0xFF262115)
                                          : const Color(0xFFFEF8ED))
                                      : Colors.transparent,
                              border: isMarked
                                  ? Border.all(
                                      color: isSelected
                                          ? const Color(0xFFF59E0B)
                                          : const Color(0xFFC8AA76),
                                      width: isSelected ? 1.5 : 1,
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  v.textUthmani,
                                  style: TextStyle(
                                    fontFamily: 'Amiri',
                                    fontSize: 21,
                                    height: 2.2,
                                    color: isDark
                                        ? const Color(0xFFECE7DE)
                                        : const Color(0xFF111815),
                                    fontWeight: isMarked
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                                if (isMarked) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF9B7A38),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text(
                                      '✦ Mirip',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                                Text(
                                  ' ۝${_toArabicDigits(v.verseNumber)} ',
                                  style: const TextStyle(
                                    fontFamily: 'Amiri',
                                    fontSize: 16,
                                    color: Color(0xFF9B7A38),
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
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _toArabicDigits(int num) {
    const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return num.toString().split('').map((d) => digits[int.parse(d)]).join();
  }
}
