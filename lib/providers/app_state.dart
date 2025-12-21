import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flashback_cam/models/app_settings.dart';
import 'package:flashback_cam/models/debug_info.dart';
import 'package:flashback_cam/models/device_capabilities.dart';
import 'package:flashback_cam/models/video_recording.dart';
import 'package:flashback_cam/services/camera_service.dart';
import 'package:flashback_cam/services/device_service.dart';
import 'package:flashback_cam/services/storage_service.dart';
import 'package:flashback_cam/services/subscription_service.dart';
import 'package:flashback_cam/services/ad_service.dart';
import 'package:flashback_cam/services/settings_service.dart';
import 'package:flashback_cam/services/rating_service.dart';
import 'package:flashback_cam/services/paywall_service.dart';
import 'package:flashback_cam/services/deferred_init_service.dart';
import 'package:permission_handler/permission_handler.dart';

/// ═══════════════════════════════════════════════════════════════════════════════
/// APP STATE - COLD START OPTIMIZED
///
/// COLD START OPTIMIZATION STRATEGY:
///
/// Phase 1 (Cold Start - runs immediately):
/// - Load lightweight cached data (settings, user preferences)
/// - NO camera initialization
/// - NO SDK initialization (ads, billing)
/// - UI shows immediately with placeholder/loading state
///
/// Phase 2 (Deferred - runs after first frame):
/// - Camera preview initialization (when permissions granted)
/// - Heavy services start in background
///
/// Phase 3 (User-Triggered - on demand):
/// - Buffer/recording starts on "Start Buffer" tap
/// - Ads SDK initializes on first ad request
/// - Billing initializes on paywall open
///
/// This ensures first frame renders in <500ms.
/// ═══════════════════════════════════════════════════════════════════════════════

enum CameraMode {
  idle, // Camera and buffer OFF
  buffering, // Camera ON, buffer active, ready to record
  recording, // Currently recording video
  processing // Finalizing video after recording
}

class AppState extends ChangeNotifier {
  final CameraService _cameraService = CameraService();
  late final DeviceService _deviceService;
  final StorageService _storageService = StorageService();
  late final SubscriptionService _subscriptionService;
  final AdService _adService = AdService();
  final SettingsService _settingsService = SettingsService();
  final RatingService _ratingService = RatingService();
  final PaywallService _paywallService = PaywallService();

  // Expose AdService for screens that need banner ads
  AdService get adService => _adService;

  bool _isInitialized = false;
  bool _isInitializing = false;
  CameraMode _cameraMode = CameraMode.idle;
  int _bufferSeconds = 0;
  String _flashMode = 'off';
  double _finalizeProgress = 0.0;
  int? _previewTextureId;
  bool _isProUser = false;
  int _bufferDuration = 5; // 5 seconds for free, 10 for pro
  bool _permissionsGranted = false;
  bool _permissionsPermanentlyDenied = false;
  String? _initializationError;
  double _zoomLevel = 1.0;
  double _maxZoom = 8.0; // Will be updated from camera capabilities

  // Recording error tracking - cleared after being read
  String? _lastRecordingError;

  // Max duration reached message - cleared after being read
  String? _maxDurationReachedMessage;

  // Flag to indicate recording is being prepared (after button tap, before recording starts)
  bool _isPreparingRecording = false;

  // Dynamic buffer progress tracking
  DateTime? _bufferStartTime;
  Timer? _progressTimer;
  int _bufferRemainingSeconds = 0;

  // ═══════════════════════════════════════════════════════════════════════════════
  // BUFFER UNLOCK STATE - Track rewarded ad unlocks for buffer duration
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Currently unlocked buffer duration (via rewarded ad) - resets after save
  int? _rewardedBufferUnlock;

  /// Number of rewarded buffer unlocks used in this session
  int _rewardedUnlockCount = 0;

  /// Maximum rewarded unlocks before showing paywall
  static const int _maxRewardedUnlocksBeforePaywall = 2;

  /// Get the currently unlocked buffer duration (null if none)
  int? get rewardedBufferUnlock => _rewardedBufferUnlock;

  /// Check if a buffer duration is currently unlocked via rewarded ad
  bool get hasRewardedBufferUnlock => _rewardedBufferUnlock != null;

  /// Check if user has used too many rewarded unlocks and should see paywall
  bool get shouldShowPaywallInsteadOfRewardedAd =>
      _rewardedUnlockCount >= _maxRewardedUnlocksBeforePaywall;

  // ═══════════════════════════════════════════════════════════════════════════════
  // STORAGE STATE - Track storage mode and errors for UI
  // ═══════════════════════════════════════════════════════════════════════════════
  StorageMode _storageMode = StorageMode.normal;
  String? _storageErrorMessage;
  bool _isStorageLow = false;

  /// Current storage mode (normal or low)
  StorageMode get storageMode => _storageMode;

  /// True if storage is low and features are limited
  bool get isStorageLow => _isStorageLow;

  /// Storage error message, if any (cleared after being read)
  String? get storageErrorMessage {
    final msg = _storageErrorMessage;
    _storageErrorMessage = null;
    return msg;
  }

  /// Refresh storage status from native code
  Future<void> refreshStorageStatus() async {
    try {
      final status = await _cameraService.getStorageStatus();
      final availableMB = status['availableMB'] as int? ?? 0;
      final lowStorageThresholdMB =
          status['lowStorageThresholdMB'] as int? ?? 1024;
      final modeStr = status['mode'] as String? ?? 'NORMAL';

      _storageMode = modeStr == 'LOW' ? StorageMode.low : StorageMode.normal;
      _isStorageLow = availableMB < lowStorageThresholdMB;

      debugPrint(
          '📊 Storage status: ${availableMB}MB available, mode: $modeStr, isLow: $_isStorageLow');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to refresh storage status: $e');
    }
  }

  /// Clear storage error state (call after user acknowledges error)
  void clearStorageError() {
    _storageErrorMessage = null;
    notifyListeners();
  }

  /// Get adjusted settings for current storage conditions
  Future<Map<String, dynamic>?> getAdjustedSettingsForStorage({
    required String resolution,
    required int fps,
    required int bufferSeconds,
  }) async {
    try {
      return await _cameraService.getAdjustedSettingsForStorage(
        resolution: resolution,
        fps: fps,
        bufferSeconds: bufferSeconds,
      );
    } catch (e) {
      debugPrint('❌ Failed to get adjusted settings: $e');
      return null;
    }
  }

  int get selectedBufferSeconds => _settingsService.settings.preRollSeconds;

  CameraService get cameraService => _cameraService;

  // Shows how many seconds of buffer are currently available (0 to N)
  int get bufferRemainingSeconds => _bufferRemainingSeconds;

  // Visual progress for the buffer ring (continuously animates)
  double get bufferProgress {
    if (_bufferStartTime == null || _cameraMode == CameraMode.idle) return 0.0;
    final elapsedMs =
        DateTime.now().difference(_bufferStartTime!).inMilliseconds;
    final bufferDurationMs = selectedBufferSeconds * 1000;
    // Continuous animation showing the buffer is actively recording
    return (elapsedMs % bufferDurationMs) / bufferDurationMs;
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // COLD START: Track initialization phases
  // ═══════════════════════════════════════════════════════════════════════════════
  bool _phase1Complete = false; // Lightweight init (cached data)
  bool _phase2Complete = false; // Camera preview
  bool _cameraInitialized = false; // Camera hardware ready
  final DeferredInitService _deferredInit = DeferredInitService();

  /// Check if basic UI can be shown (Phase 1 complete)
  bool get isUIReady => _phase1Complete;

  /// Check if camera preview is ready (Phase 2 complete)
  bool get isCameraReady => _cameraInitialized;

  AppState() {
    _subscriptionService = SubscriptionService();
    _deviceService = DeviceService(_cameraService);
    // COLD START: Start Phase 1 (lightweight) immediately
    _initializePhase1();
  }

  /// ═══════════════════════════════════════════════════════════════════════════════
  /// PHASE 1: Lightweight initialization - runs during cold start
  ///
  /// COLD START OPTIMIZATION:
  /// - Only loads cached data from SharedPreferences
  /// - NO camera, NO SDKs, NO network calls
  /// - Target: complete in <100ms
  /// - UI can render immediately after this
  /// ═══════════════════════════════════════════════════════════════════════════════
  Future<void> _initializePhase1() async {
    final startTime = DateTime.now();
    debugPrint('🚀 COLD START: Phase 1 starting...');

    try {
      // Only load lightweight cached data - these read from SharedPreferences
      // and don't involve any SDK initialization or network calls
      await Future.wait([
        _storageService.initialize(), // Loads cached video list
        _settingsService.initialize(), // Loads user preferences
        _subscriptionService
            .initialize(), // Loads cached subscription status ONLY
        _ratingService.initialize(), // Loads rating counters
        _paywallService.initialize(), // Loads paywall counters
        // NOTE: AdService.initialize() is now a no-op (deferred)
        _adService.initialize(),
      ]);

      _phase1Complete = true;
      _isInitialized = true; // Mark as initialized so UI can render

      final duration = DateTime.now().difference(startTime);
      debugPrint(
          '✅ COLD START: Phase 1 complete in ${duration.inMilliseconds}ms');
      debugPrint('   UI is now ready to render');

      notifyListeners(); // Trigger UI rebuild

      // Schedule Phase 2 after first frame
      _schedulePhase2();
    } catch (e, stackTrace) {
      debugPrint('❌ Phase 1 initialization failed: $e');
      debugPrint('Stack trace: $stackTrace');
      _initializationError = 'Failed to initialize app: $e';
      _phase1Complete = true;
      notifyListeners();
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════════════
  /// PHASE 2: Camera preview initialization - runs after first frame
  ///
  /// COLD START OPTIMIZATION:
  /// - Deferred until after UI is visible
  /// - Initializes camera preview for live viewfinder
  /// - Buffer/recording is still NOT started (user must tap button)
  /// ═══════════════════════════════════════════════════════════════════════════════
  void _schedulePhase2() {
    // Use addPostFrameCallback to ensure this runs after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePhase2();
    });
  }

  Future<void> _initializePhase2() async {
    if (_isInitializing || _phase2Complete) return;
    _isInitializing = true;

    final startTime = DateTime.now();
    debugPrint('🎥 COLD START: Phase 2 starting (camera preview)...');

    try {
      // Check permissions first
      final hasPermissions = await _ensureRequiredPermissions();
      if (!hasPermissions) {
        debugPrint('Camera permissions not granted; camera setup skipped.');
        _cameraMode = CameraMode.idle;
        _phase2Complete = true;
        _isInitializing = false;
        notifyListeners();
        return;
      }

      // Detect device capabilities
      await _deviceService.detectCapabilities();

      // Set up camera event listener
      _cameraService.eventStream.listen(_handleCameraEvent);

      // Initialize camera with user's saved settings
      final initialSettings = _settingsService.settings;
      final resolvedResolution =
          _resolveResolutionForCamera(initialSettings.resolution);
      final resolvedFps = _resolveFpsForCamera(initialSettings.fps);

      await _cameraService.initialize(
        resolution: resolvedResolution,
        fps: resolvedFps,
        codec: 'H.264',
        preRollSeconds: initialSettings.preRollSeconds,
        stabilization: initialSettings.stabilization,
      );

      debugPrint('Camera initialized, waiting for camera device to open...');

      final cameraReady = await _cameraService.waitForCameraReady(
        timeout: const Duration(seconds: 3),
      );
      debugPrint('Camera ready: $cameraReady');

      // Create camera preview texture
      _previewTextureId = await _cameraService.createPreview();
      if (_previewTextureId == null) {
        throw Exception('Failed to create preview texture');
      }

      debugPrint('Preview texture created: $_previewTextureId');

      _initializationError = null;
      _cameraInitialized = true;
      _cameraMode = CameraMode.idle; // Ready for user to start buffer

      // Start preview
      await _cameraService.startPreview();

      // Get max zoom (non-blocking)
      _maxZoom = await _cameraService.getMaxZoom();
      debugPrint('🔍 Max zoom: $_maxZoom');

      _phase2Complete = true;

      final duration = DateTime.now().difference(startTime);
      debugPrint(
          '✅ COLD START: Phase 2 complete in ${duration.inMilliseconds}ms');
      debugPrint('   Camera preview is ready');
      debugPrint('   Buffer will start when user taps "Start Buffer"');

      // Print deferred init report
      _deferredInit.printInitReport();
    } catch (e, stackTrace) {
      debugPrint('❌ Phase 2 initialization failed: $e');
      debugPrint('Stack trace: $stackTrace');
      _initializationError = 'Failed to initialize camera: $e';
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════════════
  /// REMOVED: Old synchronous _initialize() that blocked cold start
  /// This was the main cause of slow cold start - it initialized everything
  /// including camera, ads, billing, etc. before the first frame.
  /// ═══════════════════════════════════════════════════════════════════════════════

  Future<bool> _ensureRequiredPermissions() async {
    // Only request the core permissions needed to show the system prompt.
    // Storage/media access is handled later (e.g. when exporting videos).
    final permissions = [Permission.camera, Permission.microphone];

    // On Android 13+ (API 33+), we need notification permission for buffer indicator
    if (Platform.isAndroid) {
      permissions.add(Permission.notification);
    }

    final statusMap = <Permission, PermissionStatus>{};

    bool granted = true;
    bool permanentlyDenied = false;
    for (final permission in permissions) {
      var status = await permission.status;
      debugPrint('Permission ${permission.value}: initial status=$status');

      if (!status.isGranted && !status.isPermanentlyDenied) {
        status = await permission.request();
        debugPrint(
            'Permission ${permission.value}: post-request status=$status');
      }

      statusMap[permission] = status;

      // Notification permission is optional - app works without it (just no buffer notification)
      // Only block app if core permissions (camera/microphone) are denied
      final isOptionalPermission = permission == Permission.notification;

      if (status.isPermanentlyDenied && !isOptionalPermission) {
        permanentlyDenied = true;
      }
      if (!status.isGranted && !isOptionalPermission) {
        granted = false;
      }
    }

    _permissionsGranted = granted;
    _permissionsPermanentlyDenied = permanentlyDenied;
    if (!granted) {
      final deniedList = statusMap.entries
          .where((entry) => !entry.value.isGranted)
          .map((entry) => entry.key.value)
          .join(', ');

      _initializationError = permanentlyDenied
          ? 'Camera permissions permanently denied ($deniedList). Enable them from Settings.'
          : 'Missing permissions ($deniedList). Please accept the system prompt to continue.';
    } else {
      _initializationError = null;
    }

    debugPrint(
        'Permission status -> granted=$granted, permanentlyDenied=$permanentlyDenied, details=$statusMap');
    notifyListeners();
    return granted;
  }

  // Update how full the buffer is (cycles from 0 to selectedBufferSeconds continuously)
  void _updateBufferFillLevel() {
    if (_bufferStartTime == null) {
      _bufferRemainingSeconds = 0;
      return;
    }

    final elapsedSeconds =
        DateTime.now().difference(_bufferStartTime!).inSeconds;

    // Calculate current position in the cycle (1 to selectedBufferSeconds, then resets to 1)
    final remainder = elapsedSeconds % selectedBufferSeconds;
    _bufferRemainingSeconds =
        remainder == 0 ? selectedBufferSeconds : remainder;
  }

  void _handleCameraEvent(Map<String, dynamic> event) {
    try {
      final eventType = event['type'] as String?;

      switch (eventType) {
        case 'recordingStarted':
          _cameraMode = CameraMode.recording;
          _isPreparingRecording = false;
          notifyListeners();
          break;
        case 'recordingFinished':
          _cameraMode = CameraMode.buffering;
          _finalizeProgress = 0.0;

          // Construct video data from the simplified event
          final path = event['path'] as String;
          final duration = (event['duration'] as num?)?.toInt() ?? 0;

          // Ensure file exists before adding
          final file = File(path);
          if (!file.existsSync()) {
            debugPrint('❌ Recording finished but file not found: $path');
            return;
          }

          final videoData = {
            'id': file.uri.pathSegments.last,
            'filePath': path,
            'thumbnailPath': null,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'duration': duration,
            'size': file.lengthSync(),
            'resolution': '1080p',
            'fps': 30,
            'preRollSeconds': 0
          };

          _addVideoFromEvent(videoData);
          notifyListeners();
          _showAdIfNeeded();
          break;

        case 'recordingStopped':
          _cameraMode = CameraMode.processing;
          notifyListeners();
          _showAdIfNeeded();
          break;
        case 'maxDurationReached':
          final maxMinutes = event['maxMinutes'] as int? ?? 0;
          final resolution = event['resolution'] as String? ?? '';
          final fps = event['fps'] as int? ?? 0;
          debugPrint(
              'Max recording duration reached: ${maxMinutes}min at $resolution@${fps}fps');
          _maxDurationReachedMessage =
              'Recording auto-stopped after $maxMinutes minutes (max for $resolution@${fps}fps)';
          notifyListeners();
          break;
        case 'finalizeProgress':
          _finalizeProgress = (event['progress'] as num?)?.toDouble() ?? 0.0;
          notifyListeners();
          break;
        case 'finalizeCompleted':
          // Return to buffering state after processing
          _cameraMode = CameraMode.buffering;
          _finalizeProgress = 0.0;
          final videoDataRaw = event['video'];
          if (videoDataRaw != null) {
            Map<String, dynamic>? videoData;
            if (videoDataRaw is Map<String, dynamic>) {
              videoData = videoDataRaw;
            } else if (videoDataRaw is Map) {
              videoData = Map<String, dynamic>.from(
                  videoDataRaw.cast<String, dynamic>());
            }
            if (videoData != null) {
              _addVideoFromEvent(videoData);
            }
          }
          notifyListeners();
          break;
        case 'bufferUpdate':
          _bufferSeconds = (event['seconds'] as num?)?.toInt() ?? 0;
          final isBuffering = event['isBuffering'] as bool? ?? false;
          final bufferDuration =
              (event['bufferDuration'] as num?)?.toInt() ?? 5;
          debugPrint(
              'Buffer update: ${_bufferSeconds}s (max: ${bufferDuration}s, continuous: $isBuffering)');
          notifyListeners();
          break;
        case 'subscriptionUpdated':
          final isProUser = event['isProUser'] as bool? ?? false;
          final bufferDuration =
              (event['bufferDuration'] as num?)?.toInt() ?? 5;
          _isProUser = isProUser;
          _bufferDuration = bufferDuration;
          debugPrint(
              'Subscription updated: pro=$isProUser, buffer=${bufferDuration}s');
          notifyListeners();
          break;
        case 'recordingError':
          final error = event['error'] as String? ?? 'Unknown error';
          final errorCode = event['code'] as String?;
          debugPrint('Recording error: $error (code: $errorCode)');
          _lastRecordingError = error;
          _isPreparingRecording = false;
          _cameraMode = CameraMode.buffering;
          notifyListeners();
          break;
        case 'thermalWarning':
          debugPrint('Thermal warning: ${event['message']}');
          break;
        case 'lowStorage':
          final availableMB = event['availableMB'] as int? ?? 0;
          final thresholdMB = event['thresholdMB'] as int? ?? 0;
          debugPrint(
              '⚠️ Low storage warning: ${availableMB}MB available (threshold: ${thresholdMB}MB)');
          _isStorageLow = true;
          _storageMode = StorageMode.low;
          _storageErrorMessage = 'Low storage: ${availableMB}MB available';
          notifyListeners();
          break;
        case 'storageFull':
          final savedPath = event['savedPath'] as String?;
          final error = event['error'] as String? ?? 'Storage full';
          debugPrint('🛑 Storage full during recording: $error');
          if (savedPath != null) {
            debugPrint('  Recording saved to: $savedPath');
          }
          _isStorageLow = true;
          _storageErrorMessage = error;
          _cameraMode = CameraMode.buffering;
          _isPreparingRecording = false;
          notifyListeners();
          break;
        case 'recovered':
          debugPrint('Recovered video: ${event['video']}');
          break;
        case 'cameraOpened':
          debugPrint('Camera device opened');
          // This event is handled by waitForCameraReady() during initialization
          break;
        case 'previewStarted':
          debugPrint('Camera preview started');
          // Ensure UI updates to show the preview
          notifyListeners();
          break;
      }
    } catch (e, stackTrace) {
      debugPrint('Error handling camera event: $e');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('Event data: $event');
    }
  }

  void _addVideoFromEvent(Map<String, dynamic> videoData) {
    try {
      // Convert from native event format to VideoRecording format
      final now = DateTime.now();
      final videoId = videoData['id'] as String;
      final filePath = videoData['filePath'] as String;
      final thumbnailPath = videoData['thumbnailPath'] as String?;
      final timestamp = (videoData['timestamp'] as num?)?.toInt() ??
          now.millisecondsSinceEpoch;

      debugPrint('═══════════════════════════════════════════════════');
      debugPrint('NEW VIDEO FROM NATIVE:');
      debugPrint('  ID: $videoId');
      debugPrint('  Path: $filePath');
      debugPrint('  Thumbnail: $thumbnailPath');
      debugPrint('  Thumbnail is null: ${thumbnailPath == null}');
      debugPrint('  Thumbnail is empty: ${thumbnailPath?.isEmpty ?? true}');
      if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
        debugPrint(
            '  Thumbnail file exists: ${File(thumbnailPath).existsSync()}');
      }
      debugPrint('  All video data keys: ${videoData.keys.toList()}');
      debugPrint(
          '  Timestamp: $timestamp (${DateTime.fromMillisecondsSinceEpoch(timestamp)})');
      debugPrint('  Size: ${videoData['size']} bytes');
      debugPrint('═══════════════════════════════════════════════════');

      final video = VideoRecording(
        id: videoId,
        filePath: filePath,
        thumbnailPath: thumbnailPath,
        durationSeconds: ((videoData['duration'] as num?) ?? 0) ~/
            1000, // Convert from ms to seconds
        resolution: videoData['resolution'] as String? ?? '1080p',
        fps: videoData['fps'] as int? ?? 30,
        codec: 'H.264',
        preRollSeconds: videoData['preRollSeconds'] as int? ?? 3,
        fileSizeBytes: (videoData['size'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
        updatedAt: now,
      );

      _storageService.addVideo(video);
      debugPrint('Added video to gallery: ${video.id}');

      // Track video save for rating/paywall services
      onVideoSaved();

      // Clear rewarded buffer unlock after save (one-time use)
      _clearRewardedBufferUnlock();
    } catch (e) {
      debugPrint('Failed to add video from event: $e');
      debugPrint('Video data: $videoData');
    }
  }

  Future<void> _showAdIfNeeded() async {
    if (!isPro) {
      await _adService.showInterstitialAd();
    }
  }

  /// Show interstitial ad when opening gallery (not every time)
  Future<void> showGalleryAd() async {
    if (!isPro) {
      await _adService.showGalleryInterstitialAd();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // BUFFER DURATION CONTROL - From camera preview screen
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Available buffer durations (in seconds)
  static const List<int> availableBufferDurations = [10, 20, 30];

  /// Default buffer duration for all users
  static const int defaultBufferDuration = 10;

  /// Check if a buffer duration is available for the current user
  /// Returns: 'available', 'locked', or 'unlocked' (via rewarded ad)
  String getBufferDurationStatus(int seconds) {
    // 10s is always available
    if (seconds == 10) return 'available';

    // Pro users have access to all durations
    if (isPro) return 'available';

    // Check if this duration is unlocked via rewarded ad
    if (_rewardedBufferUnlock == seconds) return 'unlocked';

    // Otherwise it's locked for free users
    return 'locked';
  }

  /// Check if user can select a buffer duration
  /// Returns true if selection is allowed, false if blocked
  bool canSelectBufferDuration(int seconds) {
    // Block during recording or processing
    if (_cameraMode == CameraMode.recording ||
        _cameraMode == CameraMode.processing) {
      return false;
    }
    return true;
  }

  /// Attempt to select a buffer duration
  /// For locked durations, this will trigger rewarded ad or paywall
  /// Returns: 'success', 'blocked', 'needs_ad', 'needs_paywall'
  String trySelectBufferDuration(int seconds) {
    // Block during recording/processing
    if (!canSelectBufferDuration(seconds)) {
      return 'blocked';
    }

    // 10s is always available
    if (seconds == 10) {
      return 'success';
    }

    // Pro users can select any duration
    if (isPro) {
      return 'success';
    }

    // Check if already unlocked
    if (_rewardedBufferUnlock == seconds) {
      return 'success';
    }

    // Free user trying to select locked duration
    // Check if they should see paywall instead of rewarded ad
    if (shouldShowPaywallInsteadOfRewardedAd) {
      return 'needs_paywall';
    }

    return 'needs_ad';
  }

  /// Show rewarded ad to unlock a buffer duration
  /// Returns true if unlock was successful
  Future<bool> showRewardedAdForBuffer(int seconds) async {
    debugPrint('🎬 Showing rewarded ad to unlock ${seconds}s buffer');

    final success = await _adService.showRewardedAdForBufferUnlock();

    if (success) {
      _rewardedBufferUnlock = seconds;
      _rewardedUnlockCount++;
      debugPrint(
          '✅ Buffer ${seconds}s unlocked via rewarded ad (count: $_rewardedUnlockCount)');
      notifyListeners();
      return true;
    }

    debugPrint('❌ Rewarded ad failed or was cancelled');
    return false;
  }

  /// Clear the rewarded buffer unlock (called after video save)
  void _clearRewardedBufferUnlock() {
    if (_rewardedBufferUnlock != null) {
      debugPrint(
          '🔒 Clearing rewarded buffer unlock, reverting to ${defaultBufferDuration}s');
      _rewardedBufferUnlock = null;

      // Revert to default buffer duration if currently using unlocked duration
      final currentBuffer = _settingsService.settings.preRollSeconds;
      if (currentBuffer > defaultBufferDuration && !isPro) {
        _updateBufferDurationInternal(defaultBufferDuration);
      }

      notifyListeners();
    }
  }

  /// Change buffer duration (internal, after validation)
  Future<void> _updateBufferDurationInternal(int seconds) async {
    final currentSettings = _settingsService.settings;
    if (currentSettings.preRollSeconds == seconds) return;

    debugPrint(
        '⏱️ Changing buffer duration from ${currentSettings.preRollSeconds}s to ${seconds}s');

    // Update settings
    await updateSettings(currentSettings.copyWith(preRollSeconds: seconds));

    // If buffer is active, restart it with new duration
    if (_cameraMode == CameraMode.buffering) {
      await _restartBufferWithNewDuration();
    }
  }

  /// Change buffer duration with full validation
  /// Returns true if change was successful
  Future<bool> changeBufferDuration(int seconds) async {
    final status = trySelectBufferDuration(seconds);

    if (status != 'success') {
      debugPrint('❌ Cannot change buffer to ${seconds}s: $status');
      return false;
    }

    await _updateBufferDurationInternal(seconds);
    return true;
  }

  /// Restart buffer with new duration (called when duration changes while buffering)
  Future<void> _restartBufferWithNewDuration() async {
    if (_cameraMode != CameraMode.buffering) return;

    debugPrint('🔄 Restarting buffer with new duration...');

    try {
      // Stop current buffer
      _progressTimer?.cancel();
      await _cameraService.stopBuffer();

      // Clear buffer state
      _bufferStartTime = null;
      _bufferSeconds = 0;
      _bufferRemainingSeconds = 0;

      // Start new buffer with updated duration
      await _cameraService.startBuffer();

      // Mark buffer start time
      _bufferStartTime = DateTime.now();

      // Restart progress timer
      _progressTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
        if (_cameraMode == CameraMode.idle) {
          timer.cancel();
          return;
        }
        if (hasListeners) {
          _updateBufferFillLevel();
          notifyListeners();
        }
      });

      debugPrint('✅ Buffer restarted with ${selectedBufferSeconds}s duration');
    } catch (e) {
      debugPrint('❌ Failed to restart buffer: $e');
    }
  }

  /// Check and update storage mode before starting buffer
  Future<void> _updateStorageMode() async {
    try {
      final status = await _cameraService.getStorageStatus();
      _storageMode =
          status['storageMode'] == 'low' ? StorageMode.low : StorageMode.normal;
      _isStorageLow = status['isLowStorage'] as bool? ?? false;
      debugPrint('Storage status: mode=$_storageMode, isLow=$_isStorageLow');
    } catch (e) {
      debugPrint('Failed to update storage mode: $e');
    }
  }

  Future<void> startBuffer() async {
    if (!_isInitialized || _cameraMode != CameraMode.idle) return;

    try {
      debugPrint('Starting buffer: checking storage and starting encoders...');

      // Update storage mode before starting
      await _updateStorageMode();

      // Start buffer (preview already running)
      // This will throw if there's insufficient storage
      await _cameraService.startBuffer();

      // Mark buffer start time
      _bufferStartTime = DateTime.now();
      _bufferRemainingSeconds = 0;

      // Start progress timer for animation and fill level updates
      _progressTimer?.cancel();
      _progressTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
        if (_cameraMode == CameraMode.idle) {
          timer.cancel();
          return;
        }

        if (hasListeners) {
          _updateBufferFillLevel();
          notifyListeners();
        }
      });

      _cameraMode = CameraMode.buffering;
      notifyListeners();

      debugPrint('✅ Buffer started - encoders active, ready to record');
    } on PlatformException catch (e) {
      debugPrint('Failed to start buffer: ${e.code} - ${e.message}');

      // Handle storage-specific errors
      if (e.code == 'INSUFFICIENT_STORAGE') {
        _storageErrorMessage = e.message ??
            'Not enough storage for buffer. Please free up space or reduce quality.';
        _isStorageLow = true;
        _storageMode = StorageMode.low;
      } else {
        _storageErrorMessage = 'Failed to start buffer: ${e.message}';
      }

      _cameraMode = CameraMode.idle;
      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('Failed to start buffer: $e');
      debugPrint('Stack trace: $stackTrace');
      _cameraMode = CameraMode.idle;
      notifyListeners();
    }
  }

  Future<void> stopBuffer() async {
    if (_cameraMode == CameraMode.idle) return;
    if (_cameraMode == CameraMode.recording) {
      debugPrint('Cannot stop buffer while recording');
      return;
    }

    try {
      debugPrint('Stopping buffer: stopping encoders (keeping preview)...');

      // Stop timers
      _progressTimer?.cancel();
      _progressTimer = null;

      // Stop buffer only (keep preview running)
      await _cameraService.stopBuffer();

      // Clear buffer state (but keep preview texture)
      _bufferStartTime = null;
      _bufferSeconds = 0;
      _bufferRemainingSeconds = 0;

      _cameraMode = CameraMode.idle;
      notifyListeners();

      debugPrint('✅ Buffer stopped - encoders off, preview still on');
    } catch (e, stackTrace) {
      debugPrint('Failed to stop buffer: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  Future<void> startRecording() async {
    if (!_isInitialized) {
      debugPrint('Cannot start recording: not initialized');
      return;
    }

    // CRITICAL: Recording only works when buffering is active
    // This is required for DVR-style pre-roll recording
    if (_cameraMode != CameraMode.buffering) {
      debugPrint(
          'Cannot start recording: buffer must be active first (current mode: $_cameraMode)');
      _lastRecordingError =
          'Start buffer first to enable recording with pre-roll';
      notifyListeners();
      return;
    }

    // Prevent double-taps while preparing
    if (_isPreparingRecording) {
      debugPrint('Already preparing to record, ignoring tap');
      return;
    }

    try {
      _isPreparingRecording = true;
      notifyListeners();

      await _cameraService.startRecording();
      // State will be updated by recordingStarted event
    } on PlatformException catch (e) {
      debugPrint('Failed to start recording: ${e.code} - ${e.message}');
      _isPreparingRecording = false;

      // Handle storage-specific errors
      if (e.code == 'INSUFFICIENT_STORAGE') {
        _lastRecordingError = e.message ??
            'Not enough storage to safely record. Try reducing resolution, frame rate, or buffer duration.';
        _storageErrorMessage = _lastRecordingError;
        _isStorageLow = true;
        _storageMode = StorageMode.low;
      } else if (e.code == 'BUFFER_NOT_ACTIVE') {
        _lastRecordingError =
            'Start buffer first to enable recording with pre-roll';
      } else if (e.code == 'EXPORT_IN_PROGRESS') {
        _lastRecordingError = 'Previous recording is still being saved';
      } else {
        _lastRecordingError = e.message ?? 'Failed to start recording';
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to start recording: $e');
      _isPreparingRecording = false;

      // Parse error message for user-friendly feedback
      final errorStr = e.toString();
      if (errorStr.contains('BUFFER_NOT_ACTIVE')) {
        _lastRecordingError =
            'Start buffer first to enable recording with pre-roll';
      } else if (errorStr.contains('EXPORT_IN_PROGRESS')) {
        _lastRecordingError = 'Previous recording is still being saved';
      } else if (errorStr.contains('INSUFFICIENT_STORAGE')) {
        _lastRecordingError =
            'Not enough storage to safely record. Try reducing resolution, frame rate, or buffer duration.';
        _storageErrorMessage = _lastRecordingError;
        _isStorageLow = true;
      } else {
        _lastRecordingError = 'Failed to start recording';
      }
      notifyListeners();
    }
  }

  Future<void> stopRecording() async {
    if (_cameraMode != CameraMode.recording) return;

    // Optimistically transition to processing to prevent double-taps
    _cameraMode = CameraMode.processing;
    notifyListeners();

    try {
      await _cameraService.stopRecording();
      _showAdIfNeeded();
    } catch (e) {
      debugPrint('Failed to stop recording: $e');
      // If native side says no recording exists, force state reset
      if (e.toString().contains('NO_RECORDING')) {
        _cameraMode = CameraMode.buffering;
        notifyListeners();
      } else {
        // On other errors, also reset to buffering to avoid getting stuck
        _cameraMode = CameraMode.buffering;
        notifyListeners();
      }
    }
  }

  Future<void> switchCamera() async {
    await _cameraService.switchCamera();
    // Reset zoom level when switching cameras
    print('🔄 Resetting zoom to 1.0 after camera switch');
    _zoomLevel = 1.0;
    notifyListeners();
    // Fetch max zoom for the new camera
    try {
      final maxZoom = await _cameraService.getMaxZoom();
      print('📷 New camera max zoom: $maxZoom');
      _maxZoom = maxZoom;
      notifyListeners();
    } catch (e) {
      print('❌ Error getting max zoom for new camera: $e');
    }
  }

  Future<void> toggleFlash() async {
    _flashMode = _flashMode == 'off' ? 'on' : 'off';
    await _cameraService.setFlashMode(_flashMode);
    notifyListeners();
  }

  /// Mark camera instructions as seen (persisted)
  Future<void> markCameraInstructionsSeen() async {
    final currentSettings = _settingsService.settings;
    if (!currentSettings.hasSeenCameraInstructions) {
      await updateSettings(
        currentSettings.copyWith(hasSeenCameraInstructions: true),
      );
    }
  }

  /// Check if user has seen camera instructions
  bool get hasSeenCameraInstructions =>
      _settingsService.settings.hasSeenCameraInstructions;

  /// Mark trial popup as seen (for current session only - not persisted)
  /// This is no longer used since we show the popup every app launch
  Future<void> markTrialPopupSeen() async {
    // No longer persist - popup shows every app launch for free users
  }

  /// Check if user has seen trial popup (not used anymore)
  bool get hasSeenTrialPopup => false;

  /// Check if we should show trial popup
  /// Shows every app launch for users who don't have Pro access (paid or trial)
  bool get shouldShowTrialPopup {
    // Don't show if user already has Pro (paid subscription)
    if (isPro) return false;
    // Don't show if user is in active trial
    if (isTrialActive) return false;
    // Show for all other users (free users who can start trial)
    return true;
  }

  Future<void> updateSettings(AppSettings settings) async {
    final normalizedSettings = settings.copyWith(
      resolution: settings.resolution.toUpperCase(),
      updatedAt: DateTime.now(),
    );

    final resolvedResolution =
        _resolveResolutionForCamera(normalizedSettings.resolution);
    final resolvedFps = _resolveFpsForCamera(normalizedSettings.fps);

    await _settingsService.updateSettings(normalizedSettings);
    await _cameraService.updateSettings(
      resolution: resolvedResolution,
      fps: resolvedFps,
      codec: 'H.264',
      preRollSeconds: normalizedSettings.preRollSeconds,
      stabilization: normalizedSettings.stabilization,
    );

    notifyListeners();
  }

  String _resolveResolutionForCamera(String requestedResolution) {
    final normalized = requestedResolution.toUpperCase();

    if (!isPro && normalized == '4K') {
      return '1080P';
    }

    final caps = _deviceService.capabilities;
    if (normalized == '4K' && caps != null && !caps.supports4K) {
      return '1080P';
    }

    return normalized;
  }

  int _resolveFpsForCamera(int requestedFps) {
    if (!isPro && requestedFps == 60) {
      return 30;
    }
    return requestedFps;
  }

  Future<bool> purchasePro(String tier) async {
    final success = await _subscriptionService.purchaseSubscription(tier);
    if (success) {
      notifyListeners();
    }
    return success;
  }

  Future<bool> restorePurchases() async {
    final success = await _subscriptionService.restorePurchases();
    if (success) {
      notifyListeners();
    }
    return success;
  }

  Future<void> deleteVideo(String id) async {
    await _storageService.deleteVideo(id);
    notifyListeners();
  }

  Future<bool> refreshPermissions() async {
    final granted = await _ensureRequiredPermissions();
    if (granted && !_phase2Complete && !_isInitializing) {
      // Re-trigger Phase 2 if permissions were just granted
      _initializePhase2();
    }
    return granted;
  }

  bool get isInitialized => _isInitialized;
  // Note: isCameraReady is defined earlier in the class with the phase tracking
  bool get isInitializing => _isInitializing;
  bool get permissionsGranted => _permissionsGranted;
  bool get permissionsPermanentlyDenied => _permissionsPermanentlyDenied;
  String? get initializationError => _initializationError;
  CameraMode get cameraMode => _cameraMode;
  bool get isRecording => _cameraMode == CameraMode.recording;
  bool get isFinalizing => _cameraMode == CameraMode.processing;
  bool get isBuffering => _cameraMode == CameraMode.buffering;
  bool get isIdle => _cameraMode == CameraMode.idle;
  int get bufferSeconds => _bufferSeconds;
  String get flashMode => _flashMode;
  double get finalizeProgress => _finalizeProgress;
  int? get previewTextureId => _previewTextureId;

  /// Returns true if user has Pro access (paid subscription OR active trial)
  bool get isPro => _subscriptionService.hasProAccess;
  SubscriptionService get subscriptionService => _subscriptionService;
  AppSettings get settings => _settingsService.settings;
  DeviceCapabilities? get deviceCapabilities => _deviceService.capabilities;
  DeviceService get deviceService => _deviceService;
  List<VideoRecording> get videos => _storageService.getVideos();
  VideoRecording? get latestVideo => _storageService.latestVideo;
  bool get isProUser => _isProUser;
  int get bufferDuration => _bufferDuration;
  DateTime? get bufferStartTime => _bufferStartTime;

  // Trial-related getters
  bool get hasProAccess => _subscriptionService.hasProAccess;
  bool get isTrialActive => _subscriptionService.isTrialActive;
  bool get trialUsed => _subscriptionService.trialUsed;
  int get trialDaysRemaining => _subscriptionService.trialDaysRemaining;
  bool get canStartTrial => _subscriptionService.canStartTrial;

  /// Get and clear the last recording error (returns null if no error)
  String? consumeRecordingError() {
    final error = _lastRecordingError;
    _lastRecordingError = null;
    return error;
  }

  /// Get and clear the max duration reached message (returns null if no message)
  String? consumeMaxDurationMessage() {
    final message = _maxDurationReachedMessage;
    _maxDurationReachedMessage = null;
    return message;
  }

  /// Returns true if recording is being prepared (after tap, before recording starts)
  bool get isPreparingRecording => _isPreparingRecording;

  double get zoomLevel => _zoomLevel;
  double get maxZoom => _maxZoom;

  Future<void> setZoom(double zoom) async {
    try {
      debugPrint('🔍 setZoom called: requested=$zoom, maxZoom=$_maxZoom');
      final clampedZoom = zoom.clamp(1.0, _maxZoom);
      debugPrint('🔍 setZoom: clamped=$clampedZoom, calling native...');
      final actualZoom = await _cameraService.setZoom(clampedZoom);
      debugPrint('🔍 setZoom: received actualZoom=$actualZoom from native');
      _zoomLevel = actualZoom;
      notifyListeners();
      debugPrint('✅ Zoom set to: $_zoomLevel');
    } catch (e) {
      debugPrint('❌ Failed to set zoom: $e');
    }
  }

  Future<void> updateSubscription({required bool isProUser}) async {
    if (_isProUser != isProUser) {
      _isProUser = isProUser;
      _bufferDuration = isProUser ? 10 : 5;

      // Update camera service with new subscription status
      await _cameraService.updateSubscription(isProUser: isProUser);

      debugPrint(
          'Subscription updated: pro=$isProUser, buffer=${_bufferDuration}s');
      notifyListeners();
    }
  }

  /// Fetches debug information from the native plugin (developer only)
  Future<DebugInfo> getDebugInfo() async {
    try {
      final debugData = await _cameraService.getDebugInfo();
      return DebugInfo.fromMap(debugData);
    } catch (e) {
      debugPrint('Failed to fetch debug info: $e');
      return DebugInfo.empty();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // RATING & PAYWALL SERVICES
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Rating service for managing app rating prompts
  RatingService get ratingService => _ratingService;

  /// Paywall service for managing lifetime offer triggers
  PaywallService get paywallService => _paywallService;

  /// Check if buffer selection should trigger paywall (for free users)
  bool shouldShowPaywallForBuffer(int seconds) {
    if (isPro) return false;
    return _paywallService.shouldTriggerBufferPaywall(seconds);
  }

  /// Check if Day 3 paywall should be shown (call on app open)
  bool shouldShowDayThreePaywall() {
    if (isPro) return false;
    return _paywallService.shouldTriggerDayThreePaywall();
  }

  /// Record video saved and check for paywall/rating triggers
  /// Call this after a successful video save
  Future<void> onVideoSaved() async {
    // Record for rating service
    await _ratingService.recordVideoSaved();

    // Record for paywall service (only matters for free users)
    if (!isPro) {
      await _paywallService.recordVideoSaved();
    }

    debugPrint(
        '📊 Video saved tracked: rating=${_ratingService.savedVideoCount}, paywall=${_paywallService.savedVideoCount}');
  }

  /// Check if video save limit paywall should trigger (for free users)
  bool shouldShowVideoLimitPaywall() {
    if (isPro) return false;
    return _paywallService.shouldTriggerVideoLimitPaywall();
  }

  /// Check if rating popup should be shown after video save
  bool shouldShowRatingPopup() {
    // Don't show during recording, buffering, or processing
    if (_cameraMode != CameraMode.idle && _cameraMode != CameraMode.buffering) {
      return false;
    }
    return _ratingService.shouldShowRatingPopup();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _cameraService.dispose();
    _adService.dispose();
    _subscriptionService.dispose();
    _ratingService.dispose();
    _paywallService.dispose();
    super.dispose();
  }
}
