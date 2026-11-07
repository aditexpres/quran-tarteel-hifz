#!/usr/bin/env bash
# ==============================================================================
# fix_macos_install.sh
# Skrip Perbaikan Otomatis Gatekeeper & Izin macOS untuk Qur'an Tarteel Hifz
#
# Masalah yang Diperbaiki:
# 1. Peringatan macOS Gatekeeper: "Aplikasi rusak dan tidak dapat dibuka. Pindahkan ke Tong Sampah"
#    (Penyebab: Flag karantina com.apple.quarantine dari unduhan internet & ad-hoc signature).
# 2. Peringatan: "Pengembang tidak teridentifikasi" (Unidentified Developer).
# 3. Izin akses mikrofon (audio-input) dan jaringan lokal/internet.
#
# Cara Pakai:
#   1. Di Terminal: bash fix_macos_install.sh
#   2. Atau klik 2x file fix_macos_install.command di Finder Mac
# ==============================================================================

set -e

echo "=================================================================="
echo "  Perbaikan Otomatis Izin Instalasi macOS - Qur'an Tarteel Hifz   "
echo "=================================================================="
echo ""

APP_TARGET=""
POSSIBLE_PATHS=(
  "/Applications/Qur'an Tarteel Hifz.app"
  "/Applications/Quran Tarteel Hifz.app"
  "/Applications/quran_tarteel_hifz.app"
  "$HOME/Applications/Qur'an Tarteel Hifz.app"
  "$HOME/Applications/Quran Tarteel Hifz.app"
  "$HOME/Applications/quran_tarteel_hifz.app"
)

for p in "${POSSIBLE_PATHS[@]}"; do
  if [ -d "$p" ]; then
    APP_TARGET="$p"
    break
  fi
done

# Jika belum di /Applications, periksa apakah masih ada di folder Downloads
if [ -z "$APP_TARGET" ]; then
  DOWNLOAD_APP=$(find "$HOME/Downloads" -maxdepth 2 \( -name "*quran*tarteel*.app" -o -name "*Quran*Tarteel*.app" \) 2>/dev/null | head -n 1)
  if [ -n "$DOWNLOAD_APP" ]; then
    echo "Ditemukan file aplikasi di folder Downloads: $DOWNLOAD_APP"
    echo "Memindahkan aplikasi ke folder /Applications..."
    APP_TARGET="/Applications/Qur'an Tarteel Hifz.app"
    rm -rf "$APP_TARGET"
    cp -R "$DOWNLOAD_APP" "$APP_TARGET"
  fi
fi

if [ -n "$APP_TARGET" ] && [ -d "$APP_TARGET" ]; then
  echo "Target aplikasi: $APP_TARGET"

  echo "[1/3] Menghapus flag karantina macOS (com.apple.quarantine)..."
  xattr -cr "$APP_TARGET" 2>/dev/null || true

  echo "[2/3] Memperbaiki code signature ad-hoc dan Frameworks dylib..."
  if [ -d "$APP_TARGET/Contents/Frameworks" ]; then
    for d in "$APP_TARGET/Contents/Frameworks"/*.dylib; do
      if [ -f "$d" ]; then
        codesign --force --sign - --timestamp=none "$d" 2>/dev/null || true
      fi
    done
  fi
  codesign --force --deep --sign - --timestamp=none "$APP_TARGET" 2>/dev/null || true

  echo "[3/3] Membuka Qur'an Tarteel Hifz..."
  open "$APP_TARGET"

  echo ""
  echo "=================================================================="
  echo "✅ SUKSES! Aplikasi telah diperbaiki dan berhasil dijalankan."
  echo "=================================================================="
else
  echo "❌ File aplikasi belum ditemukan di /Applications atau Downloads."
  echo ""
  echo "Solusi Cepat:"
  echo "1. Pasang aplikasi ke folder Applications terlebih dahulu."
  echo "2. Lalu buka Terminal di Mac dan jalankan perintah berikut:"
  echo ""
  echo "   xattr -cr \"/Applications/Qur'an Tarteel Hifz.app\""
  echo "   codesign --force --deep --sign - \"/Applications/Qur'an Tarteel Hifz.app\""
  echo "   open \"/Applications/Qur'an Tarteel Hifz.app\""
  echo ""
fi
