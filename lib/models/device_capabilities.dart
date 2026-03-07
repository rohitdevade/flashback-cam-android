enum RamTier { high, mid, low }

enum BufferMode { ram, disk }

class DeviceCapabilities {
  final int ramMB;
  final RamTier ramTier;
  final BufferMode preferredBufferMode;

  /// Returns true if device has 4GB RAM or less (low-memory mode)
  /// These devices need restricted resolution, FPS, and buffer options
  bool get isLowMemoryDevice => ramMB <= 4096;

  /// Returns true if device has 7GB RAM or more (high-memory mode)
  /// Note: "8GB" phones typically report ~7500MB due to reserved memory
  bool get isHighMemoryDevice => ramMB >= 7168;
  final List<String> supportedResolutions;
  final List<int> supportedFps;
  final List<String> supportedCodecs;
  final bool supports4K;
  final bool supports60fps;
  final bool supportsHEVC;

  DeviceCapabilities({
    required this.ramMB,
    required this.ramTier,
    required this.preferredBufferMode,
    required this.supportedResolutions,
    required this.supportedFps,
    required this.supportedCodecs,
    required this.supports4K,
    required this.supports60fps,
    required this.supportsHEVC,
  });

  factory DeviceCapabilities.fromJson(Map<String, dynamic> json) {
    final ramMB = json['ramMB'] as int;
    final ramTier = ramMB >= 6144
        ? RamTier.high
        : (ramMB >= 3072 ? RamTier.mid : RamTier.low);
    final preferredBufferMode = (() {
      final rawValue = json['preferredBufferMode'] as String?;
      if (rawValue == null) {
        return ramTier == RamTier.high ? BufferMode.ram : BufferMode.disk;
      }
      return BufferMode.values.firstWhere(
        (mode) => mode.name.toLowerCase() == rawValue.toLowerCase(),
        orElse: () =>
            ramTier == RamTier.high ? BufferMode.ram : BufferMode.disk,
      );
    })();

    return DeviceCapabilities(
      ramMB: ramMB,
      ramTier: ramTier,
      preferredBufferMode: preferredBufferMode,
      supportedResolutions:
          (json['supportedResolutions'] as List).cast<String>(),
      supportedFps: (json['supportedFps'] as List).cast<int>(),
      supportedCodecs: (json['supportedCodecs'] as List).cast<String>(),
      supports4K: (json['supportedResolutions'] as List).contains('4K'),
      supports60fps: (json['supportedFps'] as List).contains(60),
      supportsHEVC: (json['supportedCodecs'] as List).contains('HEVC'),
    );
  }

  Map<String, dynamic> toJson() => {
        'ramMB': ramMB,
        'ramTier': ramTier.name,
        'preferredBufferMode': preferredBufferMode.name,
        'supportedResolutions': supportedResolutions,
        'supportedFps': supportedFps,
        'supportedCodecs': supportedCodecs,
        'supports4K': supports4K,
        'supports60fps': supports60fps,
        'supportsHEVC': supportsHEVC,
      };

  String get ramTierDisplay {
    switch (ramTier) {
      case RamTier.high:
        return 'High (${(ramMB / 1024).toStringAsFixed(1)} GB)';
      case RamTier.mid:
        return 'Mid (${(ramMB / 1024).toStringAsFixed(1)} GB)';
      case RamTier.low:
        return 'Low (${(ramMB / 1024).toStringAsFixed(1)} GB)';
    }
  }

  String get bufferModeDisplay => preferredBufferMode == BufferMode.ram
      ? 'RAM Ring Buffer'
      : 'Disk Fragment Buffer';
}
