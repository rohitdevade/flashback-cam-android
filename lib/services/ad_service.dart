import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  InterstitialAd? _interstitialAd;
  BannerAd? _galleryBannerAd;
  BannerAd? _settingsBannerAd;
  BannerAd? _videoPlayerBannerAd;
  bool _isInterstitialAdLoaded = false;
  int _galleryVisitCount = 0;
  static const int _showAdEveryNthGalleryVisit =
      3; // Show ad every 3rd gallery visit

  // Test Ad IDs for AdMob
  // Android Test IDs
  static const String _androidTestInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _androidTestBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';

  // iOS Test IDs
  static const String _iosTestInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/4411468910';
  static const String _iosTestBannerAdUnitId =
      'ca-app-pub-3940256099942544/2934735716';

  String get _interstitialAdUnitId {
    if (Platform.isAndroid) {
      return _androidTestInterstitialAdUnitId;
    } else if (Platform.isIOS) {
      return _iosTestInterstitialAdUnitId;
    }
    return '';
  }

  String get _bannerAdUnitId {
    if (Platform.isAndroid) {
      return _androidTestBannerAdUnitId;
    } else if (Platform.isIOS) {
      return _iosTestBannerAdUnitId;
    }
    return '';
  }

  Future<void> initialize() async {
    debugPrint('AdService: Initializing Mobile Ads SDK...');
    await MobileAds.instance.initialize();
    debugPrint('AdService: Mobile Ads SDK initialized');
    await loadInterstitialAd();
  }

  Future<void> loadInterstitialAd() async {
    if (_interstitialAd != null) return;

    debugPrint('AdService: Loading interstitial ad...');
    await InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('AdService: Interstitial ad loaded');
          _interstitialAd = ad;
          _isInterstitialAdLoaded = true;
          _interstitialAd!.setImmersiveMode(true);

          _interstitialAd!.fullScreenContentCallback =
              FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              debugPrint('AdService: Interstitial ad dismissed');
              ad.dispose();
              _interstitialAd = null;
              _isInterstitialAdLoaded = false;
              loadInterstitialAd(); // Preload next ad
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              debugPrint('AdService: Interstitial ad failed to show: $error');
              ad.dispose();
              _interstitialAd = null;
              _isInterstitialAdLoaded = false;
              loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (error) {
          debugPrint('AdService: Failed to load interstitial ad: $error');
          _isInterstitialAdLoaded = false;
        },
      ),
    );
  }

  Future<void> showInterstitialAd() async {
    if (!_isInterstitialAdLoaded || _interstitialAd == null) {
      debugPrint('AdService: Interstitial ad not loaded, loading now...');
      await loadInterstitialAd();
      // Wait a bit for ad to load
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (_interstitialAd != null) {
      debugPrint('AdService: Showing interstitial ad');
      await _interstitialAd!.show();
    } else {
      debugPrint('AdService: No interstitial ad available to show');
    }
  }

  /// Show interstitial ad when opening gallery (not every time)
  Future<void> showGalleryInterstitialAd() async {
    _galleryVisitCount++;
    debugPrint('AdService: Gallery visit count: $_galleryVisitCount');

    if (_galleryVisitCount >= _showAdEveryNthGalleryVisit) {
      _galleryVisitCount = 0;
      await showInterstitialAd();
    }
  }

  /// Create and return a banner ad for gallery screen
  BannerAd createGalleryBannerAd() {
    _galleryBannerAd?.dispose();
    _galleryBannerAd = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('AdService: Gallery banner ad loaded');
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('AdService: Gallery banner ad failed to load: $error');
          ad.dispose();
        },
        onAdOpened: (ad) => debugPrint('AdService: Gallery banner ad opened'),
        onAdClosed: (ad) => debugPrint('AdService: Gallery banner ad closed'),
      ),
    );
    _galleryBannerAd!.load();
    return _galleryBannerAd!;
  }

  /// Create and return a banner ad for settings screen
  BannerAd createSettingsBannerAd() {
    _settingsBannerAd?.dispose();
    _settingsBannerAd = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('AdService: Settings banner ad loaded');
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('AdService: Settings banner ad failed to load: $error');
          ad.dispose();
        },
        onAdOpened: (ad) => debugPrint('AdService: Settings banner ad opened'),
        onAdClosed: (ad) => debugPrint('AdService: Settings banner ad closed'),
      ),
    );
    _settingsBannerAd!.load();
    return _settingsBannerAd!;
  }

  /// Create and return a banner ad for video player screen
  BannerAd createVideoPlayerBannerAd() {
    _videoPlayerBannerAd?.dispose();
    _videoPlayerBannerAd = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('AdService: Video player banner ad loaded');
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint(
              'AdService: Video player banner ad failed to load: $error');
          ad.dispose();
        },
        onAdOpened: (ad) =>
            debugPrint('AdService: Video player banner ad opened'),
        onAdClosed: (ad) =>
            debugPrint('AdService: Video player banner ad closed'),
      ),
    );
    _videoPlayerBannerAd!.load();
    return _videoPlayerBannerAd!;
  }

  bool get isAdLoaded => _isInterstitialAdLoaded;

  void dispose() {
    debugPrint('AdService: Disposing ads');
    _interstitialAd?.dispose();
    _galleryBannerAd?.dispose();
    _settingsBannerAd?.dispose();
    _videoPlayerBannerAd?.dispose();
  }
}
