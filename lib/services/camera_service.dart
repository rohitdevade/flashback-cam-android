import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

enum CameraEvent {
  recordingStarted,
  recordingStopped,
  finalizeProgress,
  finalizeCompleted,
  lowStorage,
  thermalWarning,
  recovered,
  bufferUpdate,
  subscriptionUpdated,
  recordingError,
  storageFull, // Storage full during recording
  insufficientStorage, // Not enough storage to start buffer/recording
}

/// Storage mode indicating current storage conditions.
/// Used to adjust UI and available features.
enum StorageMode {
  normal, // Sufficient storage - all features available
  low, // Low storage - 4K disabled, buffer duration limited
}

/// Result of storage check operations
class StorageCheckResult {
  final bool hasEnoughSpace;
  final int availableBytes;
  final int requiredBytes;
  final StorageMode storageMode;
  final String? message;

  StorageCheckResult({
    required this.hasEnoughSpace,
    required this.availableBytes,
    required this.requiredBytes,
    required this.storageMode,
    this.message,
  });

  factory StorageCheckResult.fromMap(Map<String, dynamic> map) {
    return StorageCheckResult(
      hasEnoughSpace: map['hasEnoughSpace'] as bool? ?? true,
      availableBytes: (map['availableBytes'] as num?)?.toInt() ?? 0,
      requiredBytes: (map['requiredBytes'] as num?)?.toInt() ?? 0,
      storageMode:
          map['storageMode'] == 'low' ? StorageMode.low : StorageMode.normal,
      message: map['message'] as String?,
    );
  }

  int get availableMB => availableBytes ~/ (1024 * 1024);
  int get requiredMB => requiredBytes ~/ (1024 * 1024);
}

class CameraService {
  static const _channel = MethodChannel('flashback_cam/camera');
  static const _eventChannel = EventChannel('flashback_cam/camera_events');

  Stream<Map<String, dynamic>>? _eventStream;
  int? _textureId;

  Future<int?> createPreview() async {
    try {
      final textureId = await _channel.invokeMethod<int>('createPreview');
      _textureId = textureId;
      debugPrint('Camera preview created with texture ID: $textureId');
      return textureId;
    } catch (e) {
      debugPrint('Failed to create camera preview: $e');
      return null;
    }
  }

  Future<void> disposePreview() async {
    if (_textureId != null) {
      try {
        await _channel
            .invokeMethod('disposePreview', {'textureId': _textureId});
        _textureId = null;
        debugPrint('Camera preview disposed');
      } catch (e) {
        debugPrint('Failed to dispose camera preview: $e');
      }
    }
  }

  int? get textureId => _textureId;

  Future<void> initialize({
    required String resolution,
    required int fps,
    required String codec,
    required int preRollSeconds,
    required bool stabilization,
  }) async {
    try {
      await _channel.invokeMethod('initialize', {
        'resolution': resolution,
        'fps': fps,
        'codec': codec,
        'preRollSeconds': preRollSeconds,
        'stabilization': stabilization,
      });
      debugPrint('Camera initialized: $resolution @ ${fps}fps');
    } catch (e) {
      debugPrint('Failed to initialize camera: $e');
      rethrow;
    }
  }

  Future<void> startBuffer() async {
    try {
      await _channel.invokeMethod('startBuffer');
      debugPrint('Camera buffer started');
    } catch (e) {
      debugPrint('Failed to start buffer: $e');
      rethrow;
    }
  }

  Future<void> startPreview() async {
    try {
      await _channel.invokeMethod('startPreview');
      debugPrint('Camera preview started');
    } catch (e) {
      debugPrint('Failed to start preview: $e');
    }
  }

  Future<void> stopBuffer() async {
    try {
      await _channel.invokeMethod('stopBuffer');
      debugPrint('Camera buffer stopped');
    } catch (e) {
      debugPrint('Failed to stop buffer: $e');
    }
  }

  Future<String> startRecording() async {
    try {
      final recordingId = await _channel.invokeMethod<String>('startRecording');
      debugPrint('Recording started: $recordingId');
      return recordingId ?? '';
    } catch (e) {
      debugPrint('Failed to start recording: $e');
      rethrow;
    }
  }

  Future<void> stopRecording() async {
    try {
      await _channel.invokeMethod('stopRecording');
      debugPrint('Recording stopped');
    } catch (e) {
      debugPrint('Failed to stop recording: $e');
      rethrow;
    }
  }

  Future<void> switchCamera() async {
    try {
      await _channel.invokeMethod('switchCamera');
      debugPrint('Camera switched');
    } catch (e) {
      debugPrint('Failed to switch camera: $e');
    }
  }

  Future<void> updateSubscription({required bool isProUser}) async {
    try {
      await _channel.invokeMethod('updateSubscription', {
        'isProUser': isProUser,
      });
      debugPrint('Subscription updated: pro=$isProUser');
    } catch (e) {
      debugPrint('Failed to update subscription: $e');
    }
  }

  Future<void> setFlashMode(String mode) async {
    try {
      await _channel.invokeMethod('setFlashMode', {'mode': mode});
      debugPrint('Flash mode set to: $mode');
    } catch (e) {
      debugPrint('Failed to set flash mode: $e');
    }
  }

  Future<double> setZoom(double zoom) async {
    try {
      final result =
          await _channel.invokeMethod<double>('setZoom', {'zoom': zoom});
      debugPrint('Zoom set to: $zoom, actual: $result');
      return result ?? zoom;
    } catch (e) {
      debugPrint('Failed to set zoom: $e');
      return zoom;
    }
  }

  Future<double> getMaxZoom() async {
    try {
      final result = await _channel.invokeMethod<double>('getMaxZoom');
      debugPrint('🔍 Max zoom from camera: $result');
      return result ?? 1.0;
    } catch (e) {
      debugPrint('❌ Failed to get max zoom: $e');
      return 1.0;
    }
  }

  Future<Map<String, dynamic>> getDeviceCapabilities() async {
    try {
      final capabilities =
          await _channel.invokeMethod<Map>('getDeviceCapabilities');
      return Map<String, dynamic>.from(capabilities ?? {});
    } catch (e) {
      debugPrint('Failed to get device capabilities: $e');
      return {
        'ramMB': 4096,
        'supportedResolutions': ['1080p'],
        'supportedFps': [30],
        'supportedCodecs': ['H.264'],
      };
    }
  }

  /// Check detailed video recording capabilities for specific resolution/fps combos
  Future<Map<String, bool>> checkDetailedCapabilities() async {
    try {
      debugPrint('🔍 Checking detailed device capabilities...');
      final result =
          await _channel.invokeMethod<Map>('checkDetailedCapabilities');
      final capabilities = Map<String, bool>.from(result ?? {});

      debugPrint('✅ Device capabilities:');
      debugPrint('   • 4K: ${capabilities['supports4K']}');
      debugPrint('   • 1080p 60fps: ${capabilities['supports1080p60fps']}');
      debugPrint('   • 4K 60fps: ${capabilities['supports4K60fps']}');
      debugPrint('   • 1080p 30fps: ${capabilities['supports1080p30fps']}');

      return capabilities;
    } catch (e) {
      debugPrint('❌ Failed to check detailed capabilities: $e');
      // Fallback to safe defaults
      return {
        'supports4K': false,
        'supports1080p60fps': false,
        'supports4K60fps': false,
        'supports1080p30fps': true,
      };
    }
  }

  Future<void> updateSettings({
    String? resolution,
    int? fps,
    String? codec,
    int? preRollSeconds,
    bool? stabilization,
  }) async {
    try {
      final params = <String, dynamic>{};
      if (resolution != null) params['resolution'] = resolution;
      if (fps != null) params['fps'] = fps;
      if (codec != null) params['codec'] = codec;
      if (preRollSeconds != null) params['preRollSeconds'] = preRollSeconds;
      if (stabilization != null) params['stabilization'] = stabilization;

      await _channel.invokeMethod('updateSettings', params);
      debugPrint('Camera settings updated');
    } catch (e) {
      debugPrint('Failed to update settings: $e');
    }
  }

  /// Fetch debug information from native plugin (developer only)
  Future<Map<String, dynamic>> getDebugInfo() async {
    try {
      final result = await _channel.invokeMethod<Map>('getDebugInfo');
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      debugPrint('Failed to get debug info: $e');
      return {};
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // STORAGE MANAGEMENT - Low storage handling to prevent crashes and corruption
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Get current storage status including available space and storage mode.
  /// Returns a map with:
  /// - availableBytes: Available storage in bytes
  /// - totalBytes: Total storage in bytes
  /// - availableMB: Available storage in MB
  /// - totalMB: Total storage in MB
  /// - storageMode: 'normal' or 'low'
  /// - isLowStorage: boolean indicating if storage is low
  /// - lowStorageThresholdMB: The threshold below which storage is considered low
  Future<Map<String, dynamic>> getStorageStatus() async {
    try {
      final result = await _channel.invokeMethod<Map>('getStorageStatus');
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      debugPrint('Failed to get storage status: $e');
      return {
        'availableBytes': 0,
        'totalBytes': 0,
        'storageMode': 'normal',
        'isLowStorage': false,
      };
    }
  }

  /// Check if there's enough storage space to start buffering.
  /// Returns a map with:
  /// - hasEnoughSpace: boolean
  /// - availableBytes/availableMB: Available storage
  /// - requiredBytes/requiredMB: Required storage
  /// - storageMode: 'normal' or 'low'
  /// - message: Error message if space is insufficient
  Future<Map<String, dynamic>> checkBufferStorageSpace({
    String? resolution,
    int? fps,
  }) async {
    try {
      final result =
          await _channel.invokeMethod<Map>('checkBufferStorageSpace', {
        if (resolution != null) 'resolution': resolution,
        if (fps != null) 'fps': fps,
      });
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      debugPrint('Failed to check buffer storage space: $e');
      return {
        'hasEnoughSpace': true, // Default to allowing buffer
        'storageMode': 'normal',
      };
    }
  }

  /// Check if there's enough storage space to start recording.
  /// Returns a map with:
  /// - hasEnoughSpace: boolean
  /// - availableBytes/availableMB: Available storage
  /// - requiredBytes/requiredMB: Required storage
  /// - storageMode: 'normal' or 'low'
  /// - message: Error message if space is insufficient
  Future<Map<String, dynamic>> checkRecordingStorageSpace({
    String? resolution,
    int? fps,
    int? bufferDurationSeconds,
    int? expectedRecordingSeconds,
  }) async {
    try {
      final result =
          await _channel.invokeMethod<Map>('checkRecordingStorageSpace', {
        if (resolution != null) 'resolution': resolution,
        if (fps != null) 'fps': fps,
        if (bufferDurationSeconds != null)
          'bufferDurationSeconds': bufferDurationSeconds,
        if (expectedRecordingSeconds != null)
          'expectedRecordingSeconds': expectedRecordingSeconds,
      });
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      debugPrint('Failed to check recording storage space: $e');
      return {
        'hasEnoughSpace': true, // Default to allowing recording
        'storageMode': 'normal',
      };
    }
  }

  /// Get adjusted settings for low storage mode.
  /// If storage is low, 4K is disabled and buffer duration is limited.
  /// Returns a map with:
  /// - resolution: Adjusted resolution (4K -> 1080P if low storage)
  /// - fps: Adjusted fps (60 -> 30 if low storage)
  /// - maxBufferSeconds: Limited buffer seconds if low storage
  /// - storageMode: 'normal' or 'low'
  /// - adjusted: boolean indicating if settings were adjusted
  Future<Map<String, dynamic>> getAdjustedSettingsForStorage({
    required String resolution,
    required int fps,
    required int bufferSeconds,
  }) async {
    try {
      final result =
          await _channel.invokeMethod<Map>('getAdjustedSettingsForStorage', {
        'resolution': resolution,
        'fps': fps,
        'bufferSeconds': bufferSeconds,
      });
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      debugPrint('Failed to get adjusted settings: $e');
      return {
        'resolution': resolution,
        'fps': fps,
        'maxBufferSeconds': bufferSeconds,
        'storageMode': 'normal',
        'adjusted': false,
      };
    }
  }

  /// Manually cleanup buffer files.
  Future<void> cleanupBufferFiles() async {
    try {
      await _channel.invokeMethod('cleanupBufferFiles');
      debugPrint('Buffer files cleaned up');
    } catch (e) {
      debugPrint('Failed to cleanup buffer files: $e');
    }
  }

  Stream<Map<String, dynamic>> get eventStream {
    _eventStream ??= _eventChannel.receiveBroadcastStream().map((event) {
      if (event is Map<String, dynamic>) {
        return event;
      } else if (event is Map) {
        // Deep convert any Map to Map<String, dynamic>
        return _convertMap(event);
      } else {
        debugPrint('Unexpected event type: ${event.runtimeType}');
        return <String, dynamic>{'type': 'unknown', 'data': event};
      }
    });
    return _eventStream!;
  }

  // Helper method to recursively convert Maps
  Map<String, dynamic> _convertMap(Map<dynamic, dynamic> map) {
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      if (key is String) {
        if (value is Map) {
          result[key] = _convertMap(value);
        } else if (value is List) {
          result[key] = value.map((item) {
            if (item is Map) {
              return _convertMap(item);
            }
            return item;
          }).toList();
        } else {
          result[key] = value;
        }
      }
    });
    return result;
  }

  Future<void> dispose() async {
    try {
      await stopBuffer();
      await disposePreview();
      await _channel.invokeMethod('dispose');
      debugPrint('Camera service disposed');
    } catch (e) {
      debugPrint('Failed to dispose camera: $e');
    }
  }
}
