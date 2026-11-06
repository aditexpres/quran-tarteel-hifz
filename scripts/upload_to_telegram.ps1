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
        Caption = "🍏 *Qur'an Tarteel Hifz v1.0.0 — macOS Universal DMG*`nInstaller resmi Apple Silicon (M1/M2/M3/M4) + Intel Mac.`nDilengkapi engine whisper.cpp dengan akselerasi Apple Metal GPU!"
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
