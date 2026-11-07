#!/usr/bin/env bash
# ==============================================================================
# setup_flutter_project.sh
# [OPSI 1] Skrip Otomasi Pembuatan Proyek Flutter Lintas Platform
# (Android, Windows, macOS), Konfigurasi Izin Mikrofon/Internet/Instalasi APK,
# Pemasangan Keystore Deterministik (Anti-Conflict Update), Build Database,
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
  mkdir -p "$PROJECT_NAME/android/app/src/main/kotlin/com/example/quran_tarteel_hifz"
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
echo " 3. Mengonfigurasi Izin Mikrofon, Internet & Pemasang APK (Android & macOS)"
echo "=================================================================="
ANDROID_MANIFEST="$PROJECT_NAME/android/app/src/main/AndroidManifest.xml"
cat > "$ANDROID_MANIFEST" << 'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Izin Wajib untuk Voice Hifz (Mikrofon PCM 16kHz), Unduh Model/Audio, & In-App APK Update -->
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.VIBRATE" />
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />

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

        <!-- ContentProvider Internal Tanpa Dependensi Eksternal untuk Instalasi APK Pembaruan -->
        <provider
            android:name=".ApkFileProvider"
            android:authorities="com.example.quran_tarteel_hifz.apkprovider"
            android:exported="false"
            android:grantUriPermissions="true" />

        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
EOF

# Tulis MainActivity.kt dengan MethodChannel In-App APK Installer & Browser Intent
KOTLIN_DIR="$PROJECT_NAME/android/app/src/main/kotlin/com/example/quran_tarteel_hifz"
mkdir -p "$KOTLIN_DIR"
cat > "$KOTLIN_DIR/MainActivity.kt" << 'EOF'
package com.example.quran_tarteel_hifz

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Intent
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.qurantarteelhifz/installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (url != null) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_URL_ERR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_URL", "URL is null", null)
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        try {
                            val srcFile = File(filePath)
                            val destFile = File(applicationContext.cacheDir, "QuranTarteelHifz-update.apk")
                            if (srcFile.absolutePath != destFile.absolutePath) {
                                srcFile.copyTo(destFile, overwrite = true)
                            }

                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                if (!packageManager.canRequestPackageInstalls()) {
                                    val permIntent = Intent(
                                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                        Uri.parse("package:$packageName")
                                    ).apply {
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    startActivity(permIntent)
                                }
                            }

                            val contentUri = Uri.parse("content://${applicationContext.packageName}.apkprovider/QuranTarteelHifz-update.apk")
                            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(contentUri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(installIntent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_ERR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_PATH", "filePath is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

class ApkFileProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String = "application/vnd.android.package-archive"

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor {
        val file = File(context?.cacheDir, uri.lastPathSegment ?: "QuranTarteelHifz-update.apk")
        val cols = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val values = arrayOfNulls<Any>(cols.size)
        for (i in cols.indices) {
            when (cols[i]) {
                OpenableColumns.DISPLAY_NAME -> values[i] = file.name
                OpenableColumns.SIZE -> values[i] = file.length()
            }
        }
        val cursor = MatrixCursor(cols, 1)
        cursor.addRow(values)
        return cursor
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val fileName = uri.lastPathSegment ?: "QuranTarteelHifz-update.apk"
        val file = File(context?.cacheDir, fileName)
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
EOF

echo "=================================================================="
echo " 3b. Memasang Keystore Permanen (~/.android/debug.keystore)"
echo "     Agar Update APK Tidak Pernah Konflik Signature Antar Versi"
echo "=================================================================="
mkdir -p "$HOME/.android"
if [ -f "$SCRIPT_DIR/signing/release_cert.pem" ] && [ -f "$SCRIPT_DIR/signing/release_key.pem" ] && command -v openssl >/dev/null 2>&1 && command -v keytool >/dev/null 2>&1; then
  rm -f "$HOME/.android/debug.keystore" /tmp/quran_debug.p12
  openssl pkcs12 -export \
    -in "$SCRIPT_DIR/signing/release_cert.pem" \
    -inkey "$SCRIPT_DIR/signing/release_key.pem" \
    -out /tmp/quran_debug.p12 \
    -name androiddebugkey \
    -passout pass:android
  keytool -importkeystore \
    -srckeystore /tmp/quran_debug.p12 \
    -srcstoretype PKCS12 \
    -srcstorepass android \
    -destkeystore "$HOME/.android/debug.keystore" \
    -deststoretype JKS \
    -deststorepass android \
    -destkeypass android \
    -noprompt
  rm -f /tmp/quran_debug.p12
  echo "[Keystore] Berhasil memasang JKS deterministik ke $HOME/.android/debug.keystore"
elif [ -f "$SCRIPT_DIR/signing/debug.keystore" ]; then
  cp "$SCRIPT_DIR/signing/debug.keystore" "$HOME/.android/debug.keystore"
  echo "[Keystore] Berhasil menyalin debug.keystore deterministik ke $HOME/.android/debug.keystore"
fi

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
