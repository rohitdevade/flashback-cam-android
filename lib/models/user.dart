class User {
  final String id;
  final bool isPro;
  final String? proTier;
  final DateTime? proExpiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? trialStartedAt;
  final bool trialUsed;

  User({
    required this.id,
    this.isPro = false,
    this.proTier,
    this.proExpiresAt,
    required this.createdAt,
    required this.updatedAt,
    this.trialStartedAt,
    this.trialUsed = false,
  });

  /// Check if the user is currently in an active free trial
  bool get isTrialActive {
    if (trialStartedAt == null) return false;
    final trialEndDate = trialStartedAt!.add(const Duration(days: 7));
    return DateTime.now().isBefore(trialEndDate);
  }

  /// Get days remaining in trial
  int get trialDaysRemaining {
    if (trialStartedAt == null) return 0;
    final trialEndDate = trialStartedAt!.add(const Duration(days: 7));
    final remaining = trialEndDate.difference(DateTime.now()).inDays;
    return remaining > 0 ? remaining : 0;
  }

  /// Check if user has Pro features (either paid or trial)
  bool get hasProAccess => isPro || isTrialActive;

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        isPro: json['isPro'] as bool? ?? false,
        proTier: json['proTier'] as String?,
        proExpiresAt: json['proExpiresAt'] != null
            ? DateTime.parse(json['proExpiresAt'] as String)
            : null,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        trialStartedAt: json['trialStartedAt'] != null
            ? DateTime.parse(json['trialStartedAt'] as String)
            : null,
        trialUsed: json['trialUsed'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'isPro': isPro,
        'proTier': proTier,
        'proExpiresAt': proExpiresAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'trialStartedAt': trialStartedAt?.toIso8601String(),
        'trialUsed': trialUsed,
      };

  User copyWith({
    String? id,
    bool? isPro,
    String? proTier,
    DateTime? proExpiresAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? trialStartedAt,
    bool? trialUsed,
  }) =>
      User(
        id: id ?? this.id,
        isPro: isPro ?? this.isPro,
        proTier: proTier ?? this.proTier,
        proExpiresAt: proExpiresAt ?? this.proExpiresAt,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        trialStartedAt: trialStartedAt ?? this.trialStartedAt,
        trialUsed: trialUsed ?? this.trialUsed,
      );
}
