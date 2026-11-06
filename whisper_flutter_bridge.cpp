// whisper_flutter_bridge.cpp
// =============================================================================
// Jembatan C-ABI (FFI Bridge) antara `whisper.cpp` dan Dart FFI Flutter
// untuk Aplikasi Qur'an Tarteel Lintas Platform (Android .so, Windows .dll, macOS .dylib).
//
// Mengapa menggunakan jembatan C sederhana ini?
// Struct `whisper_full_params` di `whisper.h` berukuran besar dan memiliki
// alignment yang berbeda-beda antar versi kompiler (Android NDK Clang, MSVC Windows,
// Apple Clang macOS). Dengan mengekspor 4 fungsi C bertipe primitif di bawah ini,
// pemanggilan Dart FFI dijamin 100% stabil di semua arsitektur CPU (ARM64 & x86_64).
// =============================================================================

#include "whisper.h"
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>

#if defined(_WIN32)
#define FFI_EXPORT extern "C" __declspec(dllexport)
#else
#define FFI_EXPORT extern "C" __attribute__((visibility("default"))) __attribute__((used))
#endif

// 1. Inisialisasi model GGML/GGUF Al-Qur'an dan kembalikan pointer context sebagai int64_t
FFI_EXPORT int64_t whisper_bridge_init(const char* model_path) {
    if (model_path == nullptr || std::strlen(model_path) == 0) {
        return 0;
    }
    struct whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = true; // Aktifkan akselerasi GPU/Metal jika tersedia

    struct whisper_context* ctx = whisper_init_from_file_with_params(model_path, cparams);
    return reinterpret_cast<int64_t>(ctx);
}

// 2. Transkripsi array sampel audio Float32 (16kHz Mono) khusus Bahasa Arab Al-Qur'an
FFI_EXPORT const char* whisper_bridge_transcribe_arabic(
    int64_t ctx_handle,
    const float* pcm_f32,
    int32_t n_samples,
    int32_t n_threads
) {
    auto* ctx = reinterpret_cast<struct whisper_context*>(ctx_handle);
    if (ctx == nullptr || pcm_f32 == nullptr || n_samples <= 0) {
        return nullptr;
    }

    struct whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    wparams.language         = "ar";   // Kunci bahasa ke Bahasa Arab
    wparams.translate        = false;  // Jangan terjemahkan ke bahasa Inggris
    wparams.no_context       = true;   // Hindari halusinasi antar jendela sliding window
    wparams.single_segment   = true;   // Optimasi kecepatan real-time (1 segmen per 2 detik)
    wparams.print_realtime   = false;
    wparams.print_progress   = false;
    wparams.print_timestamps = false;
    wparams.print_special    = false;

    int32_t hw_threads = static_cast<int32_t>(std::thread::hardware_concurrency());
    if (n_threads <= 0) {
        n_threads = (hw_threads >= 4) ? 4 : (hw_threads > 1 ? hw_threads : 2);
    }
    wparams.n_threads = n_threads;

    if (whisper_full(ctx, wparams, pcm_f32, n_samples) != 0) {
        return nullptr;
    }

    std::string combined_text;
    const int n_segments = whisper_full_n_segments(ctx);
    for (int i = 0; i < n_segments; ++i) {
        const char* seg_text = whisper_full_get_segment_text(ctx, i);
        if (seg_text != nullptr) {
            combined_text += seg_text;
        }
    }

    // Alokasikan buffer string C agar bisa dibaca oleh Dart FFI lalu dibebaskan via whisper_bridge_free_string
    char* out_str = static_cast<char*>(std::malloc(combined_text.size() + 1));
    if (out_str != nullptr) {
        std::memcpy(out_str, combined_text.c_str(), combined_text.size() + 1);
    }
    return out_str;
}

// 3. Bebaskan memori string hasil transkripsi setelah disalin ke String Dart
FFI_EXPORT void whisper_bridge_free_string(const char* str_ptr) {
    if (str_ptr != nullptr) {
        std::free(const_cast<char*>(str_ptr));
    }
}

// 4. Bebaskan context whisper_context saat aplikasi ditutup
FFI_EXPORT void whisper_bridge_free(int64_t ctx_handle) {
    auto* ctx = reinterpret_cast<struct whisper_context*>(ctx_handle);
    if (ctx != nullptr) {
        whisper_free(ctx);
    }
}
