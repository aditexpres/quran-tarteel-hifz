param(
    [string]$BotToken = "8975743496:AAG0-A4OTy6-tdj2ljUftW77ozqS1Vb3yK0",
    [string]$ChatId = "-1004438916138",
    [string]$ReleaseDir = "$PSScriptRoot\..\releases"
)

$files = @(
    @{
        Path = "$ReleaseDir\app-arm64-v8a-release.apk"
        Caption = "📱 *Qur'an Tarteel Hifz v1.0.0 — Android APK (arm64-v8a)*`nPaket rilis resmi untuk smartphone Android 64-bit modern.`nFitur: Voice Hifz AI, Mushaf 15 Baris Madinah, Radar Mutasyabihat, & Audio Murattal Auto-Correction."
    },
    @{
        Path = "$ReleaseDir\app-armeabi-v7a-release.apk"
        Caption = "📱 *Qur'an Tarteel Hifz v1.0.0 — Android APK (armeabi-v7a)*`nPaket rilis resmi untuk smartphone Android 32-bit.`nFitur: Voice Hifz AI, Mushaf 15 Baris Madinah, Radar Mutasyabihat, & Audio Murattal Auto-Correction."
    },
    @{
        Path = "$ReleaseDir\QuranTarteelHifz-macOS-Universal.dmg"
        Caption = "🍏 *Qur'an Tarteel Hifz v1.0.0 — macOS Universal DMG*`nInstaller drag & drop resmi Apple Silicon (M1/M2/M3/M4) + Intel Mac.`nDilengkapi helper 1-klik buka aplikasi dan engine whisper.cpp Metal GPU!"
    },
    @{
        Path = "$ReleaseDir\QuranTarteelHifz-macOS-Universal.pkg"
        Caption = "🍏 *Qur'an Tarteel Hifz v1.0.0 — macOS Native PKG Installer*`nInstaller wizard resmi Apple macOS (langsung terpasang ke /Applications).`nLangsung klik 2x untuk memasang tanpa kendala Gatekeeper!"
    },
    @{
        Path = "$ReleaseDir\QuranTarteelHifz-Windows-x64.zip"
        Caption = "💻 *Qur'an Tarteel Hifz v1.0.0 — Windows Desktop Portable ZIP*`nPaket mandiri Windows 64-bit (EXE + whisper.dll AVX2).`nEkstrak dan langsung jalankan quran_tarteel_hifz.exe tanpa instalasi rumit!"
    }
)

foreach ($item in $files) {
    $filePath = $item.Path
    if (-not (Test-Path $filePath)) {
        Write-Warning "File tidak ditemukan: $filePath"
        continue
    }

    $fileInfo = Get-Item $filePath
    $sizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
    Write-Host "`nMengunggah $($fileInfo.Name) ($sizeMB MB) ke channel Telegram ($ChatId)..." -ForegroundColor Cyan

    $success = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Write-Host "Percobaan upload ke-$attempt..." -ForegroundColor Yellow
        $result = & curl.exe -4 -X POST "https://api.telegram.org/bot$BotToken/sendDocument" `
            --connect-timeout 30 `
            --max-time 600 `
            -F "chat_id=$ChatId" `
            -F "caption=$($item.Caption)" `
            -F "parse_mode=Markdown" `
            -F "document=@$filePath" 2>&1

        if ($result -match '"ok":true') {
            Write-Host "✅ Berhasil mengirim $($fileInfo.Name)!" -ForegroundColor Green
            $success = $true
            break
        } else {
            Write-Warning "Gagal pada percobaan ke-$attempt: $result"
            Start-Sleep -Seconds 3
        }
    }

    if (-not $success) {
        Write-Error "Gagal mengunggah $($fileInfo.Name) setelah 3 percobaan."
    }
}
