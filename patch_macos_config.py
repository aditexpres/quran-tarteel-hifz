#!/usr/bin/env python3
# ==============================================================================
# patch_macos_config.py
# Mengonfigurasi Entitlements (Release & DebugProfile) dan Info.plist untuk macOS:
# 1. Non-sandboxed (app-sandbox: false) untuk distribusi bebas Gatekeeper di luar App Store
# 2. Izin JIT compiler (allow-jit: true)
# 3. Izin akses jaringan (network.client: true)
# 4. Izin mikrofon (device.audio-input: true & NSMicrophoneUsageDescription)
# 5. Izin pemuatan dynamic library whisper (cs.disable-library-validation: true)
# 6. Nama tampilan aplikasi resmi (CFBundleDisplayName: Qur'an Tarteel Hifz)
# ==============================================================================

import os
import sys

ENTITLEMENTS_CONTENT = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
"""

DEFAULT_INFO_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIconFile</key>
	<string></string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundleDisplayName</key>
	<string>Qur'an Tarteel Hifz</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$(FLUTTER_BUILD_NAME)</string>
	<key>CFBundleVersion</key>
	<string>$(FLUTTER_BUILD_NUMBER)</string>
	<key>LSMinimumSystemVersion</key>
	<string>$(MACOSX_DEPLOYMENT_TARGET)</string>
	<key>NSHumanReadableCopyright</key>
	<string>$(PRODUCT_COPYRIGHT)</string>
	<key>NSMainNibFile</key>
	<string>MainMenu</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>Aplikasi Qur'an Tarteel Hifz membutuhkan izin mikrofon untuk menyimak bacaan hafalan Al-Qur'an secara real-time.</string>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
</dict>
</plist>
"""

def patch_macos_project(project_dir: str):
    macos_dir = os.path.join(project_dir, 'macos')
    runner_dir = os.path.join(macos_dir, 'Runner')
    os.makedirs(runner_dir, exist_ok=True)

    # 1. Tulis Release.entitlements & DebugProfile.entitlements
    release_ent = os.path.join(runner_dir, 'Release.entitlements')
    with open(release_ent, 'w', encoding='utf-8') as f:
        f.write(ENTITLEMENTS_CONTENT)
    print(f"[macOS Config] Berhasil menulis {release_ent}")

    debug_ent = os.path.join(runner_dir, 'DebugProfile.entitlements')
    with open(debug_ent, 'w', encoding='utf-8') as f:
        f.write(ENTITLEMENTS_CONTENT)
    print(f"[macOS Config] Berhasil menulis {debug_ent}")

    # 2. Patch Info.plist
    info_plist_path = os.path.join(runner_dir, 'Info.plist')
    if not os.path.exists(info_plist_path):
        with open(info_plist_path, 'w', encoding='utf-8') as f:
            f.write(DEFAULT_INFO_PLIST)
        print(f"[macOS Config] Berhasil membuat default {info_plist_path}")
    else:
        with open(info_plist_path, 'r', encoding='utf-8') as f:
            content = f.read()

        insertions = []
        if 'NSMicrophoneUsageDescription' not in content:
            insertions.append(
                "\t<key>NSMicrophoneUsageDescription</key>\n"
                "\t<string>Aplikasi Qur'an Tarteel Hifz membutuhkan izin mikrofon untuk menyimak bacaan hafalan Al-Qur'an secara real-time.</string>"
            )
        if 'CFBundleDisplayName' not in content:
            insertions.append(
                "\t<key>CFBundleDisplayName</key>\n"
                "\t<string>Qur'an Tarteel Hifz</string>"
            )
        if 'NSAppTransportSecurity' not in content:
            insertions.append(
                "\t<key>NSAppTransportSecurity</key>\n"
                "\t<dict>\n"
                "\t\t<key>NSAllowsArbitraryLoads</key>\n"
                "\t\t<true/>\n"
                "\t</dict>"
            )

        if insertions:
            insert_str = "\n".join(insertions) + "\n"
            if "</dict>" in content:
                # Sisipkan sebelum </dict> penutup terakhir
                idx = content.rfind("</dict>")
                content = content[:idx] + insert_str + content[idx:]
                with open(info_plist_path, 'w', encoding='utf-8') as f:
                    f.write(content)
                print(f"[macOS Config] Berhasil memperbarui {info_plist_path} dengan izin mikrofon & nama aplikasi.")
            else:
                print(f"[macOS Config] Format {info_plist_path} tidak dikenal, lewati modifikasi.")
        else:
            print(f"[macOS Config] {info_plist_path} sudah memiliki seluruh izin yang diperlukan.")

def main():
    target_dir = sys.argv[1] if len(sys.argv) > 1 else 'quran_tarteel_hifz'
    print(f"[macOS Config] Mengonfigurasi proyek macOS di: {target_dir}")
    patch_macos_project(target_dir)

if __name__ == '__main__':
    main()
