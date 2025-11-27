class DebugInfo {
  final String deviceTier; // HIGH, MID, LOW
  final String bufferStrategy; // RAM, DISK
  final int selectedBufferSeconds;
  final String videoResolution; // e.g., "1920x1080"
  final int videoFps;
  final String videoCodec; // e.g., "H.264"
  final String audioCodec; // e.g., "AAC"
  final String? lastRecordingStatus; // e.g., "Success", "Failed: small file"
  final String? lastRecordingPath;
  final List<String> debugLogs; // Recent log entries

  DebugInfo({
    required this.deviceTier,
    required this.bufferStrategy,
    required this.selectedBufferSeconds,
    required this.videoResolution,
    required this.videoFps,
    required this.videoCodec,
    required this.audioCodec,
    this.lastRecordingStatus,
    this.lastRecordingPath,
    this.debugLogs = const [],
  });

  factory DebugInfo.fromMap(Map<String, dynamic> map) {
    return DebugInfo(
      deviceTier: map['deviceTier'] as String? ?? 'UNKNOWN',
      bufferStrategy: map['bufferStrategy'] as String? ?? 'UNKNOWN',
      selectedBufferSeconds: map['selectedBufferSeconds'] as int? ?? 0,
      videoResolution: map['videoResolution'] as String? ?? 'N/A',
      videoFps: map['videoFps'] as int? ?? 0,
      videoCodec: map['videoCodec'] as String? ?? 'N/A',
      audioCodec: map['audioCodec'] as String? ?? 'N/A',
      lastRecordingStatus: map['lastRecordingStatus'] as String?,
      lastRecordingPath: map['lastRecordingPath'] as String?,
      debugLogs: (map['debugLogs'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  static DebugInfo empty() {
    return DebugInfo(
      deviceTier: 'UNKNOWN',
      bufferStrategy: 'UNKNOWN',
      selectedBufferSeconds: 0,
      videoResolution: 'N/A',
      videoFps: 0,
      videoCodec: 'N/A',
      audioCodec: 'N/A',
      debugLogs: [],
    );
  }
}
