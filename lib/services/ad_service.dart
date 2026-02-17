import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flashback_cam/services/deferred_init_service.dart';

/// ═══════════════════════════════════════════════════════════════════════════════
/// AD SERVICE - COLD START OPTIMIZED
///
/// COLD START OPTIMIZATION:
/// - SDK initialization is DEFERRED until first ad request or UI is visible
/// - NO AdMob SDK loading during app startup
/// - Consent gathering happens lazily on first ad interaction
/// - This removes ~200-500ms from cold start time
///
/// When AdMob SDK is initialized:
/// - On first interstitial/rewarded ad request
/// - On first banner ad load
/// - Never during Application.onCreate or main()
/// ═══════════════════════════════════════════════════════════════════════════════
class AdService {
  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  BannerAd? _galleryBannerAd;
  BannerAd? _settingsBannerAd;
  BannerAd? _videoPlayerBannerAd;
  bool _isInterstitialAdLoaded = false;
  bool _isRewardedAdLoaded = false;
  int _galleryVisitCount = 0;
  int _recordingCount = 0; // Track recordings for ad frequency
  static const int _showAdEveryNthGalleryVisit =
      2; // Show ad every alternate gallery visit

  // ═══════════════════════════════════════════════════════════════════════════════
  // MOCK ADS FOR TESTING - Set to true to simulate rewarded ads without real ads
  // ═══════════════════════════════════════════════════════════════════════════════
  static const bool _useMockRewardedAds = false;

  // UMP Consent status
  bool _consentGathered = false;
  bool _canShowAds = false;

  // COLD START: Track if SDK has been initialized (deferred)
  bool _sdkInitialized = false;
  final DeferredInitService _deferredInit = DeferredInitService();

  // Production Ad IDs for AdMob
  // App ID: ca-app-pub-6281772921050479~8837812493
  // Android Production IDs
  static const String _androidInterstitialAdUnitId =
      'ca-app-pub-6281772921050479/1838942262';
  static const String _androidBannerAdUnitId =
      'ca-app-pub-6281772921050479/8339829482';
  static const String _androidRewardedAdUnitId =
      'ca-app-pub-6281772921050479/3448085484'; // Rewarded ad for buffer unlock

  // iOS Production IDs (not used currently)
  static const String _iosInterstitialAdUnitId = '';
  static const String _iosBannerAdUnitId = '';
  static const String _iosRewardedAdUnitId = '';

  String get _interstitialAdUnitId {
    if (Platform.isAndroid) {
      return _androidInterstitialAdUnitId;
    } else if (Platform.isIOS) {
      return _iosInterstitialAdUnitId;
    }
    return '';
  }

  String get _bannerAdUnitId {
    if (Platform.isAndroid) {
      return _androidBannerAdUnitId;
    } else if (Platform.isIOS) {
      return _iosBannerAdUnitId;
    }
    return '';
  }

  String get _rewardedAdUnitId {
    if (Platform.isAndroid) {
      return _androidRewardedAdUnitId;
    } else if (Platform.isIOS) {
      return _iosRewardedAdUnitId;
    }
    return '';
  }

  /// Check if we can request ads based on consent status
  bool get canShowAds => _canShowAds;

  /// Check if consent has been gathered
  bool get consentGathered => _consentGathered;

  /// Check if rewarded ad is loaded and ready
  bool get isRewardedAdLoaded => _isRewardedAdLoaded;

  /// Check if SDK has been initialized (for UI state)
  bool get isSdkInitialized => _sdkInitialized;

  /// ═══════════════════════════════════════════════════════════════════════════════
  /// COLD START: No-op initialize - actual SDK init is deferred
  ///
  /// This method does NOTHING during cold start to ensure fast first frame.
  /// The actual SDK initialization happens on first ad request.
  /// ═══════════════════════════════════════════════════════════════════════════════
  Future<void> initialize() async {
    // COLD START OPTIMIZATION: Do nothing here
    // AdMob SDK will be initialized lazily on first ad request
    debugPrint(
        'AdService: Deferred initialization mode - SDK will load on first ad request');
  }

  /// ═══════════════════════════════════════════════════════════════════════════════
  /// COLD START: Lazy SDK initialization - called on first ad request
  ///
  /// This ensures the AdMob SDK is only loaded when actually needed,
  /// removing ~200-500ms from cold start time.
  /// ═══════════════════════════════════════════════════════════════════════════════
  Future<void> _ensureSdkInitialized() async {
    if (_sdkInitialized) return;

    await _deferredInit.initializeComponent(
      DeferredComponents.ads,
      () async {
        debugPrint('AdService: Lazy-initializing Mobile Ads SDK...');

        // First, gather consent using UMP before loading any ads
        await _gatherConsent();

        // Initialize Mobile Ads SDK
        await MobileAds.instance.initialize();
        _sdkInitialized = true;
        debugPrint('AdService: Mobile Ads SDK initialized (deferred)');

        // Only load ads if we can show them
        if (_canShowAds) {
          await loadInterstitialAd();
          await loadRewardedAd();
        } else {
          debugPrint(
              'AdService: Cannot show ads - consent not given or not required');
        }
      },
    );
  }

  /// ═══════════════════════════════════════════════════════════════════════════════
  /// REMOVED: Old synchronous initialize method
  /// The code below is the original initialize() that ran during cold start
  /// ═══════════════════════════════════════════════════════════════════════════════

  /// Gather user consent using UMP (User Messaging Platform)
  /// This is required for GDPR compliance in EU/EEA
  Future<void> _gatherConsent() async {
    debugPrint('AdService: Gathering user consent...');

    final completer = Completer<void>();

    // Configure consent request parameters
    final params = ConsentRequestParameters();

    // For testing purposes in debug mode, you can enable test geography
    // Uncomment the following lines to test consent flow:
    // if (kDebugMode) {
    //   final debugSettings = ConsentDebugSettings(
    //     debugGeography: DebugGeography.debugGeographyEea,
    //     testIdentifiers: ['YOUR_TEST_DEVICE_ID'], // Add your test device ID
    //   );
    //   params = ConsentRequestParameters(consentDebugSettings: debugSettings);
    // }

    // Request consent info update
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        debugPrint('AdService: Consent info updated successfully');

        // Check if consent form is available and required
        if (await ConsentInformation.instance.isConsentFormAvailable()) {
          debugPrint('AdService: Consent form is available');
          await _loadAndShowConsentFormIfRequired();
        } else {
          debugPrint('AdService: Consent form is not available');
        }

        // Update consent status
        await _updateConsentStatus();
        _consentGathered = true;

        if (!completer.isCompleted) completer.complete();
      },
      (FormError error) {
        debugPrint('AdService: Consent info update failed: ${error.message}');
        // Even if consent update fails, we might still be able to show ads
        // (e.g., in regions where consent is not required)
        _updateConsentStatus();
        _consentGathered = true;

        if (!completer.isCompleted) completer.complete();
      },
    );

    // Wait for consent gathering with timeout
    await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        debugPrint('AdService: Consent gathering timed out');
        _consentGathered = true;
        _updateConsentStatus();
      },
    );
  }

  /// Load and show consent form if required
  Future<void> _loadAndShowConsentFormIfRequired() async {
    final status = await ConsentInformation.instance.getConsentStatus();
    debugPrint('AdService: Current consent status: $status');

    if (status == ConsentStatus.required) {
      debugPrint('AdService: Consent is required, loading form...');

      final completer = Completer<void>();

      ConsentForm.loadConsentForm(
        (ConsentForm consentForm) async {
          debugPrint('AdService: Consent form loaded');

          // Show the consent form
          consentForm.show((FormError? formError) {
            if (formError != null) {
              debugPrint(
                  'AdService: Error showing consent form: ${formError.message}');
            } else {
              debugPrint('AdService: Consent form shown and dismissed');
            }
            if (!completer.isCompleted) completer.complete();
          });
        },
        (FormError error) {
          debugPrint(
              'AdService: Failed to load consent form: ${error.message}');
          if (!completer.isCompleted) completer.complete();
        },
      );

      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('AdService: Consent form display timed out');
        },
      );
    }
  }

  /// Update the consent status and determine if we can show ads
  Future<void> _updateConsentStatus() async {
    final status = await ConsentInformation.instance.getConsentStatus();
    debugPrint('AdService: Final consent status: $status');

    // Check if we can request ads
    // We can show ads if:
    // 1. Consent is not required (non-EEA users)
    // 2. Consent was obtained
    // 3. Consent status is unknown (we'll try to show ads)
    _canShowAds = status == ConsentStatus.notRequired ||
        status == ConsentStatus.obtained ||
        status == ConsentStatus.unknown;

    debugPrint('AdService: Can show ads: $_canShowAds');
  }

  /// Allow user to change consent preferences (for privacy settings)
  Future<void> showPrivacyOptionsForm() async {
    final status =
        await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
    debugPrint('AdService: Privacy options requirement status: $status');

    if (status == PrivacyOptionsRequirementStatus.required) {
      final completer = Completer<void>();

      ConsentForm.showPrivacyOptionsForm((FormError? formError) {
        if (formError != null) {
          debugPrint(
              'AdService: Error showing privacy options: ${formError.message}');
        } else {
          debugPrint('AdService: Privacy options form dismissed');
        }
        // Update consent status after user changes preferences
        _updateConsentStatus();
        if (!completer.isCompleted) completer.complete();
      });

      await completer.future;
    } else {
      debugPrint('AdService: Privacy options form not required');
    }
  }

  /// Check if privacy options form should be shown in settings
  Future<bool> isPrivacyOptionsRequired() async {
    final status =
        await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
    return status == PrivacyOptionsRequirementStatus.required;
  }

  /// Reset consent for testing purposes (debug only)
  Future<void> resetConsent() async {
    if (kDebugMode) {
      debugPrint('AdService: Resetting consent information');
      await ConsentInformation.instance.reset();
      _consentGathered = false;
      _canShowAds = false;
    }
  }

  Future<void> loadInterstitialAd() async {
    // COLD START: Ensure SDK is initialized before loading ads
    await _ensureSdkInitialized();

    if (_interstitialAd != null) return;

    // Check consent before loading ads
    if (!_canShowAds) {
      debugPrint('AdService: Cannot load interstitial ad - no consent');
      return;
    }

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

          // Retry loading ad after 2 seconds
          Future.delayed(const Duration(seconds: 2), () {
            loadInterstitialAd();
          });
        },
      ),
    );
  }

  Future<void> showInterstitialAd() async {
    // Check consent before showing ads
    if (!_canShowAds) {
      debugPrint('AdService: Cannot show interstitial ad - no consent');
      return;
    }

    if (!_isInterstitialAdLoaded || _interstitialAd == null) {
      debugPrint('AdService: Interstitial ad not ready, skipping');
      // Non-blocking: load for next time instead of waiting
      await loadInterstitialAd();
      return;
    }

    if (_interstitialAd != null) {
      debugPrint('AdService: Showing interstitial ad');
      await _interstitialAd!.show();
    } else {
      debugPrint('AdService: No interstitial ad available to show');
    }
  }

  /// Show interstitial ad when opening gallery (every time now)
  Future<void> showGalleryInterstitialAd() async {
    debugPrint('AdService: Showing gallery ad (every time)');
    await showInterstitialAd();
  }

  /// Show interstitial ad after recording with custom frequency
  /// Pattern: 1st (show), 2nd (skip), 3rd (show), 4th (skip), 5th (show), etc.
  Future<void> showRecordingInterstitialAd() async {
    _recordingCount++;
    debugPrint('AdService: Recording count: $_recordingCount');

    // Show on odd recordings only: 1st, 3rd, 5th, 7th...
    if (_recordingCount.isOdd) {
      debugPrint('AdService: Showing ad for recording #$_recordingCount');
      await showInterstitialAd();
    } else {
      debugPrint('AdService: Skipping ad for recording #$_recordingCount');
    }
  }

  /// Load a rewarded ad for buffer unlock
  Future<void> loadRewardedAd() async {
    // COLD START: Ensure SDK is initialized before loading ads
    await _ensureSdkInitialized();

    if (_rewardedAd != null) return;

    // Check consent before loading ads
    if (!_canShowAds) {
      debugPrint('AdService: Cannot load rewarded ad - no consent');
      return;
    }

    debugPrint('AdService: Loading rewarded ad...');
    await RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('AdService: Rewarded ad loaded');
          _rewardedAd = ad;
          _isRewardedAdLoaded = true;
          _rewardedAd!.setImmersiveMode(true);
        },
        onAdFailedToLoad: (error) {
          debugPrint('AdService: Failed to load rewarded ad: $error');
          _isRewardedAdLoaded = false;
        },
      ),
    );
  }

  /// Show rewarded ad for buffer unlock
  /// Returns true if the user earned the reward, false otherwise
  Future<bool> showRewardedAdForBufferUnlock() async {
    // ═══════════════════════════════════════════════════════════════════════════════
    // MOCK MODE - Simulate successful rewarded ad for testing
    // ═══════════════════════════════════════════════════════════════════════════════
    if (_useMockRewardedAds) {
      debugPrint('AdService: [MOCK] Simulating rewarded ad...');
      // Simulate ad loading and watching time
      await Future.delayed(const Duration(seconds: 2));
      debugPrint('AdService: [MOCK] User earned reward!');
      return true;
    }

    // Check consent before showing ads
    if (!_canShowAds) {
      debugPrint('AdService: Cannot show rewarded ad - no consent');
      return false;
    }

    if (!_isRewardedAdLoaded || _rewardedAd == null) {
      debugPrint('AdService: Rewarded ad not loaded, loading now...');
      await loadRewardedAd();
      // Wait a bit for ad to load
      await Future.delayed(const Duration(milliseconds: 1000));
    }

    if (_rewardedAd == null) {
      debugPrint('AdService: No rewarded ad available to show');
      return false;
    }

    final completer = Completer<bool>();
    bool _rewardEarned = false;

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        debugPrint(
            'AdService: Rewarded ad dismissed, reward earned: $_rewardEarned');
        ad.dispose();
        _rewardedAd = null;
        _isRewardedAdLoaded = false;
        loadRewardedAd(); // Preload next ad
        if (!completer.isCompleted) {
          completer.complete(_rewardEarned);
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('AdService: Rewarded ad failed to show: $error');
        ad.dispose();
        _rewardedAd = null;
        _isRewardedAdLoaded = false;
        loadRewardedAd();
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      },
    );

    debugPrint('AdService: Showing rewarded ad');
    await _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) {
        debugPrint(
            'AdService: User earned reward: ${reward.amount} ${reward.type}');
        _rewardEarned = true;
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        debugPrint('AdService: Rewarded ad timed out');
        return false;
      },
    );
  }

  /// Create and return a banner ad for gallery screen
  /// Returns null if consent is not given
  /// COLD START: Initializes SDK lazily on first banner request
  Future<BannerAd?> createGalleryBannerAd() async {
    // COLD START: Ensure SDK is initialized before creating ads
    await _ensureSdkInitialized();

    // Check consent before creating ads
    if (!_canShowAds) {
      debugPrint('AdService: Cannot create gallery banner ad - no consent');
      return null;
    }

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
  /// Returns null if consent is not given
  /// COLD START: Initializes SDK lazily on first banner request
  Future<BannerAd?> createSettingsBannerAd() async {
    // COLD START: Ensure SDK is initialized before creating ads
    await _ensureSdkInitialized();

    // Check consent before creating ads
    if (!_canShowAds) {
      debugPrint('AdService: Cannot create settings banner ad - no consent');
      return null;
    }

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
  /// Returns null if consent is not given
  /// COLD START: Initializes SDK lazily on first banner request
  Future<BannerAd?> createVideoPlayerBannerAd() async {
    // COLD START: Ensure SDK is initialized before creating ads
    await _ensureSdkInitialized();

    // Check consent before creating ads
    if (!_canShowAds) {
      debugPrint(
          'AdService: Cannot create video player banner ad - no consent');
      return null;
    }

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
    _rewardedAd?.dispose();
    _galleryBannerAd?.dispose();
    _settingsBannerAd?.dispose();
    _videoPlayerBannerAd?.dispose();
  }
}
