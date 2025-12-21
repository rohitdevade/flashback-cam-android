import 'dart:async';
import 'package:flutter/foundation.dart';

/// ═══════════════════════════════════════════════════════════════════════════════
/// DEFERRED INITIALIZATION SERVICE
///
/// COLD START OPTIMIZATION:
/// This service manages lazy initialization of heavy components to ensure
/// the first frame renders as fast as possible (<500ms target).
///
/// Key principles:
/// 1. NO heavy work during app cold start
/// 2. Critical UI renders immediately with minimal setup
/// 3. All SDK/service initialization is deferred
/// 4. User-triggered actions load components on-demand
/// ═══════════════════════════════════════════════════════════════════════════════

/// Represents the initialization state of a component
enum InitState {
  notStarted,
  inProgress,
  completed,
  failed,
}

/// Manages deferred/lazy initialization of app components
class DeferredInitService {
  static final DeferredInitService _instance = DeferredInitService._internal();
  factory DeferredInitService() => _instance;
  DeferredInitService._internal();

  // Track initialization state of each component
  final Map<String, InitState> _initStates = {};
  final Map<String, Completer<void>> _initCompleters = {};

  // Initialization timestamps for debugging cold start
  final Map<String, DateTime> _initStartTimes = {};
  final Map<String, Duration> _initDurations = {};

  /// Check if a component has been initialized
  bool isInitialized(String component) =>
      _initStates[component] == InitState.completed;

  /// Check if a component is currently initializing
  bool isInitializing(String component) =>
      _initStates[component] == InitState.inProgress;

  /// Get the initialization duration for a component (for debugging)
  Duration? getInitDuration(String component) => _initDurations[component];

  /// Initialize a component with deferred/lazy loading
  /// Returns immediately if already initialized or initializing
  Future<void> initializeComponent(
    String component,
    Future<void> Function() initializer,
  ) async {
    // Already completed
    if (_initStates[component] == InitState.completed) {
      debugPrint('⚡ $component already initialized, skipping');
      return;
    }

    // Already in progress - wait for it
    if (_initStates[component] == InitState.inProgress) {
      debugPrint('⏳ $component initialization in progress, waiting...');
      await _initCompleters[component]?.future;
      return;
    }

    // Start initialization
    _initStates[component] = InitState.inProgress;
    _initCompleters[component] = Completer<void>();
    _initStartTimes[component] = DateTime.now();

    debugPrint('🚀 Starting deferred initialization of $component');

    try {
      await initializer();

      _initStates[component] = InitState.completed;
      _initDurations[component] =
          DateTime.now().difference(_initStartTimes[component]!);

      debugPrint(
          '✅ $component initialized in ${_initDurations[component]!.inMilliseconds}ms');
      _initCompleters[component]!.complete();
    } catch (e) {
      _initStates[component] = InitState.failed;
      debugPrint('❌ Failed to initialize $component: $e');
      _initCompleters[component]!.completeError(e);
      rethrow;
    }
  }

  /// Wait for a component to be initialized (if it's in progress)
  Future<void> waitForComponent(String component) async {
    if (_initStates[component] == InitState.completed) return;
    if (_initStates[component] == InitState.inProgress) {
      await _initCompleters[component]?.future;
    }
  }

  /// Reset a component's state (useful for retry scenarios)
  void resetComponent(String component) {
    _initStates.remove(component);
    _initCompleters.remove(component);
    _initStartTimes.remove(component);
    _initDurations.remove(component);
  }

  /// Print initialization report (for debugging cold start)
  void printInitReport() {
    debugPrint(
        '═══════════════════════════════════════════════════════════════');
    debugPrint('DEFERRED INITIALIZATION REPORT');
    debugPrint(
        '═══════════════════════════════════════════════════════════════');

    var totalMs = 0;
    for (final entry in _initDurations.entries) {
      final ms = entry.value.inMilliseconds;
      totalMs += ms;
      debugPrint('  ${entry.key}: ${ms}ms');
    }

    debugPrint(
        '───────────────────────────────────────────────────────────────');
    debugPrint('  TOTAL DEFERRED INIT TIME: ${totalMs}ms');
    debugPrint('  (This time was NOT blocking the first frame)');
    debugPrint(
        '═══════════════════════════════════════════════════════════════');
  }
}

/// Component identifiers for deferred initialization
class DeferredComponents {
  /// AdMob SDK - initialized on first ad request or after UI visible
  static const String ads = 'ads';

  /// Billing/IAP client - initialized on paywall open
  static const String billing = 'billing';

  /// Camera system - initialized when user taps "Start Buffer"
  static const String camera = 'camera';

  /// Camera preview - initialized after camera
  static const String cameraPreview = 'cameraPreview';

  /// Analytics - initialized async after UI visible
  static const String analytics = 'analytics';

  /// Storage/SharedPreferences - lightweight, can init early but async
  static const String storage = 'storage';

  /// Settings - lightweight, can init early but async
  static const String settings = 'settings';

  /// Rating service - lightweight, can init early but async
  static const String rating = 'rating';

  /// Paywall service - lightweight, can init early but async
  static const String paywall = 'paywall';

  /// Device capabilities detection - init with camera
  static const String deviceCapabilities = 'deviceCapabilities';
}
