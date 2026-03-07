const Object _userFieldUnset = Object();

enum SubscriptionStatus {
  free,
  trialActive,
  active,
  trialCancelled,
  expired,
  gracePeriod,
}

extension SubscriptionStatusX on SubscriptionStatus {
  String get storageValue => switch (this) {
        SubscriptionStatus.free => 'free',
        SubscriptionStatus.trialActive => 'trial_active',
        SubscriptionStatus.active => 'active',
        SubscriptionStatus.trialCancelled => 'trial_cancelled',
        SubscriptionStatus.expired => 'expired',
        SubscriptionStatus.gracePeriod => 'grace_period',
      };

  bool get hasProAccess => switch (this) {
        SubscriptionStatus.trialActive ||
        SubscriptionStatus.active ||
        SubscriptionStatus.trialCancelled ||
        SubscriptionStatus.gracePeriod =>
          true,
        SubscriptionStatus.free || SubscriptionStatus.expired => false,
      };

  bool get isTrialState => switch (this) {
        SubscriptionStatus.trialActive ||
        SubscriptionStatus.trialCancelled =>
          true,
        SubscriptionStatus.free ||
        SubscriptionStatus.active ||
        SubscriptionStatus.expired ||
        SubscriptionStatus.gracePeriod =>
          false,
      };

  static SubscriptionStatus fromStorageValue(
    String? value, {
    required bool isPro,
    DateTime? proExpiresAt,
    DateTime? trialStartedAt,
    required bool trialUsed,
    required int trialDurationDays,
  }) {
    switch (value) {
      case 'free':
        return SubscriptionStatus.free;
      case 'trial_active':
        return SubscriptionStatus.trialActive;
      case 'active':
        return SubscriptionStatus.active;
      case 'trial_cancelled':
        return SubscriptionStatus.trialCancelled;
      case 'expired':
        return SubscriptionStatus.expired;
      case 'grace_period':
      case 'billing_retry':
        return SubscriptionStatus.gracePeriod;
      default:
        break;
    }

    if (isPro) {
      if (proExpiresAt != null && DateTime.now().isAfter(proExpiresAt)) {
        return SubscriptionStatus.expired;
      }
      return SubscriptionStatus.active;
    }

    if (trialStartedAt != null) {
      final trialEndDate =
          trialStartedAt.add(Duration(days: trialDurationDays));
      if (DateTime.now().isBefore(trialEndDate)) {
        return SubscriptionStatus.trialActive;
      }
      return SubscriptionStatus.expired;
    }

    return trialUsed ? SubscriptionStatus.expired : SubscriptionStatus.free;
  }
}

class User {
  final String id;
  final bool isPro;
  final String? proTier;
  final DateTime? proExpiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? trialStartedAt;
  final bool trialUsed;
  final String? subscriptionStatusValue;
  final bool subscriptionWillRenew;
  final DateTime? gracePeriodExpiresAt;
  final DateTime? lastValidatedAt;
  final int trialDurationDays;

  User({
    required this.id,
    this.isPro = false,
    this.proTier,
    this.proExpiresAt,
    required this.createdAt,
    required this.updatedAt,
    this.trialStartedAt,
    this.trialUsed = false,
    this.subscriptionStatusValue,
    this.subscriptionWillRenew = false,
    this.gracePeriodExpiresAt,
    this.lastValidatedAt,
    this.trialDurationDays = 3,
  });

  SubscriptionStatus get subscriptionStatus =>
      SubscriptionStatusX.fromStorageValue(
        subscriptionStatusValue,
        isPro: isPro,
        proExpiresAt: proExpiresAt,
        trialStartedAt: trialStartedAt,
        trialUsed: trialUsed,
        trialDurationDays: trialDurationDays,
      );

  DateTime? get trialEndsAt {
    if (trialStartedAt == null) return null;
    return trialStartedAt!.add(Duration(days: trialDurationDays));
  }

  /// Check if the user is currently in an active free trial
  bool get isTrialActive {
    if (!subscriptionStatus.isTrialState) return false;
    final trialEndDate = trialEndsAt;
    if (trialEndDate == null) return false;
    return DateTime.now().isBefore(trialEndDate);
  }

  bool get isCancelledButTrialActive =>
      subscriptionStatus == SubscriptionStatus.trialCancelled && isTrialActive;

  bool get isInGracePeriod {
    if (subscriptionStatus != SubscriptionStatus.gracePeriod) return false;
    if (gracePeriodExpiresAt == null) return true;
    return DateTime.now().isBefore(gracePeriodExpiresAt!);
  }

  bool get isExpired => subscriptionStatus == SubscriptionStatus.expired;

  /// Get days remaining in trial
  int get trialDaysRemaining {
    final trialEndDate = trialEndsAt;
    if (trialEndDate == null) return 0;
    final remaining = trialEndDate.difference(DateTime.now());
    if (remaining.inSeconds <= 0) return 0;
    return (remaining.inHours / 24).ceil();
  }

  /// Check if user has Pro features (either paid or trial)
  bool get hasProAccess => subscriptionStatus.hasProAccess;

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
        subscriptionStatusValue: json['subscriptionStatus'] as String?,
        subscriptionWillRenew: json['subscriptionWillRenew'] as bool? ?? false,
        gracePeriodExpiresAt: json['gracePeriodExpiresAt'] != null
            ? DateTime.parse(json['gracePeriodExpiresAt'] as String)
            : null,
        lastValidatedAt: json['lastValidatedAt'] != null
            ? DateTime.parse(json['lastValidatedAt'] as String)
            : null,
        trialDurationDays: json['trialDurationDays'] as int? ?? 3,
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
        'subscriptionStatus': subscriptionStatusValue,
        'subscriptionWillRenew': subscriptionWillRenew,
        'gracePeriodExpiresAt': gracePeriodExpiresAt?.toIso8601String(),
        'lastValidatedAt': lastValidatedAt?.toIso8601String(),
        'trialDurationDays': trialDurationDays,
      };

  User copyWith({
    String? id,
    bool? isPro,
    Object? proTier = _userFieldUnset,
    Object? proExpiresAt = _userFieldUnset,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? trialStartedAt = _userFieldUnset,
    bool? trialUsed,
    Object? subscriptionStatus = _userFieldUnset,
    bool? subscriptionWillRenew,
    Object? gracePeriodExpiresAt = _userFieldUnset,
    Object? lastValidatedAt = _userFieldUnset,
    int? trialDurationDays,
  }) =>
      User(
        id: id ?? this.id,
        isPro: isPro ?? this.isPro,
        proTier: identical(proTier, _userFieldUnset)
            ? this.proTier
            : proTier as String?,
        proExpiresAt: identical(proExpiresAt, _userFieldUnset)
            ? this.proExpiresAt
            : proExpiresAt as DateTime?,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        trialStartedAt: identical(trialStartedAt, _userFieldUnset)
            ? this.trialStartedAt
            : trialStartedAt as DateTime?,
        trialUsed: trialUsed ?? this.trialUsed,
        subscriptionStatusValue: identical(subscriptionStatus, _userFieldUnset)
            ? subscriptionStatusValue
            : subscriptionStatus as String?,
        subscriptionWillRenew:
            subscriptionWillRenew ?? this.subscriptionWillRenew,
        gracePeriodExpiresAt: identical(gracePeriodExpiresAt, _userFieldUnset)
            ? this.gracePeriodExpiresAt
            : gracePeriodExpiresAt as DateTime?,
        lastValidatedAt: identical(lastValidatedAt, _userFieldUnset)
            ? this.lastValidatedAt
            : lastValidatedAt as DateTime?,
        trialDurationDays: trialDurationDays ?? this.trialDurationDays,
      );
}
