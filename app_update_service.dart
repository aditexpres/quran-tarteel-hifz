// lib/app_update_service.dart
// ==============================================================================
// Layanan Pembaruan Otomatis Lintas Platform (Android APK, Windows EXE, macOS DMG)
// Terintegrasi langsung dengan GitHub Releases API repositori resmi.
// Mendukung unduhan langsung di dalam aplikasi (In-App Download dengan Progress Bar)
// serta pemasangan otomatis (Native Android Package Installer, Windows Self-Updater,
// dan macOS DMG Mounter).
// ==============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String title;
  final String releaseNotes;
  final String releaseUrl;
  final String? apkArm64Url;
  final String? apkArm32Url;
  final String? apkX86Url;
  final String? windowsDownloadUrl;
  final String? macosDownloadUrl;
  final bool hasUpdate;

  AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.title,
    required this.releaseNotes,
    required this.releaseUrl,
    this.apkArm64Url,
    this.apkArm32Url,
    this.apkX86Url,
    this.windowsDownloadUrl,
    this.macosDownloadUrl,
    required this.hasUpdate,
  });

  String? get apkDownloadUrl => apkArm64Url ?? apkArm32Url ?? apkX86Url;

  String? get targetPlatformDownloadUrl {
    if (Platform.isAndroid) return apkDownloadUrl ?? releaseUrl;
    if (Platform.isWindows) return windowsDownloadUrl ?? releaseUrl;
    if (Platform.isMacOS) return macosDownloadUrl ?? releaseUrl;
    return releaseUrl;
  }
}

class AppUpdateService {
  static const String currentVersion = '1.2.1';
  static const String _githubRepoOwner = 'aditexpres';
  static const String _githubRepoName = 'quran-tarteel-hifz';
  static const MethodChannel _installerChannel = MethodChannel('com.qurantarteelhifz/installer');

  /// Memeriksa pembaruan dari GitHub Releases API
  static Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final url = Uri.parse(
        'https://api.github.com/repos/$_githubRepoOwner/$_githubRepoName/releases/latest',
      );
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'QuranTarteelHifz-App',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        return null;
      }

      final Map<String, dynamic> data = json.decode(response.body);
      final rawTag = data['tag_name'] as String? ?? '1.0.0';
      final cleanLatestVersion = rawTag.replaceAll(RegExp(r'[^0-9.]'), '');
      final releaseNotes = data['body'] as String? ?? 'Peningkatan performa dan pembaruan sistem.';
      final title = data['name'] as String? ?? 'Rilis Terbaru $rawTag';
      final htmlUrl = data['html_url'] as String? ?? 'https://github.com/$_githubRepoOwner/$_githubRepoName/releases';

      String? apkArm64;
      String? apkArm32;
      String? apkX86;
      String? winUrl;
      String? macUrl;

      final assets = data['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        final downloadUrl = asset['browser_download_url'] as String?;
        if (downloadUrl == null) continue;

        if (name.endsWith('.apk')) {
          if (name.contains('arm64-v8a') || name.contains('universal')) {
            apkArm64 = downloadUrl;
          } else if (name.contains('armeabi-v7a')) {
            apkArm32 = downloadUrl;
          } else if (name.contains('x86_64')) {
            apkX86 = downloadUrl;
          } else {
            apkArm64 ??= downloadUrl;
          }
        } else if (name.endsWith('.zip') && (name.contains('windows') || name.contains('win'))) {
          winUrl ??= downloadUrl;
        } else if (name.endsWith('.dmg')) {
          macUrl ??= downloadUrl;
        }
      }

      final hasUpdate = _isVersionHigher(cleanLatestVersion, currentVersion);

      return AppUpdateInfo(
        currentVersion: currentVersion,
        latestVersion: cleanLatestVersion,
        title: title,
        releaseNotes: releaseNotes,
        releaseUrl: htmlUrl,
        apkArm64Url: apkArm64,
        apkArm32Url: apkArm32,
        apkX86Url: apkX86,
        windowsDownloadUrl: winUrl,
        macosDownloadUrl: macUrl,
        hasUpdate: hasUpdate,
      );
    } catch (e) {
      debugPrint('[AppUpdateService] Gagal memeriksa update: $e');
      return null;
    }
  }

  /// Membandingkan semver: apakah v1 lebih tinggi dari v2
  static bool _isVersionHigher(String v1, String v2) {
    try {
      final parts1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final parts2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (int i = 0; i < 3; i++) {
        final p1 = i < parts1.length ? parts1[i] : 0;
        final p2 = i < parts2.length ? parts2[i] : 0;
        if (p1 > p2) return true;
        if (p1 < p2) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Periksa pembaruan otomatis di latar belakang saat startup
  static Future<void> checkUpdateSilently(BuildContext context) async {
    final info = await checkForUpdate();
    if (info != null && info.hasUpdate && context.mounted) {
      showUpdateDialog(context, info);
    }
  }

  /// Pengecekan manual saat pengguna menekan tombol "Periksa Pembaruan"
  static Future<void> manualCheck(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Memeriksa rilis terbaru di GitHub...'),
              ],
            ),
          ),
        ),
      ),
    );

    final info = await checkForUpdate();
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // Tutup loading

    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal terhubung ke server pembaruan GitHub.')),
      );
      return;
    }

    if (info.hasUpdate) {
      showUpdateDialog(context, info);
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Color(0xFF165B33)),
              SizedBox(width: 8),
              Expanded(child: Text('Aplikasi Sudah Versi Terbaru')),
            ],
          ),
          content: Text(
            'Qur\'an Tarteel Hifz sudah menggunakan versi paling mutakhir (v$currentVersion). Tidak ada pembaruan yang diperlukan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    }
  }

  /// Membuka tautan unduhan di browser eksternal sesuai sistem operasi
  static Future<void> openDownloadUrl(String url) async {
    try {
      if (Platform.isAndroid) {
        await _installerChannel.invokeMethod('openUrl', {'url': url});
      } else if (Platform.isWindows) {
        await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Gagal membuka browser download: $e');
    }
  }

  /// Memicu instalasi APK langsung di Android melalui MethodChannel
  static Future<bool> installApkOnAndroid(String filePath) async {
    try {
      final res = await _installerChannel.invokeMethod<bool>('installApk', {
        'filePath': filePath,
      });
      return res ?? true;
    } catch (e) {
      debugPrint('[AppUpdateService] Gagal memicu installer APK: $e');
      return false;
    }
  }

  /// Menampilkan dialog pembaruan yang mendukung unduhan langsung di dalam aplikasi
  static void showUpdateDialog(BuildContext context, AppUpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _InAppUpdateDialog(info: info),
    );
  }
}

class _InAppUpdateDialog extends StatefulWidget {
  final AppUpdateInfo info;

  const _InAppUpdateDialog({required this.info});

  @override
  State<_InAppUpdateDialog> createState() => _InAppUpdateDialogState();
}

class _InAppUpdateDialogState extends State<_InAppUpdateDialog> {
  bool _isDownloading = false;
  bool _downloadFinished = false;
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _statusMessage;
  String? _errorMessage;
  String? _downloadedFilePath;
  http.Client? _httpClient;

  @override
  void dispose() {
    _httpClient?.close();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> _startInAppDownload() async {
    final targetUrl = widget.info.targetPlatformDownloadUrl;
    if (targetUrl == null || !targetUrl.startsWith('http')) {
      setState(() {
        _errorMessage = 'Tautan unduhan tidak ditemukan untuk perangkat ini.';
      });
      return;
    }

    // Jika URL mengarah ke halaman web rilis (bukan file langsung), buka di browser
    final lowerUrl = targetUrl.toLowerCase();
    if (!lowerUrl.endsWith('.apk') && !lowerUrl.endsWith('.zip') && !lowerUrl.endsWith('.dmg')) {
      await AppUpdateService.openDownloadUrl(targetUrl);
      if (mounted) Navigator.pop(context);
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadFinished = false;
      _errorMessage = null;
      _progress = 0.0;
      _receivedBytes = 0;
      _totalBytes = 0;
      _statusMessage = 'Menghubungkan ke server GitHub Releases...';
    });

    try {
      _httpClient = http.Client();
      final request = http.Request('GET', Uri.parse(targetUrl));
      request.headers['User-Agent'] = 'QuranTarteelHifz-App';
      final response = await _httpClient!.send(request);

      if (response.statusCode != 200) {
        throw Exception('Server mengembalikan kode HTTP ${response.statusCode}');
      }

      _totalBytes = response.contentLength ?? 0;

      // Tentukan lokasi penyimpanan file sementara
      final tempDir = await getTemporaryDirectory();
      String fileName = 'QuranTarteelHifz-v${widget.info.latestVersion}';
      if (Platform.isAndroid) {
        fileName = 'QuranTarteelHifz-update.apk';
      } else if (Platform.isWindows) {
        fileName = '$fileName-Windows-x64.zip';
      } else if (Platform.isMacOS) {
        fileName = '$fileName-macOS-Universal.dmg';
      }

      final saveFile = File('${tempDir.path}${Platform.pathSeparator}$fileName');
      if (await saveFile.exists()) {
        await saveFile.delete();
      }

      final sink = saveFile.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        _receivedBytes += chunk.length;
        if (mounted) {
          setState(() {
            if (_totalBytes > 0) {
              _progress = _receivedBytes / _totalBytes;
              _statusMessage =
                  'Mengunduh pembaruan... ${(_progress * 100).toStringAsFixed(0)}% (${_formatBytes(_receivedBytes)} / ${_formatBytes(_totalBytes)})';
            } else {
              _statusMessage = 'Mengunduh pembaruan... ${_formatBytes(_receivedBytes)}';
            }
          });
        }
      }

      await sink.flush();
      await sink.close();

      _downloadedFilePath = saveFile.path;

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadFinished = true;
          _progress = 1.0;
          _statusMessage = 'Unduhan selesai! Memulai proses pemasangan otomatis...';
        });
      }

      await _applyDownloadedUpdate(saveFile.path);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Gagal mengunduh di dalam aplikasi: $e\nSilakan gunakan tombol "Unduh via Browser".';
        });
      }
    }
  }

  Future<void> _applyDownloadedUpdate(String filePath) async {
    try {
      if (Platform.isAndroid) {
        final ok = await AppUpdateService.installApkOnAndroid(filePath);
        if (!ok && mounted) {
          setState(() {
            _errorMessage = 'Gagal membuka pemasang APK otomatis. Gunakan "Unduh via Browser".';
          });
        }
      } else if (Platform.isWindows) {
        await _applyWindowsUpdate(filePath);
      } else if (Platform.isMacOS) {
        await Process.run('open', [filePath]);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Gagal menerapkan pembaruan otomatis: $e';
        });
      }
    }
  }

  Future<void> _applyWindowsUpdate(String zipPath) async {
    final tempDir = Directory.systemTemp;
    final extractDir = Directory('${tempDir.path}\\QuranTarteelHifz_Update_Extracted');
    if (await extractDir.exists()) {
      await extractDir.delete(recursive: true);
    }
    await extractDir.create(recursive: true);

    setState(() {
      _statusMessage = 'Mengekstrak paket pembaruan Windows EXE...';
    });

    final expandResult = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      'Expand-Archive -Path "$zipPath" -DestinationPath "${extractDir.path}" -Force',
    ]);

    if (expandResult.exitCode != 0) {
      throw Exception('Gagal mengekstrak ZIP: ${expandResult.stderr}');
    }

    final currentExePath = Platform.resolvedExecutable;
    final currentAppDir = File(currentExePath).parent.path;
    final batFile = File('${tempDir.path}\\apply_quran_update.bat');

    final batScript = '''
@echo off
timeout /t 2 /nobreak >nul
xcopy /s /e /y "${extractDir.path}\\*" "$currentAppDir\\" >nul
start "" "$currentExePath"
del "%~f0"
''';

    await batFile.writeAsString(batScript);
    await Process.start('cmd', ['/c', batFile.path], mode: ProcessStartMode.detached);
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF165B33).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.system_update_rounded, color: Color(0xFF165B33)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pembaruan Tersedia', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  'Versi v${info.latestVersion} (Saat ini: v${info.currentVersion})',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              info.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  info.releaseNotes,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_isDownloading || _downloadFinished) ...[
              LinearProgressIndicator(
                value: _totalBytes > 0 ? _progress : null,
                minHeight: 8,
                borderRadius: BorderRadius.circular(6),
                backgroundColor: const Color(0xFFE6DFD3),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF165B33)),
              ),
              const SizedBox(height: 8),
              Text(
                _statusMessage ?? 'Mengunduh...',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF165B33)),
              ),
            ] else ...[
              Text(
                Platform.isAndroid
                    ? 'Menekan "Unduh & Pasang" akan mengunduh APK langsung di dalam aplikasi dan membuka pemasang otomatis Android.'
                    : Platform.isWindows
                        ? 'Menekan "Unduh & Pasang" akan mengunduh paket terbaru, mengekstraknya otomatis, dan memulai ulang aplikasi.'
                        : 'Menekan "Unduh & Pasang" akan mengunduh installer DMG langsung dan membukanya.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDECEC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE8B4B4)),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFA82424)),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isDownloading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Nanti Saja'),
          ),
        TextButton.icon(
          onPressed: () {
            final targetUrl = info.targetPlatformDownloadUrl ?? info.releaseUrl;
            AppUpdateService.openDownloadUrl(targetUrl);
          },
          icon: const Icon(Icons.open_in_browser_rounded, size: 16),
          label: const Text('Unduh via Browser'),
        ),
        if (_downloadFinished && _downloadedFilePath != null)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF165B33),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () => _applyDownloadedUpdate(_downloadedFilePath!),
            icon: const Icon(Icons.install_mobile_rounded, size: 18),
            label: const Text('Pasang Sekarang'),
          )
        else
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF165B33),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: _isDownloading ? null : _startInAppDownload,
            icon: _isDownloading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download_rounded, size: 18),
            label: Text(_isDownloading ? 'Mengunduh...' : 'Unduh & Pasang'),
          ),
      ],
    );
  }
}
