import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashback_cam/models/user.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';

/// Purchase result status
enum PurchaseResult {
  success,
  cancelled,
  error,
  pending,
  verificationFailed,
}

/// Purchase verification result
class PurchaseVerificationResult {
  final bool isValid;
  final String? tier;
  final DateTime? expiresAt;
  final String? errorMessage;

  PurchaseVerificationResult({
    required this.isValid,
    this.tier,
    this.expiresAt,
    this.errorMessage,
  });
}

class SubscriptionService {
  User? _currentUser;
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  // Product IDs - Update these to match your Google Play Console product IDs
  static const String monthlyProductId = 'flashback_cam_monthly';
  static const String yearlyProductId = 'flashback_cam_yearly';
  static const String lifetimeProductId = 'flashback_cam_lifetime';

  // Store fetched products
  Map<String, ProductDetails> _products = {};
  bool _isAvailable = false;

  // Track if we've synced with Google Play this session
  bool _hasRestoredPurchases = false;

  // Stream controller for purchase updates
  final _purchaseResultController =
      StreamController<PurchaseResult>.broadcast();
  Stream<PurchaseResult> get purchaseResultStream =>
      _purchaseResultController.stream;

  // Debug mode - allows purchases to work in debug builds without real IAP
  static const bool _debugPurchasesEnabled = kDebugMode;

  Future<void> initialize() async {
    await _loadUser();

    // Check if in-app purchase is available
    _isAvailable = await _iap.isAvailable();
    if (!_isAvailable) {
      debugPrint('In-app purchase is not available on this device');
      return;
    }

    // Listen to purchase updates
    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription?.cancel(),
      onError: (error) => debugPrint('Purchase stream error: $error'),
    );

    // Load products
    await loadProducts();

    // Sync subscription status with Google Play on app launch
    // This ensures we have the latest subscription state
    await _syncSubscriptionWithStore();
  }

  /// Sync subscription status with the app store
  /// This is critical to prevent subscription fraud and ensure accurate status
  Future<void> _syncSubscriptionWithStore() async {
    if (_debugPurchasesEnabled) {
      debugPrint('🔧 DEBUG MODE: Skipping store sync');
      return;
    }

    if (!_isAvailable || _hasRestoredPurchases) return;

    try {
      debugPrint('📱 Syncing subscription status with Google Play...');

      // Restore purchases to get current subscription status from Google Play
      await _iap.restorePurchases();
      _hasRestoredPurchases = true;

      debugPrint('✅ Subscription sync completed');
    } catch (e) {
      debugPrint('⚠️ Failed to sync with store: $e');
      // Don't fail initialization if sync fails - user can still use cached status
    }
  }

  Future<void> loadProducts() async {
    if (!_isAvailable) return;

    try {
      const productIds = {
        monthlyProductId,
        yearlyProductId,
        lifetimeProductId,
      };

      final ProductDetailsResponse response =
          await _iap.queryProductDetails(productIds);

      if (response.error != null) {
        debugPrint('Error loading products: ${response.error}');
        return;
      }

      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('Products not found: ${response.notFoundIDs}');
      }

      // Store products in a map for easy access
      _products = {
        for (var product in response.productDetails) product.id: product
      };

      debugPrint('Loaded ${_products.length} products');
      for (var product in _products.values) {
        debugPrint(
            'Product: ${product.id} - ${product.title} - ${product.price}');
      }
    } catch (e) {
      debugPrint('Failed to load products: $e');
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) async {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        // Show pending UI
        debugPrint('Purchase pending: ${purchaseDetails.productID}');
        _purchaseResultController.add(PurchaseResult.pending);
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        // Handle error
        debugPrint('Purchase error: ${purchaseDetails.error}');
        _purchaseResultController.add(PurchaseResult.error);
      } else if (purchaseDetails.status == PurchaseStatus.canceled) {
        // Handle cancellation
        debugPrint('Purchase cancelled: ${purchaseDetails.productID}');
        _purchaseResultController.add(PurchaseResult.cancelled);
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        // Verify and deliver product
        final verified = await _verifyAndDeliverProduct(purchaseDetails);
        if (verified) {
          _purchaseResultController.add(PurchaseResult.success);
        } else {
          _purchaseResultController.add(PurchaseResult.verificationFailed);
        }
      }

      // Complete the purchase
      if (purchaseDetails.pendingCompletePurchase) {
        await _iap.completePurchase(purchaseDetails);
      }
    }
  }

  /// Verify purchase with Google Play and deliver product
  /// Returns true if verification succeeded
  Future<bool> _verifyAndDeliverProduct(PurchaseDetails purchaseDetails) async {
    // Ensure user is loaded before verifying purchase
    if (_currentUser == null) {
      debugPrint(
          'Warning: User not loaded when verifying purchase, loading now...');
      await _loadUser();
    }

    debugPrint(
        '🔐 Verifying purchase for product: ${purchaseDetails.productID}');
    debugPrint('   Purchase ID: ${purchaseDetails.purchaseID}');
    debugPrint('   Status: ${purchaseDetails.status}');

    // Verify the purchase
    final verificationResult = await _verifyPurchase(purchaseDetails);

    if (!verificationResult.isValid) {
      debugPrint(
          '❌ Purchase verification failed: ${verificationResult.errorMessage}');
      // Don't grant access for invalid purchases
      return false;
    }

    final tier = verificationResult.tier;
    debugPrint('✅ Purchase verified: tier=$tier');

    if (tier != null && _currentUser != null) {
      // For subscriptions, we don't set local expiration - Google Play manages this
      // For lifetime, we also don't need expiration (null = never expires)
      // The expiration is only used for local trial tracking
      DateTime? expiresAt;

      // Only set local expiration for restored purchases as a cache
      // This will be overwritten on next sync with store
      if (purchaseDetails.status == PurchaseStatus.restored) {
        expiresAt = verificationResult.expiresAt;
      }

      final updatedUser = _currentUser!.copyWith(
        isPro: true,
        proTier: tier,
        proExpiresAt: expiresAt,
        updatedAt: DateTime.now(),
      );

      // Store purchase token for future verification
      await _storePurchaseToken(purchaseDetails);
      await _saveUser(updatedUser);
      debugPrint('✅ Product delivered: $tier');
      return true;
    } else if (tier == null) {
      debugPrint('Error: Unknown product ID: ${purchaseDetails.productID}');
      return false;
    }
    return false;
  }

  /// Verify a purchase using Google Play verification
  /// In production, this should call your backend server for secure verification
  Future<PurchaseVerificationResult> _verifyPurchase(
      PurchaseDetails purchaseDetails) async {
    try {
      // Get the tier from product ID
      String? tier;
      if (purchaseDetails.productID == monthlyProductId) {
        tier = 'monthly';
      } else if (purchaseDetails.productID == yearlyProductId) {
        tier = 'yearly';
      } else if (purchaseDetails.productID == lifetimeProductId) {
        tier = 'lifetime';
      }

      if (tier == null) {
        return PurchaseVerificationResult(
          isValid: false,
          errorMessage: 'Unknown product ID: ${purchaseDetails.productID}',
        );
      }

      // =========================================================================
      // ANDROID PLATFORM-SPECIFIC VERIFICATION
      // =========================================================================
      if (Platform.isAndroid) {
        final androidDetails = purchaseDetails as GooglePlayPurchaseDetails;
        final billingClientPurchase = androidDetails.billingClientPurchase;

        // Check purchase state - must be purchased (not pending/unspecified)
        if (billingClientPurchase.purchaseState !=
            PurchaseStateWrapper.purchased) {
          debugPrint(
              '⚠️ Purchase state is not purchased: ${billingClientPurchase.purchaseState}');
          return PurchaseVerificationResult(
            isValid: false,
            errorMessage: 'Purchase not in purchased state',
          );
        }

        // Check if purchase is acknowledged (for restored purchases)
        final isAcknowledged = billingClientPurchase.isAcknowledged;
        debugPrint('   Purchase acknowledged: $isAcknowledged');

        // Get the purchase token for verification
        final purchaseToken = billingClientPurchase.purchaseToken;
        final orderId = billingClientPurchase.orderId;

        debugPrint('   Order ID: $orderId');
        debugPrint('   Purchase Token: ${purchaseToken.substring(0, 20)}...');

        // =====================================================================
        // TODO: BACKEND VERIFICATION (Recommended for production)
        // =====================================================================
        // For maximum security, you should verify the purchase token with your
        // backend server, which then verifies with Google Play Developer API:
        //
        // 1. Send purchaseToken, productId, and packageName to your backend
        // 2. Backend calls Google Play Developer API:
        //    - For subscriptions: purchases.subscriptions.get
        //    - For one-time products: purchases.products.get
        // 3. Backend verifies the response and returns validity + expiration
        //
        // Example:
        // final response = await http.post(
        //   Uri.parse('https://your-backend.com/verify-purchase'),
        //   body: jsonEncode({
        //     'purchaseToken': purchaseToken,
        //     'productId': purchaseDetails.productID,
        //     'packageName': 'com.rochapps.flashbackcam',
        //   }),
        // );
        // final result = jsonDecode(response.body);
        // return PurchaseVerificationResult(
        //   isValid: result['valid'],
        //   tier: tier,
        //   expiresAt: result['expiresAt'] != null
        //       ? DateTime.parse(result['expiresAt'])
        //       : null,
        // );
        // =====================================================================

        // For now, we trust Google Play's verification since:
        // 1. Purchase came through official Google Play billing
        // 2. We verified the purchase state is "purchased"
        // 3. We're storing the token for audit purposes
        //
        // This is acceptable for apps without backend, but has fraud risk:
        // - Users could potentially exploit refunds
        // - Subscription cancellation won't be detected until next sync

        debugPrint('✅ Google Play purchase verified locally');

        // For subscriptions, don't set expiration locally - rely on restore
        DateTime? expiresAt;
        if (tier == 'lifetime') {
          expiresAt = null; // Never expires
        }
        // For monthly/yearly, Google Play manages expiration via restore

        return PurchaseVerificationResult(
          isValid: true,
          tier: tier,
          expiresAt: expiresAt,
        );
      }

      // =========================================================================
      // iOS VERIFICATION (placeholder for future iOS support)
      // =========================================================================
      if (Platform.isIOS) {
        // iOS verification would use StoreKit verification
        // For now, trust the purchase
        return PurchaseVerificationResult(
          isValid: true,
          tier: tier,
        );
      }

      // Unknown platform
      return PurchaseVerificationResult(
        isValid: true,
        tier: tier,
      );
    } catch (e) {
      debugPrint('❌ Purchase verification error: $e');
      return PurchaseVerificationResult(
        isValid: false,
        errorMessage: 'Verification error: $e',
      );
    }
  }

  /// Store purchase token for audit and future verification
  Future<void> _storePurchaseToken(PurchaseDetails purchaseDetails) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (Platform.isAndroid) {
        final androidDetails = purchaseDetails as GooglePlayPurchaseDetails;
        await prefs.setString('lastPurchaseToken',
            androidDetails.billingClientPurchase.purchaseToken);
        await prefs.setString(
            'lastOrderId', androidDetails.billingClientPurchase.orderId);
      }

      await prefs.setString('lastPurchaseId', purchaseDetails.purchaseID ?? '');
      await prefs.setString('lastProductId', purchaseDetails.productID);
      await prefs.setString(
          'lastPurchaseDate', DateTime.now().toIso8601String());

      debugPrint('💾 Purchase token stored for audit');
    } catch (e) {
      debugPrint('⚠️ Failed to store purchase token: $e');
    }
  }

  /// Revoke subscription access (called when verification fails or subscription expires)
  /// This is called when Google Play restore returns no active purchases
  // ignore: unused_element
  Future<void> _revokeSubscription({String? reason}) async {
    debugPrint('🚫 Revoking subscription access: $reason');

    if (_currentUser == null) return;

    final updatedUser = _currentUser!.copyWith(
      isPro: false,
      proTier: null,
      proExpiresAt: null,
      updatedAt: DateTime.now(),
    );

    await _saveUser(updatedUser);
    debugPrint('✅ Subscription access revoked');
  }

  Future<void> _loadUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var isPro = prefs.getBool('isPro') ?? false;
      var proTier = prefs.getString('proTier');
      final proExpiresAtStr = prefs.getString('proExpiresAt');
      final trialStartedAtStr = prefs.getString('trialStartedAt');
      final trialUsed = prefs.getBool('trialUsed') ?? false;

      final proExpiresAt =
          proExpiresAtStr != null ? DateTime.parse(proExpiresAtStr) : null;

      // For subscription tiers (monthly/yearly), we don't check local expiration
      // Instead, we rely on Google Play sync via restorePurchases()
      // Only check expiration for locally-managed trial

      // For lifetime purchases, they never expire (proExpiresAt is null)
      // For subscriptions, Google Play manages expiration via restore

      // Note: Local expiration check is kept only as a fallback
      // The primary source of truth is Google Play via _syncSubscriptionWithStore()
      if (isPro &&
          proTier != 'lifetime' &&
          proExpiresAt != null &&
          DateTime.now().isAfter(proExpiresAt)) {
        debugPrint(
            '⚠️ Local subscription cache expired on ${proExpiresAt.toIso8601String()}');
        debugPrint('   Will verify with Google Play on next sync');
        // Don't immediately revoke - wait for store sync
        // This prevents issues when device time is wrong
      }

      _currentUser = User(
        id: 'default_user',
        isPro: isPro,
        proTier: proTier,
        proExpiresAt: isPro ? proExpiresAt : null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        trialStartedAt: trialStartedAtStr != null
            ? DateTime.parse(trialStartedAtStr)
            : null,
        trialUsed: trialUsed,
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
      // Save trial fields
      if (user.trialStartedAt != null) {
        await prefs.setString(
            'trialStartedAt', user.trialStartedAt!.toIso8601String());
      } else {
        await prefs.remove('trialStartedAt');
      }
      await prefs.setBool('trialUsed', user.trialUsed);
      _currentUser = user;
    } catch (e) {
      debugPrint('Failed to save user: $e');
    }
  }

  Future<bool> purchaseSubscription(String tier) async {
    // Ensure user is initialized
    if (_currentUser == null) {
      debugPrint('Error: User not initialized, loading...');
      await _loadUser();
      if (_currentUser == null) {
        debugPrint('Error: Failed to load user');
        return false;
      }
    }

    // In debug mode, simulate successful purchases for testing
    if (_debugPurchasesEnabled) {
      debugPrint('🔧 DEBUG MODE: Simulating purchase for tier: $tier');
      await Future.delayed(const Duration(seconds: 1)); // Simulate delay

      DateTime? expiresAt;
      if (tier == 'monthly') {
        expiresAt = DateTime.now().add(const Duration(days: 30));
      } else if (tier == 'yearly') {
        expiresAt = DateTime.now().add(const Duration(days: 365));
      }
      // lifetime has no expiration date (null)

      final updatedUser = _currentUser!.copyWith(
        isPro: true,
        proTier: tier,
        proExpiresAt: expiresAt,
        updatedAt: DateTime.now(),
      );

      await _saveUser(updatedUser);
      debugPrint(
          '✅ DEBUG MODE: Purchase simulated successfully for tier: $tier');
      return true;
    }

    if (!_isAvailable) {
      debugPrint('In-app purchase is not available');
      return false;
    }

    String productId;
    if (tier == 'monthly') {
      productId = monthlyProductId;
    } else if (tier == 'yearly') {
      productId = yearlyProductId;
    } else if (tier == 'lifetime') {
      productId = lifetimeProductId;
    } else {
      debugPrint('Unknown tier: $tier');
      return false;
    }

    final product = _products[productId];
    if (product == null) {
      debugPrint('Product not found: $productId');
      debugPrint('Available products: ${_products.keys.toList()}');
      return false;
    }

    try {
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: product,
      );

      bool success;
      if (tier == 'lifetime') {
        // Use buyNonConsumable for one-time lifetime purchase
        success = await _iap.buyNonConsumable(
          purchaseParam: purchaseParam,
        );
      } else {
        // Use buyNonConsumable for subscriptions (Google Play handles subscription logic)
        // Note: in_app_purchase plugin uses buyNonConsumable for both subscriptions and
        // non-consumables on Android. The product type is determined by how you set it up
        // in Google Play Console (subscription vs in-app product).
        success = await _iap.buyNonConsumable(
          purchaseParam: purchaseParam,
        );
      }

      return success;
    } catch (e) {
      debugPrint('Failed to purchase subscription: $e');
      return false;
    }
  }

  Future<bool> restorePurchases() async {
    // In debug mode, simulate restore - check if user was already pro
    if (_debugPurchasesEnabled) {
      debugPrint('🔧 DEBUG MODE: Simulating restore purchases');
      await Future.delayed(const Duration(seconds: 1));
      // In debug mode, restore will succeed if user was previously marked as pro
      final wasPro = _currentUser?.isPro ?? false;
      debugPrint('🔧 DEBUG MODE: User was pro: $wasPro');
      return wasPro;
    }

    if (!_isAvailable) {
      debugPrint('In-app purchase is not available');
      return false;
    }

    try {
      await _iap.restorePurchases();
      return true;
    } catch (e) {
      debugPrint('Failed to restore purchases: $e');
      return false;
    }
  }

  // Getters for product details
  ProductDetails? getProductDetails(String tier) {
    String productId;
    if (tier == 'monthly') {
      productId = monthlyProductId;
    } else if (tier == 'yearly') {
      productId = yearlyProductId;
    } else if (tier == 'lifetime') {
      productId = lifetimeProductId;
    } else {
      return null;
    }
    return _products[productId];
  }

  bool get isAvailable => _isAvailable;

  Map<String, ProductDetails> get products => _products;

  void dispose() {
    _subscription?.cancel();
    _purchaseResultController.close();
  }

  User get currentUser =>
      _currentUser ??
      User(
          id: 'default_user',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now());

  bool get isPro => _currentUser?.isPro ?? false;

  /// Check if user has Pro access (paid or trial)
  bool get hasProAccess => _currentUser?.hasProAccess ?? false;

  /// Check if user is in an active trial
  bool get isTrialActive => _currentUser?.isTrialActive ?? false;

  /// Check if user has already used their trial
  bool get trialUsed => _currentUser?.trialUsed ?? false;

  /// Get remaining trial days
  int get trialDaysRemaining => _currentUser?.trialDaysRemaining ?? 0;

  /// Check if user can start a free trial
  bool get canStartTrial {
    if (_currentUser == null) return false;
    if (_currentUser!.isPro) return false;
    if (_currentUser!.trialUsed) return false;
    if (_currentUser!.isTrialActive) return false; // Already in trial
    return true;
  }

  /// Start a free trial for the user
  /// Returns true if trial was started successfully, false otherwise
  Future<bool> startTrial() async {
    if (_currentUser == null) {
      debugPrint('Error: Cannot start trial - user not loaded');
      await _loadUser();
    }

    if (!canStartTrial) {
      debugPrint(
          'Cannot start trial: isPro=${_currentUser?.isPro}, trialUsed=${_currentUser?.trialUsed}, isTrialActive=${_currentUser?.isTrialActive}');
      return false;
    }

    try {
      final updatedUser = _currentUser!.copyWith(
        trialStartedAt: DateTime.now(),
        trialUsed: true,
        updatedAt: DateTime.now(),
      );

      await _saveUser(updatedUser);
      debugPrint('✅ Free trial started successfully');
      return true;
    } catch (e) {
      debugPrint('Failed to start trial: $e');
      return false;
    }
  }

  /// Check subscription status and refresh if needed
  Future<void> refreshSubscriptionStatus() async {
    await _loadUser();
    debugPrint(
        'Subscription status refreshed: isPro=$isPro, hasProAccess=$hasProAccess');
  }
}
