#!/usr/bin/env python3
import json
import os
import sys
import urllib.request
import time

REPO = "aditexpres/quran-tarteel-hifz"
RELEASE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "releases")

def download_file(url, target_path):
    print(f"Downloading {os.path.basename(target_path)}...")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req) as resp, open(target_path, "wb") as f:
        total_size = int(resp.headers.get("content-length", 0))
        downloaded = 0
        chunk_size = 1024 * 512
        while True:
            chunk = resp.read(chunk_size)
            if not chunk:
                break
            f.write(chunk)
            downloaded += len(chunk)
            if total_size > 0:
                percent = int(downloaded * 100 / total_size)
                print(f"\r  -> {percent}% ({round(downloaded/(1024*1024), 2)} MB / {round(total_size/(1024*1024), 2)} MB)", end="")
        print(" [SELESAI]")

def main():
    os.makedirs(RELEASE_DIR, exist_ok=True)
    api_url = f"https://api.github.com/repos/{REPO}/releases/latest"
    req = urllib.request.Request(api_url, headers={"User-Agent": "Mozilla/5.0"})
    
    print(f"Menghubungi GitHub API: {api_url}")
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))

    tag_name = data.get("tag_name")
    print(f"Rilis Terbaru Ditemukan: {tag_name}")
    print(f"Direktori Target: {os.path.abspath(RELEASE_DIR)}\n")

    assets = data.get("assets", [])
    if not assets:
        print("Tidak ada aset rilis ditemukan.")
        return

    success_count = 0
    for asset in assets:
        name = asset["name"]
        dl_url = asset["browser_download_url"]
        size_mb = round(asset["size"] / (1024 * 1024), 2)
        target_path = os.path.join(RELEASE_DIR, name)
        
        print(f"\n[{success_count + 1}/{len(assets)}] {name} ({size_mb} MB)")
        try:
            download_file(dl_url, target_path)
            success_count += 1
        except Exception as e:
            print(f"  -> Gagal mengunduh {name}: {e}")

    print(f"\n=======================================================")
    print(f"Berhasil mengunduh {success_count}/{len(assets)} berkas rilis {tag_name} ke:")
    print(f"{os.path.abspath(RELEASE_DIR)}")
    print(f"=======================================================")

if __name__ == "__main__":
    main()
