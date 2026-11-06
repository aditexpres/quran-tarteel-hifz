#!/usr/bin/env bash
# ==============================================================================
# build_whisper_native.sh
# Skrip Otomasi Kompilasi Native Library `whisper.cpp` + `whisper_flutter_bridge.cpp`
# untuk:
#   1. Android (`libwhisper.so` — arm64-v8a & x86_64 via Android NDK)
#   2. Windows (`whisper.dll` — x86_64 AVX2 via CMake MSVC/MinGW)
#   3. macOS   (`libwhisper.dylib` — Universal Binary arm64 + x86_64 + Metal GPU)
# Serta Konversi & Kuantisasi Model Hugging Face `tarteel-ai/whisper-tiny-ar-quran` ke GGML.
#
# Cara Pakai:
#   bash build_whisper_native.sh android     # Build khusus Android (.so)
#   bash build_whisper_native.sh macos       # Build khusus macOS (.dylib)
#   bash build_whisper_native.sh windows     # Build khusus Windows (.dll)
#   bash build_whisper_native.sh convert     # Konversi & kuantisasi model Tarteel ke GGML q5_0
# ==============================================================================

set -euo pipefail

TARGET="${1:-help}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_PROJECT_DIR="$SCRIPT_DIR/quran_tarteel_hifz"
BUILD_ROOT="$SCRIPT_DIR/native_whisper_build"
WHISPER_CPP_DIR="$BUILD_ROOT/whisper.cpp"

mkdir -p "$BUILD_ROOT"

# 1. Pastikan repositori whisper.cpp tersedia dan salin whisper_flutter_bridge.cpp
prepare_whisper_repo() {
  if [ ! -d "$WHISPER_CPP_DIR" ]; then
    echo "[1/3] Mengunduh repositori resmi ggerganov/whisper.cpp..."
    git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git "$WHISPER_CPP_DIR"
  fi

  cp "$SCRIPT_DIR/whisper_flutter_bridge.cpp" "$WHISPER_CPP_DIR/whisper_flutter_bridge.cpp"

  # Tambahkan target shared library `whisper_bridge` ke CMakeLists.txt jika belum ada
  if ! grep -q "whisper_flutter_bridge.cpp" "$WHISPER_CPP_DIR/CMakeLists.txt"; then
    cat >> "$WHISPER_CPP_DIR/CMakeLists.txt" << 'EOF'

# --- Target Shared Library untuk Flutter Dart FFI ---
add_library(whisper_flutter SHARED whisper_flutter_bridge.cpp)
target_link_libraries(whisper_flutter PRIVATE whisper)
set_target_properties(whisper_flutter PROPERTIES OUTPUT_NAME "whisper")
EOF
  fi
}

# 2. Kompilasi untuk Android (libwhisper.so -> arm64-v8a & x86_64)
build_android() {
  prepare_whisper_repo
  if [ -z "${ANDROID_NDK_HOME:-}" ]; then
    echo "ERROR: Variabel environment ANDROID_NDK_HOME belum diatur."
    echo "Contoh: export ANDROID_NDK_HOME=\$HOME/Android/Sdk/ndk/26.1.10909125"
    exit 1
  fi

  TOOLCHAIN="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
  JNI_LIBS_DIR="$FLUTTER_PROJECT_DIR/android/app/src/main/jniLibs"

  for ABI in "arm64-v8a" "x86_64"; do
    echo "[2/3] Mengompilasi libwhisper.so untuk Android ABI: $ABI..."
    ABI_BUILD_DIR="$BUILD_ROOT/build-android-$ABI"
    cmake -S "$WHISPER_CPP_DIR" -B "$ABI_BUILD_DIR" \
      -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
      -DANDROID_ABI="$ABI" \
      -DANDROID_PLATFORM=android-24 \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON \
      -DWHISPER_BUILD_TESTS=OFF \
      -DWHISPER_BUILD_EXAMPLES=OFF

    cmake --build "$ABI_BUILD_DIR" --config Release -j

    mkdir -p "$JNI_LIBS_DIR/$ABI"
    find "$ABI_BUILD_DIR" -name "libwhisper.so" -exec cp {} "$JNI_LIBS_DIR/$ABI/libwhisper.so" \;
    echo "  -> Tersimpan di: $JNI_LIBS_DIR/$ABI/libwhisper.so"
  done
  echo "[3/3] Kompilasi Android selesai!"
}

# 3. Kompilasi untuk macOS (libwhisper.dylib Universal Binary + Apple Metal GPU)
build_macos() {
  prepare_whisper_repo
  echo "[2/3] Mengompilasi libwhisper.dylib untuk macOS (Universal arm64 + x86_64 dengan Metal)..."
  MACOS_BUILD_DIR="$BUILD_ROOT/build-macos"

  cmake -S "$WHISPER_CPP_DIR" -B "$MACOS_BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DBUILD_SHARED_LIBS=ON \
    -DGGML_METAL=ON \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF

  cmake --build "$MACOS_BUILD_DIR" --config Release -j

  MACOS_OUT_DIR="$FLUTTER_PROJECT_DIR/macos/Runner"
  mkdir -p "$MACOS_OUT_DIR"
  find "$MACOS_BUILD_DIR" -name "libwhisper.dylib" -exec cp {} "$MACOS_OUT_DIR/libwhisper.dylib" \;
  echo "[3/3] Selesai! Tersimpan di: $MACOS_OUT_DIR/libwhisper.dylib"
}

# 4. Kompilasi untuk Windows (whisper.dll x86_64 AVX2)
build_windows() {
  prepare_whisper_repo
  echo "[2/3] Mengompilasi whisper.dll untuk Windows (x86_64 Release)..."
  WIN_BUILD_DIR="$BUILD_ROOT/build-windows"

  cmake -S "$WHISPER_CPP_DIR" -B "$WIN_BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF

  cmake --build "$WIN_BUILD_DIR" --config Release -j

  WIN_OUT_DIR="$FLUTTER_PROJECT_DIR/windows/runner"
  mkdir -p "$WIN_OUT_DIR"
  find "$WIN_BUILD_DIR" -name "whisper.dll" -exec cp {} "$WIN_OUT_DIR/whisper.dll" \;
  echo "[3/3] Selesai! Tersimpan di: $WIN_OUT_DIR/whisper.dll"
}

# 5. Konversi & Kuantisasi Model Hugging Face `tarteel-ai/whisper-tiny-ar-quran` ke GGML
convert_tarteel_model() {
  prepare_whisper_repo
  echo "[1/3] Mengunduh model Hugging Face tarteel-ai/whisper-tiny-ar-quran..."
  HF_MODEL_DIR="$BUILD_ROOT/whisper-tiny-ar-quran"
  if [ ! -d "$HF_MODEL_DIR" ]; then
    git clone https://huggingface.co/tarteel-ai/whisper-tiny-ar-quran "$HF_MODEL_DIR"
  fi

  OPENAI_ASSETS_DIR="$BUILD_ROOT/openai-whisper"
  if [ ! -d "$OPENAI_ASSETS_DIR" ]; then
    git clone --depth 1 https://github.com/openai/whisper.git "$OPENAI_ASSETS_DIR"
  fi

  echo "[2/3] Mengonversi model PyTorch ke format GGML (ggml-tarteel-whisper-tiny-ar-quran.bin)..."
  python3 "$WHISPER_CPP_DIR/models/convert-h5-to-ggml.py" \
    "$HF_MODEL_DIR" \
    "$OPENAI_ASSETS_DIR" \
    "$BUILD_ROOT"

  mv "$BUILD_ROOT/ggml-model.bin" "$BUILD_ROOT/ggml-tarteel-whisper-tiny-ar-quran.bin"
  echo "[3/3] Selesai! Model GGML siap di: $BUILD_ROOT/ggml-tarteel-whisper-tiny-ar-quran.bin"
}

case "$TARGET" in
  android)
    build_android
    ;;
  macos)
    build_macos
    ;;
  windows)
    build_windows
    ;;
  convert)
    convert_tarteel_model
    ;;
  *)
    echo "Penggunaan: bash build_whisper_native.sh [android | macos | windows | convert]"
    ;;
esac