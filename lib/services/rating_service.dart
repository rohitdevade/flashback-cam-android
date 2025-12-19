import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage app rating prompts
/// Only shows rating popup when user has experienced real value
class RatingService {
  static const String _savedVideoCountKey = 'rating_saved_video_count';
  static const String _appOpenDaysKey = 'rating_app_open_days';
  static const String _hasRatedKey = 'rating_has_rated';
  static const String _lastDismissedKey = 'rating_last_dismissed';
  static const String _firstOpenDateKey = 'rating_first_open_date';

  // Thresholds for showing rating popup
  static const int _minSavedVideos = 2;
  static const int _minAppOpenDays = 2;
  static const int _dismissCooldownDays = 5;

  int _savedVideoCount = 0;
  Set<String> _appOpenDays = {};
  bool _hasRated = false;
  DateTime? _lastDismissed;
  DateTime? _firstOpenDate;
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
      _hasRated = prefs.getBool(_hasRatedKey) ?? false;

      // Load app open days
      final daysJson = prefs.getStringList(_appOpenDaysKey);
      _appOpenDays = daysJson?.toSet() ?? {};

      // Load last dismissed date
      final lastDismissedStr = prefs.getString(_lastDismissedKey);
      if (lastDismissedStr != null) {
        _lastDismissed = DateTime.tryParse(lastDismissedStr);
      }

      // Load first open date
      final firstOpenStr = prefs.getString(_firstOpenDateKey);
      if (firstOpenStr != null) {
        _firstOpenDate = DateTime.tryParse(firstOpenStr);
      }

      // Record today's app open
      await _recordAppOpen();

      _isInitialized = true;
      debugPrint(
          '📊 RatingService initialized: videos=$_savedVideoCount, days=${_appOpenDays.length}, rated=$_hasRated');
    } catch (e) {
      debugPrint('❌ Failed to initialize RatingService: $e');
    }
  }

  /// Record that the app was opened today
  Future<void> _recordAppOpen() async {
    final today = _getTodayKey();

    // Set first open date if not set
    if (_firstOpenDate == null) {
      _firstOpenDate = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _firstOpenDateKey, _firstOpenDate!.toIso8601String());
    }

    if (!_appOpenDays.contains(today)) {
      _appOpenDays.add(today);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_appOpenDaysKey, _appOpenDays.toList());
      debugPrint(
          '📅 New app open day recorded: $today (total: ${_appOpenDays.length})');
    }
  }

  /// Record a successful video save
  Future<void> recordVideoSaved() async {
    _savedVideoCount++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_savedVideoCountKey, _savedVideoCount);
    debugPrint('🎬 Video saved count: $_savedVideoCount');
  }

  /// Check if rating popup should be shown
  /// This should be called 1-2 seconds after a successful save
  bool shouldShowRatingPopup() {
    // Never show if already rated
    if (_hasRated) {
      debugPrint('📊 Rating: Already rated, skipping');
      return false;
    }

    // Never show on first launch (check first open date)
    if (_firstOpenDate != null) {
      final daysSinceFirstOpen =
          DateTime.now().difference(_firstOpenDate!).inDays;
      if (daysSinceFirstOpen == 0 && _appOpenDays.length <= 1) {
        debugPrint('📊 Rating: First launch day, skipping');
        return false;
      }
    }

    // Check saved video threshold
    if (_savedVideoCount < _minSavedVideos) {
      debugPrint(
          '📊 Rating: Not enough videos ($_savedVideoCount < $_minSavedVideos)');
      return false;
    }

    // Check app open days threshold
    if (_appOpenDays.length < _minAppOpenDays) {
      debugPrint(
          '📊 Rating: Not enough open days (${_appOpenDays.length} < $_minAppOpenDays)');
      return false;
    }

    // Check cooldown after dismissal
    if (_lastDismissed != null) {
      final daysSinceDismiss =
          DateTime.now().difference(_lastDismissed!).inDays;
      if (daysSinceDismiss < _dismissCooldownDays) {
        debugPrint(
            '📊 Rating: In cooldown ($daysSinceDismiss < $_dismissCooldownDays days)');
        return false;
      }
    }

    debugPrint('✅ Rating: All conditions met, should show popup');
    return true;
  }

  /// Request to show rating popup (call after successful save with delay)
  void requestRatingPopup() {
    if (shouldShowRatingPopup()) {
      _ratingRequestController.add(null);
    }
  }

  /// Mark that user has given a rating (any rating)
  Future<void> markAsRated() async {
    _hasRated = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasRatedKey, true);
    debugPrint('⭐ User marked as rated');
  }

  /// Mark popup as dismissed (for 5-day cooldown)
  Future<void> markDismissed() async {
    _lastDismissed = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastDismissedKey, _lastDismissed!.toIso8601String());
    debugPrint('❌ Rating popup dismissed, cooldown started');
  }

  /// Get today's date key (YYYY-MM-DD format)
  String _getTodayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Getters for current state
  int get savedVideoCount => _savedVideoCount;
  int get appOpenDays => _appOpenDays.length;
  bool get hasRated => _hasRated;

  void dispose() {
    _ratingRequestController.close();
  }
}
