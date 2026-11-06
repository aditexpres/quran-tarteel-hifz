// lib/app_update_service.dart
// ==============================================================================
// Layanan Pembaruan Otomatis Lintas Platform (Android APK, Windows EXE, macOS DMG)
// Terintegrasi langsung dengan GitHub Releases API repositori resmi.
// ==============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String title;
  final String releaseNotes;
  final String releaseUrl;
  final String? apkDownloadUrl;
  final String? windowsDownloadUrl;
  final String? macosDownloadUrl;
  final bool hasUpdate;

  AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.title,
    required this.releaseNotes,
    required this.releaseUrl,
    this.apkDownloadUrl,
    this.windowsDownloadUrl,
    this.macosDownloadUrl,
    required this.hasUpdate,
  });

  String? get targetPlatformDownloadUrl {
    if (Platform.isAndroid) return apkDownloadUrl ?? releaseUrl;
    if (Platform.isWindows) return windowsDownloadUrl ?? releaseUrl;
    if (Platform.isMacOS) return macosDownloadUrl ?? releaseUrl;
    return releaseUrl;
  }
}

class AppUpdateService {
  static const String currentVersion = '1.1.0';
  static const String _githubRepoOwner = 'aditexpres';
  static const String _githubRepoName = 'quran-tarteel-hifz';

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
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return null;
      }

      final Map<String, dynamic> data = json.decode(response.body);
      final rawTag = data['tag_name'] as String? ?? '1.0.0';
      final cleanLatestVersion = rawTag.replaceAll(RegExp(r'[^0-9.]'), '');
      final releaseNotes = data['body'] as String? ?? 'Peningkatan performa dan pembaruan sistem.';
      final title = data['name'] as String? ?? 'Rilis Terbaru $rawTag';
      final htmlUrl = data['html_url'] as String? ?? 'https://github.com/$_githubRepoOwner/$_githubRepoName/releases';

      // Ekstrak URL Aset Installer
      String? apkUrl;
      String? winUrl;
      String? macUrl;

      final assets = data['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        final downloadUrl = asset['browser_download_url'] as String?;
        if (downloadUrl == null) continue;

        if (name.endsWith('.apk')) {
          apkUrl ??= downloadUrl;
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
        apkDownloadUrl: apkUrl,
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
              Text('Aplikasi Sudah Versi Terbaru'),
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

  /// Membuka tautan unduhan sesuai sistem operasi
  static Future<void> openDownloadUrl(String url) async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else if (Platform.isAndroid) {
        // Pada Android, gunakan am start intent browser
        await Process.run('am', ['start', '-a', 'android.intent.action.VIEW', '-d', url]);
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Gagal membuka browser download: $e');
    }
  }

  /// Menampilkan dialog pembaruan yang rapi dan elegan
  static void showUpdateDialog(BuildContext context, AppUpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
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
                constraints: const BoxConstraints(maxHeight: 180),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surface,
                  border: Border.all(color: Theme.of(ctx).dividerColor),
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
              Text(
                Platform.isAndroid
                    ? 'Menekan "Perbarui Sekarang" akan mengunduh file APK rilis terbaru secara langsung.'
                    : Platform.isWindows
                        ? 'Menekan "Perbarui Sekarang" akan mengunduh paket Windows EXE portabel terbaru.'
                        : 'Menekan "Perbarui Sekarang" akan mengunduh bundel installer DMG macOS terbaru.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Nanti Saja'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF165B33),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              final targetUrl = info.targetPlatformDownloadUrl ?? info.releaseUrl;
              openDownloadUrl(targetUrl);
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Perbarui Sekarang'),
          ),
        ],
      ),
    );
  }
}
