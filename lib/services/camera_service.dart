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
