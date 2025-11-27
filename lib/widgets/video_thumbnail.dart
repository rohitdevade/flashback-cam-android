import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flashback_cam/models/video_recording.dart';
import 'package:flashback_cam/theme.dart';

class VideoThumbnail extends StatelessWidget {
  final VideoRecording? video;
  final double size;
  final VoidCallback? onTap;

  const VideoThumbnail({
    super.key,
    this.video,
    this.size = 60,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : AppColors.cardLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
            width: 2,
          ),
        ),
        child: video == null
            ? Center(
                child: Icon(
                  Icons.videocam_outlined,
                  color: AppColors.textSecondary,
                  size: size * 0.4,
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    // Show thumbnail if available
                    if (video!.thumbnailPath != null &&
                        video!.thumbnailPath!.isNotEmpty)
                      Positioned.fill(
                        child: Builder(
                          builder: (context) {
                            print(
                                'VideoThumbnail: Loading ${video!.thumbnailPath}');
                            print(
                                'File exists: ${File(video!.thumbnailPath!).existsSync()}');
                            return Image.file(
                              File(video!.thumbnailPath!),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                // Fallback to icon if image fails
                                print(
                                    'VideoThumbnail: Failed to load ${video!.thumbnailPath}: $error');
                                return Center(
                                  child: Icon(
                                    Icons.play_circle_outline,
                                    color: Colors.white,
                                    size: size * 0.35,
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      )
                    else
                      Center(
                        child: Icon(
                          Icons.play_circle_outline,
                          color: Colors.white,
                          size: size * 0.35,
                        ),
                      ),
                    // Duration badge
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          video!.formattedDuration,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
