/**
 * app.js — Qur'an Tarteel Hifz & Radar Mutasyabihat Web Application Engine
 * Terintegrasi penuh dengan:
 * 1. Mushaf Madinah 15 Baris & Mode Blur/Peek Kata (Shortcut Spasi)
 * 2. Voice Hifz AI (Web Speech API + Fuzzy Arabic Normalizer + Dual-Path Trap Jump)
 * 3. Radar Mutasyabihat dengan Memory Anchor (Local Storage) & Diff Highlights
 * 4. Pemutar Audio Murattal CDN EveryAyah (4 Qari + Loop A-B + Auto-Correction)
 * 5. Mode Drill Kuis Sambung Ayat
 */

(function () {
  'use strict';

  // =========================================================================
  // 1. STATE GLOBAL APLIKASI
  // =========================================================================
  const state = {
    data: null,
    activeSurahId: 78,
    activePageNumber: 582,
    activeVerseIndex: 0,
    activeWordPosition: 0,
    hideMode: true,
    isListening: false,
    recognition: null,
    reciter: 'Husary_128kbps',
    repeatCount: 1,
    currentRepeat: 0,
    activeScope: 'all',
    searchQuery: '',
    drill: {
      questions: [],
      currentIndex: 0,
      score: 0,
      answered: false
    }
  };

  // Cache DOM Elements
  const DOM = {
    surahSelect: document.getElementById('surah-select'),
    btnHideMode: document.getElementById('btn-hide-mode'),
    btnFullscreen: document.getElementById('btn-fullscreen'),
    btnThemeToggle: document.getElementById('btn-theme-toggle'),
    themeIconSun: document.getElementById('theme-icon-sun'),
    themeIconMoon: document.getElementById('theme-icon-moon'),
    tabBtns: document.querySelectorAll('.tab-btn'),
    tabSections: document.querySelectorAll('.tab-section'),
    
    // Mushaf elements
    mushafLinesContainer: document.getElementById('mushaf-lines-container'),
    mushafSurahLabel: document.getElementById('mushaf-surah-label'),
    mushafPageLabel: document.getElementById('mushaf-page-label'),
    pageIndicator: document.getElementById('page-indicator'),
    btnPrevPage: document.getElementById('btn-prev-page'),
    btnNextPage: document.getElementById('btn-next-page'),

    // Marked Mushaf elements
    markedJuzLabel: document.getElementById('marked-juz-label'),
    markedSurahLabel: document.getElementById('marked-surah-label'),
    markedPageLabel: document.getElementById('marked-page-label'),
    markedBismillahBar: document.getElementById('marked-bismillah-bar'),
    markedVersesFlow: document.getElementById('marked-verses-flow'),
    mutasyabihatInspector: document.getElementById('mutasyabihat-inspector'),
    inspectorTitle: document.getElementById('inspector-title'),
    inspectorBody: document.getElementById('inspector-body'),
    btnCloseInspector: document.getElementById('btn-close-inspector'),
    
    // Verse detail
    detailVerseBadge: document.getElementById('detail-verse-badge'),
    detailArabic: document.getElementById('detail-arabic'),
    detailTranslation: document.getElementById('detail-translation'),
    detailWordsList: document.getElementById('detail-words-list'),
    btnCopyVerse: document.getElementById('btn-copy-verse'),

    // Voice Hifz elements
    btnToggleMic: document.getElementById('btn-toggle-mic'),
    voiceIndicator: document.getElementById('voice-indicator'),
    transcriptDisplay: document.getElementById('transcript-display'),
    trapAlertBox: document.getElementById('trap-alert-box'),
    alertTitle: document.getElementById('alert-title'),
    alertDesc: document.getElementById('alert-desc'),
    btnPlayCorrection: document.getElementById('btn-play-correction'),
    btnDismissAlert: document.getElementById('btn-dismiss-alert'),

    // Murattal Audio
    globalAudio: document.getElementById('global-murattal-audio'),
    reciterSelect: document.getElementById('reciter-select'),
    btnPlayVerse: document.getElementById('btn-play-verse'),
    btnLoopVerse: document.getElementById('btn-loop-verse'),

    // Radar Mutasyabihat
    radarCardsContainer: document.getElementById('radar-cards-container'),
    radarSearchInput: document.getElementById('radar-search-input'),
    scopeBtns: document.querySelectorAll('.filter-actions .btn'),
    mutasyabihatCountBadge: document.getElementById('mutasyabihat-count-badge'),

    // Drill Mode
    drillPromptInfo: document.getElementById('drill-prompt-info'),
    drillPromptArabic: document.getElementById('drill-prompt-arabic'),
    drillOptA: document.getElementById('drill-opt-a'),
    drillOptB: document.getElementById('drill-opt-b'),
    drillOptAText: document.getElementById('drill-opt-a-text'),
    drillOptBText: document.getElementById('drill-opt-b-text'),
    drillFeedback: document.getElementById('drill-feedback'),
    drillFeedbackTitle: document.getElementById('drill-feedback-title'),
    drillFeedbackDesc: document.getElementById('drill-feedback-desc'),
    drillFeedbackAnchor: document.getElementById('drill-feedback-anchor'),
    drillScoreBadge: document.getElementById('drill-score-badge'),
    btnNextDrill: document.getElementById('btn-next-drill'),

    // Modal Memory Anchor
    anchorModal: document.getElementById('anchor-modal'),
    modalAnchorInput: document.getElementById('modal-anchor-input'),
    btnCloseModal: document.getElementById('btn-close-modal'),
    btnCancelModal: document.getElementById('btn-cancel-modal'),
    btnSaveModal: document.getElementById('btn-save-modal')
  };

  let activeEditingGroupId = null;

  // =========================================================================
  // 2. UTILITAS TEKS ARAB & FUZZY MATCHER
  // =========================================================================
  const ARABIC_DIACRITICS_REGEX = /[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06DC\u06DF-\u06E8\u06EA-\u06ED\u0640]/g;

  function normalizeArabic(text) {
    if (!text) return '';
    let cleaned = text.replace(ARABIC_DIACRITICS_REGEX, '');
    cleaned = cleaned.replace(/[أإآٱ]/g, 'ا');
    cleaned = cleaned.replace(/ى/g, 'ي').replace(/ة/g, 'ه').replace(/ؤ/g, 'و').replace(/ئ/g, 'ي');
    return cleaned.replace(/\s+/g, ' ').trim();
  }

  function toArabicDigits(num) {
    const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return String(num).split('').map(d => digits[parseInt(d, 10)] || d).join('');
  }

  function calculateSimilarity(str1, str2) {
    const s1 = normalizeArabic(str1);
    const s2 = normalizeArabic(str2);
    if (s1 === s2) return 1.0;
    if (!s1 || !s2) return 0.0;

    const longer = s1.length > s2.length ? s1 : s2;
    const shorter = s1.length > s2.length ? s2 : s1;
    if (longer.length === 0) return 1.0;

    // Levenshtein Distance
    const costs = [];
    for (let i = 0; i <= longer.length; i++) {
      let lastVal = i;
      for (let j = 0; j <= shorter.length; j++) {
        if (i === 0) {
          costs[j] = j;
        } else if (j > 0) {
          let newVal = costs[j - 1];
          if (longer.charAt(i - 1) !== shorter.charAt(j - 1)) {
            newVal = Math.min(Math.min(newVal, lastVal), costs[j]) + 1;
          }
          costs[j - 1] = lastVal;
          lastVal = newVal;
        }
      }
      if (i > 0) costs[shorter.length] = lastVal;
    }
    return (longer.length - costs[shorter.length]) / parseFloat(longer.length);
  }

  // =========================================================================
  // 3. INISIALISASI & LOAD DATASET
  // =========================================================================
  async function initApp() {
    if (window.QURAN_DATA) {
      state.data = window.QURAN_DATA;
    } else {
      try {
        const resp = await fetch('data/quran_data.json');
        state.data = await resp.json();
      } catch (err) {
        console.error('Gagal memuat dataset quran_data:', err);
      }
    }

    if (!state.data) return;

    initTheme();
    populateSurahDropdown();
    setupEventListeners();
    setupSpeechRecognition();
    renderMushafView();
    renderMarkedMushafView();
    renderRadarMutasyabihat();
    initDrillQuestions();
  }

  function initTheme() {
    const saved = localStorage.getItem('quran_theme') || 'light';
    setTheme(saved);

    if (DOM.btnThemeToggle) {
      DOM.btnThemeToggle.addEventListener('click', () => {
        const isDark = document.documentElement.classList.contains('dark');
        setTheme(isDark ? 'light' : 'dark');
      });
    }
  }

  function setTheme(theme) {
    if (theme === 'dark') {
      document.documentElement.classList.add('dark');
      document.documentElement.classList.remove('light');
      if (DOM.themeIconSun) DOM.themeIconSun.classList.add('hidden');
      if (DOM.themeIconMoon) DOM.themeIconMoon.classList.remove('hidden');
    } else {
      document.documentElement.classList.remove('dark');
      document.documentElement.classList.add('light');
      if (DOM.themeIconSun) DOM.themeIconSun.classList.remove('hidden');
      if (DOM.themeIconMoon) DOM.themeIconMoon.classList.add('hidden');
    }
    localStorage.setItem('quran_theme', theme);
  }

  function populateSurahDropdown() {
    DOM.surahSelect.innerHTML = '';
    state.data.surahs.forEach(surah => {
      const opt = document.createElement('option');
      opt.value = surah.id;
      opt.textContent = `${surah.id}. QS. ${surah.name_latin} (${surah.name_arabic})`;
      DOM.surahSelect.appendChild(opt);
    });
    DOM.surahSelect.value = state.activeSurahId;
  }

  // =========================================================================
  // 4. MUSHAF 15-BARIS LAYOUT ENGINE
  // =========================================================================
  function renderMushafView() {
    const surah = state.data.surahs.find(s => s.id === state.activeSurahId);
    if (!surah) return;

    DOM.mushafSurahLabel.textContent = `سُورَةُ ${surah.name_arabic}`;
    DOM.mushafPageLabel.textContent = toArabicDigits(state.activePageNumber);
    DOM.pageIndicator.textContent = `Halaman ${state.activePageNumber}`;

    const verses = state.data.verses.filter(v => v.surah_id === state.activeSurahId);
    if (!verses.length) return;

    // Render 15 Baris Mushaf
    DOM.mushafLinesContainer.innerHTML = '';

    // Baris 1: Header Surah
    const headerLine = document.createElement('div');
    headerLine.className = 'mushaf-line surah-header-line';
    headerLine.innerHTML = `<span class="surah-header-banner">سُورَةُ ${surah.name_arabic} • ${surah.revelation_type === 'madaniyah' ? 'مَدَنِيَّة' : 'مَكِّيَّة'}</span>`;
    DOM.mushafLinesContainer.appendChild(headerLine);

    // Baris 2: Basmalah (jika bukan At-Taubah)
    if (surah.id !== 9) {
      const bismillahLine = document.createElement('div');
      bismillahLine.className = 'mushaf-line bismillah-line';
      bismillahLine.textContent = 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ';
      DOM.mushafLinesContainer.appendChild(bismillahLine);
    }

    // Bangun token kata per ayat
    const allWords = [];
    verses.forEach(v => {
      v.words.forEach(w => {
        allWords.push({
          verse: v,
          word: w
        });
      });
      // Penanda akhir ayat
      allWords.push({
        verse: v,
        isEnd: true,
        verseNumber: v.verse_number
      });
    });

    // Bagi menjadi baris proporsional agar genap tepat 15 baris
    const remainingLineSlots = 15 - DOM.mushafLinesContainer.children.length;
    const wordsPerLine = Math.max(4, Math.ceil(allWords.length / remainingLineSlots));

    let wordIdx = 0;
    for (let lineNo = 0; lineNo < remainingLineSlots; lineNo++) {
      const lineEl = document.createElement('div');
      lineEl.className = 'mushaf-line';

      const slice = allWords.slice(wordIdx, wordIdx + wordsPerLine);
      wordIdx += wordsPerLine;

      slice.forEach(item => {
        if (item.isEnd) {
          const marker = document.createElement('span');
          marker.className = 'ayah-end-marker';
          marker.textContent = ` ۝${toArabicDigits(item.verseNumber)} `;
          lineEl.appendChild(marker);
        } else {
          const wordSpan = document.createElement('span');
          wordSpan.className = 'mushaf-word';
          if (state.hideMode) wordSpan.classList.add('blurred');
          wordSpan.textContent = item.word.text_uthmani;
          wordSpan.dataset.verseId = item.verse.id;
          wordSpan.dataset.wordPos = item.word.position;

          wordSpan.addEventListener('click', () => {
            selectActiveVerse(item.verse, item.word.position);
            wordSpan.classList.remove('blurred');
            wordSpan.classList.add('revealed');
          });

          lineEl.appendChild(wordSpan);
        }
      });

      DOM.mushafLinesContainer.appendChild(lineEl);
      if (wordIdx >= allWords.length) break;
    }

    // Pastikan jika kurang dari 15 baris, isi placeholder baris proporsional
    while (DOM.mushafLinesContainer.children.length < 15) {
      const emptyLine = document.createElement('div');
      emptyLine.className = 'mushaf-line';
      DOM.mushafLinesContainer.appendChild(emptyLine);
    }

    // Tampilkan detail ayat pertama
    selectActiveVerse(verses[0], 0);
  }

  function selectActiveVerse(verse, wordPosition = 0) {
    state.activeVerseIndex = verse.verse_number - 1;
    state.activeWordPosition = wordPosition;

    DOM.detailVerseBadge.textContent = `QS. ${verse.surah_name_latin} : Ayat ${verse.verse_number} (Halaman ${verse.page_number})`;
    DOM.detailArabic.textContent = verse.text_uthmani;
    DOM.detailTranslation.textContent = verse.translation_id;

    // Render Kata Perkata
    DOM.detailWordsList.innerHTML = '';
    verse.words.forEach(w => {
      const chip = document.createElement('div');
      chip.className = 'wbw-chip';
      chip.innerHTML = `
        <span class="wbw-arabic">${w.text_uthmani}</span>
        <span class="wbw-trans">${w.translation_id || '-'}</span>
      `;
      chip.addEventListener('click', () => {
        revealWordInMushaf(verse.id, w.position);
      });
      DOM.detailWordsList.appendChild(chip);
    });
  }

  function revealWordInMushaf(verseId, wordPosition) {
    const el = document.querySelector(`.mushaf-word[data-verse-id="${verseId}"][data-word-pos="${wordPosition}"]`);
    if (el) {
      el.classList.remove('blurred');
      el.classList.add('revealed');
      el.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }
  }

  function peekNextWord() {
    const words = document.querySelectorAll('.mushaf-word.blurred');
    if (words.length > 0) {
      const first = words[0];
      first.classList.remove('blurred');
      first.classList.add('revealed');
      first.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }
  }

  // =========================================================================
  // 4B. MODE MUSHAF BERTANDA MUTASYABIHAT (FULL MUSHAF DENGAN SOROT AYAT MIRIP)
  // =========================================================================
  function renderMarkedMushafView() {
    if (!DOM.markedVersesFlow) return;

    const surah = state.data.surahs.find(s => s.id === state.activeSurahId);
    if (!surah) return;

    if (DOM.markedSurahLabel) DOM.markedSurahLabel.textContent = `سُورَةُ ${surah.name_arabic}`;
    if (DOM.markedPageLabel) DOM.markedPageLabel.textContent = toArabicDigits(state.activePageNumber);
    if (DOM.markedJuzLabel) DOM.markedJuzLabel.textContent = `الجزء ${toArabicDigits(30)}`;

    if (DOM.markedBismillahBar) {
      DOM.markedBismillahBar.style.display = surah.id === 9 ? 'none' : 'block';
    }

    const verses = state.data.verses.filter(v => v.surah_id === state.activeSurahId);
    if (!verses.length) return;

    DOM.markedVersesFlow.innerHTML = '';

    verses.forEach(v => {
      // Cari apakah ayat ini memiliki kembaran mutasyabihat
      const pair = (state.data.mutasyabihat || []).find(p => 
        (p.surah_id_1 === v.surah_id && p.verse_num_1 === v.verse_number) ||
        (p.surah_id_2 === v.surah_id && p.verse_num_2 === v.verse_number)
      );

      const segment = document.createElement('span');
      segment.className = 'verse-segment';
      segment.dataset.verseId = v.id;
      segment.dataset.verseNumber = v.verse_number;

      if (pair) {
        segment.classList.add('has-mutasyabihat');
        const isSide1 = pair.surah_id_1 === v.surah_id && pair.verse_num_1 === v.verse_number;
        const diffPositions = isSide1 ? pair.diff_1 : pair.diff_2;
        
        segment.innerHTML = `${highlightDiffWords(v.text_uthmani, diffPositions)} <span class="twin-badge">✦ Mirip</span><span class="ayah-end-marker"> ۝${toArabicDigits(v.verse_number)} </span>`;

        // Interaksi Hover & Click / Touch untuk menyorot
        segment.addEventListener('mouseenter', () => {
          highlightAndInspectVerse(segment, pair, isSide1, v);
        });

        segment.addEventListener('click', () => {
          highlightAndInspectVerse(segment, pair, isSide1, v);
          if (DOM.mutasyabihatInspector) {
            DOM.mutasyabihatInspector.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
          }
        });
      } else {
        segment.innerHTML = `${v.text_uthmani} <span class="ayah-end-marker"> ۝${toArabicDigits(v.verse_number)} </span>`;
      }

      DOM.markedVersesFlow.appendChild(segment);
    });
  }

  function highlightAndInspectVerse(segmentEl, pair, isSide1, currentVerse) {
    if (!DOM.inspectorTitle || !DOM.inspectorBody) return;

    document.querySelectorAll('.verse-segment.active-highlight').forEach(el => el.classList.remove('active-highlight'));
    segmentEl.classList.add('active-highlight');

    const twinSurahName = isSide1 ? pair.surah_name_2 : pair.surah_name_1;
    const twinVerseNum = isSide1 ? pair.verse_num_2 : pair.verse_num_1;
    const twinSurahId = isSide1 ? pair.surah_id_2 : pair.surah_id_1;
    const twinText = isSide1 ? pair.text_2 : pair.text_1;
    const twinDiff = isSide1 ? pair.diff_2 : pair.diff_1;
    const currentDiff = isSide1 ? pair.diff_1 : pair.diff_2;
    const nextCurrent = isSide1 ? pair.next_words_1 : pair.next_words_2;
    const nextTwin = isSide1 ? pair.next_words_2 : pair.next_words_1;

    DOM.inspectorTitle.textContent = `QS. ${currentVerse.surah_name_latin} : ${currentVerse.verse_number} ⇄ QS. ${twinSurahName} : ${twinVerseNum}`;

    const savedAnchor = localStorage.getItem(`memory_anchor_${pair.group_id}`) || '';

    DOM.inspectorBody.innerHTML = `
      <div class="inspector-compare-grid">
        <div class="inspector-box">
          <div class="inspector-box-header">
            <span>Ayat Aktif: QS. ${currentVerse.surah_name_latin} : ${currentVerse.verse_number}</span>
            <button class="btn btn-ghost btn-xs btn-inspect-audio" data-surah="${currentVerse.surah_id}" data-verse="${currentVerse.verse_number}">
              <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"></polygon></svg>
              <span>Putar Audio</span>
            </button>
          </div>
          <div class="inspector-arabic">${highlightDiffWords(currentVerse.text_uthmani, currentDiff)}</div>
          <div class="inspector-next">
            Lanjutan ayat yang benar: <strong>${nextCurrent || '...'}</strong>
          </div>
        </div>

        <div class="inspector-box">
          <div class="inspector-box-header">
            <span>Kembaran Serupa: QS. ${twinSurahName} : ${twinVerseNum}</span>
            <button class="btn btn-ghost btn-xs btn-inspect-audio" data-surah="${twinSurahId}" data-verse="${twinVerseNum}">
              <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"></polygon></svg>
              <span>Putar Audio</span>
            </button>
          </div>
          <div class="inspector-arabic">${highlightDiffWords(twinText, twinDiff)}</div>
          <div class="inspector-next">
            Lanjutan ayat kembarannya: <strong>${nextTwin || '...'}</strong>
          </div>
        </div>
      </div>

      <div class="inspector-anchor">
        <strong>Jembatan Ingatan (Anti-Tertukar):</strong> ${savedAnchor || 'Belum ada catatan rumus. Tambahkan rumus catatan di menu Radar Mutasyabihat.'}
      </div>
    `;

    DOM.inspectorBody.querySelectorAll('.btn-inspect-audio').forEach(btn => {
      btn.addEventListener('click', (e) => {
        const s = parseInt(e.currentTarget.dataset.surah, 10);
        const v = parseInt(e.currentTarget.dataset.verse, 10);
        playMurattalAudio(s, v);
      });
    });
  }

  // =========================================================================
  // 5. RADAR MUTASYABIHAT & MEMORY ANCHORS
  // =========================================================================
  function renderRadarMutasyabihat() {
    const container = DOM.radarCardsContainer;
    container.innerHTML = '';

    let pairs = state.data.mutasyabihat || [];

    // Filter scope
    if (state.activeScope === 'surah') {
      pairs = pairs.filter(p => p.surah_id_1 === state.activeSurahId || p.surah_id_2 === state.activeSurahId);
    }

    // Filter search
    if (state.searchQuery.trim()) {
      const q = state.searchQuery.toLowerCase();
      pairs = pairs.filter(p => 
        p.title.toLowerCase().includes(q) ||
        p.surah_name_1.toLowerCase().includes(q) ||
        p.surah_name_2.toLowerCase().includes(q) ||
        p.text_1.includes(q) ||
        p.text_2.includes(q)
      );
    }

    DOM.mutasyabihatCountBadge.textContent = pairs.length;

    if (!pairs.length) {
      container.innerHTML = `
        <div class="empty-placeholder" style="text-align: center; padding: 40px; color: var(--text-secondary);">
          Tidak ditemukan pasangan ayat mutasyabihat yang cocok.
        </div>
      `;
      return;
    }

    pairs.forEach(pair => {
      const savedAnchor = localStorage.getItem(`memory_anchor_${pair.group_id}`) || '';

      const card = document.createElement('div');
      card.className = 'mutasyabihat-card';

      // Format kata dengan highlight kata pembeda
      const formattedText1 = highlightDiffWords(pair.text_1, pair.diff_1);
      const formattedText2 = highlightDiffWords(pair.text_2, pair.diff_2);

      card.innerHTML = `
        <div class="m-card-header">
          <span class="m-title">${pair.title}</span>
          <span class="m-scope-badge">Juz ${pair.scope_juz || '30'}</span>
        </div>

        <div class="m-pair-grid">
          <div class="m-verse-box">
            <div class="m-verse-header">
              <span>QS. ${pair.surah_name_1} : ${pair.verse_num_1}</span>
              <button class="btn btn-ghost btn-xs btn-audio-compare" data-surah="${pair.surah_id_1}" data-verse="${pair.verse_num_1}">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><polygon points="5 3 19 12 5 21 5 3"></polygon></svg>
                <span>Putar Audio</span>
              </button>
            </div>
            <div class="m-arabic">${formattedText1}</div>
            <div class="m-next-words">
              Lanjutan ayat berikutnya: <strong>${pair.next_words_1 || '...'}</strong>
            </div>
          </div>

          <div class="m-verse-box">
            <div class="m-verse-header">
              <span>QS. ${pair.surah_name_2} : ${pair.verse_num_2}</span>
              <button class="btn btn-ghost btn-xs btn-audio-compare" data-surah="${pair.surah_id_2}" data-verse="${pair.verse_num_2}">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><polygon points="5 3 19 12 5 21 5 3"></polygon></svg>
                <span>Putar Audio</span>
              </button>
            </div>
            <div class="m-arabic">${formattedText2}</div>
            <div class="m-next-words">
              Lanjutan ayat berikutnya: <strong>${pair.next_words_2 || '...'}</strong>
            </div>
          </div>
        </div>

        <div class="m-memory-anchor-row">
          <div class="anchor-text">
            <strong>Jembatan Ingatan:</strong> 
            <span id="anchor-display-${pair.group_id}">${savedAnchor || 'Belum ada rumus catatan. Klik tombol edit untuk menambah rumus anti-tertukar.'}</span>
          </div>
          <button class="btn btn-secondary btn-xs btn-edit-anchor" data-group-id="${pair.group_id}">Edit Rumus</button>
        </div>
      `;

      container.appendChild(card);
    });

    // Event listener audio compare
    container.querySelectorAll('.btn-audio-compare').forEach(btn => {
      btn.addEventListener('click', (e) => {
        const s = parseInt(e.currentTarget.dataset.surah, 10);
        const v = parseInt(e.currentTarget.dataset.verse, 10);
        playMurattalAudio(s, v);
      });
    });

    // Event listener edit memory anchor
    container.querySelectorAll('.btn-edit-anchor').forEach(btn => {
      btn.addEventListener('click', (e) => {
        const gid = parseInt(e.currentTarget.dataset.groupId, 10);
        openMemoryAnchorModal(gid);
      });
    });
  }

  function highlightDiffWords(text, diffPositions) {
    if (!diffPositions || !diffPositions.length) return text;
    const tokens = text.split(' ');
    const diffSet = new Set(diffPositions);
    return tokens.map((t, idx) => {
      if (diffSet.has(idx + 1)) {
        return `<span class="diff-highlight">${t}</span>`;
      }
      return t;
    }).join(' ');
  }

  function openMemoryAnchorModal(groupId) {
    activeEditingGroupId = groupId;
    const saved = localStorage.getItem(`memory_anchor_${groupId}`) || '';
    DOM.modalAnchorInput.value = saved;
    DOM.anchorModal.showModal();
  }

  // =========================================================================
  // 6. VOICE HIFZ ENGINE & DUAL-PATH LISTENING (WEB SPEECH API)
  // =========================================================================
  function setupSpeechRecognition() {
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognition) {
      DOM.voiceIndicator.textContent = 'Web Speech API tidak didukung browser ini. Menggunakan Simulator Cepat.';
      return;
    }

    state.recognition = new SpeechRecognition();
    state.recognition.continuous = true;
    state.recognition.interimResults = true;
    state.recognition.lang = 'ar-SA'; // Kunci bahasa ke Bahasa Arab

    state.recognition.onstart = () => {
      state.isListening = true;
      DOM.btnToggleMic.classList.add('listening');
      DOM.voiceIndicator.textContent = 'Mendengarkan bacaan Arab Anda secara real-time...';
    };

    state.recognition.onresult = (event) => {
      let interim = '';
      for (let i = event.resultIndex; i < event.results.length; ++i) {
        interim += event.results[i][0].transcript;
      }
      if (interim) {
        DOM.transcriptDisplay.textContent = `Suara: "${interim}"`;
        evaluateVoiceSpeech(interim);
      }
    };

    state.recognition.onerror = (event) => {
      console.warn('Speech recognition error:', event.error);
      if (event.error === 'not-allowed') {
        DOM.voiceIndicator.textContent = 'Izin mikrofon belum diberikan.';
      }
    };

    state.recognition.onend = () => {
      state.isListening = false;
      DOM.btnToggleMic.classList.remove('listening');
      DOM.voiceIndicator.textContent = 'Mikrofon nonaktif. Klik untuk mulai menyimak.';
    };
  }

  function toggleListening() {
    if (!state.recognition) {
      // Simulator interaktif jika browser tidak memiliki Web Speech API
      runInteractiveVoiceSimulation();
      return;
    }

    if (state.isListening) {
      state.recognition.stop();
    } else {
      state.recognition.start();
    }
  }

  function evaluateVoiceSpeech(transcript) {
    const currentVerse = state.data.verses.find(
      v => v.surah_id === state.activeSurahId && v.verse_number === state.activeVerseIndex + 1
    );
    if (!currentVerse) return;

    // 1. Cek kecocokan ayat saat ini
    const simCurrent = calculateSimilarity(transcript, currentVerse.text_clean);
    if (simCurrent >= 0.70) {
      // Unblur kata saat ini
      currentVerse.words.forEach(w => revealWordInMushaf(currentVerse.id, w.position));
      DOM.trapAlertBox.classList.add('hidden');
      return;
    }

    // 2. Dual-Path Evaluation: Cek apakah menyambung ke ayat selanjutnya yang benar vs jebakan lompat surah!
    const nextVerse = state.data.verses.find(
      v => v.surah_id === state.activeSurahId && v.verse_number === currentVerse.verse_number + 1
    );

    // Cari kembaran mutasyabihat dari ayat saat ini
    const pair = state.data.mutasyabihat.find(
      p => (p.surah_id_1 === currentVerse.surah_id && p.verse_num_1 === currentVerse.verse_number) ||
           (p.surah_id_2 === currentVerse.surah_id && p.verse_num_2 === currentVerse.verse_number)
    );

    if (pair) {
      const isSide1 = pair.surah_id_1 === currentVerse.surah_id && pair.verse_num_1 === currentVerse.verse_number;
      const trapSurahId = isSide1 ? pair.surah_id_2 : pair.surah_id_1;
      const trapVerseNum = (isSide1 ? pair.verse_num_2 : pair.verse_num_1) + 1;
      const trapNextWords = isSide1 ? pair.next_words_2 : pair.next_words_1;

      // Evaluasi apakah transkrip mendekati awal ayat jebakan
      const simTrap = calculateSimilarity(transcript, trapNextWords);
      if (simTrap >= 0.65) {
        // Trigger TRAP JUMP ALERT!
        DOM.alertTitle.textContent = `⚠️ Terdeteksi Lompat Surah! (Kemiripan ${Math.round(simTrap * 100)}%)`;
        DOM.alertDesc.textContent = `Anda seharusnya menyambung ke QS. ${currentVerse.surah_name_latin}:${currentVerse.verse_number + 1}, namun lidah Anda membaca kelanjutan QS. Surah ${trapSurahId}:${trapVerseNum}.`;
        DOM.trapAlertBox.classList.remove('hidden');

        // Otomatis putar audio koreksi ayat yang BENAR
        if (nextVerse) {
          playMurattalAudio(nextVerse.surah_id, nextVerse.verse_number);
        }
      }
    }
  }

  function runInteractiveVoiceSimulation() {
    const currentVerse = state.data.verses.find(
      v => v.surah_id === state.activeSurahId && v.verse_number === state.activeVerseIndex + 1
    );
    if (!currentVerse) return;

    // Simulasi membuka kata demi kata
    peekNextWord();
    DOM.voiceIndicator.textContent = `[Simulator] Membuka kata demi kata untuk QS. ${currentVerse.surah_name_latin}:${currentVerse.verse_number}`;
  }

  // =========================================================================
  // 7. PEMUTAR AUDIO MURATTAL PER AYAT (EVERYAYAH CDN)
  // =========================================================================
  function getAudioUrl(surahId, verseNumber) {
    const s = String(surahId).padStart(3, '0');
    const v = String(verseNumber).padStart(3, '0');
    return `https://everyayah.com/data/${state.reciter}/${s}${v}.mp3`;
  }

  function playMurattalAudio(surahId, verseNumber) {
    const url = getAudioUrl(surahId, verseNumber);
    DOM.globalAudio.src = url;
    DOM.globalAudio.play().catch(e => console.warn('Audio play hindered:', e));

    DOM.btnPlayVerse.innerHTML = `
      <svg class="btn-svg" width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
        <rect x="6" y="4" width="4" height="16"></rect>
        <rect x="14" y="4" width="4" height="16"></rect>
      </svg>
      <span>Jeda Audio</span>
    `;

    DOM.globalAudio.onended = () => {
      DOM.btnPlayVerse.innerHTML = `
        <svg class="btn-svg" width="14" height="14" viewBox="0 0 24 24" fill="currentColor" stroke="none" aria-hidden="true">
          <polygon points="5 3 19 12 5 21 5 3"></polygon>
        </svg>
        <span>Putar Audio</span>
      `;
      if (state.repeatCount > 1 && state.currentRepeat < state.repeatCount - 1) {
        state.currentRepeat++;
        DOM.globalAudio.play();
      } else {
        state.currentRepeat = 0;
      }
    };
  }

  function togglePlayCurrentVerse() {
    if (!DOM.globalAudio.paused && DOM.globalAudio.src) {
      DOM.globalAudio.pause();
      DOM.btnPlayVerse.innerHTML = `
        <svg class="btn-svg" width="14" height="14" viewBox="0 0 24 24" fill="currentColor" stroke="none" aria-hidden="true">
          <polygon points="5 3 19 12 5 21 5 3"></polygon>
        </svg>
        <span>Putar Audio</span>
      `;
    } else {
      const currentVerse = state.data.verses.find(
        v => v.surah_id === state.activeSurahId && v.verse_number === state.activeVerseIndex + 1
      );
      if (currentVerse) {
        playMurattalAudio(currentVerse.surah_id, currentVerse.verse_number);
      }
    }
  }

  // =========================================================================
  // 8. MODE DRILL KUIS SAMBUNG AYAT
  // =========================================================================
  function initDrillQuestions() {
    const pairs = state.data.mutasyabihat || [];
    if (!pairs.length) return;

    // Acak pasangan untuk kuis
    state.drill.questions = pairs.slice().sort(() => Math.random() - 0.5);
    state.drill.currentIndex = 0;
    state.drill.score = 0;
    renderDrillCard();
  }

  function renderDrillCard() {
    const q = state.drill.questions[state.drill.currentIndex];
    if (!q) return;

    state.drill.answered = false;
    DOM.drillFeedback.classList.add('hidden');
    DOM.drillScoreBadge.textContent = `Skor: ${state.drill.score} / ${state.drill.currentIndex}`;

    DOM.drillPromptInfo.textContent = `Anda sedang membaca QS. ${q.surah_name_1} : Ayat ${q.verse_num_1}`;
    DOM.drillPromptArabic.textContent = q.text_1;

    // Jawaban benar vs jebakan
    const correctNext = q.next_words_1 || 'فَإِذَا جَاءَتِ الطَّامَّةُ الْكُبْرَىٰ';
    const trapNext = q.next_words_2 || 'فَإِذَا جَاءَتِ الصَّاخَّةُ';

    // Acak posisi opsi A dan B
    const isCorrectA = Math.random() > 0.5;
    DOM.drillOptA.dataset.isCorrect = isCorrectA ? 'true' : 'false';
    DOM.drillOptB.dataset.isCorrect = isCorrectA ? 'false' : 'true';

    DOM.drillOptAText.textContent = isCorrectA ? correctNext : trapNext;
    DOM.drillOptBText.textContent = isCorrectA ? trapNext : correctNext;
  }

  function handleDrillAnswer(isChoiceA) {
    if (state.drill.answered) return;
    state.drill.answered = true;

    const btn = isChoiceA ? DOM.drillOptA : DOM.drillOptB;
    const isCorrect = btn.dataset.isCorrect === 'true';
    const q = state.drill.questions[state.drill.currentIndex];

    if (isCorrect) {
      state.drill.score++;
      DOM.drillFeedback.className = 'drill-feedback correct';
      DOM.drillFeedbackTitle.textContent = 'Jawaban Tepat';
      DOM.drillFeedbackDesc.textContent = `Anda berhasil melanjutkan ayat tanpa terjebak ke surah ${q.surah_name_2}.`;
    } else {
      DOM.drillFeedback.className = 'drill-feedback wrong';
      DOM.drillFeedbackTitle.textContent = 'Perhatian: Pilihan Keliru';
      DOM.drillFeedbackDesc.textContent = `Itu adalah lanjutan milik QS. ${q.surah_name_2} : ${q.verse_num_2 + 1}.`;
    }

    const savedAnchor = localStorage.getItem(`memory_anchor_${q.group_id}`);
    if (savedAnchor) {
      DOM.drillFeedbackAnchor.textContent = `Rumus Jembatan Ingatan: ${savedAnchor}`;
      DOM.drillFeedbackAnchor.style.display = 'block';
    } else {
      DOM.drillFeedbackAnchor.style.display = 'none';
    }

    DOM.drillScoreBadge.textContent = `Skor: ${state.drill.score} / ${state.drill.currentIndex + 1}`;
    DOM.drillFeedback.classList.remove('hidden');
  }

  // =========================================================================
  // 9. EVENT LISTENERS
  // =========================================================================
  function setupEventListeners() {
    // Nav Tabs
    DOM.tabBtns.forEach(btn => {
      btn.addEventListener('click', () => {
        DOM.tabBtns.forEach(b => b.classList.remove('active'));
        DOM.tabSections.forEach(s => s.classList.remove('active'));
        btn.classList.add('active');
        document.getElementById(`section-${btn.dataset.tab}`).classList.add('active');
      });
    });

    // Surah Dropdown Change
    DOM.surahSelect.addEventListener('change', (e) => {
      state.activeSurahId = parseInt(e.target.value, 10);
      const firstVerse = state.data.verses.find(v => v.surah_id === state.activeSurahId);
      if (firstVerse) {
        state.activePageNumber = firstVerse.page_number;
      }
      renderMushafView();
      renderMarkedMushafView();
      if (state.activeScope === 'surah') {
        renderRadarMutasyabihat();
      }
    });

    // Close Inspector
    if (DOM.btnCloseInspector) {
      DOM.btnCloseInspector.addEventListener('click', () => {
        document.querySelectorAll('.verse-segment.active-highlight').forEach(el => el.classList.remove('active-highlight'));
        if (DOM.inspectorTitle) DOM.inspectorTitle.textContent = 'Pilih ayat bertanda di atas';
        if (DOM.inspectorBody) {
          DOM.inspectorBody.innerHTML = '<p class="inspector-placeholder">Arahkan kursor atau sentuh ayat yang memiliki tanda emas di atas untuk melihat detail perbandingan ayat mirip, kata pembeda, dan sambungan surahnya.</p>';
        }
      });
    }

    // Hide/Peek Mode Toggle
    DOM.btnHideMode.addEventListener('click', () => {
      state.hideMode = !state.hideMode;
      DOM.btnHideMode.classList.toggle('active', state.hideMode);
      document.querySelectorAll('.mushaf-word').forEach(w => {
        if (state.hideMode) {
          w.classList.add('blurred');
          w.classList.remove('revealed');
        } else {
          w.classList.remove('blurred');
        }
      });
    });

    // Fullscreen Toggle
    DOM.btnFullscreen.addEventListener('click', () => {
      if (!document.fullscreenElement) {
        document.documentElement.requestFullscreen().catch(() => {});
      } else {
        document.exitFullscreen().catch(() => {});
      }
    });

    // Page navigation
    DOM.btnPrevPage.addEventListener('click', () => {
      if (state.activePageNumber > 582) {
        state.activePageNumber--;
        renderMushafView();
      }
    });

    DOM.btnNextPage.addEventListener('click', () => {
      if (state.activePageNumber < 604) {
        state.activePageNumber++;
        renderMushafView();
      }
    });

    // Voice & Mic
    DOM.btnToggleMic.addEventListener('click', toggleListening);
    DOM.btnDismissAlert.addEventListener('click', () => DOM.trapAlertBox.classList.add('hidden'));

    // Murattal Playback
    DOM.btnPlayVerse.addEventListener('click', togglePlayCurrentVerse);
    DOM.reciterSelect.addEventListener('change', (e) => {
      state.reciter = e.target.value;
    });
    DOM.btnLoopVerse.addEventListener('click', () => {
      const counts = [1, 3, 5];
      const nextIdx = (counts.indexOf(state.repeatCount) + 1) % counts.length;
      state.repeatCount = counts[nextIdx];
      DOM.btnLoopVerse.innerHTML = `
        <svg class="btn-svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <polyline points="17 1 21 5 17 9"></polyline>
          <path d="M3 11V9a4 4 0 0 1 4-4h14"></path>
          <polyline points="7 23 3 19 7 15"></polyline>
          <path d="M21 13v2a4 4 0 0 1-4 4H3"></path>
        </svg>
        <span>Ulangi ${state.repeatCount}x</span>
      `;
    });

    // Copy Verse
    DOM.btnCopyVerse.addEventListener('click', () => {
      const text = `${DOM.detailArabic.textContent}\n${DOM.detailTranslation.textContent}`;
      navigator.clipboard.writeText(text).then(() => {
        DOM.btnCopyVerse.textContent = 'Tersalin!';
        setTimeout(() => DOM.btnCopyVerse.textContent = 'Salin', 1500);
      });
    });

    // Radar Filter & Search
    DOM.radarSearchInput.addEventListener('input', (e) => {
      state.searchQuery = e.target.value;
      renderRadarMutasyabihat();
    });

    DOM.scopeBtns.forEach(btn => {
      btn.addEventListener('click', () => {
        DOM.scopeBtns.forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        state.activeScope = btn.dataset.scope;
        renderRadarMutasyabihat();
      });
    });

    // Drill Mode Answers
    DOM.drillOptA.addEventListener('click', () => handleDrillAnswer(true));
    DOM.drillOptB.addEventListener('click', () => handleDrillAnswer(false));
    DOM.btnNextDrill.addEventListener('click', () => {
      state.drill.currentIndex = (state.drill.currentIndex + 1) % state.drill.questions.length;
      renderDrillCard();
    });

    // Modal Anchor
    DOM.btnCloseModal.addEventListener('click', () => DOM.anchorModal.close());
    DOM.btnCancelModal.addEventListener('click', () => DOM.anchorModal.close());
    DOM.btnSaveModal.addEventListener('click', () => {
      if (activeEditingGroupId) {
        const val = DOM.modalAnchorInput.value.trim();
        localStorage.setItem(`memory_anchor_${activeEditingGroupId}`, val);
        const display = document.getElementById(`anchor-display-${activeEditingGroupId}`);
        if (display) display.textContent = val || 'Belum ada rumus catatan.';
      }
      DOM.anchorModal.close();
    });

    // Keyboard Shortcuts: Space to Peek
    window.addEventListener('keydown', (e) => {
      if (e.code === 'Space' && e.target.tagName !== 'INPUT' && e.target.tagName !== 'TEXTAREA') {
        e.preventDefault();
        peekNextWord();
      }
    });
  }

  // Jalankan saat DOM siap
  document.addEventListener('DOMContentLoaded', initApp);
})();
