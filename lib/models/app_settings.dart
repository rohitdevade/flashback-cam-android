class AppSettings {
  final int preRollSeconds;
  final String resolution;
  final int fps;
  // Only H.264 supported, remove codec field
  final String bitrate;
  final bool stabilization;
  final bool showGrid;
  final bool hasSeenCameraInstructions;
  final DateTime updatedAt;

  AppSettings({
    required this.preRollSeconds,
    required this.resolution,
    required this.fps,
    // codec removed
    required this.bitrate,
    required this.stabilization,
    required this.showGrid,
    required this.hasSeenCameraInstructions,
    required this.updatedAt,
  });

  factory AppSettings.defaults() => AppSettings(
        preRollSeconds: 5,
        resolution: '1080P',
        fps: 30,
        bitrate: 'Auto',
        stabilization: true,
        showGrid: false,
        hasSeenCameraInstructions: false,
        updatedAt: DateTime.now(),
      );

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        preRollSeconds: json['preRollSeconds'] as int? ?? 5,
        resolution: ((json['resolution'] as String?) ?? '1080P').toUpperCase(),
        fps: json['fps'] as int? ?? 30,
        bitrate: json['bitrate'] as String? ?? 'Auto',
        stabilization: json['stabilization'] as bool? ?? true,
        showGrid: json['showGrid'] as bool? ?? false,
        hasSeenCameraInstructions:
            json['hasSeenCameraInstructions'] as bool? ?? false,
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'preRollSeconds': preRollSeconds,
        'resolution': resolution,
        'fps': fps,
        'bitrate': bitrate,
        'stabilization': stabilization,
        'showGrid': showGrid,
        'hasSeenCameraInstructions': hasSeenCameraInstructions,
        'updatedAt': updatedAt.toIso8601String(),
      };

  AppSettings copyWith({
    int? preRollSeconds,
    String? resolution,
    int? fps,
    String? bitrate,
    bool? stabilization,
    bool? showGrid,
    bool? hasSeenCameraInstructions,
    DateTime? updatedAt,
  }) =>
      AppSettings(
        preRollSeconds: preRollSeconds ?? this.preRollSeconds,
        resolution: resolution ?? this.resolution,
        fps: fps ?? this.fps,
        bitrate: bitrate ?? this.bitrate,
        stabilization: stabilization ?? this.stabilization,
        showGrid: showGrid ?? this.showGrid,
        hasSeenCameraInstructions:
            hasSeenCameraInstructions ?? this.hasSeenCameraInstructions,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
