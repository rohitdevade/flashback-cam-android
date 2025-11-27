import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
import 'package:permission_handler/permission_handler.dart';

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

  // Dynamic buffer progress tracking
  DateTime? _bufferStartTime;
  Timer? _progressTimer;
  int _bufferRemainingSeconds = 0;

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

  AppState() {
    _subscriptionService = SubscriptionService();
    _deviceService = DeviceService(_cameraService);
    _initialize();
  }

  Future<void> _initialize() async {
    if (_isInitializing) {
      debugPrint(
          'Initialization already in progress, ignoring duplicate call.');
      return;
    }
    _isInitializing = true;
    try {
      await Future.wait([
        _storageService.initialize(),
        _subscriptionService.initialize(),
        _adService.initialize(),
        _settingsService.initialize(),
      ]);

      final hasPermissions = await _ensureRequiredPermissions();
      if (!hasPermissions) {
        debugPrint('Camera permissions not granted; camera setup skipped.');
        _isInitialized = false;
        _cameraMode = CameraMode.idle;
        return;
      }

      await _deviceService.detectCapabilities();

      _cameraService.eventStream.listen(_handleCameraEvent);

      // Resolve preferred settings before initializing camera
      final initialSettings = _settingsService.settings;
      final resolvedResolution =
          _resolveResolutionForCamera(initialSettings.resolution);
      final resolvedFps = _resolveFpsForCamera(initialSettings.fps);

      // Initialize camera and preview on startup (but not buffer)
      await _cameraService.initialize(
        resolution: resolvedResolution,
        fps: resolvedFps,
        codec: 'H.264',
        preRollSeconds: initialSettings.preRollSeconds,
        stabilization: initialSettings.stabilization,
      );

      debugPrint('Camera initialized, waiting for camera device to open...');

      // Wait for camera to fully open
      await Future.delayed(Duration(milliseconds: 800));

      debugPrint('Creating preview texture...');

      // Create camera preview texture
      _previewTextureId = await _cameraService.createPreview();

      if (_previewTextureId == null) {
        throw Exception('Failed to create preview texture');
      }

      debugPrint('Preview texture created: $_previewTextureId');
      notifyListeners(); // Update UI to show texture

      // Wait a bit longer for texture to be fully ready
      await Future.delayed(Duration(milliseconds: 200));

      // Start preview (this will create the capture session)
      debugPrint('Starting camera preview...');
      await _cameraService.startPreview();

      debugPrint('Preview started successfully');

      // Fetch max zoom from camera
      debugPrint('Fetching max zoom from camera...');
      _maxZoom = await _cameraService.getMaxZoom();
      debugPrint('🔍 Max zoom updated to: $_maxZoom');

      _initializationError = null;
      _isInitialized = true;
      _cameraMode = CameraMode.idle; // Start in IDLE state with preview ON
      notifyListeners();

      debugPrint('✅ App initialized in IDLE mode - preview ON, buffer OFF');
    } catch (e, stackTrace) {
      debugPrint('Failed to initialize app state: $e');
      debugPrint('Stack trace: $stackTrace');
      _initializationError = 'Failed to initialize camera: $e';
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<bool> _ensureRequiredPermissions() async {
    // Only request the core permissions needed to show the system prompt.
    // Storage/media access is handled later (e.g. when exporting videos).
    final permissions = [Permission.camera, Permission.microphone];
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
      if (status.isPermanentlyDenied) {
        permanentlyDenied = true;
      }
      if (!status.isGranted) {
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
          debugPrint('Recording error: $error');
          _cameraMode = CameraMode.buffering;
          notifyListeners();
          break;
        case 'thermalWarning':
          debugPrint('Thermal warning: ${event['message']}');
          break;
        case 'lowStorage':
          debugPrint('Low storage warning');
          break;
        case 'recovered':
          debugPrint('Recovered video: ${event['video']}');
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

  Future<void> startBuffer() async {
    if (!_isInitialized || _cameraMode != CameraMode.idle) return;

    try {
      debugPrint('Starting buffer: starting encoders...');

      // Start buffer (preview already running)
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
    if (!_isInitialized || _cameraMode != CameraMode.buffering) {
      debugPrint('Cannot start recording: camera mode is $_cameraMode');
      return;
    }
    try {
      await _cameraService.startRecording();
      // State will be updated by recordingStarted event
    } catch (e) {
      debugPrint('Failed to start recording: $e');
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
    if (granted && !_isInitialized && !_isInitializing) {
      await _initialize();
    }
    return granted;
  }

  bool get isInitialized => _isInitialized;
  bool get isCameraReady =>
      _permissionsGranted &&
      _initializationError == null &&
      _previewTextureId != null &&
      _isInitialized;
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
  bool get isPro => _subscriptionService.isPro;
  SubscriptionService get subscriptionService => _subscriptionService;
  AppSettings get settings => _settingsService.settings;
  DeviceCapabilities? get deviceCapabilities => _deviceService.capabilities;
  DeviceService get deviceService => _deviceService;
  List<VideoRecording> get videos => _storageService.getVideos();
  VideoRecording? get latestVideo => _storageService.latestVideo;
  bool get isProUser => _isProUser;
  int get bufferDuration => _bufferDuration;
  DateTime? get bufferStartTime => _bufferStartTime;
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

  @override
  void dispose() {
    _progressTimer?.cancel();
    _cameraService.dispose();
    _adService.dispose();
    _subscriptionService.dispose();
    super.dispose();
  }
}
