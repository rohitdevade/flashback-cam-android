import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage app rating prompts
/// Rules:
/// 1) Show only when eligible and requested by UI flow (gallery return)
/// 2) Show at most once per app session
/// 3) After 4-5 stars, suppress for 30 days
/// 4) After 1-3 stars, suppress for 2 days
class RatingService {
  static const String _savedVideoCountKey = 'rating_saved_video_count';
  static const String _nextEligibleAtKey = 'rating_next_eligible_at';

  static const int _highRatingCooldownDays = 30;
  static const int _lowRatingCooldownDays = 2;

  int _savedVideoCount = 0;
  DateTime? _nextEligibleAt;
  bool _shownInCurrentSession = false;
  bool _isInitialized = false;

  /// Stream controller for rating popup requests
  final _ratingRequestController = StreamController<void>.broadcast();
  Stream<void> get ratingRequestStream => _ratingRequestController.stream;

  /// Initialize the rating service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      _savedVideoCount = prefs.getInt(_savedVideoCountKey) ?? 0;

      final nextEligibleStr = prefs.getString(_nextEligibleAtKey);
      if (nextEligibleStr != null) {
        _nextEligibleAt = DateTime.tryParse(nextEligibleStr);
      }

      _isInitialized = true;
      debugPrint(
          '📊 RatingService initialized: videos=$_savedVideoCount, nextEligibleAt=${_nextEligibleAt?.toIso8601String()}, shownThisSession=$_shownInCurrentSession');
    } catch (e) {
      debugPrint('❌ Failed to initialize RatingService: $e');
    }
  }

  /// Record a saved video for analytics/debug counters.
  Future<void> recordVideoSaved() async {
    _savedVideoCount++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_savedVideoCountKey, _savedVideoCount);
  }

  /// Kept for compatibility with existing call sites; no longer affects rating flow.
  void markAdShownSuccessfully() {
    debugPrint('📺 Ad shown successfully');
  }

  /// Check if rating popup should be shown
  /// Enforces once-per-session and persisted cooldown window.
  bool shouldShowRatingPopup() {
    if (!_isInitialized) {
      debugPrint('📊 Rating: Service not initialized, skipping');
      return false;
    }

    if (_shownInCurrentSession) {
      debugPrint('📊 Rating: Already shown this session, skipping');
      return false;
    }

    final now = DateTime.now();
    if (_nextEligibleAt != null && now.isBefore(_nextEligibleAt!)) {
      debugPrint(
          '📊 Rating: In cooldown until ${_nextEligibleAt!.toIso8601String()}, skipping');
      return false;
    }

    debugPrint('✅ Rating: Should show popup');
    return true;
  }

  /// Mark popup as shown for current app session.
  void markPopupShownThisSession() {
    _shownInCurrentSession = true;
    debugPrint('📊 Rating popup shown (session locked)');
  }

  /// Compatibility alias for older callers.
  void markAsShown() {
    markPopupShownThisSession();
  }

  /// Request to show rating popup.
  void requestRatingPopup() {
    if (shouldShowRatingPopup()) {
      _ratingRequestController.add(null);
    }
  }

  /// User gave 4-5 stars: suppress popup for 30 days.
  Future<void> markHighRatingSubmitted() async {
    final nextDate = DateTime.now().add(
      const Duration(days: _highRatingCooldownDays),
    );
    _nextEligibleAt = nextDate;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nextEligibleAtKey, nextDate.toIso8601String());
    debugPrint(
        '⭐ High rating submitted: next eligible at ${nextDate.toIso8601String()}');
  }

  /// User gave 1-3 stars: suppress popup for 2 days.
  Future<void> markLowRatingSubmitted() async {
    final nextDate = DateTime.now().add(
      const Duration(days: _lowRatingCooldownDays),
    );
    _nextEligibleAt = nextDate;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nextEligibleAtKey, nextDate.toIso8601String());
    debugPrint(
        '📊 Low rating submitted: next eligible at ${nextDate.toIso8601String()}');
  }

  /// Compatibility aliases for older call sites.
  Future<void> markAsRated() => markHighRatingSubmitted();

  Future<void> markDismissed() => markLowRatingSubmitted();

  int get savedVideoCount => _savedVideoCount;

  void dispose() {
    _ratingRequestController.close();
  }
}
