#!/usr/bin/env bash
# ==============================================================================
# setup_flutter_project.sh
# [OPSI 1] Skrip Otomasi Pembuatan Proyek Flutter Lintas Platform
# (Android, Windows, macOS), Konfigurasi Izin Mikrofon/Internet, Build Database,
# Penyalinan Unit Test (`test/quran_hifz_test.dart`), & Workflow CI/CD GitHub Actions.
# ==============================================================================

set -euo pipefail

PROJECT_NAME="quran_tarteel_hifz"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================================="
echo " 1. Membuat Kerangka Proyek Flutter ($PROJECT_NAME)"
echo "=================================================================="
if command -v flutter >/dev/null 2>&1; then
  flutter create --platforms=android,windows,macos "$PROJECT_NAME"
else
  echo "[Info] Flutter CLI belum terdeteksi di PATH, membuat struktur direktori proyek secara manual..."
  mkdir -p "$PROJECT_NAME/lib"
  mkdir -p "$PROJECT_NAME/test"
  mkdir -p "$PROJECT_NAME/assets/db"
  mkdir -p "$PROJECT_NAME/android/app/src/main"
  mkdir -p "$PROJECT_NAME/macos/Runner"
fi

mkdir -p "$PROJECT_NAME/lib"
mkdir -p "$PROJECT_NAME/test"
mkdir -p "$PROJECT_NAME/assets/db"
mkdir -p "$PROJECT_NAME/.github/workflows"

echo "=================================================================="
echo " 2. Menyalin Modul Dart, Unit Test, Workflow CI/CD, & pubspec.yaml"
echo "=================================================================="
cp "$SCRIPT_DIR/pubspec.yaml" "$PROJECT_NAME/pubspec.yaml"
cp "$SCRIPT_DIR/quran_hifz_repository.dart" "$PROJECT_NAME/lib/quran_hifz_repository.dart"
cp "$SCRIPT_DIR/mushaf_15line_and_audio.dart" "$PROJECT_NAME/lib/mushaf_15line_and_audio.dart"
cp "$SCRIPT_DIR/whisper_voice_service.dart" "$PROJECT_NAME/lib/whisper_voice_service.dart"
cp "$SCRIPT_DIR/app_update_service.dart" "$PROJECT_NAME/lib/app_update_service.dart"
cp "$SCRIPT_DIR/marked_mushaf_view.dart" "$PROJECT_NAME/lib/marked_mushaf_view.dart"
cp "$SCRIPT_DIR/quran_hifz_app.dart" "$PROJECT_NAME/lib/main.dart"

# Salin quran_hifz_test.dart ke folder test/ dengan penyesuaian path import `../lib/`
rm -f "$PROJECT_NAME/test/widget_test.dart"
if [ -f "$SCRIPT_DIR/quran_hifz_test.dart" ]; then
  sed \
    -e "s|import 'mushaf_15line_and_audio.dart';|import '../lib/mushaf_15line_and_audio.dart';|g" \
    -e "s|import 'quran_hifz_repository.dart';|import '../lib/quran_hifz_repository.dart';|g" \
    -e "s|import 'whisper_voice_service.dart';|import '../lib/whisper_voice_service.dart';|g" \
    "$SCRIPT_DIR/quran_hifz_test.dart" > "$PROJECT_NAME/test/quran_hifz_test.dart"
fi

# Salin workflow GitHub Actions jika tersedia
if [ -f "$SCRIPT_DIR/release_build.yml" ]; then
  mkdir -p "$SCRIPT_DIR/.github/workflows"
  cp "$SCRIPT_DIR/release_build.yml" "$SCRIPT_DIR/.github/workflows/release_build.yml"
  cp "$SCRIPT_DIR/release_build.yml" "$PROJECT_NAME/.github/workflows/release_build.yml"
fi

echo "=================================================================="
echo " 3. Mengonfigurasi Izin Mikrofon & Internet (Android & macOS)"
echo "=================================================================="
ANDROID_MANIFEST="$PROJECT_NAME/android/app/src/main/AndroidManifest.xml"
cat > "$ANDROID_MANIFEST" << 'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Izin Wajib untuk Voice Hifz (Mikrofon PCM 16kHz) & Unduh Model/Audio Murattal -->
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.VIBRATE" />

    <application
        android:label="Qur'an Tarteel Hifz"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
EOF

MACOS_ENTITLEMENTS="$PROJECT_NAME/macos/Runner/DebugProfile.entitlements"
cat > "$MACOS_ENTITLEMENTS" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
EOF

echo "=================================================================="
echo " 4. Membangun Database SQLite (quran_master.db) ke assets/db/"
echo "=================================================================="
python3 "$SCRIPT_DIR/build_quran_db.py" \
  --offline-demo \
  --master-out "$PROJECT_NAME/assets/db/quran_master.db" \
  --user-out "$PROJECT_NAME/assets/db/user_hifz.db"

echo "=================================================================="
echo " Selesai! Proyek '$PROJECT_NAME' siap dijalankan & diuji:"
echo "   cd $PROJECT_NAME"
echo "   flutter pub get"
echo "   flutter test test/quran_hifz_test.dart"
echo "   flutter run"
echo "=================================================================="