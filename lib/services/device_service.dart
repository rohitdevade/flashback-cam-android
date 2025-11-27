import 'package:flutter/foundation.dart';
import 'package:flashback_cam/models/device_capabilities.dart';
import 'package:flashback_cam/services/camera_service.dart';

class DeviceService {
  final CameraService _cameraService;
  DeviceCapabilities? _capabilities;

  DeviceService(this._cameraService);

  Future<DeviceCapabilities> detectCapabilities() async {
    if (_capabilities != null) return _capabilities!;

    final capabilitiesData = await _cameraService.getDeviceCapabilities();
    _capabilities = DeviceCapabilities.fromJson(capabilitiesData);
    debugPrint('Device capabilities detected: ${_capabilities?.toJson()}');
    return _capabilities!;
  }

  DeviceCapabilities? get capabilities => _capabilities;

  List<String> getAvailableResolutions(bool isPro) {
    final caps = _capabilities;
    if (caps == null) return ['1080p'];

    final resolutions = [...caps.supportedResolutions];
    if (!isPro) {
      resolutions.removeWhere((r) => r == '4K');
    }
    return resolutions;
  }

  List<int> getAvailableFps(bool isPro) {
    final caps = _capabilities;
    if (caps == null) return [30];

    final fpsList = [...caps.supportedFps];
    if (!isPro) {
      fpsList.removeWhere((f) => f == 60);
    }
    return fpsList;
  }

  List<String> getAvailableCodecs(bool isPro) {
    final caps = _capabilities;
    if (caps == null) return ['Auto', 'H.264'];

    final codecs = ['Auto', ...caps.supportedCodecs];
    if (!isPro) {
      codecs.removeWhere((c) => c == 'HEVC');
    }
    return codecs;
  }

  int getMaxPreRollSeconds(bool isPro) => isPro ? 10 : 5;

  List<int> getPreRollOptions(bool isPro) => isPro ? [3, 5, 10] : [3, 5];

  bool shouldUseRamBuffer(String resolution, int fps) {
    final caps = _capabilities;
    if (caps == null) return false;
    if (caps.ramTier == RamTier.low) return false;
    if (resolution == '4K' && fps == 60) return false;
    return caps.ramTier == RamTier.high;
  }
}
