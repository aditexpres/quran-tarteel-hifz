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
    radarSurahId: null,
    radarVerseNumber: null,
    keepMicContinuous: false,
    drill: {
      questions: [],
      currentIndex: 0,
      score: 0,
      answered: false
    },
    correction: {
      verseNumber: 1,
      blindMode: false,
      autoAdvance: true,
      autoPlayQariOnMistake: false,
      isContinuousSimulating: false,
      wordResults: [],
      selectedWordIdx: -1,
      sessionHistory: [],
      lastFinalizedKey: null,
      simCounter: 0
    },
    gtaf: {
      viewMode: 'verse', // 'verse' (Ayat & Per Kata) | 'mushaf' (Mushaf 15 Baris)
      sidebarOpen: true,
      idxTab: 'surah', // 'surah' | 'juz' | 'page' | 'bookmarks'
      idxSearch: '',
      showVoicePanel: false,
      showWbw: true,
      showTranslit: true,
      showTranslation: true,
      showTafsirAll: false,
      blurHifz: false,
      arabicScale: 1.0,
      autoNextAudio: true,
      playingSurahId: null,
      playingVerseNumber: null,
      expandedTafsirKeys: new Set(),
      revealedWordKeys: new Set(),
      bookmarks: [],
      lastRead: null
    }
  };

  let corrAutoAdvanceTimer = null;
  let corrContinuousSimTimer = null;

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
    mushafJuzLabel: document.getElementById('mushaf-juz-label'),
    mushafSurahLabel: document.getElementById('mushaf-surah-label'),
    mushafPageLabel: document.getElementById('mushaf-page-label'),
    pageIndicator: document.getElementById('page-indicator'),
    btnPrevPage: document.getElementById('btn-prev-page'),
    btnNextPage: document.getElementById('btn-next-page'),

    // Marked Mushaf elements
    markedPageContainer: document.getElementById('marked-page-container'),
    markedJuzLabel: document.getElementById('marked-juz-label'),
    markedSurahLabel: document.getElementById('marked-surah-label'),
    btnMarkedSurahLabel: document.getElementById('btn-marked-surah-label'),
    btnMarkedBannerPicker: document.getElementById('btn-marked-banner-picker'),
    btnMarkedSwipePicker: document.getElementById('btn-marked-swipe-picker'),
    markedPickerBadgeText: document.getElementById('marked-picker-badge-text'),
    markedPageLabel: document.getElementById('marked-page-label'),
    markedBismillahBar: document.getElementById('marked-bismillah-bar'),
    markedVersesFlow: document.getElementById('marked-verses-flow'),
    btnMarkedPrevSurah: document.getElementById('btn-marked-prev-surah'),
    btnMarkedNextSurah: document.getElementById('btn-marked-next-surah'),
    markedPrevSurahLabel: document.getElementById('marked-prev-surah-label'),
    markedNextSurahLabel: document.getElementById('marked-next-surah-label'),
    mutasyabihatInspector: document.getElementById('mutasyabihat-inspector'),
    inspectorTitle: document.getElementById('inspector-title'),
    inspectorBody: document.getElementById('inspector-body'),
    btnCloseInspector: document.getElementById('btn-close-inspector'),
    surahPickerModal: document.getElementById('surah-picker-modal'),
    btnCloseSurahPicker: document.getElementById('btn-close-surah-picker'),
    surahPickerSearch: document.getElementById('surah-picker-search'),
    surahPickerList: document.getElementById('surah-picker-list'),

    // Correction Mode elements
    corrSurahSelect: document.getElementById('corr-surah-select'),
    corrVerseSelect: document.getElementById('corr-verse-select'),
    btnCorrPrev: document.getElementById('btn-corr-prev'),
    btnCorrNext: document.getElementById('btn-corr-next'),
    btnCorrAutoAdvance: document.getElementById('btn-corr-auto-advance'),
    btnCorrAutoQari: document.getElementById('btn-corr-auto-qari'),
    btnCorrBlind: document.getElementById('btn-corr-blind'),
    btnCorrListenQari: document.getElementById('btn-corr-listen-qari'),
    btnCorrMic: document.getElementById('btn-corr-mic'),
    corrMicLabel: document.getElementById('corr-mic-label'),
    btnCorrSimContinuous: document.getElementById('btn-corr-sim-continuous'),
    btnCorrSimPerfect: document.getElementById('btn-corr-sim-perfect'),
    btnCorrSimMistake: document.getElementById('btn-corr-sim-mistake'),
    corrTranscriptInput: document.getElementById('corr-transcript-input'),
    btnCorrEvaluate: document.getElementById('btn-corr-evaluate'),
    corrMetricAcc: document.getElementById('corr-metric-acc'),
    corrMetricCorrect: document.getElementById('corr-metric-correct'),
    corrMetricNear: document.getElementById('corr-metric-near'),
    corrMetricWrong: document.getElementById('corr-metric-wrong'),
    corrAutoAdvanceBanner: document.getElementById('corr-auto-advance-banner'),
    corrAutoAdvanceText: document.getElementById('corr-auto-advance-text'),
    btnCorrHoldVerse: document.getElementById('btn-corr-hold-verse'),
    corrSurahHeader: document.getElementById('corr-surah-header'),
    corrWordsFlow: document.getElementById('corr-words-flow'),
    corrVerseTranslation: document.getElementById('corr-verse-translation'),
    corrSessionHistoryCard: document.getElementById('corr-session-history-card'),
    corrHistTotal: document.getElementById('corr-hist-total'),
    corrHistCorrect: document.getElementById('corr-hist-correct'),
    corrHistMistake: document.getElementById('corr-hist-mistake'),
    btnCorrClearHistory: document.getElementById('btn-corr-clear-history'),
    corrHistoryList: document.getElementById('corr-history-list'),
    corrInspectorBadge: document.getElementById('corr-inspector-badge'),
    corrInspectorTitle: document.getElementById('corr-inspector-title'),
    corrInspectorBody: document.getElementById('corr-inspector-body'),
    
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
    radarSurahSelect: document.getElementById('radar-surah-select'),
    radarVerseSelect: document.getElementById('radar-verse-select'),
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
    btnSaveModal: document.getElementById('btn-save-modal'),

    // GTAF Basic Qur'an Reader Elements
    gtafLayoutContainer: document.getElementById('gtaf-layout-container'),
    gtafSidebar: document.getElementById('gtaf-sidebar'),
    btnGtafCloseSidebar: document.getElementById('btn-gtaf-close-sidebar'),
    btnGtafToggleSidebar: document.getElementById('btn-gtaf-toggle-sidebar'),
    gtafIdxTabs: document.querySelectorAll('.gtaf-idx-tab'),
    gtafSidebarSearch: document.getElementById('gtaf-sidebar-search'),
    gtafPinCount: document.getElementById('gtaf-pin-count'),
    gtafLastReadBanner: document.getElementById('gtaf-last-read-banner'),
    gtafLastReadText: document.getElementById('gtaf-last-read-text'),
    btnGtafResumeRead: document.getElementById('btn-gtaf-resume-read'),
    gtafSidebarList: document.getElementById('gtaf-sidebar-list'),
    gtafSurahSelect: document.getElementById('gtaf-surah-select'),
    gtafVerseSelect: document.getElementById('gtaf-verse-select'),
    btnGtafModeVerse: document.getElementById('btn-gtaf-mode-verse'),
    btnGtafModeMushaf: document.getElementById('btn-gtaf-mode-mushaf'),
    btnGtafToggleVoicePanel: document.getElementById('btn-gtaf-toggle-voice-panel'),
    gtafVoicePanel: document.getElementById('gtaf-voice-panel'),
    btnGtafOptWbw: document.getElementById('btn-gtaf-opt-wbw'),
    btnGtafOptTranslit: document.getElementById('btn-gtaf-opt-translit'),
    btnGtafOptTranslation: document.getElementById('btn-gtaf-opt-translation'),
    btnGtafOptTafsir: document.getElementById('btn-gtaf-opt-tafsir'),
    btnGtafOptBlur: document.getElementById('btn-gtaf-opt-blur'),
    btnGtafFontDec: document.getElementById('btn-gtaf-font-dec'),
    btnGtafFontReset: document.getElementById('btn-gtaf-font-reset'),
    btnGtafFontInc: document.getElementById('btn-gtaf-font-inc'),
    gtafVerseReaderView: document.getElementById('gtaf-verse-reader-view'),
    gtafMushafSheetView: document.getElementById('gtaf-mushaf-sheet-view'),
    gtafBannerNum: document.getElementById('gtaf-banner-num'),
    gtafBannerLatin: document.getElementById('gtaf-banner-latin'),
    gtafBannerMeta: document.getElementById('gtaf-banner-meta'),
    gtafBannerArabic: document.getElementById('gtaf-banner-arabic'),
    btnGtafPlaySurah: document.getElementById('btn-gtaf-play-surah'),
    gtafBismillahRow: document.getElementById('gtaf-bismillah-row'),
    gtafVersesList: document.getElementById('gtaf-verses-list'),
    btnGtafPrevSurah: document.getElementById('btn-gtaf-prev-surah'),
    btnGtafScrollTop: document.getElementById('btn-gtaf-scroll-top'),
    btnGtafNextSurah: document.getElementById('btn-gtaf-next-surah'),

    // Sticky Audio Bar Elements
    gtafStickyAudioBar: document.getElementById('gtaf-sticky-audio-bar'),
    gtafAudioTitle: document.getElementById('gtaf-audio-title'),
    gtafAudioSubtitle: document.getElementById('gtaf-audio-subtitle'),
    btnGtafAudioPrev: document.getElementById('btn-gtaf-audio-prev'),
    btnGtafAudioPlay: document.getElementById('btn-gtaf-audio-play'),
    btnGtafAudioNext: document.getElementById('btn-gtaf-audio-next'),
    gtafAudioReciter: document.getElementById('gtaf-audio-reciter'),
    btnGtafAudioAutonext: document.getElementById('btn-gtaf-audio-autonext'),
    btnGtafAudioLoop: document.getElementById('btn-gtaf-audio-loop'),
    btnGtafAudioClose: document.getElementById('btn-gtaf-audio-close')
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
    initGtafState();
    populateSurahDropdown();
    setupEventListeners();
    setupSpeechRecognition();
    renderMushafView();
    renderMarkedMushafView();
    renderCorrectionView();
    renderRadarMutasyabihat();
    initDrillQuestions();
  }

  function initGtafState() {
    try {
      const savedPins = localStorage.getItem('quran_gtaf_bookmarks');
      if (savedPins) {
        state.gtaf.bookmarks = JSON.parse(savedPins) || [];
      }
      const savedLast = localStorage.getItem('quran_gtaf_last_read');
      if (savedLast) {
        state.gtaf.lastRead = JSON.parse(savedLast) || null;
      }
    } catch (_) {}
  }

  function saveGtafBookmarks() {
    try {
      localStorage.setItem('quran_gtaf_bookmarks', JSON.stringify(state.gtaf.bookmarks));
    } catch (_) {}
  }

  function setGtafLastRead(verse) {
    if (!verse) return;
    const surah = state.data.surahs.find(s => s.id === verse.surah_id);
    state.gtaf.lastRead = {
      surahId: verse.surah_id,
      surahName: surah ? surah.name_latin : (verse.surah_name_latin || `Surah ${verse.surah_id}`),
      verseNumber: verse.verse_number,
      pageNumber: verse.page_number
    };
    try {
      localStorage.setItem('quran_gtaf_last_read', JSON.stringify(state.gtaf.lastRead));
    } catch (_) {}
    renderGtafSidebar();
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

    const verses = state.data.verses.filter(v => v.surah_id === state.activeSurahId);
    if (!verses.length) return;

    const currentJuz = verses[0].juz_number || 30;

    if (DOM.mushafJuzLabel) DOM.mushafJuzLabel.textContent = `الجزء ${toArabicDigits(currentJuz)}`;
    DOM.mushafSurahLabel.textContent = `سُورَةُ ${surah.name_arabic}`;
    DOM.mushafPageLabel.textContent = toArabicDigits(state.activePageNumber);
    DOM.pageIndicator.textContent = `Halaman ${state.activePageNumber}`;

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

    // Sinkronkan juga tampilan Al-Qur'an Dasar model quran.gtaf.org
    renderGtafSidebar();
    renderGtafReaderView();
  }

  // =========================================================================
  // 4A. ENGINE PEMBACA AL-QUR'AN DASAR MODEL QURAN.GTAF.ORG
  // =========================================================================
  function jumpToSurahAndVerse(surahId, verseNumber = 1, smoothScroll = true) {
    stopContinuousSimulation();
    cancelCorrAutoAdvance(true);
    const sId = parseInt(surahId, 10);
    const vNum = parseInt(verseNumber, 10) || 1;
    const surahChanged = state.activeSurahId !== sId;
    state.activeSurahId = sId;
    state.activeVerseIndex = Math.max(0, vNum - 1);

    const targetVerse = state.data.verses.find(v => v.surah_id === sId && v.verse_number === vNum) ||
      state.data.verses.find(v => v.surah_id === sId);
    if (targetVerse) {
      state.activePageNumber = targetVerse.page_number;
    }

    if (DOM.surahSelect) DOM.surahSelect.value = String(sId);
    if (surahChanged) {
      renderMushafView();
      renderMarkedMushafView();
      state.correction.verseNumber = vNum;
      state.correction.wordResults = [];
      state.correction.lastFinalizedKey = null;
      renderCorrectionView();
      if (state.activeScope === 'surah') {
        renderRadarMutasyabihat();
      }
    } else {
      if (DOM.gtafVerseSelect) DOM.gtafVerseSelect.value = String(vNum);
      if (targetVerse) selectActiveVerse(targetVerse, 0);
      renderGtafSidebar();
    }

    if (smoothScroll) {
      setTimeout(() => {
        const cardEl = document.getElementById(`gtaf-ayah-${sId}-${vNum}`);
        if (cardEl && state.gtaf.viewMode === 'verse') {
          cardEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
      }, 80);
    }
  }

  function renderGtafSidebar() {
    if (!DOM.gtafSidebarList) return;

    if (DOM.gtafPinCount) {
      DOM.gtafPinCount.textContent = String(state.gtaf.bookmarks.length);
    }

    if (DOM.gtafLastReadBanner && DOM.gtafLastReadText) {
      if (state.gtaf.lastRead) {
        DOM.gtafLastReadBanner.classList.remove('hidden');
        DOM.gtafLastReadText.textContent = `QS. ${state.gtaf.lastRead.surahName} : Ayat ${state.gtaf.lastRead.verseNumber}`;
      } else {
        DOM.gtafLastReadBanner.classList.add('hidden');
      }
    }

    const q = (state.gtaf.idxSearch || '').toLowerCase().trim();
    const tab = state.gtaf.idxTab || 'surah';
    DOM.gtafSidebarList.innerHTML = '';

    if (tab === 'surah') {
      const surahs = (state.data.surahs || []).filter(s => {
        if (!q) return true;
        return s.name_latin.toLowerCase().includes(q) ||
          s.translation_id.toLowerCase().includes(q) ||
          s.name_arabic.includes(q) ||
          String(s.id) === q;
      });

      if (!surahs.length) {
        DOM.gtafSidebarList.innerHTML = `<div style="padding:20px; text-align:center; font-size:0.82rem; color:var(--text-secondary);">Surah tidak ditemukan.</div>`;
        return;
      }

      surahs.forEach(s => {
        const isActive = s.id === state.activeSurahId;
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = `gtaf-idx-item ${isActive ? 'active' : ''}`;
        btn.innerHTML = `
          <div class="gtaf-idx-left">
            <span class="gtaf-idx-num">${s.id}</span>
            <div class="gtaf-idx-meta">
              <div class="gtaf-idx-title">${s.name_latin}</div>
              <div class="gtaf-idx-sub">${s.translation_id} • ${s.total_verses} Ayat</div>
            </div>
          </div>
          <span class="gtaf-idx-arabic">${s.name_arabic}</span>
        `;
        btn.addEventListener('click', () => {
          jumpToSurahAndVerse(s.id, 1, false);
          window.scrollTo({ top: 0, behavior: 'smooth' });
        });
        DOM.gtafSidebarList.appendChild(btn);
      });
    } else if (tab === 'juz') {
      const juzMap = new Map();
      (state.data.verses || []).forEach(v => {
        if (!juzMap.has(v.juz_number)) {
          juzMap.set(v.juz_number, v);
        }
      });

      const juzList = [];
      for (let j = 1; j <= 30; j++) {
        const firstV = juzMap.get(j);
        if (firstV) {
          const sObj = state.data.surahs.find(s => s.id === firstV.surah_id);
          juzList.push({
            juz: j,
            surahId: firstV.surah_id,
            surahName: sObj ? sObj.name_latin : firstV.surah_name_latin,
            verseNumber: firstV.verse_number,
            pageNumber: firstV.page_number
          });
        }
      }

      const filteredJuz = juzList.filter(item => {
        if (!q) return true;
        return String(item.juz).includes(q) ||
          `juz ${item.juz}`.includes(q) ||
          item.surahName.toLowerCase().includes(q);
      });

      filteredJuz.forEach(item => {
        const activeFirst = state.data.verses.find(v => v.surah_id === state.activeSurahId);
        const isActive = activeFirst && activeFirst.juz_number === item.juz;
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = `gtaf-idx-item ${isActive ? 'active' : ''}`;
        btn.innerHTML = `
          <div class="gtaf-idx-left">
            <span class="gtaf-idx-num">${item.juz}</span>
            <div class="gtaf-idx-meta">
              <div class="gtaf-idx-title">Juz ${item.juz}</div>
              <div class="gtaf-idx-sub">Mulai QS. ${item.surahName} : ${item.verseNumber} • Hal ${item.pageNumber}</div>
            </div>
          </div>
          <span class="gtaf-idx-arabic">الجزء ${toArabicDigits(item.juz)}</span>
        `;
        btn.addEventListener('click', () => {
          jumpToSurahAndVerse(item.surahId, item.verseNumber, true);
        });
        DOM.gtafSidebarList.appendChild(btn);
      });
    } else if (tab === 'page') {
      const pageMap = new Map();
      (state.data.verses || []).forEach(v => {
        if (!pageMap.has(v.page_number)) {
          pageMap.set(v.page_number, v);
        }
      });

      const pages = Array.from(pageMap.keys()).sort((a, b) => a - b);
      const filteredPages = pages.filter(p => {
        if (!q) return true;
        const firstV = pageMap.get(p);
        const sName = (firstV && firstV.surah_name_latin ? firstV.surah_name_latin : '').toLowerCase();
        return String(p).includes(q) || sName.includes(q);
      }).slice(0, 120);

      filteredPages.forEach(p => {
        const firstV = pageMap.get(p);
        const isActive = state.activePageNumber === p;
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = `gtaf-idx-item ${isActive ? 'active' : ''}`;
        btn.innerHTML = `
          <div class="gtaf-idx-left">
            <span class="gtaf-idx-num">${p}</span>
            <div class="gtaf-idx-meta">
              <div class="gtaf-idx-title">Halaman ${p}</div>
              <div class="gtaf-idx-sub">QS. ${firstV.surah_name_latin} : ${firstV.verse_number} • Juz ${firstV.juz_number}</div>
            </div>
          </div>
          <span class="gtaf-idx-arabic">${toArabicDigits(p)}</span>
        `;
        btn.addEventListener('click', () => {
          state.activePageNumber = p;
          jumpToSurahAndVerse(firstV.surah_id, firstV.verse_number, true);
        });
        DOM.gtafSidebarList.appendChild(btn);
      });
    } else if (tab === 'bookmarks') {
      const pins = (state.gtaf.bookmarks || []).filter(b => {
        if (!q) return true;
        return b.surahName.toLowerCase().includes(q) || String(b.key).includes(q);
      });

      if (!pins.length) {
        DOM.gtafSidebarList.innerHTML = `
          <div style="padding:20px 12px; text-align:center; font-size:0.8rem; color:var(--text-secondary); line-height:1.5;">
            Belum ada ayat yang disimpan.<br>Klik ikon <strong>Pin (🔖)</strong> pada kartu ayat untuk menandai ayat favorit atau batas hafalan.
          </div>
        `;
        return;
      }

      pins.forEach(b => {
        const row = document.createElement('div');
        row.className = 'gtaf-idx-item';
        row.innerHTML = `
          <div class="gtaf-idx-left" style="flex:1; cursor:pointer;">
            <span class="gtaf-idx-num">${b.surahId}:${b.verseNumber}</span>
            <div class="gtaf-idx-meta">
              <div class="gtaf-idx-title">QS. ${b.surahName} : Ayat ${b.verseNumber}</div>
              <div class="gtaf-idx-sub">Hal ${b.pageNumber} • Juz ${b.juzNumber}</div>
            </div>
          </div>
          <button type="button" class="btn-close btn-remove-pin" data-key="${b.key}" title="Hapus Penanda" aria-label="Hapus Penanda">✕</button>
        `;
        row.querySelector('.gtaf-idx-left').addEventListener('click', () => {
          jumpToSurahAndVerse(b.surahId, b.verseNumber, true);
        });
        row.querySelector('.btn-remove-pin').addEventListener('click', (e) => {
          e.stopPropagation();
          state.gtaf.bookmarks = state.gtaf.bookmarks.filter(item => item.key !== b.key);
          saveGtafBookmarks();
          renderGtafSidebar();
          renderGtafReaderView();
        });
        DOM.gtafSidebarList.appendChild(row);
      });
    }
  }

  function renderGtafReaderView() {
    if (!DOM.gtafVersesList) return;

    const surahs = state.data.surahs || [];
    const surahIdx = surahs.findIndex(s => s.id === state.activeSurahId);
    const surah = surahs[surahIdx] || surahs[0];
    if (!surah) return;

    const verses = state.data.verses.filter(v => v.surah_id === state.activeSurahId);
    if (!verses.length) return;

    // Populate top dropdowns
    if (DOM.gtafSurahSelect) {
      if (DOM.gtafSurahSelect.options.length !== surahs.length) {
        DOM.gtafSurahSelect.innerHTML = '';
        surahs.forEach(s => {
          const opt = document.createElement('option');
          opt.value = s.id;
          opt.textContent = `${s.id}. QS. ${s.name_latin} (${s.total_verses} Ayat)`;
          DOM.gtafSurahSelect.appendChild(opt);
        });
      }
      DOM.gtafSurahSelect.value = String(surah.id);
    }

    if (DOM.gtafVerseSelect) {
      DOM.gtafVerseSelect.innerHTML = '';
      verses.forEach(v => {
        const opt = document.createElement('option');
        opt.value = v.verse_number;
        opt.textContent = `Loncat: Ayat ${v.verse_number}`;
        DOM.gtafVerseSelect.appendChild(opt);
      });
      const currentVNum = Math.min(verses.length, Math.max(1, state.activeVerseIndex + 1));
      DOM.gtafVerseSelect.value = String(currentVNum);
    }

    // Update Banner Surah
    const firstPage = verses[0].page_number;
    const lastPage = verses[verses.length - 1].page_number;
    const pageText = firstPage === lastPage ? `Halaman ${firstPage}` : `Halaman ${firstPage}-${lastPage}`;
    const revText = surah.revelation_type === 'madaniyah' ? 'Madaniyah' : 'Makkiyah';

    if (DOM.gtafBannerNum) DOM.gtafBannerNum.textContent = `Surah Ke-${surah.id}`;
    if (DOM.gtafBannerLatin) DOM.gtafBannerLatin.textContent = `QS. ${surah.name_latin} (${surah.translation_id})`;
    if (DOM.gtafBannerMeta) {
      DOM.gtafBannerMeta.textContent = `${revText} • ${surah.total_verses} Ayat • Juz ${verses[0].juz_number} • ${pageText}`;
    }
    if (DOM.gtafBannerArabic) DOM.gtafBannerArabic.textContent = `سُورَةُ ${surah.name_arabic}`;
    if (DOM.gtafBismillahRow) {
      DOM.gtafBismillahRow.style.display = (surah.id === 1 || surah.id === 9) ? 'none' : 'block';
    }

    // Update Footer Prev/Next Surah
    const prevSurah = surahIdx > 0 ? surahs[surahIdx - 1] : null;
    const nextSurah = (surahIdx >= 0 && surahIdx + 1 < surahs.length) ? surahs[surahIdx + 1] : null;
    if (DOM.btnGtafPrevSurah) {
      DOM.btnGtafPrevSurah.disabled = !prevSurah;
      DOM.btnGtafPrevSurah.textContent = prevSurah ? `◄ QS. ${prevSurah.name_latin}` : '◄ Awal Mushaf';
    }
    if (DOM.btnGtafNextSurah) {
      DOM.btnGtafNextSurah.disabled = !nextSurah;
      DOM.btnGtafNextSurah.textContent = nextSurah ? `QS. ${nextSurah.name_latin} ►` : 'Akhir Mushaf ►';
    }

    // Render Kartu Ayat Demi Ayat
    DOM.gtafVersesList.innerHTML = '';

    verses.forEach(v => {
      const verseKey = `${v.surah_id}:${v.verse_number}`;
      const isPlayingThis = state.gtaf.playingSurahId === v.surah_id &&
        state.gtaf.playingVerseNumber === v.verse_number &&
        DOM.globalAudio && !DOM.globalAudio.paused;
      const isBookmarked = state.gtaf.bookmarks.some(b => b.key === verseKey);
      const isTafsirOpen = state.gtaf.showTafsirAll || state.gtaf.expandedTafsirKeys.has(verseKey);

      // Cek apakah memiliki pasangan Mutasyabihat
      const twinPair = (state.data.mutasyabihat || []).find(p =>
        (p.surah_id_1 === v.surah_id && p.verse_num_1 === v.verse_number) ||
        (p.surah_id_2 === v.surah_id && p.verse_num_2 === v.verse_number)
      );

      const card = document.createElement('article');
      card.className = `gtaf-ayah-card ${isPlayingThis ? 'active-playing' : ''}`;
      card.id = `gtaf-ayah-${v.surah_id}-${v.verse_number}`;

      // Bangun Konten Kata Demi Kata (WBW) atau Baris Uthmani Utuh
      let arabicBodyHtml = '';
      if (state.gtaf.showWbw && v.words && v.words.length > 0) {
        const wbwBoxes = v.words.map((w, idx) => {
          const wPos = w.position || w.word_position || (idx + 1);
          const wKey = `${verseKey}:${wPos}`;
          const isBlurred = state.gtaf.blurHifz && !state.gtaf.revealedWordKeys.has(wKey);
          const translitHtml = state.gtaf.showTranslit && w.transliteration
            ? `<span class="gtaf-wbw-tr">${w.transliteration}</span>`
            : '';
          const meaningHtml = `<span class="gtaf-wbw-id">${w.translation_id || '-'}</span>`;
          return `
            <div class="gtaf-wbw-box" data-wkey="${wKey}" data-pos="${wPos}" title="Klik untuk memutar audio ayat / membuka lafal">
              <span class="gtaf-wbw-ar ${isBlurred ? 'gtaf-blur-hidden' : ''}">${w.text_uthmani}</span>
              ${translitHtml}
              ${meaningHtml}
            </div>
          `;
        }).join('');

        arabicBodyHtml = `
          <div class="gtaf-wbw-flow">
            ${wbwBoxes}
            <span class="gtaf-wbw-end-marker">۝${toArabicDigits(v.verse_number)}</span>
          </div>
        `;
      } else {
        const isBlurred = state.gtaf.blurHifz && !state.gtaf.revealedWordKeys.has(verseKey);
        arabicBodyHtml = `
          <div class="gtaf-pure-arabic-line ${isBlurred ? 'gtaf-blur-hidden' : ''}" data-vkey="${verseKey}" title="Klik untuk membuka lafal / memutar audio">
            ${v.text_uthmani} <span class="ayah-end-marker">۝${toArabicDigits(v.verse_number)}</span>
          </div>
        `;
      }

      const translationHtml = state.gtaf.showTranslation
        ? `
          <div class="gtaf-ayah-translation-box">
            <span class="gtaf-translation-label">Terjemah Kemenag RI</span>
            <div>${v.translation_id}</div>
          </div>
        `
        : '';

      let twinHtml = '';
      if (twinPair) {
        const isSide1 = twinPair.surah_id_1 === v.surah_id && twinPair.verse_num_1 === v.verse_number;
        const twinSurahId = isSide1 ? twinPair.surah_id_2 : twinPair.surah_id_1;
        const twinSurahName = isSide1 ? twinPair.surah_name_2 : twinPair.surah_name_1;
        const twinVerseNum = isSide1 ? twinPair.verse_num_2 : twinPair.verse_num_1;
        const twinText = isSide1 ? twinPair.text_2 : twinPair.text_1;
        twinHtml = `
          <div class="gtaf-ayah-twin-alert">
            <div>
              <strong>✦ Ayat Mutasyabihat:</strong> Mirip dengan <strong>QS. ${twinSurahName} : Ayat ${twinVerseNum}</strong>
              <span dir="rtl" style="font-family:var(--font-arabic); font-size:1.05rem; margin-left:6px;">(${twinText})</span>
            </div>
            <button type="button" class="btn btn-secondary btn-xs btn-gtaf-jump-twin" data-tsurah="${twinSurahId}" data-tverse="${twinVerseNum}">
              Lihat Kembaran
            </button>
          </div>
        `;
      }

      const tafsirHtml = isTafsirOpen
        ? `
          <div class="gtaf-ayah-tafsir-box">
            <strong>📖 Tafsir Wajiz Kemenag RI • QS. ${surah.name_latin} : Ayat ${v.verse_number}</strong>
            <div>${v.tafsir_wajiz || v.translation_id}</div>
          </div>
        `
        : '';

      card.innerHTML = `
        <div class="gtaf-ayah-rail">
          <div>
            <span class="gtaf-ayah-key-badge">${v.surah_id} : ${v.verse_number}</span>
            <div class="gtaf-ayah-subbadge" style="margin-top:4px;">Hal ${v.page_number} • Juz ${v.juz_number}</div>
          </div>
          <div class="gtaf-ayah-actions-grid">
            <button type="button" class="gtaf-icon-btn btn-gtaf-play ${isPlayingThis ? 'active' : ''}" title="${isPlayingThis ? 'Jeda Audio Ayat' : 'Putar Audio Ayat'}" aria-label="Putar Audio Ayat ${v.verse_number}">
              ${isPlayingThis ? '⏸' : '▶'}
            </button>
            <button type="button" class="gtaf-icon-btn btn-gtaf-pin ${isBookmarked ? 'bookmarked' : ''}" title="${isBookmarked ? 'Hapus dari Pin Ayat' : 'Simpan ke Pin Ayat'}" aria-label="Pin Ayat ${v.verse_number}">
              🔖
            </button>
            <button type="button" class="gtaf-icon-btn btn-gtaf-lastread" title="Tandai sebagai Terakhir Dibaca" aria-label="Tandai Terakhir Dibaca">
              📌
            </button>
            <button type="button" class="gtaf-icon-btn btn-gtaf-tafsir ${isTafsirOpen ? 'active' : ''}" title="Tampilkan / Sembunyikan Tafsir Wajiz" aria-label="Tafsir Ayat ${v.verse_number}">
              📖
            </button>
            <button type="button" class="gtaf-icon-btn btn-gtaf-copy" title="Salin Ayat & Terjemahan" aria-label="Salin Ayat ${v.verse_number}">
              📋
            </button>
          </div>
        </div>

        <div class="gtaf-ayah-content">
          ${arabicBodyHtml}
          ${translationHtml}
          ${twinHtml}
          ${tafsirHtml}
        </div>
      `;

      // Event Listeners pada Kartu Ayat
      const btnPlay = card.querySelector('.btn-gtaf-play');
      if (btnPlay) {
        btnPlay.addEventListener('click', () => {
          if (state.gtaf.playingSurahId === v.surah_id &&
              state.gtaf.playingVerseNumber === v.verse_number &&
              DOM.globalAudio && !DOM.globalAudio.paused) {
            DOM.globalAudio.pause();
            updateStickyAudioBarUI(false);
            renderGtafReaderView();
          } else {
            selectActiveVerse(v, 0);
            setGtafLastRead(v);
            playMurattalAudio(v.surah_id, v.verse_number);
          }
        });
      }

      const btnPin = card.querySelector('.btn-gtaf-pin');
      if (btnPin) {
        btnPin.addEventListener('click', () => {
          const existingIdx = state.gtaf.bookmarks.findIndex(b => b.key === verseKey);
          if (existingIdx >= 0) {
            state.gtaf.bookmarks.splice(existingIdx, 1);
          } else {
            state.gtaf.bookmarks.unshift({
              key: verseKey,
              surahId: v.surah_id,
              surahName: surah.name_latin,
              verseNumber: v.verse_number,
              pageNumber: v.page_number,
              juzNumber: v.juz_number
            });
          }
          saveGtafBookmarks();
          renderGtafSidebar();
          renderGtafReaderView();
        });
      }

      const btnLastRead = card.querySelector('.btn-gtaf-lastread');
      if (btnLastRead) {
        btnLastRead.addEventListener('click', () => {
          setGtafLastRead(v);
          btnLastRead.textContent = '✓';
          setTimeout(() => { btnLastRead.textContent = '📌'; }, 1200);
        });
      }

      const btnTafsir = card.querySelector('.btn-gtaf-tafsir');
      if (btnTafsir) {
        btnTafsir.addEventListener('click', () => {
          if (state.gtaf.expandedTafsirKeys.has(verseKey)) {
            state.gtaf.expandedTafsirKeys.delete(verseKey);
          } else {
            state.gtaf.expandedTafsirKeys.add(verseKey);
          }
          renderGtafReaderView();
        });
      }

      const btnCopy = card.querySelector('.btn-gtaf-copy');
      if (btnCopy) {
        btnCopy.addEventListener('click', () => {
          const copyStr = `${v.text_uthmani}\n"${v.translation_id}" (QS. ${surah.name_latin}: ${v.verse_number})`;
          navigator.clipboard.writeText(copyStr).then(() => {
            btnCopy.textContent = '✓';
            setTimeout(() => { btnCopy.textContent = '📋'; }, 1200);
          });
        });
      }

      const btnJumpTwin = card.querySelector('.btn-gtaf-jump-twin');
      if (btnJumpTwin) {
        btnJumpTwin.addEventListener('click', () => {
          const ts = parseInt(btnJumpTwin.dataset.tsurah, 10);
          const tv = parseInt(btnJumpTwin.dataset.tverse, 10);
          jumpToSurahAndVerse(ts, tv, true);
        });
      }

      card.querySelectorAll('.gtaf-wbw-box').forEach(box => {
        box.addEventListener('click', () => {
          const wKey = box.dataset.wkey;
          const pos = parseInt(box.dataset.pos, 10) || 1;
          if (state.gtaf.blurHifz && !state.gtaf.revealedWordKeys.has(wKey)) {
            state.gtaf.revealedWordKeys.add(wKey);
            const arSpan = box.querySelector('.gtaf-wbw-ar');
            if (arSpan) arSpan.classList.remove('gtaf-blur-hidden');
          } else {
            selectActiveVerse(v, pos);
            playMurattalAudio(v.surah_id, v.verse_number);
          }
        });
      });

      const pureLine = card.querySelector('.gtaf-pure-arabic-line');
      if (pureLine) {
        pureLine.addEventListener('click', () => {
          if (state.gtaf.blurHifz && !state.gtaf.revealedWordKeys.has(verseKey)) {
            state.gtaf.revealedWordKeys.add(verseKey);
            pureLine.classList.remove('gtaf-blur-hidden');
          } else {
            selectActiveVerse(v, 0);
            playMurattalAudio(v.surah_id, v.verse_number);
          }
        });
      }

      DOM.gtafVersesList.appendChild(card);
    });
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

    const surahs = state.data.surahs || [];
    const surahIdx = surahs.findIndex(s => s.id === state.activeSurahId);
    const surah = surahs[surahIdx] || surahs[0];
    if (!surah) return;

    const verses = state.data.verses.filter(v => v.surah_id === state.activeSurahId);
    if (!verses.length) return;

    const currentJuz = verses[0].juz_number || 30;

    if (DOM.markedSurahLabel) DOM.markedSurahLabel.textContent = `سُورَةُ ${surah.name_arabic}`;
    if (DOM.markedPageLabel) DOM.markedPageLabel.textContent = toArabicDigits(state.activePageNumber);
    if (DOM.markedJuzLabel) DOM.markedJuzLabel.textContent = `الجزء ${toArabicDigits(currentJuz)}`;

    const prevSurah = surahIdx > 0 ? surahs[surahIdx - 1] : null;
    const nextSurah = (surahIdx >= 0 && surahIdx + 1 < surahs.length) ? surahs[surahIdx + 1] : null;

    if (DOM.markedPrevSurahLabel) {
      DOM.markedPrevSurahLabel.textContent = prevSurah ? `◄ QS. ${prevSurah.name_latin}` : '◄ Sebelumnya';
    }
    if (DOM.btnMarkedPrevSurah) {
      DOM.btnMarkedPrevSurah.disabled = !prevSurah;
      DOM.btnMarkedPrevSurah.style.opacity = prevSurah ? '1' : '0.45';
      DOM.btnMarkedPrevSurah.style.pointerEvents = prevSurah ? 'auto' : 'none';
    }
    if (DOM.markedNextSurahLabel) {
      DOM.markedNextSurahLabel.textContent = nextSurah ? `QS. ${nextSurah.name_latin} ►` : 'Selanjutnya ►';
    }
    if (DOM.btnMarkedNextSurah) {
      DOM.btnMarkedNextSurah.disabled = !nextSurah;
      DOM.btnMarkedNextSurah.style.opacity = nextSurah ? '1' : '0.45';
      DOM.btnMarkedNextSurah.style.pointerEvents = nextSurah ? 'auto' : 'none';
    }

    if (DOM.markedPickerBadgeText) {
      DOM.markedPickerBadgeText.textContent = `QS. ${surah.name_latin} (${surah.id}/114) ▾`;
    }
    if (DOM.btnMarkedBannerPicker) {
      DOM.btnMarkedBannerPicker.textContent = `📖 Pilih Surah: QS. ${surah.name_latin} ▾`;
    }

    if (DOM.markedBismillahBar) {
      DOM.markedBismillahBar.style.display = surah.id === 9 ? 'none' : 'block';
    }

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
    const isIdentical = (!currentDiff || !currentDiff.length) && (!twinDiff || !twinDiff.length);

    DOM.inspectorBody.innerHTML = `
      ${isIdentical ? '<div style="margin-bottom:10px; padding:6px 12px; background:rgba(217, 179, 108, 0.15); border-radius:6px; font-size:12px; font-weight:600; color:var(--text-primary); border:1px solid rgba(217, 179, 108, 0.4);">⚡ Ayat Kembar Identik (100% sama persis). Poin kunci hafalan terletak pada transisi kelanjutan ayatnya!</div>' : ''}
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
  // 4C. MODAL PEMILIH SURAH (KLIK & SCROLL 114 SURAH)
  // =========================================================================
  function openSurahPickerModal() {
    if (!DOM.surahPickerModal) return;
    DOM.surahPickerModal.classList.remove('hidden');
    if (DOM.surahPickerSearch) {
      DOM.surahPickerSearch.value = '';
      setTimeout(() => DOM.surahPickerSearch.focus(), 100);
    }
    renderSurahPickerList('');

    // Scroll otomatis ke surah aktif
    setTimeout(() => {
      const activeEl = DOM.surahPickerList?.querySelector('.surah-picker-item.active');
      if (activeEl) {
        activeEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
    }, 150);
  }

  function closeSurahPickerModal() {
    if (!DOM.surahPickerModal) return;
    DOM.surahPickerModal.classList.add('hidden');
  }

  function renderSurahPickerList(query = '') {
    if (!DOM.surahPickerList) return;
    DOM.surahPickerList.innerHTML = '';

    const surahs = state.data.surahs || [];
    const q = (query || '').toLowerCase().trim();

    const filtered = surahs.filter(s => {
      if (!q) return true;
      return s.name_latin.toLowerCase().includes(q) ||
        s.translation_id.toLowerCase().includes(q) ||
        s.name_arabic.includes(q) ||
        String(s.id) === q;
    });

    if (!filtered.length) {
      DOM.surahPickerList.innerHTML = `
        <div style="text-align:center; padding:30px; color:var(--text-secondary);">
          Tidak ditemukan surah yang cocok dengan "${query}".
        </div>
      `;
      return;
    }

    filtered.forEach(s => {
      const isSelected = s.id === state.activeSurahId;
      const item = document.createElement('div');
      item.className = `surah-picker-item ${isSelected ? 'active' : ''}`;
      item.style.cssText = `
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 10px 14px;
        border-radius: 10px;
        border: 1px solid ${isSelected ? 'var(--primary)' : 'var(--border-card)'};
        background: ${isSelected ? 'var(--accent-glow, rgba(22,91,51,0.08))' : 'var(--bg-card)'};
        cursor: pointer;
        transition: all 0.15s ease;
      `;

      item.innerHTML = `
        <div style="display:flex; align-items:center; gap:12px;">
          <div style="width:32px; height:32px; border-radius:50%; background:${isSelected ? 'var(--primary)' : 'var(--border-card)'}; color:${isSelected ? '#fff' : 'inherit'}; display:flex; align-items:center; justify-content:center; font-weight:700; font-size:12px;">
            ${s.id}
          </div>
          <div>
            <div style="font-weight:700; font-size:14px; color:${isSelected ? 'var(--primary)' : 'inherit'};">
              QS. ${s.name_latin} ${isSelected ? '✓' : ''}
            </div>
            <div style="font-size:11.5px; opacity:0.75;">
              ${s.translation_id} • ${s.total_verses} Ayat • ${s.revelation_type === 'madaniyah' ? 'Madaniyah' : 'Makkiyah'}
            </div>
          </div>
        </div>
        <div style="font-family:'Amiri', serif; font-size:20px; font-weight:700; color:var(--gold, #9B7A38);">
          ${s.name_arabic}
        </div>
      `;

      item.addEventListener('click', () => {
        closeSurahPickerModal();
        if (s.id !== state.activeSurahId) {
          stopContinuousSimulation();
          cancelCorrAutoAdvance(true);
          state.activeSurahId = s.id;
          const firstVerse = state.data.verses.find(v => v.surah_id === s.id);
          if (firstVerse) {
            state.activePageNumber = firstVerse.page_number;
          }
          if (DOM.surahSelect) DOM.surahSelect.value = s.id;
          renderMushafView();
          renderMarkedMushafView();
          if (typeof renderCorrectionView === 'function') {
            state.correction.verseNumber = 1;
            state.correction.wordResults = [];
            state.correction.lastFinalizedKey = null;
            renderCorrectionView();
          }
          if (typeof renderRadarMutasyabihat === 'function') {
            renderRadarMutasyabihat();
          }
        }
      });

      DOM.surahPickerList.appendChild(item);
    });
  }

  // =========================================================================
  // 5. RADAR MUTASYABIHAT & MEMORY ANCHORS
  // =========================================================================
  function renderRadarMutasyabihat() {
    const container = DOM.radarCardsContainer;
    container.innerHTML = '';

    // Populate Cascading Dropdown: Pilih Surah
    if (DOM.radarSurahSelect) {
      if (DOM.radarSurahSelect.options.length <= 1 && state.data && state.data.surahs) {
        DOM.radarSurahSelect.innerHTML = '<option value="">Semua Surah (1 - 114)</option>';
        state.data.surahs.forEach(s => {
          const opt = document.createElement('option');
          opt.value = s.id;
          opt.textContent = `QS. ${s.id}. ${s.name_latin} (${s.name_arabic})`;
          DOM.radarSurahSelect.appendChild(opt);
        });
      }
      DOM.radarSurahSelect.value = state.radarSurahId || '';
    }

    // Populate Cascading Dropdown: Sub Pilihan Ayat
    if (DOM.radarVerseSelect) {
      DOM.radarVerseSelect.innerHTML = '<option value="">Semua Ayat</option>';
      if (state.radarSurahId && state.data && state.data.mutasyabihat) {
        const sId = parseInt(state.radarSurahId, 10);
        const verseSet = new Set();
        state.data.mutasyabihat.forEach(p => {
          if (p.surah_id_1 === sId) verseSet.add(p.verse_number_1);
          if (p.surah_id_2 === sId) verseSet.add(p.verse_number_2);
        });
        const sortedVerses = Array.from(verseSet).sort((a, b) => a - b);
        sortedVerses.forEach(v => {
          const opt = document.createElement('option');
          opt.value = v;
          opt.textContent = `Ayat ${v}`;
          DOM.radarVerseSelect.appendChild(opt);
        });
        DOM.radarVerseSelect.disabled = false;
        DOM.radarVerseSelect.value = state.radarVerseNumber || '';
      } else {
        DOM.radarVerseSelect.disabled = true;
      }
    }

    let pairs = state.data.mutasyabihat || [];

    // Filter Cascading Surah & Sub Ayat
    if (state.radarSurahId) {
      const sId = parseInt(state.radarSurahId, 10);
      pairs = pairs.filter(p => p.surah_id_1 === sId || p.surah_id_2 === sId);
      if (state.radarVerseNumber) {
        const vNum = parseInt(state.radarVerseNumber, 10);
        pairs = pairs.filter(p => 
          (p.surah_id_1 === sId && p.verse_number_1 === vNum) ||
          (p.surah_id_2 === sId && p.verse_number_2 === vNum)
        );
      }
    }

    // Filter scope
    if (state.activeScope === 'surah') {
      pairs = pairs.filter(p => p.surah_id_1 === state.activeSurahId || p.surah_id_2 === state.activeSurahId);
    } else if (state.activeScope === 'juz30') {
      pairs = pairs.filter(p => p.juz_1 === 30 || p.juz_2 === 30);
    } else if (state.activeScope === 'juz29') {
      pairs = pairs.filter(p => p.juz_1 === 29 || p.juz_2 === 29);
    } else if (state.activeScope === 'juz28') {
      pairs = pairs.filter(p => p.juz_1 === 28 || p.juz_2 === 28);
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

      const isIdentical = (!pair.diff_1 || !pair.diff_1.length) && (!pair.diff_2 || !pair.diff_2.length);

      card.innerHTML = `
        <div class="m-card-header">
          <span class="m-title">${pair.title}</span>
          <div style="display:flex; align-items:center; gap:6px;">
            ${isIdentical ? '<span class="m-scope-badge" style="background:rgba(217, 179, 108, 0.2); border:1px solid rgba(217, 179, 108, 0.45); font-weight:700;">Kembar Identik (100%)</span>' : ''}
            <span class="m-scope-badge">${pair.scope_juz ? 'Juz ' + pair.scope_juz : 'Lintas Juz'}</span>
          </div>
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
      if (DOM.btnCorrMic) DOM.btnCorrMic.classList.add('listening');
      if (DOM.corrMicLabel) {
        DOM.corrMicLabel.textContent = 'Sedang Menyimak Bersambung... (Klik untuk Berhenti)';
      }
      DOM.voiceIndicator.textContent = 'Mendengarkan bacaan Arab Anda secara real-time...';
    };

    state.recognition.onresult = (event) => {
      let interim = '';
      const lastRes = event.results[event.results.length - 1];
      const isFinal = Boolean(lastRes && lastRes.isFinal);
      for (let i = event.resultIndex; i < event.results.length; ++i) {
        interim += event.results[i][0].transcript + ' ';
      }
      interim = interim.trim();
      if (interim) {
        DOM.transcriptDisplay.textContent = `Suara: "${interim}"`;
        evaluateVoiceSpeech(interim);
        if (DOM.corrTranscriptInput) {
          DOM.corrTranscriptInput.value = interim;
          const corrSec = document.getElementById('section-correction');
          const isCorrTabActive = !corrSec || corrSec.classList.contains('active');
          evaluateCorrectionWords(interim, {
            isFinal,
            triggerAutoAdvance: isCorrTabActive,
            fromLiveMic: true
          });
        }
      }
    };

    state.recognition.onerror = (event) => {
      console.warn('Speech recognition error:', event.error);
      if (event.error === 'not-allowed' || event.error === 'service-not-allowed') {
        state.keepMicContinuous = false;
        DOM.voiceIndicator.textContent = 'Izin mikrofon belum diberikan.';
      }
    };

    state.recognition.onend = () => {
      if (state.keepMicContinuous) {
        try {
          state.recognition.start();
          return;
        } catch (_) {
          // Abaikan jika browser sedang me-reset instance
        }
      }
      state.isListening = false;
      DOM.btnToggleMic.classList.remove('listening');
      if (DOM.btnCorrMic) DOM.btnCorrMic.classList.remove('listening');
      if (DOM.corrMicLabel) {
        DOM.corrMicLabel.textContent = 'Mulai Rekam & Koreksi Bersambung';
      }
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
      state.keepMicContinuous = false;
      state.recognition.stop();
    } else {
      state.keepMicContinuous = true;
      try {
        state.recognition.start();
      } catch (_) {}
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

  const RECITER_NAMES = {
    Husary_128kbps: 'Syaikh Mahmoud Khalil Al-Husary',
    Alafasy_128kbps: 'Syaikh Mishary Rashid Alafasy',
    Minshawy_Murattal_128kbps: 'Syaikh Muhammad Siddiq Al-Minshawi',
    Abdul_Basit_Murattal_192kbps: 'Syaikh Abdul Basit Abdus Samad'
  };

  function updateStickyAudioBarUI(isPlaying) {
    if (!DOM.gtafStickyAudioBar) return;
    if (state.gtaf.playingSurahId && state.gtaf.playingVerseNumber) {
      DOM.gtafStickyAudioBar.classList.remove('hidden');
      const sObj = state.data.surahs.find(s => s.id === state.gtaf.playingSurahId);
      const sName = sObj ? sObj.name_latin : `Surah ${state.gtaf.playingSurahId}`;
      if (DOM.gtafAudioTitle) {
        DOM.gtafAudioTitle.textContent = `QS. ${sName} : Ayat ${state.gtaf.playingVerseNumber}`;
      }
      if (DOM.gtafAudioSubtitle) {
        DOM.gtafAudioSubtitle.textContent = RECITER_NAMES[state.reciter] || state.reciter;
      }
      if (DOM.btnGtafAudioPlay) {
        DOM.btnGtafAudioPlay.textContent = isPlaying ? '⏸ Jeda' : '▶ Putar';
      }
    }
  }

  function playMurattalAudio(surahId, verseNumber) {
    state.gtaf.playingSurahId = surahId;
    state.gtaf.playingVerseNumber = verseNumber;
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

    updateStickyAudioBarUI(true);
    renderGtafReaderView();

    const activeCard = document.getElementById(`gtaf-ayah-${surahId}-${verseNumber}`);
    if (activeCard && state.gtaf.viewMode === 'verse') {
      activeCard.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }

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
        if (state.gtaf.autoNextAudio) {
          const surahVerses = state.data.verses.filter(v => v.surah_id === surahId);
          if (verseNumber < surahVerses.length) {
            const nextV = surahVerses.find(v => v.verse_number === verseNumber + 1);
            if (nextV) {
              selectActiveVerse(nextV, 0);
              setGtafLastRead(nextV);
              playMurattalAudio(surahId, verseNumber + 1);
              return;
            }
          }
        }
        updateStickyAudioBarUI(false);
        renderGtafReaderView();
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
      updateStickyAudioBarUI(false);
      renderGtafReaderView();
    } else {
      const targetS = state.gtaf.playingSurahId || state.activeSurahId;
      const targetV = state.gtaf.playingVerseNumber || (state.activeVerseIndex + 1);
      playMurattalAudio(targetS, targetV);
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
  // 8B. MODE LATIHAN & KOREKSI BACAAN PER KATA + BERSAMBUNG OTOMATIS (ALA TARTEEL)
  // =========================================================================
  function getCorrectionActiveVerse() {
    const verses = state.data.verses.filter(v => v.surah_id === state.activeSurahId);
    if (!verses.length) return null;
    let found = verses.find(v => v.verse_number === state.correction.verseNumber);
    if (!found) {
      state.correction.verseNumber = verses[0].verse_number;
      found = verses[0];
    }
    return found;
  }

  function getNextSurahObj() {
    const surahs = state.data.surahs || [];
    if (!surahs.length) return null;
    const idx = surahs.findIndex(s => s.id === state.activeSurahId);
    const nextIdx = idx >= 0 ? (idx + 1) % surahs.length : 0;
    return surahs[nextIdx];
  }

  function cancelCorrAutoAdvance(hideBanner = true) {
    if (corrAutoAdvanceTimer) {
      clearTimeout(corrAutoAdvanceTimer);
      corrAutoAdvanceTimer = null;
    }
    if (hideBanner && DOM.corrAutoAdvanceBanner) {
      DOM.corrAutoAdvanceBanner.classList.add('hidden');
    }
  }

  function stopContinuousSimulation() {
    state.correction.isContinuousSimulating = false;
    if (corrContinuousSimTimer) {
      clearTimeout(corrContinuousSimTimer);
      corrContinuousSimTimer = null;
    }
    if (DOM.btnCorrSimContinuous) {
      DOM.btnCorrSimContinuous.classList.remove('active');
      DOM.btnCorrSimContinuous.textContent = "▶ Simulasi Tasmi' Bersambung (Lintas Ayat & Surah)";
    }
  }

  function advanceCorrectionToNextVerseOrSurah(resetLiveMicBuffer = false) {
    cancelCorrAutoAdvance(true);
    const verses = state.data.verses.filter(v => v.surah_id === state.activeSurahId);
    state.correction.lastFinalizedKey = null;
    state.correction.wordResults = [];
    state.correction.selectedWordIdx = -1;

    if (DOM.corrTranscriptInput) DOM.corrTranscriptInput.value = '';
    if (DOM.corrMetricAcc) DOM.corrMetricAcc.textContent = 'Akurasi: —';
    if (DOM.corrMetricCorrect) DOM.corrMetricCorrect.textContent = 'Tepat: 0 kata';
    if (DOM.corrMetricNear) DOM.corrMetricNear.textContent = 'Perlu Perbaikan: 0 kata';
    if (DOM.corrMetricWrong) DOM.corrMetricWrong.textContent = 'Salah / Terlewat: 0 kata';

    // Jika perpindahan dipicu oleh terpenuhinya jumlah kata sebelum jeda nafas WebSpeech selesai,
    // segarkan buffer pengenalan suara agar kata ayat lama tidak terbawa ke ayat berikutnya.
    if (resetLiveMicBuffer && state.isListening && state.recognition) {
      try {
        state.recognition.abort();
      } catch (_) {}
    }

    if (state.correction.verseNumber < verses.length) {
      state.correction.verseNumber++;
      renderCorrectionView();
    } else {
      const nextSurah = getNextSurahObj();
      if (nextSurah) {
        state.activeSurahId = nextSurah.id;
        if (DOM.surahSelect) DOM.surahSelect.value = String(nextSurah.id);
        const firstVerse = state.data.verses.find(v => v.surah_id === state.activeSurahId);
        if (firstVerse) {
          state.activePageNumber = firstVerse.page_number;
        }
        state.correction.verseNumber = 1;
        renderMushafView();
        renderMarkedMushafView();
        renderCorrectionView();
        if (state.activeScope === 'surah') {
          renderRadarMutasyabihat();
        }
      }
    }

    if (state.correction.isContinuousSimulating) {
      corrContinuousSimTimer = setTimeout(() => {
        runSingleContinuousSimulationStep();
      }, 650);
    }
  }

  function recordCorrectionSessionHistory(verse, summary) {
    const surah = state.data.surahs.find(s => s.id === verse.surah_id);
    const key = `${verse.surah_id}:${verse.verse_number}`;
    const item = {
      key,
      surahId: verse.surah_id,
      surahNameLatin: verse.surah_name_latin || (surah ? surah.name_latin : `Surah ${verse.surah_id}`),
      verseNumber: verse.verse_number,
      accPct: summary.accPct,
      isAllCorrect: summary.isAllCorrect,
      correctCount: summary.correctCount,
      nearCount: summary.nearCount,
      wrongCount: summary.wrongCount,
      spokenText: summary.spokenText
    };

    const existingIdx = state.correction.sessionHistory.findIndex(h => h.key === key);
    if (existingIdx >= 0) {
      state.correction.sessionHistory[existingIdx] = item;
    } else {
      state.correction.sessionHistory.push(item);
    }
    renderCorrectionSessionHistory();
  }

  function renderCorrectionSessionHistory() {
    if (!DOM.corrSessionHistoryCard || !DOM.corrHistoryList) return;
    const hist = state.correction.sessionHistory;
    if (!hist.length) {
      DOM.corrSessionHistoryCard.classList.add('hidden');
      DOM.corrHistoryList.innerHTML = '';
      return;
    }

    DOM.corrSessionHistoryCard.classList.remove('hidden');
    const okCount = hist.filter(h => h.isAllCorrect).length;
    const errCount = hist.length - okCount;

    if (DOM.corrHistTotal) DOM.corrHistTotal.textContent = `Total: ${hist.length} Ayat`;
    if (DOM.corrHistCorrect) DOM.corrHistCorrect.textContent = `✓ Lancar: ${okCount} Ayat`;
    if (DOM.corrHistMistake) DOM.corrHistMistake.textContent = `⚠️ Perlu Koreksi: ${errCount} Ayat`;

    DOM.corrHistoryList.innerHTML = '';
    hist.forEach(item => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = `corr-metric-pill ${item.isAllCorrect ? 'correct' : 'wrong'}`;
      btn.style.cursor = 'pointer';
      btn.style.border = '1px solid currentColor';
      btn.title = 'Klik untuk meninjau detail koreksi ayat ini';
      btn.textContent = `${item.isAllCorrect ? '✓' : '⚠️'} QS. ${item.surahNameLatin}:${item.verseNumber} (${item.accPct}%)`;

      btn.addEventListener('click', () => {
        stopContinuousSimulation();
        cancelCorrAutoAdvance(true);
        if (state.activeSurahId !== item.surahId) {
          state.activeSurahId = item.surahId;
          if (DOM.surahSelect) DOM.surahSelect.value = String(item.surahId);
          const firstVerse = state.data.verses.find(v => v.surah_id === state.activeSurahId);
          if (firstVerse) state.activePageNumber = firstVerse.page_number;
          renderMushafView();
          renderMarkedMushafView();
        }
        state.correction.verseNumber = item.verseNumber;
        if (DOM.corrTranscriptInput) DOM.corrTranscriptInput.value = item.spokenText;
        renderCorrectionView();
        evaluateCorrectionWords(item.spokenText, { isFinal: true, triggerAutoAdvance: false });
      });

      DOM.corrHistoryList.appendChild(btn);
    });
  }

  function runSingleContinuousSimulationStep() {
    if (!state.correction.isContinuousSimulating) return;
    const v = getCorrectionActiveVerse();
    if (!v) {
      stopContinuousSimulation();
      return;
    }

    state.correction.simCounter++;
    let spoken = v.text_uthmani;
    // Setiap ayat ke-3 pada simulasi dibuat memiliki 1 kesalahan ringan agar alur Benar & Salah terlihat nyata
    if (state.correction.simCounter % 3 === 0) {
      const tokens = v.text_uthmani.split(/\s+/).filter(Boolean);
      const mutated = tokens.map((tok, i) => {
        if (i === tokens.length - 1) return 'ٱلصَّاخَّةُ';
        return tok;
      });
      spoken = mutated.join(' ');
    }

    if (DOM.corrTranscriptInput) DOM.corrTranscriptInput.value = spoken;
    evaluateCorrectionWords(spoken, { isFinal: true, triggerAutoAdvance: true });
  }

  function renderCorrectionView() {
    if (!DOM.corrWordsFlow) return;
    const verses = state.data.verses.filter(v => v.surah_id === state.activeSurahId);
    const surah = state.data.surahs.find(s => s.id === state.activeSurahId);
    if (!verses.length || !surah) return;

    // Populate Cascading Dropdown: Pilih Surah
    if (DOM.corrSurahSelect) {
      if (DOM.corrSurahSelect.options.length !== state.data.surahs.length) {
        DOM.corrSurahSelect.innerHTML = '';
        state.data.surahs.forEach(s => {
          const opt = document.createElement('option');
          opt.value = s.id;
          opt.textContent = `QS. ${s.id}. ${s.name_latin}`;
          DOM.corrSurahSelect.appendChild(opt);
        });
      }
      DOM.corrSurahSelect.value = state.activeSurahId;
    }

    // Populate Cascading Dropdown: Sub Pilihan Ayat
    if (DOM.corrVerseSelect) {
      DOM.corrVerseSelect.innerHTML = '';
      verses.forEach(v => {
        const opt = document.createElement('option');
        opt.value = v.verse_number;
        opt.textContent = `Ayat ${v.verse_number}`;
        DOM.corrVerseSelect.appendChild(opt);
      });
      if (!verses.some(v => v.verse_number === state.correction.verseNumber)) {
        state.correction.verseNumber = verses[0].verse_number;
      }
      DOM.corrVerseSelect.value = state.correction.verseNumber;
    }

    if (DOM.btnCorrNext) {
      const isLastVerse = state.correction.verseNumber >= verses.length;
      const nextSurah = getNextSurahObj();
      DOM.btnCorrNext.textContent = isLastVerse && nextSurah
        ? `Surah Selanjutnya (${nextSurah.name_latin}) ►`
        : 'Ayat Selanjutnya ►';
    }

    const activeVerse = getCorrectionActiveVerse();
    if (!activeVerse) return;

    if (DOM.corrSurahHeader) {
      DOM.corrSurahHeader.textContent = `QS. ${surah.name_latin} (${surah.name_arabic}) : Ayat ${activeVerse.verse_number}`;
    }
    if (DOM.corrVerseTranslation) {
      DOM.corrVerseTranslation.textContent = `"${activeVerse.translation_id}"`;
    }

    renderCorrectionWordChips(activeVerse, state.correction.wordResults);
  }

  function renderCorrectionWordChips(verse, results) {
    if (!DOM.corrWordsFlow) return;
    DOM.corrWordsFlow.innerHTML = '';

    const words = verse.words && verse.words.length
      ? verse.words
      : verse.text_uthmani.split(/\s+/).map((w, i) => ({
          position: i + 1,
          text_uthmani: w,
          text_clean: normalizeArabic(w),
          translation_id: '',
          transliteration: ''
        }));

    words.forEach((w, idx) => {
      const res = results && results[idx] ? results[idx] : null;
      const chip = document.createElement('button');
      chip.type = 'button';
      let statusClass = '';
      let tagText = `Kata #${idx + 1}`;
      if (res) {
        if (res.status === 'correct') {
          statusClass = 'status-correct';
          tagText = '✓ Tepat';
        } else if (res.status === 'near') {
          statusClass = 'status-near';
          tagText = '~ Kurang Tepat';
        } else {
          statusClass = 'status-wrong';
          tagText = '✕ Salah / Terlewat';
        }
      }
      const isSelected = state.correction.selectedWordIdx === idx;
      chip.className = `corr-word-chip ${statusClass} ${isSelected ? 'selected' : ''}`;

      const revealThisWord = !state.correction.blindMode || (res && res.status !== 'wrong');
      chip.innerHTML = `
        <span class="corr-word-arabic ${revealThisWord ? '' : 'blind'}">${w.text_uthmani}</span>
        <span class="corr-word-tag">${tagText}</span>
      `;

      chip.addEventListener('click', () => {
        state.correction.selectedWordIdx = idx;
        renderCorrectionWordChips(verse, state.correction.wordResults);
        showCorrectionWordInspector(verse, w, res, idx);
      });

      DOM.corrWordsFlow.appendChild(chip);
    });
  }

  function evaluateCorrectionWords(spokenText, opts = { isFinal: true, triggerAutoAdvance: true, fromLiveMic: false }) {
    const verse = getCorrectionActiveVerse();
    if (!verse) return;

    const words = verse.words && verse.words.length
      ? verse.words
      : verse.text_uthmani.split(/\s+/).map((w, i) => ({
          position: i + 1,
          text_uthmani: w,
          text_clean: normalizeArabic(w),
          translation_id: '',
          transliteration: ''
        }));

    const rawSpokenTokens = (spokenText || '').trim().split(/\s+/).filter(Boolean);
    const cleanSpokenTokens = rawSpokenTokens.map(normalizeArabic).filter(Boolean);

    let cursor = 0;
    let correctCount = 0;
    let nearCount = 0;
    let wrongCount = 0;
    const results = [];

    words.forEach((w, idx) => {
      const expectedUthmani = w.text_uthmani;
      const expectedClean = normalizeArabic(expectedUthmani);

      if (!cleanSpokenTokens.length) {
        wrongCount++;
        results.push({
          idx,
          status: 'wrong',
          spokenWord: null,
          sim: 0,
          note: `Kata "${expectedUthmani}" belum terucap atau terlewat.`
        });
        return;
      }

      let bestIdx = -1;
      let bestSim = 0;
      const limit = Math.min(cleanSpokenTokens.length, cursor + 3);
      for (let j = cursor; j < limit; j++) {
        const sim = calculateSimilarity(expectedClean, cleanSpokenTokens[j]);
        if (sim > bestSim) {
          bestSim = sim;
          bestIdx = j;
        }
      }

      const matchedSpoken = bestIdx >= 0 && bestIdx < rawSpokenTokens.length ? rawSpokenTokens[bestIdx] : null;
      if (bestSim >= 0.84) {
        correctCount++;
        cursor = bestIdx + 1;
        results.push({
          idx,
          status: 'correct',
          spokenWord: matchedSpoken,
          sim: bestSim,
          note: `Lafal "${expectedUthmani}" sudah tepat sesuai urutan & huruf.`
        });
      } else if (bestSim >= 0.70) {
        nearCount++;
        cursor = bestIdx + 1;
        results.push({
          idx,
          status: 'near',
          spokenWord: matchedSpoken,
          sim: bestSim,
          note: `Hampir tepat (terdengar "${matchedSpoken || '-'}"). Perhatikan makhraj huruf pada lafal "${expectedUthmani}".`
        });
      } else {
        wrongCount++;
        if (cursor < cleanSpokenTokens.length && bestSim > 0.25) {
          cursor++;
        }
        results.push({
          idx,
          status: 'wrong',
          spokenWord: matchedSpoken,
          sim: bestSim,
          note: matchedSpoken
            ? `Tertukar atau salah ucap (terdengar "${matchedSpoken}"). Seharusnya membaca "${expectedUthmani}".`
            : `Kata "${expectedUthmani}" terlewat / tidak terdengar.`
        });
      }
    });

    state.correction.wordResults = results;
    const total = Math.max(1, words.length);
    const accPct = Math.round(((correctCount + nearCount * 0.5) / total) * 100);
    const isAllCorrect = wrongCount === 0 && nearCount === 0;

    if (DOM.corrMetricAcc) DOM.corrMetricAcc.textContent = `Akurasi: ${accPct}%`;
    if (DOM.corrMetricCorrect) DOM.corrMetricCorrect.textContent = `Tepat: ${correctCount} kata`;
    if (DOM.corrMetricNear) DOM.corrMetricNear.textContent = `Perlu Perbaikan: ${nearCount} kata`;
    if (DOM.corrMetricWrong) DOM.corrMetricWrong.textContent = `Salah / Terlewat: ${wrongCount} kata`;

    // Pilih otomatis kata pertama yang salah atau kurang tepat
    const firstIssueIdx = results.findIndex(r => r.status === 'wrong' || r.status === 'near');
    state.correction.selectedWordIdx = firstIssueIdx >= 0 ? firstIssueIdx : 0;

    renderCorrectionWordChips(verse, results);
    const targetIdx = state.correction.selectedWordIdx;
    if (words[targetIdx]) {
      showCorrectionWordInspector(verse, words[targetIdx], results[targetIdx], targetIdx);
    }

    // Deteksi apakah pembacaan 1 ayat sudah selesai (isFinal jeda suara ATAU jumlah kata telah memenuhi ayat)
    const reachedWordTarget = cleanSpokenTokens.length >= words.length && cleanSpokenTokens.length > 0;
    const isVerseCompleted = cleanSpokenTokens.length > 0 && (Boolean(opts.isFinal) || reachedWordTarget);

    if (opts.triggerAutoAdvance && isVerseCompleted) {
      const verseKey = `${verse.surah_id}:${verse.verse_number}`;
      // Hindari pemicuan ganda pada ayat yang sama saat interim -> final menyusul
      if (opts.fromLiveMic && state.correction.lastFinalizedKey === verseKey) {
        return;
      }
      state.correction.lastFinalizedKey = verseKey;

      recordCorrectionSessionHistory(verse, {
        accPct,
        isAllCorrect,
        correctCount,
        nearCount,
        wrongCount,
        spokenText: spokenText || ''
      });

      if (!isAllCorrect && state.correction.autoPlayQariOnMistake) {
        playMurattalAudio(verse.surah_id, verse.verse_number);
      }

      if (state.correction.autoAdvance) {
        cancelCorrAutoAdvance(false);
        const versesInSurah = state.data.verses.filter(v => v.surah_id === state.activeSurahId);
        const isLastInSurah = verse.verse_number >= versesInSurah.length;
        const nextSurah = getNextSurahObj();
        const curSurah = state.data.surahs.find(s => s.id === state.activeSurahId);
        const targetLabel = isLastInSurah && nextSurah
          ? `QS. ${nextSurah.name_latin} : Ayat 1 (Pindah Surah Otomatis)`
          : `QS. ${curSurah ? curSurah.name_latin : ''} : Ayat ${verse.verse_number + 1}`;

        const statusPrefix = isAllCorrect
          ? `✓ Bacaan Benar (${accPct}%)`
          : `⚠️ Terdeteksi Koreksi (${wrongCount + nearCount} kata perlu perbaikan, Akurasi ${accPct}%)`;

        if (DOM.corrAutoAdvanceText) {
          DOM.corrAutoAdvanceText.textContent = `${statusPrefix} — Menyambung otomatis ke ${targetLabel}...`;
        }
        if (DOM.corrAutoAdvanceBanner) {
          DOM.corrAutoAdvanceBanner.classList.remove('hidden');
        }

        const delayMs = isAllCorrect
          ? 1400
          : (state.correction.autoPlayQariOnMistake ? 3400 : 2200);
        const shouldResetMicBuf = Boolean(opts.fromLiveMic && !opts.isFinal);

        corrAutoAdvanceTimer = setTimeout(() => {
          advanceCorrectionToNextVerseOrSurah(shouldResetMicBuf);
        }, delayMs);
      }
    }
  }

  function showCorrectionWordInspector(verse, wordObj, evalRes, idx) {
    if (!DOM.corrInspectorBody) return;
    const statusLabel = !evalRes
      ? 'Detail Kosakata'
      : evalRes.status === 'correct'
        ? '✓ Bacaan Tepat'
        : evalRes.status === 'near'
          ? '~ Perlu Perbaikan Makhraj'
          : '✕ Koreksi Kata Salah / Terlewat';

    if (DOM.corrInspectorBadge) DOM.corrInspectorBadge.textContent = statusLabel;
    if (DOM.corrInspectorTitle) {
      DOM.corrInspectorTitle.textContent = `Kata ke-${idx + 1} pada QS. ${verse.surah_name_latin}:${verse.verse_number}`;
    }

    const noteText = evalRes
      ? evalRes.note
      : 'Klik tombol Rekam Suara atau Simulasi di atas untuk mengevaluasi ketepatan pelafalan kata ini.';

    DOM.corrInspectorBody.innerHTML = `
      <div class="inspector-compare-grid">
        <div class="inspector-box">
          <div class="inspector-box-header">
            <span>Lafal Mushaf yang Benar</span>
            <span>Kata #${idx + 1}</span>
          </div>
          <div class="inspector-arabic">${wordObj.text_uthmani}</div>
          <div class="inspector-next">Transliterasi: <strong>${wordObj.transliteration || '-'}</strong> • Arti: "${wordObj.translation_id || '-'}"</div>
        </div>
        <div class="inspector-box">
          <div class="inspector-box-header">
            <span>Hasil Simak Bacaan Anda</span>
            <span>${evalRes ? Math.round(evalRes.sim * 100) + '% kecocokan' : 'Belum diuji'}</span>
          </div>
          <div class="inspector-arabic">${evalRes && evalRes.spokenWord ? evalRes.spokenWord : '—'}</div>
          <div class="inspector-next">${noteText}</div>
        </div>
      </div>
      <div class="alert-action-row" style="margin-top:8px;">
        <button type="button" class="btn btn-primary btn-sm" id="btn-inspector-play-qari">Dengarkan Contoh Lafal Qari (QS. ${verse.surah_name_latin}:${verse.verse_number})</button>
      </div>
    `;

    const btnPlay = document.getElementById('btn-inspector-play-qari');
    if (btnPlay) {
      btnPlay.addEventListener('click', () => {
        playMurattalAudio(verse.surah_id, verse.verse_number);
      });
    }
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
      stopContinuousSimulation();
      cancelCorrAutoAdvance(true);
      state.activeSurahId = parseInt(e.target.value, 10);
      const firstVerse = state.data.verses.find(v => v.surah_id === state.activeSurahId);
      if (firstVerse) {
        state.activePageNumber = firstVerse.page_number;
      }
      renderMushafView();
      renderMarkedMushafView();
      state.correction.verseNumber = 1;
      state.correction.wordResults = [];
      state.correction.lastFinalizedKey = null;
      renderCorrectionView();
      if (state.activeScope === 'surah') {
        renderRadarMutasyabihat();
      }
    });

    function stepSurah(delta) {
      const surahs = state.data.surahs || [];
      if (!surahs.length) return;
      const currIdx = surahs.findIndex(s => s.id === state.activeSurahId);
      if (currIdx < 0) return;
      const nextIdx = Math.max(0, Math.min(surahs.length - 1, currIdx + delta));
      if (nextIdx !== currIdx) {
        stopContinuousSimulation();
        cancelCorrAutoAdvance(true);
        state.activeSurahId = surahs[nextIdx].id;
        if (DOM.surahSelect) DOM.surahSelect.value = String(state.activeSurahId);
        const firstVerse = state.data.verses.find(v => v.surah_id === state.activeSurahId);
        if (firstVerse) {
          state.activePageNumber = firstVerse.page_number;
        }
        renderMushafView();
        renderMarkedMushafView();
        state.correction.verseNumber = 1;
        state.correction.wordResults = [];
        state.correction.lastFinalizedKey = null;
        renderCorrectionView();
        if (state.activeScope === 'surah') {
          renderRadarMutasyabihat();
        }
      }
    }

    // Navigasi & Swipe Pindah Surah pada Mode Mushaf Bertanda
    if (DOM.btnMarkedPrevSurah) {
      DOM.btnMarkedPrevSurah.addEventListener('click', () => stepSurah(-1));
    }
    if (DOM.btnMarkedNextSurah) {
      DOM.btnMarkedNextSurah.addEventListener('click', () => stepSurah(1));
    }

    // Modal Pemilih Surah Lengkap (Klik & Scroll 114 Surah)
    if (DOM.btnMarkedBannerPicker) {
      DOM.btnMarkedBannerPicker.addEventListener('click', openSurahPickerModal);
    }
    if (DOM.btnMarkedSurahLabel) {
      DOM.btnMarkedSurahLabel.addEventListener('click', openSurahPickerModal);
    }
    if (DOM.btnMarkedSwipePicker) {
      DOM.btnMarkedSwipePicker.addEventListener('click', openSurahPickerModal);
    }
    if (DOM.btnCloseSurahPicker) {
      DOM.btnCloseSurahPicker.addEventListener('click', closeSurahPickerModal);
    }
    if (DOM.surahPickerModal) {
      DOM.surahPickerModal.addEventListener('click', (e) => {
        if (e.target === DOM.surahPickerModal) closeSurahPickerModal();
      });
    }
    if (DOM.surahPickerSearch) {
      DOM.surahPickerSearch.addEventListener('input', (e) => {
        renderSurahPickerList(e.target.value);
      });
    }
    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && DOM.surahPickerModal && !DOM.surahPickerModal.classList.contains('hidden')) {
        closeSurahPickerModal();
      }
    });

    let markedTouchStartX = 0;
    let markedTouchStartY = 0;
    if (DOM.markedPageContainer) {
      DOM.markedPageContainer.addEventListener('touchstart', (e) => {
        if (e.touches && e.touches.length === 1) {
          markedTouchStartX = e.touches[0].clientX;
          markedTouchStartY = e.touches[0].clientY;
        }
      }, { passive: true });

      DOM.markedPageContainer.addEventListener('touchend', (e) => {
        if (e.changedTouches && e.changedTouches.length === 1) {
          const deltaX = e.changedTouches[0].clientX - markedTouchStartX;
          const deltaY = e.changedTouches[0].clientY - markedTouchStartY;
          // Swipe horizontal minimal 50px dan lebih dominan dibanding vertikal
          if (Math.abs(deltaX) > 50 && Math.abs(deltaX) > Math.abs(deltaY) * 1.3) {
            if (deltaX < 0) {
              // Geser ke kiri -> Surah Selanjutnya
              stepSurah(1);
            } else {
              // Geser ke kanan -> Surah Sebelumnya
              stepSurah(-1);
            }
          }
        }
      }, { passive: true });
    }

    // Correction Mode Listeners
    if (DOM.corrSurahSelect) {
      DOM.corrSurahSelect.addEventListener('change', (e) => {
        stopContinuousSimulation();
        cancelCorrAutoAdvance(true);
        state.activeSurahId = parseInt(e.target.value, 10);
        state.activeVerseIndex = 0;
        state.activeWordPosition = 0;
        state.correction.verseNumber = 1;
        state.correction.wordResults = [];
        state.correction.selectedWordIdx = -1;
        state.correction.lastFinalizedKey = null;
        if (DOM.surahSelect) DOM.surahSelect.value = state.activeSurahId;
        renderMushafView();
        renderMarkedMushafView();
        renderCorrectionView();
        if (state.activeScope === 'surah') {
          renderRadarMutasyabihat();
        }
      });
    }

    if (DOM.corrVerseSelect) {
      DOM.corrVerseSelect.addEventListener('change', (e) => {
        stopContinuousSimulation();
        cancelCorrAutoAdvance(true);
        state.correction.verseNumber = parseInt(e.target.value, 10);
        state.correction.wordResults = [];
        state.correction.selectedWordIdx = -1;
        state.correction.lastFinalizedKey = null;
        renderCorrectionView();
      });
    }
    if (DOM.btnCorrPrev) {
      DOM.btnCorrPrev.addEventListener('click', () => {
        stopContinuousSimulation();
        cancelCorrAutoAdvance(true);
        if (state.correction.verseNumber > 1) {
          state.correction.verseNumber--;
          state.correction.wordResults = [];
          state.correction.selectedWordIdx = -1;
          state.correction.lastFinalizedKey = null;
          renderCorrectionView();
        }
      });
    }
    if (DOM.btnCorrNext) {
      DOM.btnCorrNext.addEventListener('click', () => {
        stopContinuousSimulation();
        advanceCorrectionToNextVerseOrSurah(false);
      });
    }
    if (DOM.btnCorrAutoAdvance) {
      DOM.btnCorrAutoAdvance.addEventListener('click', () => {
        state.correction.autoAdvance = !state.correction.autoAdvance;
        DOM.btnCorrAutoAdvance.classList.toggle('active', state.correction.autoAdvance);
        DOM.btnCorrAutoAdvance.setAttribute('aria-pressed', state.correction.autoAdvance ? 'true' : 'false');
        DOM.btnCorrAutoAdvance.textContent = state.correction.autoAdvance
          ? 'Sambung Otomatis (Ayat & Surah): ON'
          : 'Sambung Otomatis (Ayat & Surah): OFF';
        if (!state.correction.autoAdvance) {
          stopContinuousSimulation();
          cancelCorrAutoAdvance(true);
        }
      });
    }
    if (DOM.btnCorrAutoQari) {
      DOM.btnCorrAutoQari.addEventListener('click', () => {
        state.correction.autoPlayQariOnMistake = !state.correction.autoPlayQariOnMistake;
        DOM.btnCorrAutoQari.classList.toggle('active', state.correction.autoPlayQariOnMistake);
        DOM.btnCorrAutoQari.setAttribute('aria-pressed', state.correction.autoPlayQariOnMistake ? 'true' : 'false');
        DOM.btnCorrAutoQari.textContent = state.correction.autoPlayQariOnMistake
          ? 'Putar Qari Saat Salah: ON'
          : 'Putar Qari Saat Salah: OFF';
      });
    }
    if (DOM.btnCorrHoldVerse) {
      DOM.btnCorrHoldVerse.addEventListener('click', () => {
        stopContinuousSimulation();
        cancelCorrAutoAdvance(true);
      });
    }
    if (DOM.btnCorrClearHistory) {
      DOM.btnCorrClearHistory.addEventListener('click', () => {
        state.correction.sessionHistory = [];
        renderCorrectionSessionHistory();
      });
    }
    if (DOM.btnCorrBlind) {
      DOM.btnCorrBlind.addEventListener('click', () => {
        state.correction.blindMode = !state.correction.blindMode;
        DOM.btnCorrBlind.classList.toggle('active', state.correction.blindMode);
        DOM.btnCorrBlind.textContent = state.correction.blindMode
          ? 'Tampilkan Lafal (Mode Terbuka)'
          : 'Sembunyikan Lafal (Uji Hafalan)';
        renderCorrectionView();
      });
    }
    if (DOM.btnCorrListenQari) {
      DOM.btnCorrListenQari.addEventListener('click', () => {
        const v = getCorrectionActiveVerse();
        if (v) playMurattalAudio(v.surah_id, v.verse_number);
      });
    }
    if (DOM.btnCorrMic) {
      DOM.btnCorrMic.addEventListener('click', () => {
        if (state.recognition) {
          toggleListening();
        } else {
          // Fallback jika browser tidak mendukung Web Speech API: jalankan simulasi tasmi' bersambung
          if (DOM.btnCorrSimContinuous) DOM.btnCorrSimContinuous.click();
        }
      });
    }
    if (DOM.btnCorrSimContinuous) {
      DOM.btnCorrSimContinuous.addEventListener('click', () => {
        if (state.correction.isContinuousSimulating) {
          stopContinuousSimulation();
          cancelCorrAutoAdvance(true);
          return;
        }
        if (!state.correction.autoAdvance) {
          state.correction.autoAdvance = true;
          if (DOM.btnCorrAutoAdvance) {
            DOM.btnCorrAutoAdvance.classList.add('active');
            DOM.btnCorrAutoAdvance.setAttribute('aria-pressed', 'true');
            DOM.btnCorrAutoAdvance.textContent = 'Sambung Otomatis (Ayat & Surah): ON';
          }
        }
        state.correction.isContinuousSimulating = true;
        DOM.btnCorrSimContinuous.classList.add('active');
        DOM.btnCorrSimContinuous.textContent = "⏹ Hentikan Simulasi Tasmi' Bersambung";
        runSingleContinuousSimulationStep();
      });
    }
    if (DOM.btnCorrSimPerfect) {
      DOM.btnCorrSimPerfect.addEventListener('click', () => {
        stopContinuousSimulation();
        const v = getCorrectionActiveVerse();
        if (!v) return;
        state.correction.lastFinalizedKey = null;
        if (DOM.corrTranscriptInput) DOM.corrTranscriptInput.value = v.text_uthmani;
        evaluateCorrectionWords(v.text_uthmani, { isFinal: true, triggerAutoAdvance: true });
      });
    }
    if (DOM.btnCorrSimMistake) {
      DOM.btnCorrSimMistake.addEventListener('click', () => {
        stopContinuousSimulation();
        const v = getCorrectionActiveVerse();
        if (!v) return;
        state.correction.lastFinalizedKey = null;
        const tokens = v.text_uthmani.split(/\s+/).filter(Boolean);
        const mutated = tokens.map((tok, i) => {
          if (tokens.length >= 3 && i === 1) return tok.slice(0, Math.max(1, tok.length - 2)); // Kurang tepat
          if (i === tokens.length - 1) return 'ٱلصَّاخَّةُ'; // Kata akhir tertukar
          return tok;
        });
        const simulatedText = mutated.join(' ');
        if (DOM.corrTranscriptInput) DOM.corrTranscriptInput.value = simulatedText;
        evaluateCorrectionWords(simulatedText, { isFinal: true, triggerAutoAdvance: true });
      });
    }
    if (DOM.btnCorrEvaluate) {
      DOM.btnCorrEvaluate.addEventListener('click', () => {
        stopContinuousSimulation();
        state.correction.lastFinalizedKey = null;
        const val = DOM.corrTranscriptInput ? DOM.corrTranscriptInput.value : '';
        evaluateCorrectionWords(val, { isFinal: true, triggerAutoAdvance: true });
      });
    }

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

    // Zoom In / Zoom Out & Mode Selembar Mushaf Madinah + Scroll Mouse (Desktop) + Pinch-to-Zoom 2 Jari (Android/Mobile)
    let mushafZoom = 1.0;
    let scrollWheelDirectZoom = false;
    const mushafCard = document.getElementById('mushaf-page-container');
    const markedCard = document.getElementById('marked-page-container');
    const btnZoomIn = document.getElementById('btn-zoom-in');
    const btnZoomOut = document.getElementById('btn-zoom-out');
    const btnZoomReset = document.getElementById('btn-zoom-reset');
    const btnSingleSheet = document.getElementById('btn-toggle-single-sheet');
    const btnToggleScrollZoom = document.getElementById('btn-toggle-scroll-zoom');

    function applyMushafZoom(newScale) {
      mushafZoom = Math.min(2.5, Math.max(0.60, newScale));
      if (btnZoomReset) btnZoomReset.textContent = `${Math.round(mushafZoom * 100)}%`;
      if (mushafCard) {
        mushafCard.style.zoom = mushafZoom;
      }
      if (markedCard) {
        markedCard.style.zoom = mushafZoom;
      }
    }

    if (btnZoomIn) btnZoomIn.addEventListener('click', () => applyMushafZoom(mushafZoom + 0.15));
    if (btnZoomOut) btnZoomOut.addEventListener('click', () => applyMushafZoom(mushafZoom - 0.15));
    if (btnZoomReset) btnZoomReset.addEventListener('click', () => applyMushafZoom(1.0));
    if (btnSingleSheet && mushafCard) {
      btnSingleSheet.addEventListener('click', () => {
        const active = mushafCard.classList.toggle('single-sheet-mode');
        btnSingleSheet.classList.toggle('active', active);
      });
    }
    if (btnToggleScrollZoom) {
      btnToggleScrollZoom.addEventListener('click', () => {
        scrollWheelDirectZoom = !scrollWheelDirectZoom;
        btnToggleScrollZoom.classList.toggle('active', scrollWheelDirectZoom);
        btnToggleScrollZoom.textContent = scrollWheelDirectZoom ? 'Scroll = Zoom' : 'Ctrl+Scroll = Zoom';
      });
    }

    // Gesture Zoom (Wheel di Desktop & Pinch 2 Jari di Android/Touchscreen tanpa menghalangi Scroll 1 Jari)
    [mushafCard, markedCard].forEach(cardEl => {
      if (!cardEl) return;

      cardEl.addEventListener('wheel', (e) => {
        if (e.ctrlKey || e.metaKey || scrollWheelDirectZoom) {
          e.preventDefault();
          const delta = e.deltaY < 0 ? 0.10 : -0.10;
          applyMushafZoom(mushafZoom + delta);
        }
      }, { passive: false });

      let initialPinchDist = null;
      let initialPinchScale = 1.0;

      cardEl.addEventListener('touchstart', (e) => {
        if (e.touches.length === 2) {
          const dx = e.touches[0].clientX - e.touches[1].clientX;
          const dy = e.touches[0].clientY - e.touches[1].clientY;
          initialPinchDist = Math.hypot(dx, dy);
          initialPinchScale = mushafZoom;
        }
      }, { passive: true });

      cardEl.addEventListener('touchmove', (e) => {
        if (e.touches.length === 2 && initialPinchDist && initialPinchDist > 12) {
          e.preventDefault();
          const dx = e.touches[0].clientX - e.touches[1].clientX;
          const dy = e.touches[0].clientY - e.touches[1].clientY;
          const dist = Math.hypot(dx, dy);
          const ratio = dist / initialPinchDist;
          applyMushafZoom(initialPinchScale * ratio);
        }
      }, { passive: false });

      cardEl.addEventListener('touchend', (e) => {
        if (e.touches.length < 2) {
          initialPinchDist = null;
        }
      }, { passive: true });
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

    if (DOM.radarSurahSelect) {
      DOM.radarSurahSelect.addEventListener('change', (e) => {
        state.radarSurahId = e.target.value ? parseInt(e.target.value, 10) : null;
        state.radarVerseNumber = null;
        renderRadarMutasyabihat();
      });
    }

    if (DOM.radarVerseSelect) {
      DOM.radarVerseSelect.addEventListener('change', (e) => {
        state.radarVerseNumber = e.target.value ? parseInt(e.target.value, 10) : null;
        renderRadarMutasyabihat();
      });
    }

    DOM.scopeBtns.forEach(btn => {
      btn.addEventListener('click', () => {
        DOM.scopeBtns.forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        state.activeScope = btn.dataset.scope;
        renderRadarMutasyabihat();
      });
    });

    // GTAF Basic Qur'an Reader Listeners
    function toggleGtafSidebar(forceState) {
      state.gtaf.sidebarOpen = typeof forceState === 'boolean' ? forceState : !state.gtaf.sidebarOpen;
      if (DOM.gtafLayoutContainer) {
        DOM.gtafLayoutContainer.classList.toggle('sidebar-collapsed', !state.gtaf.sidebarOpen);
      }
    }

    if (DOM.btnGtafToggleSidebar) {
      DOM.btnGtafToggleSidebar.addEventListener('click', () => toggleGtafSidebar());
    }
    if (DOM.btnGtafCloseSidebar) {
      DOM.btnGtafCloseSidebar.addEventListener('click', () => toggleGtafSidebar(false));
    }

    if (DOM.gtafIdxTabs && DOM.gtafIdxTabs.length) {
      DOM.gtafIdxTabs.forEach(tabBtn => {
        tabBtn.addEventListener('click', () => {
          DOM.gtafIdxTabs.forEach(b => {
            b.classList.remove('active');
            b.setAttribute('aria-selected', 'false');
          });
          tabBtn.classList.add('active');
          tabBtn.setAttribute('aria-selected', 'true');
          state.gtaf.idxTab = tabBtn.dataset.idxTab || 'surah';
          renderGtafSidebar();
        });
      });
    }

    if (DOM.gtafSidebarSearch) {
      DOM.gtafSidebarSearch.addEventListener('input', (e) => {
        state.gtaf.idxSearch = e.target.value;
        renderGtafSidebar();
      });
    }

    if (DOM.btnGtafResumeRead) {
      DOM.btnGtafResumeRead.addEventListener('click', () => {
        if (state.gtaf.lastRead) {
          jumpToSurahAndVerse(state.gtaf.lastRead.surahId, state.gtaf.lastRead.verseNumber, true);
        }
      });
    }

    if (DOM.gtafSurahSelect) {
      DOM.gtafSurahSelect.addEventListener('change', (e) => {
        jumpToSurahAndVerse(parseInt(e.target.value, 10), 1, false);
        window.scrollTo({ top: 0, behavior: 'smooth' });
      });
    }

    if (DOM.gtafVerseSelect) {
      DOM.gtafVerseSelect.addEventListener('change', (e) => {
        const vNum = parseInt(e.target.value, 10) || 1;
        jumpToSurahAndVerse(state.activeSurahId, vNum, true);
      });
    }

    if (DOM.btnGtafModeVerse && DOM.btnGtafModeMushaf) {
      DOM.btnGtafModeVerse.addEventListener('click', () => {
        state.gtaf.viewMode = 'verse';
        DOM.btnGtafModeVerse.classList.add('active');
        DOM.btnGtafModeMushaf.classList.remove('active');
        if (DOM.gtafVerseReaderView) DOM.gtafVerseReaderView.classList.remove('hidden');
        if (DOM.gtafMushafSheetView) DOM.gtafMushafSheetView.classList.add('hidden');
      });

      DOM.btnGtafModeMushaf.addEventListener('click', () => {
        state.gtaf.viewMode = 'mushaf';
        DOM.btnGtafModeMushaf.classList.add('active');
        DOM.btnGtafModeVerse.classList.remove('active');
        if (DOM.gtafMushafSheetView) DOM.gtafMushafSheetView.classList.remove('hidden');
        if (DOM.gtafVerseReaderView) DOM.gtafVerseReaderView.classList.add('hidden');
      });
    }

    if (DOM.btnGtafToggleVoicePanel && DOM.gtafVoicePanel) {
      DOM.btnGtafToggleVoicePanel.addEventListener('click', () => {
        state.gtaf.showVoicePanel = !state.gtaf.showVoicePanel;
        DOM.btnGtafToggleVoicePanel.classList.toggle('active', state.gtaf.showVoicePanel);
        DOM.gtafVoicePanel.classList.toggle('hidden', !state.gtaf.showVoicePanel);
      });
    }

    if (DOM.btnGtafOptWbw) {
      DOM.btnGtafOptWbw.addEventListener('click', () => {
        state.gtaf.showWbw = !state.gtaf.showWbw;
        DOM.btnGtafOptWbw.classList.toggle('active', state.gtaf.showWbw);
        DOM.btnGtafOptWbw.setAttribute('aria-pressed', String(state.gtaf.showWbw));
        renderGtafReaderView();
      });
    }

    if (DOM.btnGtafOptTranslit) {
      DOM.btnGtafOptTranslit.addEventListener('click', () => {
        state.gtaf.showTranslit = !state.gtaf.showTranslit;
        DOM.btnGtafOptTranslit.classList.toggle('active', state.gtaf.showTranslit);
        DOM.btnGtafOptTranslit.setAttribute('aria-pressed', String(state.gtaf.showTranslit));
        renderGtafReaderView();
      });
    }

    if (DOM.btnGtafOptTranslation) {
      DOM.btnGtafOptTranslation.addEventListener('click', () => {
        state.gtaf.showTranslation = !state.gtaf.showTranslation;
        DOM.btnGtafOptTranslation.classList.toggle('active', state.gtaf.showTranslation);
        DOM.btnGtafOptTranslation.setAttribute('aria-pressed', String(state.gtaf.showTranslation));
        renderGtafReaderView();
      });
    }

    if (DOM.btnGtafOptTafsir) {
      DOM.btnGtafOptTafsir.addEventListener('click', () => {
        state.gtaf.showTafsirAll = !state.gtaf.showTafsirAll;
        DOM.btnGtafOptTafsir.classList.toggle('active', state.gtaf.showTafsirAll);
        DOM.btnGtafOptTafsir.setAttribute('aria-pressed', String(state.gtaf.showTafsirAll));
        renderGtafReaderView();
      });
    }

    if (DOM.btnGtafOptBlur) {
      DOM.btnGtafOptBlur.addEventListener('click', () => {
        state.gtaf.blurHifz = !state.gtaf.blurHifz;
        state.gtaf.revealedWordKeys.clear();
        DOM.btnGtafOptBlur.classList.toggle('active', state.gtaf.blurHifz);
        DOM.btnGtafOptBlur.setAttribute('aria-pressed', String(state.gtaf.blurHifz));
        renderGtafReaderView();
      });
    }

    function applyGtafArabicScale(newScale) {
      state.gtaf.arabicScale = Math.min(1.65, Math.max(0.75, newScale));
      document.documentElement.style.setProperty('--gtaf-ar-scale', String(state.gtaf.arabicScale));
      if (DOM.btnGtafFontReset) {
        DOM.btnGtafFontReset.textContent = `${Math.round(state.gtaf.arabicScale * 100)}%`;
      }
    }

    if (DOM.btnGtafFontDec) {
      DOM.btnGtafFontDec.addEventListener('click', () => applyGtafArabicScale(state.gtaf.arabicScale - 0.1));
    }
    if (DOM.btnGtafFontReset) {
      DOM.btnGtafFontReset.addEventListener('click', () => applyGtafArabicScale(1.0));
    }
    if (DOM.btnGtafFontInc) {
      DOM.btnGtafFontInc.addEventListener('click', () => applyGtafArabicScale(state.gtaf.arabicScale + 0.1));
    }

    if (DOM.btnGtafPlaySurah) {
      DOM.btnGtafPlaySurah.addEventListener('click', () => {
        playMurattalAudio(state.activeSurahId, 1);
      });
    }

    if (DOM.btnGtafPrevSurah) {
      DOM.btnGtafPrevSurah.addEventListener('click', () => {
        stepSurah(-1);
        window.scrollTo({ top: 0, behavior: 'smooth' });
      });
    }
    if (DOM.btnGtafNextSurah) {
      DOM.btnGtafNextSurah.addEventListener('click', () => {
        stepSurah(1);
        window.scrollTo({ top: 0, behavior: 'smooth' });
      });
    }
    if (DOM.btnGtafScrollTop) {
      DOM.btnGtafScrollTop.addEventListener('click', () => {
        window.scrollTo({ top: 0, behavior: 'smooth' });
      });
    }

    // Sticky Audio Bar Listeners
    if (DOM.btnGtafAudioPlay) {
      DOM.btnGtafAudioPlay.addEventListener('click', togglePlayCurrentVerse);
    }
    if (DOM.btnGtafAudioPrev) {
      DOM.btnGtafAudioPrev.addEventListener('click', () => {
        const sId = state.gtaf.playingSurahId || state.activeSurahId;
        const vNum = state.gtaf.playingVerseNumber || 1;
        if (vNum > 1) {
          playMurattalAudio(sId, vNum - 1);
        }
      });
    }
    if (DOM.btnGtafAudioNext) {
      DOM.btnGtafAudioNext.addEventListener('click', () => {
        const sId = state.gtaf.playingSurahId || state.activeSurahId;
        const vNum = state.gtaf.playingVerseNumber || 1;
        const verses = state.data.verses.filter(v => v.surah_id === sId);
        if (vNum < verses.length) {
          playMurattalAudio(sId, vNum + 1);
        }
      });
    }
    if (DOM.gtafAudioReciter) {
      DOM.gtafAudioReciter.addEventListener('change', (e) => {
        state.reciter = e.target.value;
        if (DOM.reciterSelect) DOM.reciterSelect.value = state.reciter;
        if (state.gtaf.playingSurahId && state.gtaf.playingVerseNumber && !DOM.globalAudio.paused) {
          playMurattalAudio(state.gtaf.playingSurahId, state.gtaf.playingVerseNumber);
        } else {
          updateStickyAudioBarUI(false);
        }
      });
    }
    if (DOM.btnGtafAudioAutonext) {
      DOM.btnGtafAudioAutonext.addEventListener('click', () => {
        state.gtaf.autoNextAudio = !state.gtaf.autoNextAudio;
        DOM.btnGtafAudioAutonext.classList.toggle('active', state.gtaf.autoNextAudio);
        DOM.btnGtafAudioAutonext.setAttribute('aria-pressed', String(state.gtaf.autoNextAudio));
        DOM.btnGtafAudioAutonext.textContent = state.gtaf.autoNextAudio
          ? 'Lanjut Otomatis: ON'
          : 'Lanjut Otomatis: OFF';
      });
    }
    if (DOM.btnGtafAudioLoop) {
      DOM.btnGtafAudioLoop.addEventListener('click', () => {
        const counts = [1, 3, 5];
        const nextIdx = (counts.indexOf(state.repeatCount) + 1) % counts.length;
        state.repeatCount = counts[nextIdx];
        DOM.btnGtafAudioLoop.textContent = `Ulangi ${state.repeatCount}x`;
        if (DOM.btnLoopVerse) {
          DOM.btnLoopVerse.querySelector('span').textContent = `Ulangi ${state.repeatCount}x`;
        }
      });
    }
    if (DOM.btnGtafAudioClose) {
      DOM.btnGtafAudioClose.addEventListener('click', () => {
        if (DOM.globalAudio) DOM.globalAudio.pause();
        state.gtaf.playingSurahId = null;
        state.gtaf.playingVerseNumber = null;
        if (DOM.gtafStickyAudioBar) DOM.gtafStickyAudioBar.classList.add('hidden');
        renderGtafReaderView();
      });
    }

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
