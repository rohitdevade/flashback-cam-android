import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashback_cam/models/video_recording.dart';

class StorageService {
  static const _videosKey = 'videos';
  List<VideoRecording> _videos = [];

  Future<void> initialize() async {
    await _loadVideos();
  }

  Future<void> _loadVideos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final videosJson = prefs.getString(_videosKey);
      if (videosJson != null) {
        final List<dynamic> videosList = json.decode(videosJson);
        _videos = videosList
            .map((v) {
              try {
                final video =
                    VideoRecording.fromJson(v as Map<String, dynamic>);
                debugPrint(
                    'Loaded video: ${video.id}, thumbnailPath: ${video.thumbnailPath}');
                return video;
              } catch (e) {
                debugPrint('Skipping corrupted video entry: $e');
                return null;
              }
            })
            .whereType<VideoRecording>()
            .toList();
        await _saveVideos();
      }
    } catch (e) {
      debugPrint('Failed to load videos: $e');
      _videos = [];
    }
  }

  Future<void> _saveVideos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final videosJson = json.encode(_videos.map((v) => v.toJson()).toList());
      await prefs.setString(_videosKey, videosJson);
    } catch (e) {
      debugPrint('Failed to save videos: $e');
    }
  }

  Future<void> addVideo(VideoRecording video) async {
    // Remove any existing video with same ID or file path to avoid duplicates
    _videos
        .removeWhere((v) => v.id == video.id || v.filePath == video.filePath);

    // Insert at the beginning (most recent)
    _videos.insert(0, video);

    debugPrint('Video added to storage: ${video.id}');
    debugPrint('  File: ${video.filePath}');
    debugPrint('  Thumbnail: ${video.thumbnailPath}');
    debugPrint('  Total videos: ${_videos.length}');

    await _saveVideos();
  }

  Future<void> deleteVideo(String id) async {
    _videos.removeWhere((v) => v.id == id);
    await _saveVideos();
  }

  List<VideoRecording> getVideos({String? searchQuery}) {
    if (searchQuery == null || searchQuery.isEmpty) {
      return List.from(_videos);
    }
    return _videos
        .where((v) =>
            v.resolution.toLowerCase().contains(searchQuery.toLowerCase()) ||
            v.codec.toLowerCase().contains(searchQuery.toLowerCase()))
        .toList();
  }

  VideoRecording? getVideoById(String id) {
    try {
      return _videos.firstWhere((v) => v.id == id);
    } catch (e) {
      return null;
    }
  }

  VideoRecording? get latestVideo => _videos.isNotEmpty ? _videos.first : null;

  int get videoCount => _videos.length;
}
