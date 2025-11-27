import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../models/video_recording.dart';

class VideoActionsService {
  static const _mediaChannel = MethodChannel('flashback_cam/media');

  static Future<void> shareVideo(
    BuildContext context,
    VideoRecording video, {
    String? shareText,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final sourceFile = File(video.filePath);
      if (!await sourceFile.exists()) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Video file is missing on disk.')),
        );
        return;
      }

      await Share.shareXFiles(
        [
          XFile(
            sourceFile.path,
            mimeType: 'video/mp4',
            name: sourceFile.uri.pathSegments.isNotEmpty
                ? sourceFile.uri.pathSegments.last
                : 'flashback_clip.mp4',
          ),
        ],
        text: shareText ?? 'Check out this flashback clip!',
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to share video: $error')),
      );
    }
  }

  static Future<void> saveToDevice(
    BuildContext context,
    VideoRecording video,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final sourceFile = File(video.filePath);
      if (!await sourceFile.exists()) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Video file is missing on disk.')),
        );
        return;
      }

      if (Platform.isAndroid) {
        var status = await Permission.videos.request();
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }

        if (!status.isGranted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Storage permission is required.')),
          );
          return;
        }

        final savedLocation = await _saveToAndroidGallery(sourceFile.path);
        if (savedLocation != null) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Saved to Videos ▸ Flashback Cam in gallery.'),
            ),
          );
          return;
        }
      } else if (Platform.isIOS) {
        final documentsDir = await getApplicationDocumentsDirectory();
        final destinationDir =
            Directory('${documentsDir.path}/Flashback Cam Exports');
        await _copyToDirectory(sourceFile, destinationDir, messenger);
        return;
      }

      // Fallback for Android failures or other platforms: copy to app storage.
      final fallbackDir = await _resolveFallbackDirectory();
      await _copyToDirectory(sourceFile, fallbackDir, messenger);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to save video: $error')),
      );
    }
  }

  static Future<Directory> _resolveFallbackDirectory() async {
    Directory? destinationDir;

    if (Platform.isAndroid) {
      final downloadDirs = await getExternalStorageDirectories(
        type: StorageDirectory.downloads,
      );

      if (downloadDirs != null && downloadDirs.isNotEmpty) {
        destinationDir = Directory('${downloadDirs.first.path}/Flashback Cam');
      } else {
        final fallbackDir = await getExternalStorageDirectory();
        if (fallbackDir != null) {
          destinationDir = Directory('${fallbackDir.path}/Flashback Cam');
        }
      }
    }

    destinationDir ??= Directory('${Directory.systemTemp.path}/FlashbackCam');
    await destinationDir.create(recursive: true);
    return destinationDir;
  }

  static Future<void> _copyToDirectory(
    File sourceFile,
    Directory destinationDir,
    ScaffoldMessengerState messenger,
  ) async {
    await destinationDir.create(recursive: true);
    final fileName = sourceFile.path.split(Platform.pathSeparator).last;
    final destinationFile = File('${destinationDir.path}/$fileName');
    await sourceFile.copy(destinationFile.path);

    messenger.showSnackBar(
      SnackBar(content: Text('Saved to ${destinationFile.path}')),
    );
  }

  static Future<String?> _saveToAndroidGallery(String sourcePath) async {
    try {
      final savedUri = await _mediaChannel.invokeMethod<String>(
        'saveVideoToGallery',
        {'sourcePath': sourcePath},
      );
      return savedUri;
    } on PlatformException catch (e) {
      debugPrint('Failed to save via platform channel: ${e.message}');
      return null;
    }
  }
}
