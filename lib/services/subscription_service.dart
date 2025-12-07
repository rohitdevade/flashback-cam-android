import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashback_cam/models/user.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Purchase result status
enum PurchaseResult {
  success,
  cancelled,
  error,
  pending,
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
        await _verifyAndDeliverProduct(purchaseDetails);
        _purchaseResultController.add(PurchaseResult.success);
      }

      // Complete the purchase
      if (purchaseDetails.pendingCompletePurchase) {
        await _iap.completePurchase(purchaseDetails);
      }
    }
  }

  Future<void> _verifyAndDeliverProduct(PurchaseDetails purchaseDetails) async {
    // In production, verify the purchase with your backend
    // For now, we'll trust the purchase

    // Ensure user is loaded before verifying purchase
    if (_currentUser == null) {
      debugPrint(
          'Warning: User not loaded when verifying purchase, loading now...');
      await _loadUser();
    }

    String? tier;
    if (purchaseDetails.productID == monthlyProductId) {
      tier = 'monthly';
    } else if (purchaseDetails.productID == yearlyProductId) {
      tier = 'yearly';
    } else if (purchaseDetails.productID == lifetimeProductId) {
      tier = 'lifetime';
    }

    debugPrint('Verifying purchase for product: ${purchaseDetails.productID}');

    if (tier != null && _currentUser != null) {
      DateTime? expiresAt;
      if (tier == 'monthly') {
        expiresAt = DateTime.now().add(const Duration(days: 30));
      } else if (tier == 'yearly') {
        expiresAt = DateTime.now().add(const Duration(days: 365));
      }
      // lifetime has no expiration (null)

      final updatedUser = _currentUser!.copyWith(
        isPro: true,
        proTier: tier,
        proExpiresAt: expiresAt,
        updatedAt: DateTime.now(),
      );

      await _saveUser(updatedUser);
      debugPrint('Product delivered: $tier');
    } else if (tier == null) {
      debugPrint('Error: Unknown product ID: ${purchaseDetails.productID}');
    }
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

      // Check if subscription has expired (for monthly/yearly, not lifetime)
      if (isPro &&
          proExpiresAt != null &&
          DateTime.now().isAfter(proExpiresAt)) {
        debugPrint('Subscription expired on ${proExpiresAt.toIso8601String()}');
        isPro = false;
        proTier = null;
        // Update SharedPreferences to reflect expired status
        await prefs.setBool('isPro', false);
        await prefs.remove('proTier');
        await prefs.remove('proExpiresAt');
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
