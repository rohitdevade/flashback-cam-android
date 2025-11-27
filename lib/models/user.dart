class User {
  final String id;
  final bool isPro;
  final String? proTier;
  final DateTime? proExpiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  User({
    required this.id,
    this.isPro = false,
    this.proTier,
    this.proExpiresAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    isPro: json['isPro'] as bool? ?? false,
    proTier: json['proTier'] as String?,
    proExpiresAt: json['proExpiresAt'] != null ? DateTime.parse(json['proExpiresAt'] as String) : null,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'isPro': isPro,
    'proTier': proTier,
    'proExpiresAt': proExpiresAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  User copyWith({
    String? id,
    bool? isPro,
    String? proTier,
    DateTime? proExpiresAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => User(
    id: id ?? this.id,
    isPro: isPro ?? this.isPro,
    proTier: proTier ?? this.proTier,
    proExpiresAt: proExpiresAt ?? this.proExpiresAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
