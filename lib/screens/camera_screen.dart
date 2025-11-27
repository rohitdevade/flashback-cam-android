import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flashback_cam/providers/app_state.dart';
import 'package:flashback_cam/models/app_settings.dart';
import 'package:flashback_cam/theme.dart';
import 'package:flashback_cam/widgets/glass_container.dart';
import 'package:flashback_cam/widgets/mode_chip.dart';
import 'package:flashback_cam/widgets/record_button.dart';
import 'package:flashback_cam/widgets/video_thumbnail.dart';
import 'package:flashback_cam/widgets/debug_info_panel.dart';
import 'package:flashback_cam/widgets/camera_instructions_overlay.dart';
import 'package:flashback_cam/screens/gallery_screen.dart';
import 'package:flashback_cam/screens/settings_screen.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  double _baseZoomLevel = 1.0;
  Map<String, bool> _capabilities = {};
  bool _capabilitiesLoaded = false;
  bool _showInstructions = false;
  bool _instructionsChecked = false;
  bool _lowMemoryWarningShown = false;

  @override
  void initState() {
    super.initState();
    _loadCapabilities();
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
    super.dispose();
  }

  Future<void> _showDebugPanel() async {
    print('🐛 DEBUG PANEL OPENING NOW!');

    final appState = context.read<AppState>();

    // Show a snackbar to confirm
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🐛 Debug Panel Opening...',
            style: TextStyle(fontWeight: FontWeight.bold)),
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
              // Zoom gesture detector - only responds to multi-touch gestures
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onScaleStart: (details) {
                    if (details.pointerCount > 1) {
                      _baseZoomLevel = appState.zoomLevel;
                      print(
                          '🔍 Scale gesture started: base zoom = $_baseZoomLevel');
                    }
                  },
                  onScaleUpdate: (details) {
                    if (details.pointerCount > 1) {
                      final newZoom = (_baseZoomLevel * details.scale)
                          .clamp(1.0, appState.maxZoom);
                      print(
                          '🔍 Scale gesture update: scale=${details.scale}, newZoom=$newZoom');
                      appState.setZoom(newZoom);
                    }
                  },
                  onScaleEnd: (details) {
                    print('🔍 Scale gesture ended');
                  },
                  onDoubleTap: () {
                    print('🔍 Double tap detected - switching camera');
                    appState.switchCamera();
                  },
                  child: Container(color: Colors.transparent),
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
                  child: Center(
                    child: ZoomIndicator(zoom: appState.zoomLevel),
                  ),
                ),
              // Camera instructions overlay (shown on first launch)
              if (_showInstructions)
                CameraInstructionsOverlay(
                  onDismiss: () {
                    setState(() => _showInstructions = false);
                    appState.markCameraInstructionsSeen();
                  },
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
            padding: const EdgeInsets.all(20),
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
            ),
          ),
        const Spacer(),
        if (appState.isFinalizing)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: FinalizingIndicator(progress: appState.finalizeProgress),
          ),
        _buildBottomControls(appState, isPortrait: true),
        const SizedBox(height: 32),
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
                  ),
                const Spacer(),
                if (appState.isFinalizing)
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: FinalizingIndicator(
                        progress: appState.finalizeProgress),
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
      onSwitchCamera: () => appState.switchCamera(),
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

  Future<void> _openGallery(AppState appState) async {
    if (appState.isRecording) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        const SnackBar(
            content: Text('Stop recording before opening the gallery.')),
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

    // Show loading state while initializing
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            isDark ? AppColors.deepCharcoal : AppColors.glassWhite,
            isDark ? Color(0xFF1E2A3A) : Color(0xFFE0E8F0),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: AppColors.electricBlue,
              strokeWidth: 2,
            ),
            SizedBox(height: 16),
            Text(
              'Initializing Camera...',
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.7),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Please wait',
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.5),
                fontSize: 14,
                fontWeight: FontWeight.w400,
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
        child: CustomPaint(
          size: Size.infinite,
          painter: GridPainter(),
        ),
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
          Offset(0, hStep * i), Offset(size.width, hStep * i), paint);
      canvas.drawLine(
          Offset(vStep * i, 0), Offset(vStep * i, size.height), paint);
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
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => SettingsScreen())),
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
                        ModeChip(
                          label: '1080P',
                          isSelected: selectedResolution == '1080P',
                          onTap: () => onResolutionChanged('1080P'),
                        ),
                        if (capabilitiesLoaded &&
                            capabilities['supports4K'] == true) ...[
                          SizedBox(width: 8),
                          ModeChip(
                            label: '4K',
                            isSelected: selectedResolution == '4K',
                            onTap: () => onResolutionChanged('4K'),
                            isLocked: !isPro,
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: 12),
                  GlassContainer(
                    padding: EdgeInsets.only(
                        left: 12, top: 8, right: 12, bottom: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ModeChip(
                          label: '30',
                          isSelected: selectedFps == 30,
                          onTap: () => onFpsChanged(30),
                        ),
                        if (capabilitiesLoaded &&
                            ((selectedResolution == '1080P' &&
                                    capabilities['supports1080p60fps'] ==
                                        true) ||
                                (selectedResolution == '4K' &&
                                    capabilities['supports4K60fps'] ==
                                        true))) ...[
                          SizedBox(width: 8),
                          ModeChip(
                            label: '60',
                            isSelected: selectedFps == 60,
                            onTap: () => onFpsChanged(60),
                            isLocked: !isPro,
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
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.electricBlue),
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
                  fontWeight: FontWeight.w600),
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
  final VoidCallback onSwitchCamera;
  final bool isPortrait;

  const BottomControls({
    super.key,
    required this.cameraMode,
    required this.isRecording,
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
    required this.onSwitchCamera,
    this.isPortrait = true,
  });

  @override
  Widget build(BuildContext context) {
    final isIdle = cameraMode == CameraMode.idle;
    final isBuffering = cameraMode == CameraMode.buffering;
    final canRecord = isCameraReady && (isBuffering || isRecording);

    if (isPortrait) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Buffer control button
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildBufferButton(isIdle, isBuffering, isRecording,
                  isCameraReady: isCameraReady),
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
                  onTap: onRecordTap,
                  bufferProgress: bufferProgress,
                  selectedBufferSeconds: selectedBufferSeconds,
                  isEnabled: canRecord,
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: isIdle ? null : onFlashTap,
                      child: Opacity(
                        opacity: (isIdle || !isCameraReady) ? 0.3 : 1.0,
                        child: GlassContainer(
                          padding: const EdgeInsets.all(12),
                          child: Icon(
                            flashMode == 'on'
                                ? Icons.flash_on
                                : Icons.flash_off,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: (isIdle || isRecording) ? null : onSwitchCamera,
                      child: Opacity(
                        opacity: (isIdle || !isCameraReady || isRecording)
                            ? 0.3
                            : 1.0,
                        child: GlassContainer(
                          padding: const EdgeInsets.all(12),
                          child: const Icon(Icons.cameraswitch,
                              color: Colors.white, size: 24),
                        ),
                      ),
                    ),
                  ],
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
          VideoThumbnail(
            video: latestVideo,
            size: 72,
            onTap: onGalleryTap,
          ),
          const SizedBox(height: 16),
          _buildBufferButton(isIdle, isBuffering, isRecording,
              isCameraReady: isCameraReady),
          const SizedBox(height: 24),
          RecordButton(
            isRecording: isRecording,
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
          const SizedBox(height: 16),
          GestureDetector(
            onTap: (!isCameraReady || isIdle || isRecording)
                ? null
                : onSwitchCamera,
            child: Opacity(
              opacity: (isIdle || !isCameraReady || isRecording) ? 0.3 : 1.0,
              child: GlassContainer(
                padding: const EdgeInsets.all(12),
                child: const Icon(
                  Icons.cameraswitch,
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

  Widget _buildBufferButton(bool isIdle, bool isBuffering, bool isRecording,
      {required bool isCameraReady}) {
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
