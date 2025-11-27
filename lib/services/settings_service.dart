import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashback_cam/models/app_settings.dart';

class SettingsService {
  static const _settingsKey = 'app_settings';
  AppSettings _settings = AppSettings.defaults();

  Future<void> initialize() async {
    await _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString(_settingsKey);
      if (settingsJson != null) {
        _settings = AppSettings.fromJson(json.decode(settingsJson));
      }
    } catch (e) {
      debugPrint('Failed to load settings: $e');
      _settings = AppSettings.defaults();
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_settingsKey, json.encode(_settings.toJson()));
    } catch (e) {
      debugPrint('Failed to save settings: $e');
    }
  }

  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
    await _saveSettings();
  }

  AppSettings get settings => _settings;
}
