import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashback_cam/models/user.dart';

class SubscriptionService {
  User? _currentUser;

  Future<void> initialize() async {
    await _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isPro = prefs.getBool('isPro') ?? false;
      final proTier = prefs.getString('proTier');
      final proExpiresAtStr = prefs.getString('proExpiresAt');

      _currentUser = User(
        id: 'default_user',
        isPro: isPro,
        proTier: proTier,
        proExpiresAt:
            proExpiresAtStr != null ? DateTime.parse(proExpiresAtStr) : null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('Failed to load user: $e');
      _currentUser = User(
        id: 'default_user',
        isPro: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }
  }

  Future<void> _saveUser(User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isPro', user.isPro);
      if (user.proTier != null) {
        await prefs.setString('proTier', user.proTier!);
      } else {
        await prefs.remove('proTier');
      }
      if (user.proExpiresAt != null) {
        await prefs.setString(
            'proExpiresAt', user.proExpiresAt!.toIso8601String());
      } else {
        await prefs.remove('proExpiresAt');
      }
      _currentUser = user;
    } catch (e) {
      debugPrint('Failed to save user: $e');
    }
  }

  Future<bool> purchaseSubscription(String tier) async {
    try {
      debugPrint('Purchasing subscription: $tier');
      await Future.delayed(Duration(seconds: 1));

      DateTime? expiresAt;
      if (tier == 'monthly') {
        expiresAt = DateTime.now().add(Duration(days: 30));
      } else if (tier == 'yearly') {
        expiresAt = DateTime.now().add(Duration(days: 365));
      }
      // lifetime has no expiration date (null)

      final updatedUser = _currentUser!.copyWith(
        isPro: true,
        proTier: tier,
        proExpiresAt: expiresAt,
        updatedAt: DateTime.now(),
      );

      await _saveUser(updatedUser);
      return true;
    } catch (e) {
      debugPrint('Failed to purchase subscription: $e');
      return false;
    }
  }

  Future<bool> restorePurchases() async {
    try {
      debugPrint('Restoring purchases...');
      await Future.delayed(Duration(seconds: 1));
      return false;
    } catch (e) {
      debugPrint('Failed to restore purchases: $e');
      return false;
    }
  }

  User get currentUser =>
      _currentUser ??
      User(
          id: 'default_user',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now());

  bool get isPro => _currentUser?.isPro ?? false;
}
