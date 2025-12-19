import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Paywall trigger reasons
enum PaywallTrigger {
  bufferSelection20s,
  bufferSelection30s,
  videoSaveLimit,
  dayThree,
  proFeatureTap,
}

/// Service to manage paywall trigger logic
/// Tracks user behavior and determines when to show the lifetime paywall
class PaywallService {
  static const String _savedVideoCountKey = 'paywall_saved_video_count';
  static const String _appOpenDaysKey = 'paywall_app_open_days';
  static const String _firstOpenDateKey = 'paywall_first_open_date';
  static const String _hasSeenPaywallKey = 'paywall_has_seen';

  // Thresholds
  static const int _maxFreeVideoSaves = 2;
  static const int _dayThreeTrigger = 3;

  int _savedVideoCount = 0;
  Set<String> _appOpenDays = {};
  DateTime? _firstOpenDate;
  bool _hasSeenPaywall = false;
  bool _isInitialized = false;

  /// Stream controller for paywall trigger requests
  final _paywallRequestController =
      StreamController<PaywallTrigger>.broadcast();
  Stream<PaywallTrigger> get paywallRequestStream =>
      _paywallRequestController.stream;

  /// Initialize the paywall service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      _savedVideoCount = prefs.getInt(_savedVideoCountKey) ?? 0;
      _hasSeenPaywall = prefs.getBool(_hasSeenPaywallKey) ?? false;

      // Load app open days
      final daysJson = prefs.getStringList(_appOpenDaysKey);
      _appOpenDays = daysJson?.toSet() ?? {};

      // Load first open date
      final firstOpenStr = prefs.getString(_firstOpenDateKey);
      if (firstOpenStr != null) {
        _firstOpenDate = DateTime.tryParse(firstOpenStr);
      }

      // Record today's app open
      await _recordAppOpen();

      _isInitialized = true;
      debugPrint(
          '💰 PaywallService initialized: videos=$_savedVideoCount, days=${_appOpenDays.length}, firstOpen=$_firstOpenDate');
    } catch (e) {
      debugPrint('❌ Failed to initialize PaywallService: $e');
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
      debugPrint('📅 First open date recorded: $_firstOpenDate');
    }

    if (!_appOpenDays.contains(today)) {
      _appOpenDays.add(today);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_appOpenDaysKey, _appOpenDays.toList());
      debugPrint(
          '📅 New app open day recorded: $today (total: ${_appOpenDays.length})');
    }
  }

  /// Record a successful video save (call BEFORE checking trigger)
  Future<void> recordVideoSaved() async {
    _savedVideoCount++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_savedVideoCountKey, _savedVideoCount);
    debugPrint('🎬 Paywall: Video saved count: $_savedVideoCount');
  }

  /// Mark paywall as seen (to avoid showing multiple times per session)
  Future<void> markPaywallSeen() async {
    _hasSeenPaywall = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSeenPaywallKey, true);
  }

  /// Reset paywall seen flag (call on new app session if needed)
  void resetPaywallSeenFlag() {
    _hasSeenPaywall = false;
  }

  /// Check if this is the first launch day
  bool get isFirstLaunchDay {
    if (_firstOpenDate == null) return true;
    final daysSinceFirstOpen =
        DateTime.now().difference(_firstOpenDate!).inDays;
    return daysSinceFirstOpen == 0;
  }

  /// Get days since first app open
  int get daysSinceFirstOpen {
    if (_firstOpenDate == null) return 0;
    return DateTime.now().difference(_firstOpenDate!).inDays;
  }

  /// Check if Day 3 trigger should fire
  bool shouldTriggerDayThreePaywall() {
    if (_hasSeenPaywall) return false;
    if (isFirstLaunchDay) return false;

    final days = daysSinceFirstOpen;
    // Trigger on day 3 or later (day 0 = first day, day 2 = third day)
    return days >= (_dayThreeTrigger - 1);
  }

  /// Check if video save limit paywall should trigger
  bool shouldTriggerVideoLimitPaywall() {
    if (_hasSeenPaywall) return false;
    if (isFirstLaunchDay) return false;

    // Trigger when user has saved MORE than the limit (after the limit is exceeded)
    return _savedVideoCount > _maxFreeVideoSaves;
  }

  /// Check if buffer selection should trigger paywall
  /// @param seconds - the buffer duration selected (20 or 30 for PRO)
  bool shouldTriggerBufferPaywall(int seconds) {
    if (_hasSeenPaywall) return false;
    if (isFirstLaunchDay) return false;

    // 20s and 30s buffers are PRO features
    return seconds >= 20;
  }

  /// Request paywall for a specific trigger
  void requestPaywall(PaywallTrigger trigger) {
    if (_hasSeenPaywall) {
      debugPrint('💰 Paywall already seen this session, skipping');
      return;
    }

    debugPrint('💰 Paywall triggered: $trigger');
    _paywallRequestController.add(trigger);
    _hasSeenPaywall = true;
  }

  /// Get today's date key (YYYY-MM-DD format)
  String _getTodayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Getters for current state
  int get savedVideoCount => _savedVideoCount;
  int get appOpenDays => _appOpenDays.length;
  bool get hasSeenPaywall => _hasSeenPaywall;
  int get maxFreeVideoSaves => _maxFreeVideoSaves;

  void dispose() {
    _paywallRequestController.close();
  }
}
