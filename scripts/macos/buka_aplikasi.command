#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
APP_TARGET="/Applications/Qur'an Tarteel Hifz.app"

echo "=========================================================="
echo "    Pemasang Otomatis Qur'an Tarteel Hifz untuk macOS     "
echo "=========================================================="
echo ""

if [ -d "$DIR/Qur'an Tarteel Hifz.app" ]; then
  echo "[1/3] Menyalin aplikasi ke /Applications..."
  rm -rf "$APP_TARGET"
  cp -R "$DIR/Qur'an Tarteel Hifz.app" /Applications/
fi

echo "[2/3] Membuka izin keamanan macOS Gatekeeper (Unquarantine)..."
xattr -cr "$APP_TARGET" 2>/dev/null || true

echo "[3/3] Menjalankan Qur'an Tarteel Hifz..."
open "$APP_TARGET"

echo ""
echo "Instalasi Berhasil! Aplikasi telah terpasang di folder Applications."
echo "Anda dapat menutup jendela Terminal ini."
