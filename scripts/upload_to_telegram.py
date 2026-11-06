import os
import subprocess
import sys
import time

BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "8975743496:AAG0-A4OTy6-tdj2ljUftW77ozqS1Vb3yK0")
CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "-1004438916138")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RELEASE_DIR = os.path.join(SCRIPT_DIR, "..", "releases")

FILES_TO_UPLOAD = [
    {
        "filename": "app-arm64-v8a-release.apk",
        "caption": (
            "📱 *Quran Tarteel Hifz v1.0.0 — Android APK (arm64-v8a)*\n"
            "Paket rilis resmi untuk smartphone Android 64-bit modern.\n"
            "Fitur: Voice Hifz AI, Mushaf 15 Baris Madinah, Radar Mutasyabihat, & Audio Murattal Auto-Correction."
        ),
    },
    {
        "filename": "app-armeabi-v7a-release.apk",
        "caption": (
            "📱 *Quran Tarteel Hifz v1.0.0 — Android APK (armeabi-v7a)*\n"
            "Paket rilis resmi untuk smartphone Android 32-bit.\n"
            "Fitur: Voice Hifz AI, Mushaf 15 Baris Madinah, Radar Mutasyabihat, & Audio Murattal Auto-Correction."
        ),
    },
    {
        "filename": "QuranTarteelHifz-macOS-Universal.dmg",
        "caption": (
            "🍏 *Quran Tarteel Hifz v1.0.0 — macOS Universal DMG*\n"
            "Installer resmi Apple Silicon (M1/M2/M3/M4) + Intel Mac.\n"
            "Dilengkapi engine whisper.cpp dengan akselerasi Apple Metal GPU!"
        ),
    },
]

def upload_file(filepath: str, caption: str):
    basename = os.path.basename(filepath)
    size_mb = round(os.path.getsize(filepath) / (1024 * 1024), 2)
    print(f"\n[Upload] Mengunggah {basename} ({size_mb} MB) ke Telegram channel {CHAT_ID}...")

    cmd = [
        "curl.exe",
        "-4",
        "-X", "POST",
        f"https://api.telegram.org/bot{BOT_TOKEN}/sendDocument",
        "--connect-timeout", "30",
        "--max-time", "600",
        "-F", f"chat_id={CHAT_ID}",
        "-F", f"caption={caption}",
        "-F", "parse_mode=Markdown",
        "-F", f"document=@{filepath}",
    ]

    for attempt in range(1, 4):
        print(f"  -> Percobaan {attempt}/3...")
        res = subprocess.run(cmd, capture_output=True, text=True)
        if '"ok":true' in res.stdout:
            print(f"  -> SUKSES! {basename} berhasil terkirim ke Telegram.")
            return True
        else:
            print(f"  -> Gagal: {res.stdout.strip()} {res.stderr.strip()}")
            time.sleep(3)

    return False

def main():
    print(f"Target Channel: {CHAT_ID}")
    success_count = 0
    for item in FILES_TO_UPLOAD:
        fp = os.path.join(RELEASE_DIR, item["filename"])
        if not os.path.exists(fp):
            print(f"File tidak ditemukan: {fp}")
            continue
        if upload_file(fp, item["caption"]):
            success_count += 1

    print(f"\nSelesai! {success_count}/{len(FILES_TO_UPLOAD)} file berhasil dikirim.")

if __name__ == "__main__":
    main()
