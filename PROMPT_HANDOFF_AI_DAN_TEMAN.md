# Panduan Handoff Proyek (Untuk AI Lain & Rekan Pengembang)

Dokumen ini berisi instruksi siap pakai (**Copy-Paste Prompt**) yang dapat Anda berikan kepada **AI lain** (untuk mem-*push* kode ke GitHub Anda) maupun kepada **teman/rekan tim Anda** (untuk membaca riwayat proyek dan melanjutkan pengembangan).

---

## Bagian 1: Prompt Siap Salin untuk AI Lain (Agar Di-Push ke GitHub Anda)

Lampirkan file **`quran_tarteel_hifz_complete_repo.zip`** (atau file tunggal **`unpack_and_push_github.py`**) ke AI lain yang memiliki akses ke terminal/GitHub Anda, lalu tempelkan perintah berikut:

> **Prompt untuk AI:**
> "Saya melampirkan paket proyek **Qur'an Tarteel Hifz & Radar Mutasyabihat Lintas Platform (Android, Windows, macOS)** yang berisi struktur lengkap aplikasi Flutter, skrip generator SQLite Dual-Database (`build_quran_db.py`), *engine* C++ FFI `whisper.cpp` (`whisper_flutter_bridge.cpp`), tata letak Mushaf Madinah 15 Baris (`mushaf_15line_and_audio.dart`), *unit test* (`quran_hifz_test.dart`), serta *workflow* CI/CD GitHub Actions (`release_build.yml`).
>
> Tolong lakukan langkah berikut:
> 1. Ekstrak seluruh isi `quran_tarteel_hifz_complete_repo.zip` (atau jalankan `python3 unpack_and_push_github.py`).
> 2. Buat repositori GitHub baru bernama `quran-tarteel-hifz` di akun GitHub saya (atau gunakan repositori yang saya tentukan).
> 3. Jalankan `bash push_to_github.sh <URL_REPO_GITHUB_SAYA>` untuk menginisialisasi Git, membuat *commit* seluruh struktur proyek beserta `.github/workflows/release_build.yml`, dan melakukan `git push -u origin main`."

---

## Bagian 2: Pesan & Tautan Handoff untuk Teman/Rekan Tim Anda

Untuk membagikan riwayat percakapan ini beserta kodenya kepada teman Anda yang sebelumnya merancang proyek di [Tautan Percakapan Awal](https://share.gemini.google/vZXu2ZC6Y9XM):

1. **Cara Membagikan Chat Ini di Gemini**: Klik ikon **Bagikan / Share (ikon panah/rantai)** di sudut atas/bawah percakapan Gemini ini, pilih **Buat tautan publik (Create public link)**, lalu kirimkan tautan `https://share.gemini.google/...` yang baru tersebut kepada teman Anda.
2. **Prompt Lanjutan untuk Teman Anda**: Teman Anda cukup membuka tautan percakapan ini (atau meng-*clone* repositori GitHub yang sudah di-*push*) dan mengirimkan pesan berikut ke AI untuk melanjutkan ke tahap berikutnya:

> **Prompt Lanjutan untuk Rekan Tim:**
> "Saya melanjutkan pengembangan proyek **Qur'an Tarteel Hifz & Radar Mutasyabihat Lintas Platform** dari repositori/percakapan ini. Saat ini keempat fondasi utama sudah selesai:
> - `build_quran_db.py` (Generator SQLite Dual-Database `quran_master.db` & `user_hifz.db` + deteksi otomatis indeks *Mutasyabihat*).
> - `quran_hifz_repository.dart` (Data Layer lintas platform `sqflite` / `sqflite_common_ffi`, Query A *Radar Mutasyabihat*, Query B *Dual-Path Listening*, & `ArabicFuzzyMatcher`).
> - `mushaf_15line_and_audio.dart` (Tampilan Mushaf Madinah 15 Baris dengan *blur/peek* perkata + Audio Murattal 4 Qari dengan koreksi otomatis saat *Trap Jump*).
> - `whisper_voice_service.dart`, `whisper_flutter_bridge.cpp`, & `build_whisper_native.sh` (Streaming mikrofon PCM 16kHz + VAD, pengunduh model [tarteel-ai/whisper-tiny-ar-quran](https://huggingface.co/tarteel-ai/whisper-tiny-ar-quran), dan jembatan C-ABI Dart FFI untuk `libwhisper.so`/`.dll`/`.dylib`).
> - `quran_hifz_app.dart`, `quran_hifz_test.dart`, & `.github/workflows/release_build.yml` (UI utama Android & Desktop Split-Screen, *unit test*, dan CI/CD rilis otomatis).
>
> Selanjutnya, bantu saya mengintegrasikan font kaligrafi QCF per halaman (1–604) dari [Quranic Universal Library (QUL)](https://qul.tarteel.ai/) serta menghubungkan *instance* langsung `AudioRecorder` (`record`) dan `AudioPlayer` (`just_audio`) pada perangkat fisik."
