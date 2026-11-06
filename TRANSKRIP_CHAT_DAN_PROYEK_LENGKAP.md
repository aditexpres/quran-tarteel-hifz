# Transkrip Lengkap Percakapan & Handoff Proyek: Aplikasi Qur'an Tarteel Lintas Platform

Dokumen ini berisi **rekaman lengkap riwayat diskusi, keputusan arsitektur, dan seluruh tahapan kode** dari:
1. **Sesi Perancangan Awal (Teman Anda)**: [Rancang Bangun Aplikasi Qur'an Tarteel Lintas Platform](https://share.gemini.google/vZXu2ZC6Y9XM)
2. **Sesi Pengembangan Lanjutan (Sesi Ini)**: Implementasi penuh Generator Database SQLite, Data Layer Flutter, Tampilan Mushaf Madinah 15 Baris, Audio Murattal Auto-Koreksi, Integrasi Mikrofon PCM 16kHz + Whisper.cpp FFI, Unit Test, hingga CI/CD GitHub Actions.

> **Cara Melanjutkan Proyek di Gemini / AI Lain (Untuk Rekan Tim):**
> Cukup unggah file **`TRANSKRIP_CHAT_DAN_PROYEK_LENGKAP.md`** ini bersama **`quran_tarteel_hifz_complete_repo.zip`** ke ruang chat Gemini Anda, lalu ketik:
> *"Baca transkrip dan paket repositori ini, lalu bantu saya melanjutkan pengembangan proyek Qur'an Tarteel Hifz."*

---

## Bagian 1: Ringkasan Sesi Perancangan Awal (Sesi 1)

* **Tujuan Utama**: Membangun aplikasi penghafal Al-Qur'an di Android yang dapat di-*porting* ke Windows dan macOS (menggunakan **Flutter** & **SQLite**), dengan fitur unggulan menyimak hafalan suara seperti [Tarteel.ai](https://www.tarteel.ai/) serta **Radar Mutasyabihat (Anti-Tertukar)** khusus untuk ayat-ayat mirip dalam 1 Juz yang sering membuat penghafal tidak sengaja melompat ke surah lain.
* **Fitur Standar Mushaf**: Tampilan Dual Mode (Mushaf Madinah 15 baris & Mode List Ayat), Terjemahan Bahasa Indonesia Kemenag RI, Terjemahan Perkata (*Word-by-Word*), dan Tafsir Wajiz.
* **Arsitektur Dual-Database SQLite**:
  - `quran_master.db` (*Read-Only Asset*): Menyimpan tabel `surahs`, `verses` (teks Uthmani & `text_clean` tanpa harakat), `words` (terjemahan perkata), `mutasyabihat_groups`, dan `mutasyabihat_items` (`diff_word_positions` & `next_verse_start_words`).
  - `user_hifz.db` (*Read-Write User Data*): Menyimpan tabel `user_memory_anchors` (catatan rumus Jembatan Ingatan pribadi) dan `error_logs` (riwayat kesalahan lompat surah).
  - Kedua database dihubungkan di runtime menggunakan perintah SQL `ATTACH DATABASE 'user_hifz.db' AS user_hifz;`.

---

## Bagian 2: Kronologi & Hasil Implementasi Sesi Lanjutan (Sesi 2)

### Tahap 1: Penyempurnaan `build_quran_db.py` & `quran_hifz_repository.dart`
* **`build_quran_db.py`**:
  - Dilengkapi pengunduh otomatis 114 Surah, ayat, terjemahan Kemenag RI (ID: 33), **terjemahan perkata (`words`)**, dan **Tafsir Wajiz** dari [Quran.com API v4](https://api.quran.com/api/v4/chapters?language=id) dengan penanganan paginasi penuh (`per_page=50`).
  - Dilengkapi fungsi `remove_diacritics()` untuk membersihkan harakat/tanda waqaf dan menormalisasi huruf (`أ إ آ ٱ` -> `ا`, `ى` -> `ي`, `ة` -> `ه`) agar pencocokan STT akurat.
  - Dilengkapi **Mesin Pemeta Otomatis Mutasyabihat** (`build_mutasyabihat_index`) berbasis `difflib.SequenceMatcher` yang mendeteksi pasangan ayat mirip, menghitung posisi kata pembeda (`diff_word_positions`), dan mengambil 3–4 kata pertama dari ayat selanjutnya (`next_verse_start_words`).
  - Ditambahkan mode `--offline-demo` untuk men-*generate* database sampel autentik Juz 30 (QS. An-Nazi'at: 32–34, QS. 'Abasa: 31–33, QS. Al-Infitar: 13–15, QS. Al-Mutaffifin: 22–23) tanpa koneksi internet.
* **`quran_hifz_repository.dart`**:
  - Mendukung inisialisasi lintas platform (`sqflite` di Android dan `sqflite_common_ffi` di Windows/macOS).
  - Mengimplementasikan **SQL Query A (`getMutasyabihatRadar`)** dengan 3 filter ruang lingkup (`withinOneJuz`, `withinOneSurah`, `crossJuz`) dan **SQL Query B (`getDualPathCandidates`)** yang mengambil kandidat `CORRECT_NEXT` sekaligus `TRAP_JUMP`.
  - Mengimplementasikan `ArabicFuzzyMatcher` (algoritma *Levenshtein Distance* & *Prefix Similarity*) untuk mendeteksi secara *real-time* apakah bacaan pengguna mengarah ke ayat yang benar atau melompat ke surah kembarannya.

### Tahap 2: Implementasi Opsi 3 — Mushaf Madinah 15 Baris & Audio Murattal (`mushaf_15line_and_audio.dart`)
* **`Mushaf15LineLayoutEngine` & `Mushaf15LinePageWidget`**:
  - Membagi daftar kata dan simbol akhir ayat pada satu halaman Mushaf (1–604) menjadi tepat **15 baris proporsional** standar Mushaf Madinah, lengkap dengan bingkai ornamen kepala Surah, baris Basmalah, medali angka Arab Timur (`۝١`, `۝٢`), serta dukungan penuh efek *blur* kata demi kata (*Hide/Peek Verse*).
* **`QuranMurattalAudioService` & `MurattalMiniPlayerDock`**:
  - Memutar audio murattal per ayat dari CDN [EveryAyah](https://everyayah.com/) dengan 4 pilihan Qari (Syaikh Mahmoud Khalil Al-Husary, Mishary Rashid Alafasy, Muhammad Siddiq Al-Minshawi, dan Abdul Basit Abdus Samad).
  - Memiliki fitur **Auto-Koreksi saat Trap Jump** (`playTrapJumpCorrection`): otomatis memutar bunyi ayat lanjutan yang benar saat pengguna terdeteksi melompat ke surah lain, ditambah fitur pengulangan (*Loop* 1x, 3x, 5x).

### Tahap 3: Implementasi Opsi 2 — Perekam Mikrofon Real-Time, Pengunduh Model Whisper, & C++ FFI (`whisper_voice_service.dart`, `whisper_flutter_bridge.cpp`, `build_whisper_native.sh`)
* **`WhisperModelDownloadManager`**:
  - Mengunduh model AI Al-Qur'an [tarteel-ai/whisper-tiny-ar-quran](https://huggingface.co/tarteel-ai/whisper-tiny-ar-quran) (~145 MB) atau [tarteel-ai/whisper-base-ar-quran](https://huggingface.co/tarteel-ai/whisper-base-ar-quran) (~278 MB) langsung ke penyimpanan lokal aplikasi dengan indikator persentase progres.
* **`CrossPlatformMicStreamService`**:
  - Memproses aliran audio PCM 16-bit 16kHz Mono dengan deteksi aktivitas suara (**RMS Voice Activity Detection / VAD**) dan **Sliding Window Buffer** (jendela 2,0 detik dengan *overlap* 0,4 detik).
* **`whisper_flutter_bridge.cpp` & `build_whisper_native.sh`**:
  - Jembatan C-ABI yang mengekspor 4 fungsi C (`whisper_bridge_init`, `whisper_bridge_transcribe_arabic`, `whisper_bridge_free_string`, `whisper_bridge_free`) dari [ggerganov/whisper.cpp](https://github.com/ggerganov/whisper.cpp) dan dipanggil oleh Dart FFI di dalam *background* `Isolate.run()`.
  - Skrip `build_whisper_native.sh` mengotomatiskan kompilasi CMake menjadi `libwhisper.so` (Android NDK), `whisper.dll` (Windows MSVC), dan `libwhisper.dylib` (macOS Universal Binary + Apple Metal GPU).

### Tahap 4: Implementasi Opsi 1, Unit Test, & CI/CD GitHub Actions (`quran_hifz_app.dart`, `pubspec.yaml`, `setup_flutter_project.sh`, `quran_hifz_test.dart`, `release_build.yml`)
* **`quran_hifz_app.dart`**:
  - Antarmuka utama adaptif yang menampilkan *Bottom Navigation* di Android dan *Split-Screen NavigationRail* di Windows/macOS (termasuk *shortcut* tombol `Spasi` untuk mengintip 1 kata berikutnya), menggabungkan Mushaf 15 Baris, Radar Mutasyabihat, Editor *Memory Anchor*, dan Kuis *Mode Drill Jebakan Mutasyabihat*.
* **`quran_hifz_test.dart`**:
  - Rangkaian *unit test* otomatis (`flutter test`) untuk menguji akurasi `ArabicFuzzyMatcher`, *query* SQLite Dual-Database *in-memory*, tata letak 15 baris Mushaf, dan konversi audio PCM 16kHz/WAV.
* **`release_build.yml` (`.github/workflows/release_build.yml`)**:
  - Pipeline CI/CD GitHub Actions 5 tahap untuk membangun database, menjalankan *unit test*, mengompilasi pustaka *native* `whisper.cpp`, mem-build APK Android, ZIP Windows, serta DMG macOS, dan mengunggahnya secara otomatis ke halaman *GitHub Releases*.

---

## Bagian 3: Daftar Seluruh File di Dalam `quran_tarteel_hifz_complete_repo.zip`

1. `README.md` — Dokumentasi utama repositori & panduan instalasi.
2. `TRANSKRIP_CHAT_DAN_PROYEK_LENGKAP.md` — Dokumen riwayat lengkap percakapan & arsitektur ini.
3. `PROMPT_HANDOFF_AI_DAN_TEMAN.md` — Template *prompt* siap salin untuk AI lain & rekan tim.
4. `build_quran_db.py` — Skrip Python pembuat database `quran_master.db` & `user_hifz.db`.
5. `pubspec.yaml` — Daftar dependensi dan aset proyek Flutter.
6. `quran_hifz_repository.dart` — Data Layer, SQLite Dual-DB Service, Repository, & `ArabicFuzzyMatcher`.
7. `mushaf_15line_and_audio.dart` — Widget Mushaf Madinah 15 Baris & `QuranMurattalAudioService`.
8. `whisper_voice_service.dart` — Mikrofon PCM 16kHz + VAD, pengunduh model Whisper, & Dart FFI.
9. `quran_hifz_app.dart` — UI utama aplikasi Flutter (`lib/main.dart`).
10. `whisper_flutter_bridge.cpp` — Wrapper C-ABI untuk `whisper.cpp`.
11. `build_whisper_native.sh` — Skrip CMake kompilasi `.so`, `.dll`, `.dylib` & konversi model GGML.
12. `setup_flutter_project.sh` — Skrip instalasi otomatis struktur proyek Flutter & izin OS.
13. `push_to_github.sh` — Skrip 1-langkah untuk `git init`, `commit`, dan `push` ke GitHub.
14. `quran_hifz_test.dart` — Suite *unit test* otomatis Flutter (`test/quran_hifz_test.dart`).
15. `release_build.yml` — Workflow CI/CD GitHub Actions (`.github/workflows/release_build.yml`).
16. `quran_tarteel_hifz/` — Folder proyek Flutter yang sudah dirakit lengkap beserta `assets/db/quran_master.db`.
