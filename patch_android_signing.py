#!/usr/bin/env python3
import os
import sys

def patch_android_project(project_dir):
    app_dir = os.path.join(project_dir, 'android', 'app')
    if not os.path.isdir(app_dir):
        print(f"[Signing] Directory {app_dir} not found, skipping patch.")
        return

    # 1. Pastikan file keystore disalin ke dalam android/app/
    src_keystore = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'signing', 'quran_release.keystore')
    dst_keystore = os.path.join(app_dir, 'quran_release.keystore')
    if os.path.exists(src_keystore):
        import shutil
        shutil.copyfile(src_keystore, dst_keystore)
        print(f"[Signing] Menyalin {src_keystore} -> {dst_keystore}")

    # 2. Tulis key.properties
    key_props_path = os.path.join(project_dir, 'android', 'key.properties')
    with open(key_props_path, 'w', encoding='utf-8') as f:
        f.write(
            "storePassword=quran_secret_password_2026\n"
            "keyPassword=quran_secret_password_2026\n"
            "keyAlias=quran_release_key\n"
            "storeFile=quran_release.keystore\n"
        )
    print(f"[Signing] key.properties dibuat di {key_props_path}")

    # 3. Patch build.gradle.kts (Kotlin DSL)
    kts_path = os.path.join(app_dir, 'build.gradle.kts')
    if os.path.isfile(kts_path):
        with open(kts_path, 'r', encoding='utf-8') as f:
            content = f.read()

        if 'quran_release.keystore' not in content:
            signing_block_kts = """    signingConfigs {
        getByName("debug") {
            keyAlias = "quran_release_key"
            keyPassword = "quran_secret_password_2026"
            storeFile = file("quran_release.keystore")
            storePassword = "quran_secret_password_2026"
        }
        create("release") {
            keyAlias = "quran_release_key"
            keyPassword = "quran_secret_password_2026"
            storeFile = file("quran_release.keystore")
            storePassword = "quran_secret_password_2026"
        }
    }
"""
            content = content.replace(
                'signingConfig = signingConfigs.getByName("debug")',
                'signingConfig = signingConfigs.getByName("release")'
            )
            idx = content.find('buildTypes {')
            if idx != -1:
                content = content[:idx] + signing_block_kts + '\n    ' + content[idx:]
            with open(kts_path, 'w', encoding='utf-8') as f:
                f.write(content)
            print(f"[Signing] Berhasil mem-patch {kts_path} dengan signingConfigs release permanen.")

    # 4. Patch build.gradle (Groovy DSL)
    groovy_path = os.path.join(app_dir, 'build.gradle')
    if os.path.isfile(groovy_path):
        with open(groovy_path, 'r', encoding='utf-8') as f:
            content = f.read()

        if 'quran_release.keystore' not in content:
            signing_block_groovy = """    signingConfigs {
        debug {
            keyAlias 'quran_release_key'
            keyPassword 'quran_secret_password_2026'
            storeFile file('quran_release.keystore')
            storePassword 'quran_secret_password_2026'
        }
        release {
            keyAlias 'quran_release_key'
            keyPassword 'quran_secret_password_2026'
            storeFile file('quran_release.keystore')
            storePassword 'quran_secret_password_2026'
        }
    }
"""
            content = content.replace('signingConfig signingConfigs.debug', 'signingConfig signingConfigs.release')
            content = content.replace('signingConfig = signingConfigs.debug', 'signingConfig = signingConfigs.release')
            idx = content.find('buildTypes {')
            if idx != -1:
                content = content[:idx] + signing_block_groovy + '\n    ' + content[idx:]
            with open(groovy_path, 'w', encoding='utf-8') as f:
                f.write(content)
            print(f"[Signing] Berhasil mem-patch {groovy_path} dengan signingConfigs release permanen.")

if __name__ == '__main__':
    target = sys.argv[1] if len(sys.argv) > 1 else 'quran_tarteel_hifz'
    patch_android_project(target)
