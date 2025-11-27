import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:flashback_cam/models/video_recording.dart';
import 'package:flashback_cam/providers/app_state.dart';
import 'package:flashback_cam/theme.dart';
import 'package:flashback_cam/widgets/glass_container.dart';
import 'package:flashback_cam/services/video_actions_service.dart';

class VideoViewerScreen extends StatefulWidget {
  final VideoRecording video;

  const VideoViewerScreen({super.key, required this.video});

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isInitialized = false;
  bool _isInitializing = false;
  double _currentPosition = 0.0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initializePlayer();
  }

  @override
  void dispose() {
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    if (_isInitializing) return;

    setState(() {
      _isInitializing = true;
      _error = null;
      _isInitialized = false;
    });

    try {
      // Step 1: Verify file exists
      final file = File(widget.video.filePath);
      debugPrint('📹 Attempting to play: ${widget.video.filePath}');

      if (!await file.exists()) {
        debugPrint('❌ File does not exist at path: ${widget.video.filePath}');
        throw Exception('Video file not found at: ${widget.video.filePath}');
      }

      // Step 2: Check file size
      final fileSize = await file.length();
      debugPrint('📹 File exists, size: $fileSize bytes');

      if (fileSize < 1000) {
        throw Exception('Video file is too small ($fileSize bytes)');
      }

      debugPrint('📹 Initializing video player: ${widget.video.filePath}');
      debugPrint(
          '📹 File size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
      debugPrint('📹 Resolution: ${widget.video.resolution}');
      debugPrint('📹 Codec: ${widget.video.codec}');
      debugPrint('📹 FPS: ${widget.video.fps}');

      // Step 3: Create controller
      final controller = VideoPlayerController.file(file);
      debugPrint('📹 VideoPlayerController created');

      // Step 4: Initialize with timeout
      await controller.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Video initialization timed out after 10 seconds');
        },
      );

      // Step 5: Validate initialization
      if (!controller.value.isInitialized) {
        throw Exception('Video controller failed to initialize');
      }

      if (controller.value.duration == Duration.zero) {
        throw Exception('Video has zero duration');
      }

      // Step 6: Set up listener
      controller.addListener(_videoListener);

      // Step 7: Update state
      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _duration = controller.value.duration;
        _position = controller.value.position;
        _isInitialized = true;
        _isInitializing = false;
        _error = null;
      });

      debugPrint('✅ Video player initialized successfully');
      debugPrint('📹 Duration: ${_duration.inSeconds}s');
      debugPrint('📹 Size: ${controller.value.size}');
    } catch (e, stackTrace) {
      debugPrint('❌ Video initialization failed: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        setState(() {
          _error = _getErrorMessage(e);
          _isInitializing = false;
          _isInitialized = false;
        });
      }

      _controller?.dispose();
      _controller = null;
    }
  }

  String _getErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('not found') || errorStr.contains('missing')) {
      return 'Video file not found. It may have been deleted.';
    } else if (errorStr.contains('timeout')) {
      return 'Video took too long to load. File may be corrupted.';
    } else if (errorStr.contains('zero duration') ||
        errorStr.contains('duration')) {
      return 'Video has invalid duration. Recording was incomplete.';
    } else if (errorStr.contains('format') || errorStr.contains('codec')) {
      return 'Video format not supported by player.';
    } else if (errorStr.contains('too small')) {
      return 'Video file is corrupted or incomplete.';
    } else if (errorStr.contains('source error') ||
        errorStr.contains('exoplayer')) {
      return 'Video file is corrupted or has invalid format.\n\nThis usually means:\n• The recording was interrupted\n• Audio/video tracks are missing\n• The MP4 container is malformed\n\nTry recording again.';
    } else {
      return 'Unable to play video:\n${error.toString()}\n\nFile: ${widget.video.filePath}';
    }
  }

  void _videoListener() {
    if (!mounted || _controller == null) return;

    final value = _controller!.value;
    final newDuration = value.duration;
    final newPosition = value.position;
    final isCurrentlyPlaying = value.isPlaying;

    // Update duration if changed
    if (newDuration != Duration.zero && newDuration != _duration) {
      _duration = newDuration;
    }

    // Calculate progress
    final durationMs = _duration.inMilliseconds;
    final positionMs = newPosition.inMilliseconds;
    final progress =
        durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

    // Sync our _isPlaying state with actual controller state
    if (_isPlaying != isCurrentlyPlaying) {
      _isPlaying = isCurrentlyPlaying;

      // If video paused externally (reached end, etc), show controls
      if (!isCurrentlyPlaying) {
        _showControls = true;
      }
    }

    setState(() {
      _position = newPosition;
      _currentPosition = progress;
    });
  }

  void _togglePlayPause() {
    if (!_isInitialized || _controller == null) return;

    if (_controller!.value.isPlaying) {
      _controller!.pause();
      setState(() {
        _isPlaying = false;
        _showControls = true; // Always show controls when pausing
      });
    } else {
      _controller!.play();
      setState(() {
        _isPlaying = true;
      });
      // Auto-hide controls after 3 seconds when playing starts
      _scheduleControlsHide();
    }
  }

  void _scheduleControlsHide() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isPlaying && _showControls) {
        setState(() => _showControls = false);
      }
    });
  }

  void _seekTo(double value) {
    if (!_isInitialized || _controller == null) return;

    final durationMs = _duration.inMilliseconds;
    if (durationMs <= 0) return;

    final newPosition = Duration(milliseconds: (value * durationMs).round());

    setState(() {
      _currentPosition = value;
      _position = newPosition;
    });

    _controller!.seekTo(newPosition);
  }

  void _toggleControls() {
    if (!_isPlaying) {
      // When paused, controls should always stay visible
      return;
    }

    setState(() {
      _showControls = !_showControls;
    });

    // If showing controls while playing, schedule auto-hide
    if (_showControls && _isPlaying) {
      _scheduleControlsHide();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _error == null ? _toggleControls : null,
        child: Stack(
          children: [
            // Video player
            _buildVideoPlayer(),

            // Controls overlay
            if (_showControls && _error == null) _buildControlsOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    // Error state
    if (_error != null) {
      return _buildErrorState();
    }

    // Loading state
    if (_isInitializing || !_isInitialized || _controller == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.electricBlue),
              SizedBox(height: 16),
              Text(
                'Loading video...',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    // Video playing state
    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: _controller!.value.aspectRatio,
          child: VideoPlayer(_controller!),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: GlassContainer(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppColors.recordRed,
                size: 64,
              ),
              const SizedBox(height: 24),
              Text(
                'Playback Error',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _initializePlayer,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.electricBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      // Delete the corrupted video
                      final shouldDelete = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete Video'),
                          content: const Text(
                              'Delete this corrupted video? This cannot be undone.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Delete',
                                  style: TextStyle(color: AppColors.recordRed)),
                            ),
                          ],
                        ),
                      );

                      if (shouldDelete == true && mounted) {
                        context.read<AppState>().deleteVideo(widget.video.id);
                        Navigator.pop(context);
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.recordRed,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.electricBlue,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.7),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withOpacity(0.8),
          ],
          stops: const [0.0, 0.2, 0.6, 1.0],
        ),
      ),
      child: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: Center(
              child: _buildPlayButton(),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              iconSize: 28,
            ),
            const Spacer(),
            IconButton(
              onPressed: _shareVideo,
              icon: const Icon(Icons.share, color: Colors.white),
              iconSize: 24,
            ),
            IconButton(
              onPressed: _downloadVideo,
              icon: const Icon(Icons.download, color: Colors.white),
              iconSize: 24,
            ),
            IconButton(
              onPressed: _showOptions,
              icon: const Icon(Icons.more_vert, color: Colors.white),
              iconSize: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _togglePlayPause();
        // Don't propagate to parent GestureDetector
      },
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withOpacity(0.5),
          border: Border.all(color: Colors.white.withOpacity(0.8), width: 2),
        ),
        child: Icon(
          _isPlaying ? Icons.pause : Icons.play_arrow,
          color: Colors.white,
          size: 48,
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress bar
            Row(
              children: [
                Text(
                  _formatDuration(_position),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.electricBlue,
                      inactiveTrackColor: Colors.white.withOpacity(0.3),
                      thumbColor: AppColors.electricBlue,
                      overlayColor: AppColors.electricBlue.withOpacity(0.3),
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: _currentPosition,
                      onChanged: _seekTo,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _formatDuration(_duration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Video info
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.electricBlue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.electricBlue),
                  ),
                  child: Text(
                    '${widget.video.preRollSeconds}s PRE-ROLL',
                    style: const TextStyle(
                      color: AppColors.electricBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${widget.video.resolution} • ${widget.video.fps}fps • ${widget.video.codec}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                Text(
                  widget.video.formattedSize,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareVideo() async {
    await VideoActionsService.shareVideo(context, widget.video);
  }

  Future<void> _downloadVideo() async {
    await VideoActionsService.saveToDevice(context, widget.video);
  }

  void _showOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.info_outline, color: AppColors.electricBlue),
              title: const Text('Video Details'),
              onTap: () {
                Navigator.pop(context);
                _showDetails();
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: AppColors.recordRed),
              title: const Text('Delete Video'),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDetails() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Video Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow('Resolution', widget.video.resolution),
            _DetailRow('Frame Rate', '${widget.video.fps} fps'),
            _DetailRow('Codec', widget.video.codec),
            _DetailRow('Duration', widget.video.formattedDuration),
            _DetailRow('Pre-roll', '${widget.video.preRollSeconds}s'),
            _DetailRow('File Size', widget.video.formattedSize),
            _DetailRow('Created', _formatDate(widget.video.createdAt)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Video'),
        content: const Text(
            'Are you sure you want to delete this video? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<AppState>().deleteVideo(widget.video.id);
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close viewer
            },
            child: const Text('Delete',
                style: TextStyle(color: AppColors.recordRed)),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
