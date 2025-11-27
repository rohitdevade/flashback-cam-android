class VideoRecording {
  final String id;
  final String filePath;
  final String? thumbnailPath;
  final int durationSeconds;
  final String resolution;
  final int fps;
  final String codec;
  final int preRollSeconds;
  final int fileSizeBytes;
  final DateTime createdAt;
  final DateTime updatedAt;

  VideoRecording({
    required this.id,
    required this.filePath,
    this.thumbnailPath,
    required this.durationSeconds,
    required this.resolution,
    required this.fps,
    required this.codec,
    required this.preRollSeconds,
    required this.fileSizeBytes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VideoRecording.fromJson(Map<String, dynamic> json) => VideoRecording(
    id: json['id'] as String,
    filePath: json['filePath'] as String,
    thumbnailPath: json['thumbnailPath'] as String?,
    durationSeconds: json['durationSeconds'] as int,
    resolution: json['resolution'] as String,
    fps: json['fps'] as int,
    codec: json['codec'] as String,
    preRollSeconds: json['preRollSeconds'] as int,
    fileSizeBytes: json['fileSizeBytes'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'filePath': filePath,
    'thumbnailPath': thumbnailPath,
    'durationSeconds': durationSeconds,
    'resolution': resolution,
    'fps': fps,
    'codec': codec,
    'preRollSeconds': preRollSeconds,
    'fileSizeBytes': fileSizeBytes,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  VideoRecording copyWith({
    String? id,
    String? filePath,
    String? thumbnailPath,
    int? durationSeconds,
    String? resolution,
    int? fps,
    String? codec,
    int? preRollSeconds,
    int? fileSizeBytes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => VideoRecording(
    id: id ?? this.id,
    filePath: filePath ?? this.filePath,
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    resolution: resolution ?? this.resolution,
    fps: fps ?? this.fps,
    codec: codec ?? this.codec,
    preRollSeconds: preRollSeconds ?? this.preRollSeconds,
    fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  String get formattedDuration {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedSize {
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    } else if (fileSizeBytes < 1024 * 1024 * 1024) {
      return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(fileSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }
}
