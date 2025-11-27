import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' hide AppState;

import 'package:flashback_cam/models/video_recording.dart';
import 'package:flashback_cam/providers/app_state.dart';
import 'package:flashback_cam/screens/video_viewer_screen.dart';
import 'package:flashback_cam/theme.dart';
import 'package:flashback_cam/widgets/frosted_glass_card.dart';
import 'package:flashback_cam/widgets/glass_container.dart';
import 'package:flashback_cam/services/video_actions_service.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

enum SortOption { newest, oldest, duration, size }

class _GalleryScreenState extends State<GalleryScreen>
    with TickerProviderStateMixin {
  String _searchQuery = '';
  SortOption _sortOption = SortOption.newest;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _resumeBufferOnExit = false;
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _fadeController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pauseBufferIfNeeded();
      _loadBannerAd();
    });
  }

  void _loadBannerAd() {
    final appState = context.read<AppState>();
    if (appState.isPro) return; // Don't show ads for pro users

    _bannerAd = appState.adService.createGalleryBannerAd();
    _bannerAd!.load().then((_) {
      if (mounted) {
        setState(() => _isBannerAdLoaded = true);
      }
    });
  }

  @override
  void dispose() {
    if (_resumeBufferOnExit) {
      final appState = context.read<AppState>();
      unawaited(appState.startBuffer());
    }
    _fadeController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _pauseBufferIfNeeded() async {
    final appState = context.read<AppState>();
    if (appState.isBuffering) {
      _resumeBufferOnExit = true;
      await appState.stopBuffer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final allVideos = appState.videos;
    final filteredVideos = _filterAndSortVideos(allVideos);

    return Scaffold(
      backgroundColor: AppColors.deepCharcoal,
      body: SafeArea(
        child: Column(
          children: [
            // Custom app bar with glassmorphism
            _buildTopBar(context),

            // Main content area
            Expanded(
              child: filteredVideos.isEmpty && allVideos.isNotEmpty
                  ? _buildNoResultsView()
                  : allVideos.isEmpty
                      ? const EmptyGallery()
                      : _buildVideoGrid(filteredVideos),
            ),

            // Banner ad at bottom (only for non-pro users)
            if (_isBannerAdLoaded && _bannerAd != null && !appState.isPro)
              Container(
                alignment: Alignment.center,
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'My Clips',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            GestureDetector(
              onTap: _showSortOptions,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.glassLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.sort,
                    color: AppColors.textPrimary, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _showSearchDialog,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.glassLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.search,
                    color: AppColors.textPrimary, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoGrid(List<VideoRecording> videos) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GridView.builder(
          physics: const BouncingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.8,
          ),
          itemCount: videos.length,
          itemBuilder: (context, index) {
            final video = videos[index];
            return TweenAnimationBuilder<double>(
              duration: Duration(milliseconds: 300 + (index * 50)),
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, 30 * (1 - value)),
                  child: Opacity(
                    opacity: value,
                    child: VideoGridItem(
                      video: video,
                      onTap: () => _navigateToViewer(video),
                      onLongPress: () => _showVideoOptions(video),
                      onOptionsTap: () => _showVideoOptions(video),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildNoResultsView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 80,
            color: AppColors.textSecondary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'No results found',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'Try adjusting your search or filter',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _searchQuery = '';
                _sortOption = SortOption.newest;
              });
            },
            child: const Text('Clear Filters'),
          ),
        ],
      ),
    );
  }

  List<VideoRecording> _filterAndSortVideos(List<VideoRecording> videos) {
    List<VideoRecording> filtered = videos;

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((video) {
        return video.resolution
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()) ||
            video.codec.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            video.fps.toString().contains(_searchQuery);
      }).toList();
    }

    // Apply sorting
    switch (_sortOption) {
      case SortOption.newest:
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case SortOption.oldest:
        filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case SortOption.duration:
        filtered.sort((a, b) => b.durationSeconds.compareTo(a.durationSeconds));
        break;
      case SortOption.size:
        filtered.sort((a, b) => b.fileSizeBytes.compareTo(a.fileSizeBytes));
        break;
    }

    return filtered;
  }

  void _navigateToViewer(VideoRecording video) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            VideoViewerScreen(video: video),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: FrostedGlassCard(
          padding: const EdgeInsets.all(20),
          borderRadius: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sort by',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 20),
              ...SortOption.values.map((option) {
                final isSelected = _sortOption == option;
                return GestureDetector(
                  onTap: () {
                    setState(() => _sortOption = option);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 16),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.electricBlue.withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.electricBlue
                            : AppColors.glassBorder,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _getSortIcon(option),
                          color: isSelected
                              ? AppColors.electricBlue
                              : AppColors.textSecondary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _getSortLabel(option),
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.electricBlue
                                : AppColors.textPrimary,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassContainer(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Search Videos',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 20),
              TextField(
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search by resolution, codec, or FPS',
                  hintStyle: const TextStyle(color: AppColors.textTertiary),
                  prefixIcon:
                      const Icon(Icons.search, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.glassLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.glassBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.glassBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: AppColors.electricBlue, width: 2),
                  ),
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() => _searchQuery = '');
                      Navigator.pop(context);
                    },
                    child: const Text('Clear'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getSortIcon(SortOption option) {
    switch (option) {
      case SortOption.newest:
        return Icons.schedule;
      case SortOption.oldest:
        return Icons.history;
      case SortOption.duration:
        return Icons.timer;
      case SortOption.size:
        return Icons.storage;
    }
  }

  String _getSortLabel(SortOption option) {
    switch (option) {
      case SortOption.newest:
        return 'Newest first';
      case SortOption.oldest:
        return 'Oldest first';
      case SortOption.duration:
        return 'Longest first';
      case SortOption.size:
        return 'Largest first';
    }
  }

  void _showVideoOptions(VideoRecording video) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => VideoOptionsSheet(
        video: video,
        parentContext: context,
      ),
    );
  }
}

class EmptyGallery extends StatelessWidget {
  const EmptyGallery({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library_outlined,
                size: 80,
                color: AppColors.textSecondary.withValues(alpha: 0.3)),
            SizedBox(height: 24),
            Text(
              'No videos yet',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            SizedBox(height: 12),
            Text(
              'Start recording to see your videos here',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
}

class VideoGridItem extends StatelessWidget {
  final VideoRecording video;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onOptionsTap;

  const VideoGridItem({
    super.key,
    required this.video,
    required this.onTap,
    required this.onLongPress,
    required this.onOptionsTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.glassBorder,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                child: Stack(
                  children: [
                    // Thumbnail image or placeholder gradient
                    if (video.thumbnailPath != null &&
                        video.thumbnailPath!.isNotEmpty)
                      Positioned.fill(
                        child: Builder(
                          builder: (context) {
                            debugPrint(
                                'GalleryScreen: Loading thumbnail ${video.thumbnailPath}');
                            debugPrint(
                                'File exists: ${File(video.thumbnailPath!).existsSync()}');
                            return Image.file(
                              File(video.thumbnailPath!),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                // Fallback to gradient if image fails to load
                                debugPrint(
                                    'GalleryScreen: Failed to load thumbnail ${video.thumbnailPath}: $error');
                                return Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        AppColors.vibrantPurple
                                            .withValues(alpha: 0.2),
                                        AppColors.electricBlue
                                            .withValues(alpha: 0.2),
                                      ],
                                    ),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.play_circle_outline,
                                      size: 48,
                                      color:
                                          Colors.white.withValues(alpha: 0.9),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      )
                    else
                      // Placeholder gradient when no thumbnail
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.vibrantPurple.withValues(alpha: 0.2),
                                AppColors.electricBlue.withValues(alpha: 0.2),
                              ],
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.play_circle_outline,
                              size: 48,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ),
                    // Play icon overlay
                    if (video.thumbnailPath != null &&
                        video.thumbnailPath!.isNotEmpty)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.center,
                              end: Alignment.center,
                              colors: [
                                Colors.black.withValues(alpha: 0.0),
                                Colors.black.withValues(alpha: 0.1),
                              ],
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.play_circle_outline,
                              size: 48,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ),
                    // Duration badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          video.formattedDuration,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: onOptionsTap,
                          child: const SizedBox(
                            width: 32,
                            height: 32,
                            child: Icon(
                              Icons.more_vert,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.video_settings,
                          size: 16, color: AppColors.vibrantPurple),
                      SizedBox(width: 6),
                      Text(
                        '${video.resolution} • ${video.fps}fps',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.storage,
                          size: 14, color: AppColors.textSecondary),
                      SizedBox(width: 6),
                      Text(
                        video.formattedSize,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Spacer(),
                      Icon(Icons.access_time,
                          size: 14, color: AppColors.textSecondary),
                      SizedBox(width: 4),
                      Text(
                        '${video.preRollSeconds}s',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoOptionsSheet extends StatelessWidget {
  final VideoRecording video;
  final BuildContext parentContext;

  const VideoOptionsSheet({
    super.key,
    required this.video,
    required this.parentContext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: 24),
          OptionTile(
            icon: Icons.share,
            label: 'Share',
            onTap: () => _handleShare(context),
          ),
          OptionTile(
            icon: Icons.download,
            label: 'Save to device',
            onTap: () => _handleDownload(context),
          ),
          OptionTile(
            icon: Icons.info_outline,
            label: 'Details',
            onTap: () {
              Navigator.pop(context);
              _showDetailsDialog(context);
            },
          ),
          OptionTile(
            icon: Icons.delete_outline,
            label: 'Delete',
            color: AppColors.recordRed,
            onTap: () {
              Navigator.pop(context);
              _confirmDelete(context);
            },
          ),
        ],
      ),
    );
  }

  void _showDetailsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Video Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DetailRow(label: 'Resolution', value: video.resolution),
            DetailRow(label: 'FPS', value: '${video.fps}'),
            DetailRow(label: 'Codec', value: video.codec),
            DetailRow(label: 'Duration', value: video.formattedDuration),
            DetailRow(label: 'Pre-roll', value: '${video.preRollSeconds}s'),
            DetailRow(label: 'Size', value: video.formattedSize),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Video'),
        content: Text(
            'Are you sure you want to delete this video? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<AppState>().deleteVideo(video.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Video deleted')),
              );
            },
            child: Text('Delete', style: TextStyle(color: AppColors.recordRed)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleShare(BuildContext sheetContext) async {
    Navigator.of(sheetContext).pop();
    await VideoActionsService.shareVideo(parentContext, video);
  }

  Future<void> _handleDownload(BuildContext sheetContext) async {
    Navigator.of(sheetContext).pop();
    await VideoActionsService.saveToDevice(parentContext, video);
  }
}

class OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const OptionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading:
            Icon(icon, color: color ?? Theme.of(context).colorScheme.primary),
        title: Text(label, style: TextStyle(color: color)),
        onTap: onTap,
      );
}

class DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const DetailRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textSecondary)),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
