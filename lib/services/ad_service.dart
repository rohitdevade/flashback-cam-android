import 'package:flutter/foundation.dart';

class AdService {
  bool _isAdLoaded = false;

  Future<void> initialize() async {
    debugPrint('Ad service initialized');
  }

  Future<void> loadInterstitialAd() async {
    try {
      debugPrint('Loading interstitial ad...');
      await Future.delayed(Duration(seconds: 1));
      _isAdLoaded = true;
    } catch (e) {
      debugPrint('Failed to load ad: $e');
      _isAdLoaded = false;
    }
  }

  Future<void> showInterstitialAd() async {
    if (!_isAdLoaded) {
      await loadInterstitialAd();
    }
    
    try {
      debugPrint('Showing interstitial ad');
      await Future.delayed(Duration(seconds: 2));
      _isAdLoaded = false;
    } catch (e) {
      debugPrint('Failed to show ad: $e');
    }
  }

  bool get isAdLoaded => _isAdLoaded;

  void dispose() {
    debugPrint('Ad service disposed');
  }
}
