import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashback_cam/models/user.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:flashback_cam/services/deferred_init_service.dart';

/// ═══════════════════════════════════════════════════════════════════════════════
/// SUBSCRIPTION SERVICE - COLD START OPTIMIZED
///
/// COLD START OPTIMIZATION:
/// - Billing client connection is DEFERRED until paywall is opened
/// - Only local cached subscription status is loaded during cold start
/// - Full IAP initialization happens lazily on first purchase attempt
/// - This removes ~300-800ms from cold start time
///
/// When Billing Client is initialized:
/// - On paywall screen open
/// - On purchase button tap
/// - Never during Application.onCreate or main()
/// ═══════════════════════════════════════════════════════════════════════════════

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
  final SubscriptionStatus? status;
  final String? tier;
  final DateTime? expiresAt;
  final DateTime? trialEndsAt;
  final DateTime? gracePeriodExpiresAt;
  final bool willAutoRenew;
  final String validationSource;
  final String? errorMessage;

  PurchaseVerificationResult({
    required this.isValid,
    this.status,
    this.tier,
    this.expiresAt,
    this.trialEndsAt,
    this.gracePeriodExpiresAt,
    this.willAutoRenew = false,
    this.validationSource = 'local',
    this.errorMessage,
  });
}

/// Lifetime pricing information fetched from Play Console
/// All prices are fetched from Google Play - NO hardcoded values
class LifetimePricing {
  /// The discounted/current price to pay (formatted with currency symbol)
  final String discountedPrice;

  /// Raw discounted price value for comparison
  final double discountedRawPrice;

  /// Original price before discount (formatted with currency symbol)
  /// Null if no discount is active
  final String? originalPrice;

  /// Raw original price value for comparison
  /// Null if no discount is active
  final double? originalRawPrice;

  /// Currency code (e.g., "USD", "INR")
  final String currencyCode;

  /// Whether a discount is currently active (determined by comparing prices)
  final bool hasActiveDiscount;

  LifetimePricing({
    required this.discountedPrice,
    required this.discountedRawPrice,
    this.originalPrice,
    this.originalRawPrice,
    required this.currencyCode,
    required this.hasActiveDiscount,
  });

  @override
  String toString() {
    if (hasActiveDiscount) {
      return 'LifetimePricing(discounted: $discountedPrice, original: $originalPrice, currency: $currencyCode)';
    }
    return 'LifetimePricing(price: $discountedPrice, currency: $currencyCode, no discount)';
  }
}

class SubscriptionService {
  static const Duration _trialDuration = Duration(days: 3);
  static const String _subscriptionValidationUrl =
      String.fromEnvironment('SUBSCRIPTION_VALIDATION_URL');

  User? _currentUser;
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  // Product IDs - Update these to match your Google Play Console product IDs
  static const String monthlyProductId = 'flashback_cam_monthly';
  static const String yearlyProductId = 'flashback_cam_yearly';
  static const String lifetimeDiscountProductId = 'lifetime_discount';
  static const String lifetimeFullPriceProductId = 'flashback_cam_lifetime';

  // Store fetched products
  Map<String, ProductDetails> _products = {};
  bool _isAvailable = false;

  // Track if we've synced with Google Play this session
  bool _hasRestoredPurchases = false;

  // Track if we're currently in a restore operation (vs new purchase)
  bool _isRestoreOperation = false;

  // Track if any valid purchases were found during restore
  bool _foundValidPurchases = false;

  // Allows the UI to await a restore result instead of only the restore kickoff.
  Completer<bool>? _restoreOperationCompleter;

  // Stream controller for purchase updates
  final _purchaseResultController =
      StreamController<PurchaseResult>.broadcast();
  Stream<PurchaseResult> get purchaseResultStream =>
      _purchaseResultController.stream;

  // Debug mode - allows purchases to work in debug builds without real IAP
  static const bool _debugPurchasesEnabled = kDebugMode;

  // Debug mode - force Pro access for testing (only works in debug builds)
  static const bool _debugForceProAccess = false;

  // COLD START: Track if billing has been fully initialized
  bool _billingInitialized = false;
  final DeferredInitService _deferredInit = DeferredInitService();

  /// ═══════════════════════════════════════════════════════════════════════════════
  /// COLD START: Minimal initialization - only load cached user data
  ///
  /// This method only loads locally cached subscription status.
  /// Billing client connection is deferred until actually needed.
  /// ═══════════════════════════════════════════════════════════════════════════════
  Future<void> initialize() async {
    // COLD START: Only load cached user data - no billing client connection
    await _loadUser();
    await _refreshCachedStatus();

    debugPrint(
        'SubscriptionService: Loaded cached user status (billing deferred)');
    debugPrint('  isPro: ${_currentUser?.isPro ?? false}');
    debugPrint('  Billing client will connect on first purchase/restore');
  }

  /// ═══════════════════════════════════════════════════════════════════════════════
  /// COLD START: Ensure billing is fully initialized before purchase operations
  ///
  /// This lazy initialization removes billing client startup from cold start.
  /// Called automatically when paywall opens or purchase is attempted.
  /// ═══════════════════════════════════════════════════════════════════════════════
  Future<void> ensureBillingInitialized() async {
    if (_billingInitialized) return;

    await _deferredInit.initializeComponent(
      DeferredComponents.billing,
      () async {
        debugPrint('SubscriptionService: Lazy-initializing billing client...');

        // Check if in-app purchase is available
        _isAvailable = await _iap.isAvailable();
        if (!_isAvailable) {
          debugPrint('In-app purchase is not available on this device');
          _billingInitialized = true;
          return;
        }

        // Listen to purchase updates
        _subscription = _iap.purchaseStream.listen(
          _onPurchaseUpdate,
          onDone: () => _subscription?.cancel(),
          onError: (error) => debugPrint('Purchase stream error: $error'),
        );

        // Load products (use internal method to avoid circular dependency)
        await _loadProductsInternal();

        // Sync subscription status with Google Play
        await _syncSubscriptionWithStore();

        _billingInitialized = true;
        debugPrint(
            'SubscriptionService: Billing client initialized (deferred)');
      },
    );
  }

  /// ═══════════════════════════════════════════════════════════════════════════════
  /// REMOVED: Old synchronous initialize that ran during cold start
  /// The code below is the original that connected billing during startup
  /// ═══════════════════════════════════════════════════════════════════════════════

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

      // Mark that we're doing a restore operation
      _isRestoreOperation = true;
      _foundValidPurchases = false;

      // Restore purchases to get current subscription status from Google Play
      await _iap.restorePurchases();
      _hasRestoredPurchases = true;

      // Note: _onPurchaseUpdate will handle revoking access if no purchases found

      debugPrint('✅ Subscription sync completed');
    } catch (e) {
      debugPrint('⚠️ Failed to sync with store: $e');
      // Don't fail initialization if sync fails - user can still use cached status
      _isRestoreOperation = false;
    }
  }

  Future<void> _refreshCachedStatus() async {
    if (_currentUser == null) return;

    final now = DateTime.now();
    final currentStatus = _currentUser!.subscriptionStatus;
    var nextStatus = currentStatus;

    if (currentStatus == SubscriptionStatus.trialCancelled &&
        _currentUser!.trialEndsAt != null &&
        !now.isBefore(_currentUser!.trialEndsAt!)) {
      nextStatus = SubscriptionStatus.expired;
    } else if (currentStatus == SubscriptionStatus.trialActive &&
        !_currentUser!.subscriptionWillRenew &&
        _currentUser!.trialEndsAt != null &&
        !now.isBefore(_currentUser!.trialEndsAt!)) {
      nextStatus = SubscriptionStatus.expired;
    } else if (currentStatus == SubscriptionStatus.gracePeriod &&
        _currentUser!.gracePeriodExpiresAt != null &&
        !now.isBefore(_currentUser!.gracePeriodExpiresAt!)) {
      nextStatus = SubscriptionStatus.expired;
    } else if (currentStatus == SubscriptionStatus.active &&
        _currentUser!.proTier != 'lifetime' &&
        !_currentUser!.subscriptionWillRenew &&
        _currentUser!.proExpiresAt != null &&
        !now.isBefore(_currentUser!.proExpiresAt!)) {
      nextStatus = SubscriptionStatus.expired;
    }

    if (nextStatus == currentStatus) return;

    final updatedUser = _currentUser!.copyWith(
      isPro: _isPaidEntitlementStatus(nextStatus, _currentUser!.proTier),
      subscriptionStatus: nextStatus.storageValue,
      gracePeriodExpiresAt: null,
      subscriptionWillRenew: false,
      updatedAt: now,
      lastValidatedAt: now,
    );
    await _saveUser(updatedUser);
  }

  /// Public method to load products - ensures billing is initialized first
  Future<void> loadProducts() async {
    // COLD START: Ensure billing is initialized before loading products
    await ensureBillingInitialized();
    // Products are already loaded during ensureBillingInitialized
  }

  /// Internal method to load products - called from ensureBillingInitialized
  /// This avoids circular dependency
  Future<void> _loadProductsInternal() async {
    if (!_isAvailable) return;

    try {
      const productIds = {
        monthlyProductId,
        yearlyProductId,
        lifetimeDiscountProductId,
        lifetimeFullPriceProductId,
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
        // Log additional pricing info for debugging
        if (product.id == lifetimeDiscountProductId ||
            product.id == lifetimeFullPriceProductId) {
          debugPrint(
              '  Raw price: ${product.rawPrice} ${product.currencyCode}');
        }
      }
    } catch (e) {
      debugPrint('Failed to load products: $e');
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) async {
    // If this is a restore operation and we get purchases, mark that we found them
    if (_isRestoreOperation && purchaseDetailsList.isNotEmpty) {
      for (var purchaseDetails in purchaseDetailsList) {
        if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          _foundValidPurchases = true;
          break;
        }
      }
    }

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

    // After processing all purchases, check if restore found nothing
    if (_isRestoreOperation) {
      _isRestoreOperation = false; // Reset flag

      if (!_foundValidPurchases) {
        debugPrint(
            '🚫 No active purchases found during restore - subscription expired');
        debugPrint('   Updating subscription status to no entitlement');
        await _revokeSubscription(reason: 'No active purchases found');
      }

      _restoreOperationCompleter?.complete(_currentUser?.hasProAccess == true);
      _restoreOperationCompleter = null;

      _foundValidPurchases = false; // Reset for next restore
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
    debugPrint(
        '✅ Purchase verified: tier=$tier status=${verificationResult.status?.storageValue} source=${verificationResult.validationSource}');

    if (tier != null &&
        _currentUser != null &&
        verificationResult.status != null) {
      final now = DateTime.now();
      final trialStartedAt = verificationResult.trialEndsAt != null
          ? (_purchaseDateForDetails(purchaseDetails) ??
              verificationResult.trialEndsAt!.subtract(_trialDuration))
          : _currentUser!.trialStartedAt;
      final updatedUser = _currentUser!.copyWith(
        isPro: _isPaidEntitlementStatus(verificationResult.status!, tier),
        proTier: tier,
        proExpiresAt:
            verificationResult.expiresAt ?? verificationResult.trialEndsAt,
        trialStartedAt: trialStartedAt,
        trialUsed: _currentUser!.trialUsed ||
            verificationResult.status!.isTrialState ||
            verificationResult.trialEndsAt != null,
        subscriptionStatus: verificationResult.status!.storageValue,
        subscriptionWillRenew: verificationResult.willAutoRenew,
        gracePeriodExpiresAt: verificationResult.gracePeriodExpiresAt,
        updatedAt: now,
        lastValidatedAt: now,
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
      final tier = _tierFromProductId(purchaseDetails.productID);

      if (tier == null) {
        return PurchaseVerificationResult(
          isValid: false,
          errorMessage: 'Unknown product ID: ${purchaseDetails.productID}',
        );
      }

      final validationUrl = _subscriptionValidationUrl.trim();
      if (validationUrl.isNotEmpty) {
        return await _verifyPurchaseWithBackend(
          validationUrl: validationUrl,
          purchaseDetails: purchaseDetails,
          tier: tier,
        );
      }

      return _verifyPurchaseLocally(
        purchaseDetails: purchaseDetails,
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

  Future<PurchaseVerificationResult> _verifyPurchaseWithBackend({
    required String validationUrl,
    required PurchaseDetails purchaseDetails,
    required String tier,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(validationUrl));
      request.headers.contentType = ContentType.json;
      request.add(
        utf8.encode(
          jsonEncode(_buildValidationPayload(purchaseDetails, tier)),
        ),
      );

      final response =
          await request.close().timeout(const Duration(seconds: 10));
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return PurchaseVerificationResult(
          isValid: false,
          errorMessage:
              'Validation backend returned ${response.statusCode}: $body',
          validationSource: 'backend',
        );
      }

      final payload = jsonDecode(body);
      if (payload is! Map<String, dynamic>) {
        return PurchaseVerificationResult(
          isValid: false,
          errorMessage: 'Validation backend returned an invalid response',
          validationSource: 'backend',
        );
      }

      final isValid = payload['isValid'] == true || payload['valid'] == true;
      final status = _statusFromBackendPayload(payload, tier: tier);
      return PurchaseVerificationResult(
        isValid: isValid,
        status: status,
        tier: payload['tier'] as String? ?? tier,
        expiresAt: _parseDateValue(payload['expiresAt']),
        trialEndsAt: _parseDateValue(payload['trialEndsAt']),
        gracePeriodExpiresAt: _parseDateValue(payload['gracePeriodEndsAt']),
        willAutoRenew: payload['willAutoRenew'] as bool? ?? false,
        validationSource: 'backend',
        errorMessage: payload['errorMessage'] as String?,
      );
    } on TimeoutException {
      return PurchaseVerificationResult(
        isValid: false,
        errorMessage: 'Validation backend timed out',
        validationSource: 'backend',
      );
    } catch (e) {
      return PurchaseVerificationResult(
        isValid: false,
        errorMessage: 'Validation backend error: $e',
        validationSource: 'backend',
      );
    } finally {
      client.close(force: true);
    }
  }

  PurchaseVerificationResult _verifyPurchaseLocally({
    required PurchaseDetails purchaseDetails,
    required String tier,
  }) {
    if (tier == 'lifetime') {
      return PurchaseVerificationResult(
        isValid: true,
        status: SubscriptionStatus.active,
        tier: tier,
        validationSource: 'local',
      );
    }

    if (Platform.isAndroid) {
      final androidDetails = purchaseDetails as GooglePlayPurchaseDetails;
      final billingClientPurchase = androidDetails.billingClientPurchase;
      if (billingClientPurchase.purchaseState !=
          PurchaseStateWrapper.purchased) {
        return PurchaseVerificationResult(
          isValid: false,
          errorMessage: 'Purchase not in purchased state',
          validationSource: 'local',
        );
      }

      final purchaseDate = _purchaseDateForDetails(purchaseDetails);
      final trialEndsAt = _deriveTrialEndDate(
        productId: purchaseDetails.productID,
        purchaseDate: purchaseDate,
      );

      if (trialEndsAt != null && DateTime.now().isBefore(trialEndsAt)) {
        final status = billingClientPurchase.isAutoRenewing
            ? SubscriptionStatus.trialActive
            : SubscriptionStatus.trialCancelled;
        return PurchaseVerificationResult(
          isValid: true,
          status: status,
          tier: tier,
          expiresAt: trialEndsAt,
          trialEndsAt: trialEndsAt,
          willAutoRenew: billingClientPurchase.isAutoRenewing,
          validationSource: 'local',
        );
      }

      return PurchaseVerificationResult(
        isValid: true,
        status: SubscriptionStatus.active,
        tier: tier,
        willAutoRenew: billingClientPurchase.isAutoRenewing,
        validationSource: 'local',
      );
    }

    final purchaseDate = _purchaseDateForDetails(purchaseDetails);
    final trialEndsAt = _deriveTrialEndDate(
      productId: purchaseDetails.productID,
      purchaseDate: purchaseDate,
    );
    if (trialEndsAt != null && DateTime.now().isBefore(trialEndsAt)) {
      return PurchaseVerificationResult(
        isValid: true,
        status: SubscriptionStatus.trialActive,
        tier: tier,
        expiresAt: trialEndsAt,
        trialEndsAt: trialEndsAt,
        willAutoRenew: true,
        validationSource: 'local',
      );
    }

    return PurchaseVerificationResult(
      isValid: true,
      status: SubscriptionStatus.active,
      tier: tier,
      willAutoRenew: true,
      validationSource: 'local',
    );
  }

  Map<String, dynamic> _buildValidationPayload(
    PurchaseDetails purchaseDetails,
    String tier,
  ) {
    final payload = <String, dynamic>{
      'platform': Platform.isIOS
          ? 'ios'
          : Platform.isAndroid
              ? 'android'
              : 'unknown',
      'tier': tier,
      'productId': purchaseDetails.productID,
      'purchaseId': purchaseDetails.purchaseID,
      'transactionDate': purchaseDetails.transactionDate,
      'verificationData': {
        'source': purchaseDetails.verificationData.source,
        'localVerificationData':
            purchaseDetails.verificationData.localVerificationData,
        'serverVerificationData':
            purchaseDetails.verificationData.serverVerificationData,
      },
    };

    if (Platform.isAndroid && purchaseDetails is GooglePlayPurchaseDetails) {
      final purchase = purchaseDetails.billingClientPurchase;
      payload['storePayload'] = {
        'orderId': purchase.orderId,
        'packageName': purchase.packageName,
        'purchaseTime': purchase.purchaseTime,
        'purchaseToken': purchase.purchaseToken,
        'products': purchase.products,
        'isAutoRenewing': purchase.isAutoRenewing,
        'originalJson': purchase.originalJson,
        'signature': purchase.signature,
        'isAcknowledged': purchase.isAcknowledged,
        'purchaseState': purchase.purchaseState.name,
      };
    }

    return payload;
  }

  SubscriptionStatus _statusFromBackendPayload(
    Map<String, dynamic> payload, {
    required String tier,
  }) {
    final rawStatus = payload['status'] as String?;
    switch (rawStatus) {
      case 'free':
        return SubscriptionStatus.free;
      case 'trial_active':
      case 'trial':
        return SubscriptionStatus.trialActive;
      case 'paid_active':
      case 'active':
        return SubscriptionStatus.active;
      case 'trial_cancelled':
      case 'trial_canceled':
      case 'cancelled_in_trial':
        return SubscriptionStatus.trialCancelled;
      case 'grace_period':
      case 'billing_retry':
        return SubscriptionStatus.gracePeriod;
      case 'expired':
        return SubscriptionStatus.expired;
      default:
        break;
    }

    if (payload['isInGracePeriod'] == true || payload['billingRetry'] == true) {
      return SubscriptionStatus.gracePeriod;
    }
    if (payload['isTrialPeriod'] == true) {
      return (payload['willAutoRenew'] as bool? ?? false)
          ? SubscriptionStatus.trialActive
          : SubscriptionStatus.trialCancelled;
    }
    if (tier == 'lifetime') {
      return SubscriptionStatus.active;
    }
    if (payload['hasAccess'] == true) {
      return SubscriptionStatus.active;
    }
    return SubscriptionStatus.expired;
  }

  DateTime? _parseDateValue(dynamic value) {
    if (value == null) return null;
    if (value is String && value.isNotEmpty) {
      final intValue = int.tryParse(value);
      if (intValue != null) {
        return DateTime.fromMillisecondsSinceEpoch(intValue).toLocal();
      }
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }

  String? _tierFromProductId(String productId) {
    if (productId == monthlyProductId) return 'monthly';
    if (productId == yearlyProductId) return 'yearly';
    if (productId == lifetimeDiscountProductId ||
        productId == lifetimeFullPriceProductId) {
      return 'lifetime';
    }
    return null;
  }

  DateTime? _purchaseDateForDetails(PurchaseDetails purchaseDetails) {
    final transactionDate = purchaseDetails.transactionDate;
    if (transactionDate == null || transactionDate.isEmpty) return null;
    final milliseconds = int.tryParse(transactionDate);
    if (milliseconds != null) {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    }
    return DateTime.tryParse(transactionDate)?.toLocal();
  }

  DateTime? _deriveTrialEndDate({
    required String productId,
    required DateTime? purchaseDate,
  }) {
    if (purchaseDate == null) return null;
    if (productId != yearlyProductId) return null;
    return purchaseDate.add(_trialDuration);
  }

  bool _isPaidEntitlementStatus(SubscriptionStatus status, String? tier) {
    if (tier == 'lifetime') return true;
    return status == SubscriptionStatus.active ||
        status == SubscriptionStatus.gracePeriod;
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
  Future<void> _revokeSubscription({String? reason}) async {
    debugPrint('🚫 Revoking subscription access: $reason');

    if (_currentUser == null) return;

    final nextStatus = (_currentUser!.trialUsed ||
            _currentUser!.proTier != null ||
            _currentUser!.subscriptionStatus != SubscriptionStatus.free)
        ? SubscriptionStatus.expired
        : SubscriptionStatus.free;

    final updatedUser = _currentUser!.copyWith(
      isPro: false,
      subscriptionStatus: nextStatus.storageValue,
      subscriptionWillRenew: false,
      gracePeriodExpiresAt: null,
      updatedAt: DateTime.now(),
      lastValidatedAt: DateTime.now(),
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
      final subscriptionStatus = prefs.getString('subscriptionStatus');
      final subscriptionWillRenew =
          prefs.getBool('subscriptionWillRenew') ?? false;
      final gracePeriodExpiresAtStr = prefs.getString('gracePeriodExpiresAt');
      final lastValidatedAtStr = prefs.getString('lastValidatedAt');
      final trialDurationDays = prefs.getInt('trialDurationDays') ?? 3;

      final proExpiresAt =
          proExpiresAtStr != null ? DateTime.parse(proExpiresAtStr) : null;
      final gracePeriodExpiresAt = gracePeriodExpiresAtStr != null
          ? DateTime.parse(gracePeriodExpiresAtStr)
          : null;
      final lastValidatedAt = lastValidatedAtStr != null
          ? DateTime.parse(lastValidatedAtStr)
          : null;

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
        subscriptionStatusValue: subscriptionStatus,
        subscriptionWillRenew: subscriptionWillRenew,
        gracePeriodExpiresAt: gracePeriodExpiresAt,
        lastValidatedAt: lastValidatedAt,
        trialDurationDays: trialDurationDays,
      );
    } catch (e) {
      debugPrint('Failed to load user: $e');
      _currentUser = User(
        id: 'default_user',
        isPro: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        subscriptionStatusValue: SubscriptionStatus.free.storageValue,
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
      if (user.subscriptionStatusValue != null) {
        await prefs.setString(
            'subscriptionStatus', user.subscriptionStatusValue!);
      } else {
        await prefs.remove('subscriptionStatus');
      }
      await prefs.setBool('subscriptionWillRenew', user.subscriptionWillRenew);
      if (user.gracePeriodExpiresAt != null) {
        await prefs.setString(
          'gracePeriodExpiresAt',
          user.gracePeriodExpiresAt!.toIso8601String(),
        );
      } else {
        await prefs.remove('gracePeriodExpiresAt');
      }
      if (user.lastValidatedAt != null) {
        await prefs.setString(
          'lastValidatedAt',
          user.lastValidatedAt!.toIso8601String(),
        );
      } else {
        await prefs.remove('lastValidatedAt');
      }
      await prefs.setInt('trialDurationDays', user.trialDurationDays);
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

    if (tier == 'lifetime' && hasLifetimePurchase) {
      debugPrint(
          'Lifetime purchase already owned; skipping duplicate purchase');
      return false;
    }

    // CRITICAL: Ensure billing is initialized before any purchase operation
    await ensureBillingInitialized();

    // In debug mode, simulate successful purchases for testing
    if (_debugPurchasesEnabled) {
      debugPrint('🔧 DEBUG MODE: Simulating purchase for tier: $tier');
      await Future.delayed(const Duration(seconds: 1)); // Simulate delay

      final now = DateTime.now();
      final isTrialPurchase = tier == 'yearly';
      DateTime? expiresAt;
      SubscriptionStatus status = SubscriptionStatus.active;
      var willAutoRenew = tier != 'lifetime';
      if (tier == 'monthly') {
        expiresAt = now.add(const Duration(days: 30));
      } else if (isTrialPurchase) {
        expiresAt = now.add(_trialDuration);
        status = SubscriptionStatus.trialActive;
      }

      final updatedUser = _currentUser!.copyWith(
        isPro: _isPaidEntitlementStatus(status, tier),
        proTier: tier,
        proExpiresAt: expiresAt,
        trialStartedAt: isTrialPurchase ? now : _currentUser!.trialStartedAt,
        trialUsed: _currentUser!.trialUsed || isTrialPurchase,
        subscriptionStatus: status.storageValue,
        subscriptionWillRenew: willAutoRenew,
        gracePeriodExpiresAt: null,
        updatedAt: now,
        lastValidatedAt: now,
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
      productId = lifetimeDiscountProductId;
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
    // CRITICAL: Ensure billing is initialized before restore operation
    await ensureBillingInitialized();

    // In debug mode, simulate restore - check if user was already pro
    if (_debugPurchasesEnabled) {
      debugPrint('🔧 DEBUG MODE: Simulating restore purchases');
      await Future.delayed(const Duration(seconds: 1));
      final hadAccess = _currentUser?.hasProAccess ?? false;
      debugPrint('🔧 DEBUG MODE: User had access: $hadAccess');
      return hadAccess;
    }

    if (!_isAvailable) {
      debugPrint('In-app purchase is not available');
      return false;
    }

    try {
      // Mark that we're doing a restore operation
      _isRestoreOperation = true;
      _foundValidPurchases = false;
      _restoreOperationCompleter = Completer<bool>();

      await _iap.restorePurchases();

      // Note: _onPurchaseUpdate will handle revoking access if no purchases found.
      return await _restoreOperationCompleter!.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⚠️ Restore timed out waiting for purchase updates');
          _isRestoreOperation = false;
          final restored = _currentUser?.isPro == true;
          _restoreOperationCompleter = null;
          return restored;
        },
      );
    } catch (e) {
      debugPrint('Failed to restore purchases: $e');
      _isRestoreOperation = false;
      _restoreOperationCompleter = null;
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
      productId = lifetimeDiscountProductId;
    } else if (tier == 'lifetime_full_price') {
      productId = lifetimeFullPriceProductId;
    } else {
      return null;
    }
    return _products[productId];
  }

  /// Get lifetime pricing information from Play Console
  /// Returns both original and discounted prices if discount is active
  LifetimePricing? getLifetimePricing() {
    final discountedProduct = _products[lifetimeDiscountProductId];
    final originalProduct = _products[lifetimeFullPriceProductId];

    if (discountedProduct == null) {
      debugPrint('⚠️ Discounted lifetime product not found');
      return null;
    }

    // If we have both products and original is more expensive, show discount UI
    final hasDiscount = originalProduct != null &&
        originalProduct.rawPrice > discountedProduct.rawPrice;

    return LifetimePricing(
      discountedPrice: discountedProduct.price,
      discountedRawPrice: discountedProduct.rawPrice,
      originalPrice: hasDiscount ? originalProduct.price : null,
      originalRawPrice: hasDiscount ? originalProduct.rawPrice : null,
      currencyCode: discountedProduct.currencyCode,
      hasActiveDiscount: hasDiscount,
    );
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

  bool get isPro => _debugForceProAccess || (_currentUser?.isPro ?? false);

  /// Check if user has Pro access (paid or trial)
  bool get hasProAccess =>
      _debugForceProAccess || (_currentUser?.hasProAccess ?? false);

  /// True when the user owns either lifetime Play product permanently.
  bool get hasLifetimePurchase =>
      _debugForceProAccess ||
      (_currentUser?.isPro == true && _currentUser?.proTier == 'lifetime');

  SubscriptionStatus get subscriptionStatus =>
      _currentUser?.subscriptionStatus ?? SubscriptionStatus.free;

  bool get isPaidSubscriptionActive =>
      subscriptionStatus == SubscriptionStatus.active;

  bool get isCancelledButTrialActive =>
      _currentUser?.isCancelledButTrialActive ?? false;

  bool get isInGracePeriod => _currentUser?.isInGracePeriod ?? false;

  bool get isExpired => _currentUser?.isExpired ?? false;

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
    if (_currentUser!.isTrialActive) return false;
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
      final now = DateTime.now();
      final updatedUser = _currentUser!.copyWith(
        isPro: false,
        proExpiresAt: now.add(_trialDuration),
        trialStartedAt: now,
        trialUsed: true,
        subscriptionStatus: SubscriptionStatus.trialActive.storageValue,
        subscriptionWillRenew: false,
        updatedAt: now,
        lastValidatedAt: now,
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
    await _refreshCachedStatus();
    debugPrint(
        'Subscription status refreshed: status=${subscriptionStatus.storageValue}, isPro=$isPro, hasProAccess=$hasProAccess');
  }

  /// ═══════════════════════════════════════════════════════════════════════════════
  /// SUBSCRIPTION VALIDATION ON STARTUP
  ///
  /// Validates subscription status with Google Play on app startup.
  /// This ensures expired subscriptions are revoked and falls back to free tier.
  ///
  /// Should be called after app initialization (Phase 2) in the background.
  /// This is non-blocking and won't affect cold start performance.
  /// ═══════════════════════════════════════════════════════════════════════════════
  Future<void> validateSubscriptionOnStartup() async {
    try {
      debugPrint('🔍 Validating subscription status on startup...');

      await _refreshCachedStatus();

      final shouldValidate = _currentUser != null &&
          (_currentUser!.subscriptionStatus != SubscriptionStatus.free ||
              _currentUser!.trialUsed ||
              _currentUser!.proTier != null);

      if (!shouldValidate) {
        debugPrint('   No cached subscription history, skipping validation');
        return;
      }

      debugPrint(
          '   Cached status=${_currentUser?.subscriptionStatus.storageValue} tier=${_currentUser?.proTier}');
      debugPrint('   Checking with store...');

      // Initialize billing client if needed (this is async and won't block)
      await ensureBillingInitialized();

      if (_debugPurchasesEnabled) {
        debugPrint('🔧 DEBUG MODE: Skipping pro validation');
        return;
      }

      // If billing is unavailable, trust local cache
      if (!_isAvailable) {
        debugPrint('   ⚠️ Billing unavailable, trusting local cache');
        return;
      }

      await _syncSubscriptionWithStore();

      debugPrint('✅ Subscription validation complete');
    } catch (e) {
      debugPrint('⚠️ Subscription validation failed: $e');
      // Don't revoke on error - user keeps cached status
    }
  }
}
