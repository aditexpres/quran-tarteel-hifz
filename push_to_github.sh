#!/usr/bin/env bash
# ==============================================================================
# push_to_github.sh
# Skrip 1-langkah untuk menginisialisasi Git dan mem-push seluruh repositori
# ke akun GitHub Anda.
#
# Cara Pakai:
#   bash push_to_github.sh https://github.com/USERNAME/quran-tarteel-hifz.git
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REPO_URL="${1:-}"
if [ -z "$REPO_URL" ]; then
  echo "Penggunaan: bash push_to_github.sh <URL_REPO_GITHUB>"
  echo "Contoh    : bash push_to_github.sh https://github.com/username/quran-tarteel-hifz.git"
  exit 1
fi

if [ ! -d ".git" ]; then
  git init
fi

git branch -M main
git add .
git commit -m "feat: complete Quran Tarteel Hifz cross-platform app, 15-line Mushaf, Whisper FFI, and CI/CD" || true

if git remote | grep -q "^origin$"; then
  git remote set-url origin "$REPO_URL"
else
  git remote add origin "$REPO_URL"
fi

git push -u origin main
echo "Berhasil di-push ke $REPO_URL!"
