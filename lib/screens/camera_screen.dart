import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:flashback_cam/providers/app_state.dart';
import 'package:flashback_cam/models/app_settings.dart';
import 'package:flashback_cam/theme.dart';
import 'package:flashback_cam/widgets/glass_container.dart';
import 'package:flashback_cam/widgets/mode_chip.dart';
import 'package:flashback_cam/widgets/record_button.dart';
import 'package:flashback_cam/widgets/video_thumbnail.dart';
import 'package:flashback_cam/widgets/debug_info_panel.dart';
import 'package:flashback_cam/widgets/camera_instructions_overlay.dart';
import 'package:flashback_cam/widgets/rating_popup.dart';
import 'package:flashback_cam/widgets/buffer_duration_selector.dart';
import 'package:flashback_cam/widgets/persistent_bottom_bar.dart';
import 'package:flashback_cam/screens/gallery_screen.dart';
import 'package:flashback_cam/screens/settings_screen.dart';
import 'package:flashback_cam/screens/lifetime_paywall_screen.dart';
import 'package:flashback_cam/services/paywall_service.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin {
  double _baseZoomLevel = 1.0;
  Map<String, bool> _capabilities = {};
  bool _capabilitiesLoaded = false;
  bool _showInstructions = false;
  bool _showInstructionsManual = false; // Triggered from bottom bar
  bool _instructionsChecked = false;
  bool _lowMemoryWarningShown = false;
  bool _dayThreePaywallChecked = false;
  int _lastVideoCount = 0;

  // Focus indicator state
  Offset? _focusPoint;
  Offset? _pendingFocusPoint;
  bool _showFocusIndicator = false;
  bool _isFocusLocked = false;
  late AnimationController _focusAnimationController;
  late Animation<double> _focusAnimation;

  @override
  void initState() {
    super.initState();
    // COLD START: Don't enable wakelock until buffer starts
    _loadCapabilities();

    // Initialize focus animation
    _focusAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _focusAnimation = Tween<double>(begin: 1.5, end: 1.0).animate(
      CurvedAnimation(parent: _focusAnimationController, curve: Curves.easeOut),
    );

    // Check for Day 3 paywall after a short delay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkDayThreePaywall();
    });
  }

  /// Check if we should show instructions (only once after AppState is initialized)
  void _checkShowInstructions(AppState appState) {
    if (_instructionsChecked) return;
    if (!appState.isInitialized) return;

    _instructionsChecked = true;
    if (!appState.hasSeenCameraInstructions) {
      setState(() => _showInstructions = true);
    }

    // Check for low memory warning (less than 4GB = 4096MB)
    _checkLowMemoryWarning(appState);
  }

  void _checkLowMemoryWarning(AppState appState) {
    if (_lowMemoryWarningShown) return;

    final deviceCaps = appState.deviceCapabilities;
    if (deviceCaps != null && deviceCaps.ramMB < 4096) {
      _lowMemoryWarningShown = true;
      // Show warning after a short delay to not overlap with instructions
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_showInstructions) {
          _showLowMemoryWarning(deviceCaps.ramMB);
        }
      });
    }
  }

  void _showLowMemoryWarning(int ramMB) {
    final ramGB = (ramMB / 1024).toStringAsFixed(1);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.memory, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Low memory detected (${ramGB}GB). For best performance, use shorter buffer times.',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 5),
        backgroundColor: AppColors.warningOrange,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Check for recording errors and show them to the user
  void _checkRecordingErrors(AppState appState) {
    // Use post-frame callback to avoid showing snackbar during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final error = appState.consumeRecordingError();
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(error, style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
            backgroundColor: AppColors.recordRed,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }

      // Check for max duration reached message
      final maxDurationMessage = appState.consumeMaxDurationMessage();
      if (maxDurationMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.timer_off, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    maxDurationMessage,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 5),
            backgroundColor: AppColors.warningOrange,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    });
  }

  /// Check for Day 3 paywall trigger
  void _checkDayThreePaywall() {
    if (_dayThreePaywallChecked) return;
    _dayThreePaywallChecked = true;

    final appState = context.read<AppState>();

    // Only show for free users, and not on first launch
    if (appState.isPro) return;
    if (appState.paywallService.isFirstLaunchDay) return;

    // Check if Day 3 paywall should trigger
    if (appState.shouldShowDayThreePaywall()) {
      // Show paywall after a short delay to let the camera initialize
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        _showLifetimePaywall(appState, PaywallTrigger.dayThree);
      });
    }
  }

  /// Check for video save triggers (rating popup or paywall)
  void _checkVideoSaveTriggers(AppState appState) {
    final currentVideoCount = appState.videos.length;

    // Check if a new video was added
    if (currentVideoCount > _lastVideoCount) {
      _lastVideoCount = currentVideoCount;

      // Don't show popups during recording/processing
      if (appState.isRecording || appState.isFinalizing) return;

      // Schedule popup check after a short delay (1-2 seconds after save)
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;

        // Re-check state hasn't changed
        final currentState = context.read<AppState>();
        if (currentState.isRecording || currentState.isFinalizing) return;

        // Check paywall first (for free users)
        if (!currentState.isPro && currentState.shouldShowVideoLimitPaywall()) {
          _showLifetimePaywall(currentState, PaywallTrigger.videoSaveLimit);
          return;
        }

        // Then check rating popup
        if (currentState.shouldShowRatingPopup()) {
          _showRatingPopup(currentState);
        }
      });
    }
  }

  /// Show the rating popup
  Future<void> _showRatingPopup(AppState appState) async {
    final result = await showRatingPopup(context);

    if (result == true) {
      // High rating (4-5 stars) -> trigger Google Play in-app review
      await appState.ratingService.markAsRated();
      _triggerInAppReview();
    } else if (result == false) {
      // Low rating (1-3 stars) -> just mark as rated, don't open Play Store
      await appState.ratingService.markAsRated();
    } else {
      // Dismissed -> mark dismissed for 5-day cooldown
      await appState.ratingService.markDismissed();
    }
  }

  /// Trigger Google Play in-app review
  Future<void> _triggerInAppReview() async {
    try {
      final inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();
        debugPrint('✅ In-app review requested');
      } else {
        debugPrint('⚠️ In-app review not available');
      }
    } catch (e) {
      debugPrint('❌ Failed to request in-app review: $e');
    }
  }

  /// Show lifetime paywall
  void _showLifetimePaywall(AppState appState, PaywallTrigger trigger) {
    appState.paywallService.requestPaywall(trigger);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LifetimePaywallScreen()),
    );
  }

  /// Open paywall for locked pro features (4K/60fps)
  void _openPaywall(BuildContext context) {
    final appState = context.read<AppState>();
    _showLifetimePaywall(appState, PaywallTrigger.proFeatureTap);
  }

  Future<void> _loadCapabilities() async {
    final appState = context.read<AppState>();
    final capabilities =
        await appState.cameraService.checkDetailedCapabilities();
    if (mounted) {
      setState(() {
        _capabilities = capabilities;
        _capabilitiesLoaded = true;
      });
    }
  }

  @override
  void dispose() {
    // Allow screen to turn off when leaving camera
    WakelockPlus.disable();
    _focusAnimationController.dispose();
    super.dispose();
  }

  Future<void> _showDebugPanel() async {
    print('🐛 DEBUG PANEL OPENING NOW!');

    final appState = context.read<AppState>();

    // Show a snackbar to confirm
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '🐛 Debug Panel Opening...',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Add delay to ensure snackbar is visible
    await Future.delayed(Duration(milliseconds: 300));

    final debugInfo = await appState.getDebugInfo();

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black87,
      isDismissible: true,
      enableDrag: true,
      elevation: 16,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Colors.orange, width: 3),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => DebugInfoPanel(
          debugInfo: debugInfo,
          scrollController: scrollController,
          onRefresh: () async {
            await appState.getDebugInfo();
            if (context.mounted) {
              Navigator.pop(context);
              _showDebugPanel();
            }
          },
        ),
      ),
    );

    print('🐛 Debug panel closed');
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = appState.settings;

    // Check if we should show instructions (after AppState is initialized)
    _checkShowInstructions(appState);

    // Check for and display any recording errors
    _checkRecordingErrors(appState);

    // Check for video save triggers (rating popup or paywall)
    _checkVideoSaveTriggers(appState);

    return OrientationBuilder(
      builder: (context, orientation) {
        final isPortraitLayout = orientation == Orientation.portrait;

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // Camera preview (non-interactive background)
              Container(
                width: double.infinity,
                height: double.infinity,
                child: Stack(
                  children: [
                    CameraPreview(isDark: isDark),
                    if (settings.showGrid) GridOverlay(),
                  ],
                ),
              ),
              // Tap to focus and zoom gesture detector
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    // Store tap position immediately
                    _pendingFocusPoint = details.localPosition;
                  },
                  onTapUp: (details) {
                    // Use the stored position for focus
                    if (_pendingFocusPoint != null) {
                      _handleTapToFocus(
                        TapUpDetails(
                          kind: details.kind,
                          localPosition: _pendingFocusPoint!,
                          globalPosition: details.globalPosition,
                        ),
                        appState,
                      );
                    }
                    _pendingFocusPoint = null;
                  },
                  onTapCancel: () {
                    _pendingFocusPoint = null;
                  },
                  onLongPressStart: (details) {
                    _pendingFocusPoint = details.localPosition;
                    _handleLongPressToLockFocus(
                        appState, details.localPosition);
                  },
                  onDoubleTap: () => _handleDoubleTapToUnlockFocus(appState),
                  onScaleStart: (details) {
                    if (details.pointerCount > 1) {
                      _pendingFocusPoint = null; // Cancel any pending focus
                      _baseZoomLevel = appState.zoomLevel;
                      print(
                        '🔍 Scale gesture started: base zoom = $_baseZoomLevel',
                      );
                    }
                  },
                  onScaleUpdate: (details) {
                    if (details.pointerCount > 1) {
                      final newZoom = (_baseZoomLevel * details.scale).clamp(
                        1.0,
                        appState.maxZoom,
                      );
                      print(
                        '🔍 Scale gesture update: scale=${details.scale}, newZoom=$newZoom',
                      );
                      appState.setZoom(newZoom);
                    }
                  },
                  onScaleEnd: (details) {
                    print('🔍 Scale gesture ended');
                  },
                  child: Container(color: Colors.transparent),
                ),
              ),
              // Focus indicator
              if (_showFocusIndicator && _focusPoint != null)
                Positioned(
                  left: _focusPoint!.dx - 40,
                  top: _focusPoint!.dy - 40,
                  child: AnimatedBuilder(
                    animation: _focusAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _focusAnimation.value,
                        child: FocusIndicator(isLocked: _isFocusLocked),
                      );
                    },
                  ),
                ),
              // UI controls - pointer events enabled for buttons
              SafeArea(
                child: isPortraitLayout
                    ? _buildPortraitChrome(appState, settings)
                    : _buildLandscapeChrome(appState, settings),
              ),
              // Zoom level indicator
              if (appState.zoomLevel > 1.01)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 80,
                  left: 0,
                  right: 0,
                  child: Center(child: ZoomIndicator(zoom: appState.zoomLevel)),
                ),
              // Camera instructions overlay (shown on first launch)
              if (_showInstructions)
                CameraInstructionsOverlay(
                  onDismiss: () {
                    setState(() => _showInstructions = false);
                    appState.markCameraInstructionsSeen();
                  },
                  onDontShowAgain: () {
                    appState.markCameraInstructionsSeen();
                  },
                  showDontShowAgain: true,
                ),
              // Camera instructions overlay (manual trigger from bottom bar)
              if (_showInstructionsManual)
                CameraInstructionsOverlay(
                  onDismiss: () {
                    setState(() => _showInstructionsManual = false);
                  },
                  showDontShowAgain: false,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPortraitChrome(AppState appState, AppSettings settings) {
    final hideTopControls = appState.isBuffering || appState.isRecording;

    return Column(
      children: [
        if (!hideTopControls)
          Padding(
            padding: const EdgeInsets.only(
              left: 20,
              right: 20,
              top: 8,
              bottom: 20,
            ),
            child: TopControls(
              selectedResolution: settings.resolution.toUpperCase(),
              selectedFps: settings.fps,
              onResolutionChanged: (value) {
                _updateSettings(appState, resolution: value);
              },
              onFpsChanged: (value) {
                _updateSettings(appState, fps: value);
              },
              isPro: appState.isPro,
              onDebugLongPress: _showDebugPanel,
              capabilities: _capabilities,
              capabilitiesLoaded: _capabilitiesLoaded,
              onLockedTap: () => _openPaywall(context),
              isLowMemoryDevice: appState.isLowMemoryDevice,
            ),
          ),
        const Spacer(),
        // Rewarded buffer unlock badge
        if (appState.hasRewardedBufferUnlock)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: RewardedBufferBadge(
              duration: appState.rewardedBufferUnlock!,
            ),
          ),
        if (appState.isFinalizing)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: FinalizingIndicator(progress: appState.finalizeProgress),
          ),
        _buildBottomControls(appState, isPortrait: true),
        const SizedBox(height: 16),
        // Persistent bottom navigation bar
        PersistentBottomBar(
          onHowItWorksTap: () {
            setState(() => _showInstructionsManual = true);
          },
          onShowPaywall: () => _openPaywall(context),
          selectedBufferSeconds: appState.selectedBufferSeconds,
          isBuffering: appState.isBuffering,
          isRecording: appState.isRecording,
          isFinalizing: appState.isFinalizing,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildLandscapeChrome(AppState appState, AppSettings settings) {
    final hideTopControls = appState.isBuffering || appState.isRecording;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!hideTopControls)
                  TopControls(
                    selectedResolution: settings.resolution.toUpperCase(),
                    selectedFps: settings.fps,
                    onResolutionChanged: (value) {
                      _updateSettings(appState, resolution: value);
                    },
                    onFpsChanged: (value) {
                      _updateSettings(appState, fps: value);
                    },
                    isPro: appState.isPro,
                    onDebugLongPress: _showDebugPanel,
                    capabilities: _capabilities,
                    capabilitiesLoaded: _capabilitiesLoaded,
                    onLockedTap: () => _openPaywall(context),
                    isLowMemoryDevice: appState.isLowMemoryDevice,
                  ),
                const Spacer(),
                // Rewarded buffer unlock badge
                if (appState.hasRewardedBufferUnlock)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: RewardedBufferBadge(
                      duration: appState.rewardedBufferUnlock!,
                    ),
                  ),
                if (appState.isFinalizing)
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: FinalizingIndicator(
                      progress: appState.finalizeProgress,
                    ),
                  ),
                // Persistent bottom bar in landscape (positioned at bottom left)
                PersistentBottomBar(
                  onHowItWorksTap: () {
                    setState(() => _showInstructionsManual = true);
                  },
                  onShowPaywall: () => _openPaywall(context),
                  selectedBufferSeconds: appState.selectedBufferSeconds,
                  isBuffering: appState.isBuffering,
                  isRecording: appState.isRecording,
                  isFinalizing: appState.isFinalizing,
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          _buildBottomControls(appState, isPortrait: false),
        ],
      ),
    );
  }

  Widget _buildBottomControls(AppState appState, {required bool isPortrait}) {
    return BottomControls(
      isPortrait: isPortrait,
      isCameraReady: appState.isCameraReady,
      cameraMode: appState.cameraMode,
      isRecording: appState.isRecording,
      isPreparingRecording: appState.isPreparingRecording,
      onRecordTap: () => appState.isRecording
          ? appState.stopRecording()
          : appState.startRecording(),
      onBufferToggle: () =>
          appState.isBuffering ? appState.stopBuffer() : appState.startBuffer(),
      bufferProgress: appState.bufferProgress,
      selectedBufferSeconds: appState.selectedBufferSeconds,
      bufferRemainingSeconds: appState.bufferRemainingSeconds,
      latestVideo: appState.latestVideo,
      onGalleryTap: () => _openGallery(appState),
      flashMode: appState.flashMode,
      onFlashTap: () => appState.toggleFlash(),
    );
  }

  void _updateSettings(AppState appState, {String? resolution, int? fps}) {
    final currentSettings = appState.settings;
    appState.updateSettings(
      currentSettings.copyWith(
        resolution: resolution ?? currentSettings.resolution,
        fps: fps ?? currentSettings.fps,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // FOCUS CONTROL - Tap to focus and focus lock
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Handle tap to focus at a point
  void _handleTapToFocus(TapUpDetails details, AppState appState) {
    if (!appState.isCameraReady) return;

    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final localPosition = details.localPosition;
    final size = box.size;

    // Convert to normalized coordinates (0.0 - 1.0)
    final normalizedX = localPosition.dx / size.width;
    final normalizedY = localPosition.dy / size.height;

    print('📍 Tap to focus at: ($normalizedX, $normalizedY)');

    // Show focus indicator
    setState(() {
      _focusPoint = localPosition;
      _showFocusIndicator = true;
      _isFocusLocked = false;
    });

    // Start animation
    _focusAnimationController.reset();
    _focusAnimationController.forward();

    // Call native focus
    appState.cameraService.setFocusPoint(normalizedX, normalizedY);

    // Hide indicator after a delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && !_isFocusLocked) {
        setState(() {
          _showFocusIndicator = false;
        });
      }
    });
  }

  /// Handle long press to lock focus at current point
  void _handleLongPressToLockFocus(AppState appState, Offset position) {
    if (!appState.isCameraReady) return;

    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final size = box.size;
    final normalizedX = position.dx / size.width;
    final normalizedY = position.dy / size.height;

    print('🔒 Lock focus at: ($normalizedX, $normalizedY)');

    setState(() {
      _focusPoint = position;
      _isFocusLocked = true;
      _showFocusIndicator = true;
    });

    // Animate to locked state
    _focusAnimationController.reset();
    _focusAnimationController.forward();

    // Call native lock focus
    appState.cameraService.lockFocus(x: normalizedX, y: normalizedY);

    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.lock, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Focus locked. Double-tap to unlock.'),
          ],
        ),
        duration: Duration(seconds: 2),
        backgroundColor: AppColors.electricBlue,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Handle double tap to unlock focus
  void _handleDoubleTapToUnlockFocus(AppState appState) {
    if (!_isFocusLocked) return;

    print('🔓 Unlock focus');

    setState(() {
      _isFocusLocked = false;
      _showFocusIndicator = false;
    });

    // Call native unlock focus
    appState.cameraService.unlockFocus();

    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.lock_open, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Focus unlocked'),
          ],
        ),
        duration: Duration(seconds: 1),
        backgroundColor: AppColors.textSecondary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _openGallery(AppState appState) async {
    if (appState.isRecording) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Stop recording before opening the gallery.'),
        ),
      );
      return;
    }

    // Stop buffer before opening gallery (won't auto-resume)
    if (appState.isBuffering) {
      await appState.stopBuffer();
    }

    // Show interstitial ad (not every time - managed by AdService)
    await appState.showGalleryAd();

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GalleryScreen()),
    );

    // Buffer stays stopped after returning from gallery - user must restart manually
  }
}

class CameraPreview extends StatelessWidget {
  final bool isDark;

  const CameraPreview({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final textureId = appState.previewTextureId;
    final error = appState.initializationError;

    if (error != null) {
      final permanentlyDenied = appState.permissionsPermanentlyDenied;
      return CameraStatusMessage(
        icon: Icons.lock_outline,
        title: 'Camera Access Needed',
        message: error,
        actionLabel: permanentlyDenied ? 'Open Settings' : 'Grant Access',
        onAction: () async {
          if (permanentlyDenied) {
            await openAppSettings();
            return;
          }

          final messenger = ScaffoldMessenger.maybeOf(context);
          final granted = await appState.refreshPermissions();

          if (!granted && messenger != null) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'Still missing camera or microphone permissions. Please approve the system prompt.',
                ),
                action: SnackBarAction(
                  label: 'Settings',
                  onPressed: () => openAppSettings(),
                ),
              ),
            );
          }
        },
      );
    }

    // Show preview when texture is available (regardless of buffer state)
    if (textureId != null) {
      return Center(
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: Texture(textureId: textureId),
        ),
      );
    }

    // Show feature carousel while camera initializes
    return FeatureHighlightCarousel(isDark: isDark);
  }
}

/// Feature highlight carousel shown during cold start
class FeatureHighlightCarousel extends StatefulWidget {
  final bool isDark;

  const FeatureHighlightCarousel({super.key, required this.isDark});

  @override
  State<FeatureHighlightCarousel> createState() =>
      _FeatureHighlightCarouselState();
}

class _FeatureHighlightCarouselState extends State<FeatureHighlightCarousel> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _autoPlayTimer;

  final List<Map<String, dynamic>> _features = [
    {
      'icon': Icons.video_library_rounded,
      'title': 'Capture Perfect Moments',
      'description':
          'Record moments that already happened with intelligent buffer',
      'color': AppColors.electricBlue,
    },
    {
      'icon': Icons.timer_outlined,
      'title': 'Smart Buffer Recording',
      'description': 'Tap pinch to zoom while recording for better shots',
      'color': AppColors.successGreen,
    },
    {
      'icon': Icons.hd_rounded,
      'title': 'High Quality Videos',
      'description': 'Record in up to 1080p at 60fps with stabilization',
      'color': AppColors.warningOrange,
    },
    {
      'icon': Icons.flash_on_rounded,
      'title': 'Pro Features Available',
      'description': 'Unlock longer buffers and unlimited recordings',
      'color': AppColors.proGold,
    },
  ];

  @override
  void initState() {
    super.initState();
    // Auto-advance every 3 seconds
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && _pageController.hasClients) {
        final nextPage = (_currentPage + 1) % _features.length;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            widget.isDark ? AppColors.deepCharcoal : AppColors.glassWhite,
            widget.isDark ? Color(0xFF1E2A3A) : Color(0xFFE0E8F0),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Feature carousel
            SizedBox(
              height: 280,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemCount: _features.length,
                itemBuilder: (context, index) {
                  final feature = _features[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Icon
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (feature['color'] as Color).withOpacity(0.2),
                            border: Border.all(
                              color: feature['color'] as Color,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            feature['icon'] as IconData,
                            size: 40,
                            color: feature['color'] as Color,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Title
                        Text(
                          feature['title'] as String,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color:
                                widget.isDark ? Colors.white : Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        // Description
                        Text(
                          feature['description'] as String,
                          style: TextStyle(
                            fontSize: 16,
                            color: widget.isDark
                                ? Colors.white.withOpacity(0.7)
                                : Colors.black54,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),
            // Page indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _features.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: _currentPage == index
                        ? AppColors.electricBlue
                        : (widget.isDark ? Colors.white : Colors.black)
                            .withOpacity(0.3),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Subtle loading indicator
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(
                  (widget.isDark ? Colors.white : Colors.black)
                      .withOpacity(0.3),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Preparing camera...',
              style: TextStyle(
                fontSize: 12,
                color: (widget.isDark ? Colors.white : Colors.black)
                    .withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GridOverlay extends StatelessWidget {
  const GridOverlay({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(size: Size.infinite, painter: GridPainter()),
      );
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    final hStep = size.height / 3;
    final vStep = size.width / 3;

    for (int i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(0, hStep * i),
        Offset(size.width, hStep * i),
        paint,
      );
      canvas.drawLine(
        Offset(vStep * i, 0),
        Offset(vStep * i, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(GridPainter oldDelegate) => false;
}

class TopControls extends StatelessWidget {
  final String selectedResolution;
  final int selectedFps;
  final Function(String) onResolutionChanged;
  final Function(int) onFpsChanged;
  final bool isPro;
  final VoidCallback onDebugLongPress;
  final Map<String, bool> capabilities;
  final bool capabilitiesLoaded;
  final VoidCallback? onLockedTap;
  final bool isLowMemoryDevice;

  const TopControls({
    super.key,
    required this.selectedResolution,
    required this.selectedFps,
    required this.onResolutionChanged,
    required this.onFpsChanged,
    required this.isPro,
    required this.onDebugLongPress,
    required this.capabilities,
    required this.capabilitiesLoaded,
    this.onLockedTap,
    this.isLowMemoryDevice = false,
  });

  @override
  Widget build(BuildContext context) {
    // Determine capability states
    final supports4K = capabilitiesLoaded && capabilities['supports4K'] == true;
    final supports1080p60fps =
        capabilitiesLoaded && capabilities['supports1080p60fps'] == true;
    final supports4K60fps =
        capabilitiesLoaded && capabilities['supports4K60fps'] == true;

    // Determine if 60fps is supported for current resolution
    final supports60fps =
        selectedResolution == '1080P' ? supports1080p60fps : supports4K60fps;

    // LOW-MEMORY MODE: Hide high-res and high-fps options entirely on ≤4GB devices
    final show1080P = !isLowMemoryDevice;
    final show4K = !isLowMemoryDevice;
    final show60fps = !isLowMemoryDevice;

    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SettingsScreen()),
          ),
          onLongPress: onDebugLongPress,
          child: GlassContainer(
            padding: EdgeInsets.all(12),
            child: Icon(Icons.settings, color: Colors.white, size: 24),
          ),
        ),
        SizedBox(width: 12),
        // Make the chips horizontally scrollable to avoid overflow on small screens
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: BouncingScrollPhysics(),
            child: Row(
              children: [
                GlassContainer(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // LOW-MEMORY MODE: Show 720P as the only/default option
                      if (isLowMemoryDevice)
                        ModeChip(
                          label: '720P',
                          isSelected: true,
                          onTap: () => onResolutionChanged('720P'),
                        ),
                      if (show1080P)
                        ModeChip(
                          label: '1080P',
                          isSelected: selectedResolution == '1080P',
                          onTap: () => onResolutionChanged('1080P'),
                        ),
                      if (show1080P && show4K) SizedBox(width: 8),
                      if (show4K)
                        ModeChip(
                          label: '4K',
                          isSelected: selectedResolution == '4K',
                          onTap: () => onResolutionChanged('4K'),
                          isLocked: !isPro && supports4K,
                          isUnsupported: !supports4K,
                          unsupportedMessage:
                              '4K recording is not supported by your device camera.',
                          onLockedTap: onLockedTap,
                        ),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                GlassContainer(
                  padding: EdgeInsets.only(
                    left: 12,
                    top: 8,
                    right: 12,
                    bottom: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ModeChip(
                        label: '30',
                        suffix: 'fps',
                        isSelected: selectedFps == 30 || isLowMemoryDevice,
                        onTap: () => onFpsChanged(30),
                      ),
                      if (show60fps) ...[
                        SizedBox(width: 8),
                        ModeChip(
                          label: '60',
                          suffix: 'fps',
                          isSelected: selectedFps == 60,
                          onTap: () => onFpsChanged(60),
                          isLocked: !isPro && supports60fps,
                          isUnsupported: !supports60fps,
                          unsupportedMessage:
                              '60fps recording at ${selectedResolution} is not supported by your device camera.',
                          onLockedTap: onLockedTap,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class BufferIndicator extends StatefulWidget {
  final int bufferSeconds;
  final int maxSeconds;

  const BufferIndicator({
    super.key,
    required this.bufferSeconds,
    required this.maxSeconds,
  });

  @override
  State<BufferIndicator> createState() => _BufferIndicatorState();
}

class _BufferIndicatorState extends State<BufferIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        widget.maxSeconds > 0 ? widget.bufferSeconds / widget.maxSeconds : 0.0;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      child: GlassContainer(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                // Progress ring
                Container(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.electricBlue,
                    ),
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                // Center dot
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.successGreen,
                  ),
                ),
              ],
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Buffer',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${widget.bufferSeconds}s / ${widget.maxSeconds}s',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      builder: (context, child) {
        return Opacity(
          opacity: _pulseAnimation.value,
          child: Transform.scale(
            scale: 1.0 + (_pulseAnimation.value - 0.75) * 0.1,
            child: child,
          ),
        );
      },
    );
  }
}

class FinalizingIndicator extends StatelessWidget {
  final double progress;

  const FinalizingIndicator({super.key, required this.progress});

  @override
  Widget build(BuildContext context) => GlassContainer(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Saving...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Container(
              width: 100,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.electricBlue,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class BottomControls extends StatelessWidget {
  final CameraMode cameraMode;
  final bool isRecording;
  final bool isPreparingRecording;
  final bool isCameraReady;
  final VoidCallback onRecordTap;
  final VoidCallback onBufferToggle;
  final double bufferProgress;
  final int selectedBufferSeconds;
  final int bufferRemainingSeconds;
  final dynamic latestVideo;
  final VoidCallback onGalleryTap;
  final String flashMode;
  final VoidCallback onFlashTap;
  final bool isPortrait;

  const BottomControls({
    super.key,
    required this.cameraMode,
    required this.isRecording,
    this.isPreparingRecording = false,
    required this.isCameraReady,
    required this.onRecordTap,
    required this.onBufferToggle,
    required this.bufferProgress,
    required this.selectedBufferSeconds,
    required this.bufferRemainingSeconds,
    required this.latestVideo,
    required this.onGalleryTap,
    required this.flashMode,
    required this.onFlashTap,
    this.isPortrait = true,
  });

  @override
  Widget build(BuildContext context) {
    final isIdle = cameraMode == CameraMode.idle;
    final isBuffering = cameraMode == CameraMode.buffering;
    // Disable button while preparing to record (prevents double-taps)
    final canRecord =
        isCameraReady && (isBuffering || isRecording) && !isPreparingRecording;

    if (isPortrait) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Buffer control button
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildBufferButton(
                isIdle,
                isBuffering,
                isRecording,
                isCameraReady: isCameraReady,
              ),
            ),
            // Main controls row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                VideoThumbnail(
                  video: latestVideo,
                  size: 60,
                  onTap: onGalleryTap,
                ),
                RecordButton(
                  isRecording: isRecording,
                  isPreparing: isPreparingRecording,
                  onTap: onRecordTap,
                  bufferProgress: bufferProgress,
                  selectedBufferSeconds: selectedBufferSeconds,
                  isEnabled: canRecord,
                ),
                GestureDetector(
                  onTap: isIdle ? null : onFlashTap,
                  child: Opacity(
                    opacity: (isIdle || !isCameraReady) ? 0.3 : 1.0,
                    child: GlassContainer(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        flashMode == 'on' ? Icons.flash_on : Icons.flash_off,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: 140,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          VideoThumbnail(video: latestVideo, size: 72, onTap: onGalleryTap),
          const SizedBox(height: 16),
          _buildBufferButton(
            isIdle,
            isBuffering,
            isRecording,
            isCameraReady: isCameraReady,
          ),
          const SizedBox(height: 24),
          RecordButton(
            isRecording: isRecording,
            isPreparing: isPreparingRecording,
            onTap: onRecordTap,
            bufferProgress: bufferProgress,
            selectedBufferSeconds: selectedBufferSeconds,
            isEnabled: canRecord,
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: (!isCameraReady || isIdle) ? null : onFlashTap,
            child: Opacity(
              opacity: (isIdle || !isCameraReady) ? 0.3 : 1.0,
              child: GlassContainer(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  flashMode == 'on' ? Icons.flash_on : Icons.flash_off,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBufferButton(
    bool isIdle,
    bool isBuffering,
    bool isRecording, {
    required bool isCameraReady,
  }) {
    return GestureDetector(
      onTap: (!isCameraReady || isRecording) ? null : onBufferToggle,
      child: Opacity(
        opacity: (!isCameraReady || isRecording) ? 0.5 : 1.0,
        child: GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isIdle ? Icons.play_arrow : Icons.stop,
                color: isIdle ? AppColors.successGreen : Colors.red,
                size: 20,
              ),
              const SizedBox(width: 8),
              if (isIdle)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Start Buffer',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${selectedBufferSeconds}s',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                )
              else if (isBuffering)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Stop Buffer',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${bufferRemainingSeconds}/${selectedBufferSeconds}s',
                      style: TextStyle(
                        color: bufferRemainingSeconds >= selectedBufferSeconds
                            ? AppColors.successGreen
                            : Colors.amber,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  'Recording...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class CameraStatusMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  const CameraStatusMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 40),
              SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  message,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: onAction == null
                      ? null
                      : () async {
                          await onAction!.call();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.electricBlue,
                    foregroundColor: Colors.black,
                  ),
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      );
}

class ZoomIndicator extends StatelessWidget {
  final double zoom;

  const ZoomIndicator({super.key, required this.zoom});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 100),
      tween: Tween(begin: zoom, end: zoom),
      builder: (context, value, child) {
        return GlassContainer(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.zoom_in, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text(
                '${value.toStringAsFixed(1)}x',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Focus indicator shown when user taps to focus
class FocusIndicator extends StatelessWidget {
  final bool isLocked;

  const FocusIndicator({super.key, this.isLocked = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        border: Border.all(
          color: isLocked ? AppColors.electricBlue : Colors.white,
          width: isLocked ? 2.5 : 2,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          // Corner brackets
          ...List.generate(4, (index) {
            final isTop = index < 2;
            final isLeft = index % 2 == 0;
            return Positioned(
              top: isTop ? 0 : null,
              bottom: !isTop ? 0 : null,
              left: isLeft ? 0 : null,
              right: !isLeft ? 0 : null,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  border: Border(
                    top: isTop
                        ? BorderSide(
                            color: isLocked
                                ? AppColors.electricBlue
                                : Colors.white,
                            width: 3,
                          )
                        : BorderSide.none,
                    bottom: !isTop
                        ? BorderSide(
                            color: isLocked
                                ? AppColors.electricBlue
                                : Colors.white,
                            width: 3,
                          )
                        : BorderSide.none,
                    left: isLeft
                        ? BorderSide(
                            color: isLocked
                                ? AppColors.electricBlue
                                : Colors.white,
                            width: 3,
                          )
                        : BorderSide.none,
                    right: !isLeft
                        ? BorderSide(
                            color: isLocked
                                ? AppColors.electricBlue
                                : Colors.white,
                            width: 3,
                          )
                        : BorderSide.none,
                  ),
                ),
              ),
            );
          }),
          // Lock icon when locked
          if (isLocked)
            Center(
              child: Icon(Icons.lock, color: AppColors.electricBlue, size: 24),
            ),
        ],
      ),
    );
  }
}
