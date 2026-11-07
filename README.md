# Qur'an Tarteel Hifz & Radar Mutasyabihat (Lintas Platform)

Aplikasi penghafal Al-Qur'an lintas platform (**Android, Windows, dan macOS**) berbasis **Flutter**, **SQLite Dual-Database**, dan **On-Device AI Speech-to-Text (`whisper.cpp`)**. Proyek ini dirancang khusus untuk membantu penghafal Al-Qur'an menyimak bacaan secara *real-time* (seperti [Tarteel.ai](https://www.tarteel.ai/)) sekaligus mencegah kesalahan **lompat surah akibat ayat mirip (*Mutasyabihat*) dalam 1 Juz**.

Dokumen ini juga berfungsi sebagai **Dokumen Handoff & Panduan Lanjutan Proyek** bagi rekan tim yang melanjutkan pengembangan dari sesi perancangan awal ([Rancang Bangun Aplikasi Qur'an Tarteel Lintas Platform](https://share.gemini.google/vZXu2ZC6Y9XM)).

| Komponen Arsitektur | Teknologi yang Digunakan | Status Implementasi | 
| ----- | ----- | ----- | 
| **Framework UI Lintas Platform** | Flutter 3.24+ (Material 3 Dark Theme, Split-Screen Desktop & Mobile Nav) | Selesai (`quran_hifz_app.dart`) | 
| **Tata Letak Mushaf** | Mushaf Standar Madinah 15 Baris + Mode Kartu Ayat + Efek Blur *Hide/Peek* | Selesai (`mushaf_15line_and_audio.dart`) | 
| **Database Lokal** | SQLite Dual-Database (`quran_master.db` Read-Only & `user_hifz.db` Read-Write) | Selesai (`build_quran_db.py` & `quran_hifz_repository.dart`) | 
| **AI Speech-to-Text (STT)** | [ggerganov/whisper.cpp](https://github.com/ggerganov/whisper.cpp) (Dart FFI C++ Bridge) + Model [tarteel-ai/whisper-tiny-ar-quran](https://huggingface.co/tarteel-ai/whisper-tiny-ar-quran) | Selesai (`whisper_flutter_bridge.cpp` & `whisper_voice_service.dart`) | 
| **Koreksi Audio Murattal** | Streaming per ayat [EveryAyah](https://everyayah.com/) (4 Qari) + Auto-Koreksi saat *Trap Jump* | Selesai (`mushaf_15line_and_audio.dart`) | 
| **Pengujian & CI/CD** | `flutter_test` + `sqflite_common_ffi` & GitHub Actions Multi-OS Release | Selesai (`quran_hifz_test.dart` & `release_build.yml`) | 

## 1. Ringkasan Handoff untuk Rekan Pengembang

Pada tahap perancangan awal ([tautan percakapan pertama](https://share.gemini.google/vZXu2ZC6Y9XM)), proyek berhenti pada rancangan skema tabel SQLite dan skrip purwarupa awal `build_quran_db.py`. Pada sesi pengembangan lanjutan ini, seluruh modul inti telah selesai dibangun dan siap dijalankan:

1. **Generator Database Otomatis (`build_quran_db.py`)**:

   * Mengunduh daftar 114 Surah, seluruh ayat Uthmani & teks bersih tanpa harakat (`text_clean`), Terjemahan Bahasa Indonesia Kemenag RI, **Terjemahan Perkata (`words`)**, dan **Tafsir Wajiz** dari [Quran.com API v4](https://api.quran.com/api/v4/chapters?language=id) dengan penanganan paginasi penuh.

   * Memetakan pasangan ayat mirip (*Mutasyabihat*) secara otomatis menggunakan kombinasi kesamaan token dan karakter (`difflib.SequenceMatcher`), mengekstrak indeks kata pembeda (`diff_word_positions`), serta menyimpan 3–4 kata awal ayat berikutnya (`next_verse_start_words`).

   * Menyediakan flag `--offline-demo` untuk membuat database sampel Juz 30 secara instan tanpa koneksi internet.

2. **Data Layer & Repository Lintas Platform (`quran_hifz_repository.dart`)**:

   * Menginisialisasi `sqflite` (Android) dan `sqflite_common_ffi` (Windows/macOS), menyalin aset `quran_master.db`, serta melakukan `ATTACH DATABASE 'user_hifz.db' AS user_hifz`.

   * Mengimplementasikan **Query A (Radar Mutasyabihat)** dengan filter ruang lingkup (*Dalam 1 Juz*, *Dalam 1 Surah*, *Lintas Juz*), **Query B (Dual-Path Listening)** yang membandingkan jalur bacaan benar (`CORRECT_NEXT`) terhadap jalur jebakan surah kembaran (`TRAP_JUMP`), serta algoritma `ArabicFuzzyMatcher` berbasis *Levenshtein Distance*.

3. **Mushaf Madinah 15 Baris & Audio Murattal Auto-Koreksi (`mushaf_15line_and_audio.dart`)**:

   * Menyusun kata demi kata ke dalam tepat **15 baris proporsional** standar Mushaf Madinah, lengkap dengan bingkai ornamen kepala Surah, baris Basmalah, medali angka Arab Timur, dan fitur *Hide/Peek Verse* (efek blur perkata).

   * Memutar audio murattal dari 4 Qari (Syaikh Al-Husary, Mishary Alafasy, Al-Minshawi, dan Abdul Basit) serta otomatis memutar ayat lanjutan yang benar ketika pengguna terkena peringatan *Trap Jump*.

4. **Mikrofon Real-Time PCM 16kHz, Pengunduh Model Whisper, & Jembatan C++ FFI (`whisper_voice_service.dart` & `whisper_flutter_bridge.cpp`)**:

   * Menangkap aliran audio mikrofon 16kHz 16-bit Mono dengan deteksi aktivitas suara (*RMS Voice Activity Detection*) dan *Sliding Window Buffer* (2,0 detik dengan *overlap* 0,4 detik).

   * Menyediakan pengunduh model otomatis dari repositori Hugging Face [tarteel-ai/whisper-tiny-ar-quran](https://huggingface.co/tarteel-ai/whisper-tiny-ar-quran) dan [tarteel-ai/whisper-base-ar-quran](https://huggingface.co/tarteel-ai/whisper-base-ar-quran).

   * Menghubungkan Dart FFI di *background* `Isolate.run()` ke wrapper C-ABI `whisper_flutter_bridge.cpp` agar antarmuka tetap berjalan mulus di 60/120 FPS.

## 2. Daftar Lengkap File di Repositori

| Nama File | Lokasi Target di Proyek Flutter | Deskripsi Singkat | 
| ----- | ----- | ----- | 
| `build_quran_db.py` | Root / `scripts/build_quran_db.py` | Skrip Python pembuat `quran_master.db` & `user_hifz.db`. | 
| `pubspec.yaml` | `quran_tarteel_hifz/pubspec.yaml` | Konfigurasi dependensi paket Flutter dan pendaftaran aset database. | 
| `quran_hifz_repository.dart` | `quran_tarteel_hifz/lib/quran_hifz_repository.dart` | Model data, layanan SQLite Dual-DB, Repository, & `ArabicFuzzyMatcher`. | 
| `mushaf_15line_and_audio.dart` | `quran_tarteel_hifz/lib/mushaf_15line_and_audio.dart` | Widget Mushaf Madinah 15 Baris & `QuranMurattalAudioService`. | 
| `whisper_voice_service.dart` | `quran_tarteel_hifz/lib/whisper_voice_service.dart` | Streaming mikrofon PCM 16kHz, VAD, pengunduh model, & Dart FFI Whisper. | 
| `quran_hifz_app.dart` | `quran_tarteel_hifz/lib/main.dart` | Layar utama responsif (Android Bottom Nav & Desktop Split-Screen). | 
| `whisper_flutter_bridge.cpp` | `native_whisper_build/whisper.cpp/` | Wrapper C-ABI untuk mengekspor fungsi `whisper.h` ke Dart FFI. | 
| `build_whisper_native.sh` | Root (`build_whisper_native.sh`) | Skrip CMake kompilasi `.so` (Android), `.dll` (Windows), & `.dylib` (macOS). | 
| `setup_flutter_project.sh` | Root (`setup_flutter_project.sh`) | Skrip otomasi *setup* proyek Flutter, izin mikrofon OS, & *build* DB. | 
| `quran_hifz_test.dart` | `quran_tarteel_hifz/test/quran_hifz_test.dart` | Unit & integration test suite (`flutter test`). | 
| `release_build.yml` | `.github/workflows/release_build.yml` | Pipeline CI/CD GitHub Actions untuk rilis APK, ZIP Windows, & DMG macOS. | 

## 3. Cara Instalasi & Menjalankan Proyek (Quickstart)

### Langkah 1: Jalankan Skrip Setup Otomatis

Pastikan Python 3 dan Flutter SDK telah terpasang, lalu jalankan:

```
chmod +x setup_flutter_project.sh build_whisper_native.sh
bash setup_flutter_project.sh

```

Skrip di atas akan otomatis membuat proyek Flutter `quran_tarteel_hifz`, menyalin seluruh file `.dart` ke `lib/` dan `test/`, mengonfigurasi izin `RECORD_AUDIO` di `AndroidManifest.xml` serta `com.apple.security.device.audio-input` di macOS, dan menghasilkan database awal `assets/db/quran_master.db`.

### Langkah 2: (Opsional) Generate Database 30 Juz Penuh (114 Surah)

Secara bawaan, `setup_flutter_project.sh` menggunakan mode `--offline-demo` agar instan. Untuk mengunduh 30 Juz penuh beserta terjemahan perkata dari [Quran.com API v4](https://api.quran.com/api/v4/chapters?language=id):

```
python3 build_quran_db.py --all \
  --master-out quran_tarteel_hifz/assets/db/quran_master.db \
  --user-out quran_tarteel_hifz/assets/db/user_hifz.db

```

### Langkah 3: Jalankan Unit Test & Aplikasi

```
cd quran_tarteel_hifz
flutter pub get
flutter test test/quran_hifz_test.dart
flutter run

```

### Langkah 4: Kompilasi Pustaka Native `whisper.cpp` (Untuk Mode Offline On-Device)

Jika ingin mengaktifkan inferensi suara C++ *on-device* di luar mode simulator:

```
# Konversi model Hugging Face tarteel-ai/whisper-tiny-ar-quran ke format GGML
bash build_whisper_native.sh convert

# Kompilasi sesuai target sistem operasi
bash build_whisper_native.sh android   # Menghasilkan libwhisper.so (arm64-v8a & x86_64)
bash build_whisper_native.sh macos     # Menghasilkan libwhisper.dylib (Universal + Metal GPU)
bash build_whisper_native.sh windows   # Menghasilkan whisper.dll (x86_64)

```

### Panduan Instalasi macOS (Apple Silicon M1/M2/M3/M4 & Intel Mac)

File rilis macOS tersedia dalam dua format resmi:

1. **Paket Installer `.pkg` (Paling Direkomendasikan & Langsung Bisa Diinstal)**:
   - Unduh `QuranTarteelHifz-macOS-Universal.pkg`.
   - Klik dua kali file `.pkg`. Jendela instalasi resmi macOS akan muncul.
   - Klik **Lanjutkan (Continue)** -> **Pasang (Install)** -> Masukkan Touch ID/password Mac.
   - Aplikasi otomatis terpasang di `/Applications` dan siap dibuka dari Launchpad!

2. **Disk Image `.dmg` (Drag & Drop + 1-Klik Helper)**:
   - Unduh dan buka `QuranTarteelHifz-macOS-Universal.dmg`.
   - Cukup klik dua kali **`Buka Aplikasi (Klik Dua Kali).command`** di dalam folder DMG. Skrip ini akan otomatis menyalin aplikasi ke `/Applications`, membersihkan karantina Gatekeeper, dan membuka aplikasi.
   - Atau geser (drag) ikon `Qur'an Tarteel Hifz.app` ke shortcut `Applications`.

3. **Solusi Cepat Jika Muncul Peringatan Gatekeeper ("Aplikasi Rusak" / "Unidentified Developer")**:
   - Jalankan skrip perbaikan otomatis:
     ```bash
     bash scripts/fix_macos_install.sh
     ```
   - Atau langsung jalankan 1 baris perintah ini di Terminal Mac:
     ```bash
     xattr -cr "/Applications/Qur'an Tarteel Hifz.app"
     codesign --force --deep --sign - "/Applications/Qur'an Tarteel Hifz.app"
     open "/Applications/Qur'an Tarteel Hifz.app"
     ```

## 4. Roadmap Pengembangan Selanjutnya (Untuk Rekan Tim)

1. **Integrasi Font QCF Per Halaman Mushaf Madinah**: Mengunduh font `.ttf` per halaman (halaman 1–604) dari [Quranic Universal Library (QUL)](https://qul.tarteel.ai/) agar ligatur kaligrafi Uthmani pada `Mushaf15LinePageWidget` identik 100% dengan cetakan Kompleks Raja Fahd.

2. **Sinkronisasi Cloud & Statistik Hifz**: Menambahkan grafik riwayat kelancaran hafalan per Juz serta ekspor/impor file cadangan `user_hifz.db` (catatan *Memory Anchor* & riwayat *Trap Jump*).

3. **Perekaman Langsung dengan Paket `record` & `just_audio`**: Menghubungkan *stream* `AudioRecorder().startStream(...)` ke parameter `liveMicPcmStream` pada `WhisperVoiceHifzController.startListening()` dan `AudioPlayer().setUrl` ke `QuranMurattalAudioService`.