import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashback_cam/models/user.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

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
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        // Handle error
        debugPrint('Purchase error: ${purchaseDetails.error}');
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        // Verify and deliver product
        await _verifyAndDeliverProduct(purchaseDetails);
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

    String? tier;
    if (purchaseDetails.productID == monthlyProductId) {
      tier = 'monthly';
    } else if (purchaseDetails.productID == yearlyProductId) {
      tier = 'yearly';
    } else if (purchaseDetails.productID == lifetimeProductId) {
      tier = 'lifetime';
    }

    if (tier != null) {
      DateTime? expiresAt;
      if (tier == 'monthly') {
        expiresAt = DateTime.now().add(Duration(days: 30));
      } else if (tier == 'yearly') {
        expiresAt = DateTime.now().add(Duration(days: 365));
      }

      final updatedUser = _currentUser!.copyWith(
        isPro: true,
        proTier: tier,
        proExpiresAt: expiresAt,
        updatedAt: DateTime.now(),
      );

      await _saveUser(updatedUser);
      debugPrint('Product delivered: $tier');
    }
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
      return false;
    }

    try {
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: product,
      );

      final bool success = await _iap.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

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
  }

  User get currentUser =>
      _currentUser ??
      User(
          id: 'default_user',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now());

  bool get isPro => _currentUser?.isPro ?? false;
}
