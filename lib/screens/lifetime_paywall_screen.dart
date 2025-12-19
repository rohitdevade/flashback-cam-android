import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flashback_cam/providers/app_state.dart';
import 'package:flashback_cam/theme.dart';
import 'package:flashback_cam/widgets/glass_container.dart';
import 'package:flashback_cam/widgets/frosted_glass_card.dart';
import 'package:flashback_cam/services/subscription_service.dart';

/// Lifetime Paywall Screen - Shows 70% discount offer
/// All prices are fetched from Google Play Console - NO hardcoded values
class LifetimePaywallScreen extends StatefulWidget {
  /// Optional: reason for showing the paywall (for analytics/display)
  final String? triggerReason;

  const LifetimePaywallScreen({
    super.key,
    this.triggerReason,
  });

  @override
  State<LifetimePaywallScreen> createState() => _LifetimePaywallScreenState();
}

class _LifetimePaywallScreenState extends State<LifetimePaywallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;
  StreamSubscription<PurchaseResult>? _purchaseSubscription;
  bool _isPurchasing = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<double>(begin: 50.0, end: 0.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final subscriptionService = appState.subscriptionService;
    final lifetimePricing = subscriptionService.getLifetimePricing();

    return Scaffold(
      backgroundColor: AppColors.deepCharcoal,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) => Opacity(
            opacity: _fadeAnimation.value,
            child: Transform.translate(
              offset: Offset(0, _slideAnimation.value),
              child: child,
            ),
          ),
          child: Column(
            children: [
              _buildTopBar(context),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      _buildHeroBanner(lifetimePricing),
                      const SizedBox(height: 32),
                      _buildFeaturesList(),
                      const SizedBox(height: 32),
                      _buildPricingCard(lifetimePricing),
                      const SizedBox(height: 24),
                      _buildPurchaseButton(lifetimePricing),
                      const SizedBox(height: 16),
                      _buildDisclaimer(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.glassWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: const Icon(
                Icons.close,
                color: AppColors.textPrimary,
                size: 22,
              ),
            ),
          ),
          const Spacer(),
          // Restore purchases button
          TextButton(
            onPressed: _restorePurchases,
            child: Text(
              'Restore',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBanner(LifetimePricing? pricing) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF6366F1), // Indigo
            Color(0xFF8B5CF6), // Purple
            Color(0xFFEC4899), // Pink
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Discount badge
          if (pricing?.hasActiveDiscount ?? false)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.local_offer_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Save 70% – Limited Time',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                  ),
                ],
              ),
            ),

          // Title
          Text(
            'Limited-Time Lifetime Offer 🎉',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          // Subtitle
          Text(
            'Unlock all buffer durations forever\nNo subscriptions • One-time payment',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  height: 1.5,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesList() {
    final features = [
      {
        'icon': Icons.history_rounded,
        'title': 'All Buffer Durations',
        'desc': '5s, 10s, 20s, 30s pre-roll',
        'note': null,
      },
      {
        'icon': Icons.video_settings_rounded,
        'title': '4K Recording',
        'desc': 'Ultra-HD video quality',
        'note': '(device support required)',
      },
      {
        'icon': Icons.speed_rounded,
        'title': '60 FPS',
        'desc': 'Smooth high-frame playback',
        'note': '(device support required)',
      },
      {
        'icon': Icons.block_rounded,
        'title': 'No Ads',
        'desc': 'Distraction-free experience',
        'note': null,
      },
      {
        'icon': Icons.all_inclusive_rounded,
        'title': 'Lifetime Access',
        'desc': 'Pay once, use forever',
        'note': null,
      },
    ];

    return GlassContainer(
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.neonGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: AppColors.neonGreen,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'PRO FEATURES INCLUDED',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.neonGreen,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.glassBorder),
          ...features.asMap().entries.map((entry) {
            final index = entry.key;
            final feature = entry.value;
            return Column(
              children: [
                _buildFeatureItem(
                  feature['icon'] as IconData,
                  feature['title'] as String,
                  feature['desc'] as String,
                  note: feature['note'] as String?,
                ),
                if (index < features.length - 1)
                  const Divider(
                    height: 1,
                    color: AppColors.glassBorder,
                    indent: 68,
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String description,
      {String? note}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.electricBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: AppColors.electricBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (note != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        note,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.7),
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.neonGreen,
            size: 22,
          ),
        ],
      ),
    );
  }

  Widget _buildPricingCard(LifetimePricing? pricing) {
    return GlassContainer(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Price display
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // Original price with strikethrough (if discount active)
              if (pricing?.hasActiveDiscount ?? false) ...[
                Text(
                  pricing!.originalPrice!,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.textTertiary,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: AppColors.textTertiary,
                        decorationThickness: 2,
                      ),
                ),
                const SizedBox(width: 12),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: AppColors.neonGreen,
                  size: 24,
                ),
                const SizedBox(width: 12),
              ],
              // Current/discounted price
              Text(
                pricing?.discountedPrice ?? 'Loading...',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: AppColors.electricBlue,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // One-time payment badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'ONE-TIME PAYMENT • LIFETIME ACCESS',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.neonGreen,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseButton(LifetimePricing? pricing) {
    final isLoading = pricing == null || _isPurchasing;

    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: isLoading ? null : _purchaseLifetime,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.electricBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              AppColors.electricBlue.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: _isPurchasing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_open_rounded, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Unlock Lifetime Access',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDisclaimer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        'One-time purchase. No subscription or recurring charges. '
        'All purchases are processed securely by Google Play. '
        'Your purchase will be restored automatically if you reinstall the app.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
              height: 1.5,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Future<void> _purchaseLifetime() async {
    HapticFeedback.mediumImpact();

    final appState = context.read<AppState>();

    setState(() => _isPurchasing = true);

    // Listen for purchase result
    _purchaseSubscription?.cancel();
    _purchaseSubscription =
        appState.subscriptionService.purchaseResultStream.listen((result) {
      if (!mounted) return;

      setState(() => _isPurchasing = false);

      switch (result) {
        case PurchaseResult.success:
          _showSuccessDialog();
          break;
        case PurchaseResult.cancelled:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Purchase was cancelled'),
              backgroundColor: AppColors.textSecondary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
          break;
        case PurchaseResult.error:
          _showErrorSnackbar('Purchase failed. Please try again.');
          break;
        case PurchaseResult.verificationFailed:
          _showErrorSnackbar(
            'Purchase verification failed. Please contact support if you were charged.',
          );
          break;
        case PurchaseResult.pending:
          // Keep showing loading
          setState(() => _isPurchasing = true);
          break;
      }
    });

    try {
      final initiated = await appState.purchasePro('lifetime');

      if (!mounted) return;

      if (!initiated) {
        setState(() => _isPurchasing = false);
        _purchaseSubscription?.cancel();
        _showErrorSnackbar('Could not start purchase. Please try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPurchasing = false);
      _purchaseSubscription?.cancel();
      _showErrorSnackbar('Purchase failed: ${e.toString()}');
    }
  }

  Future<void> _restorePurchases() async {
    HapticFeedback.lightImpact();

    final appState = context.read<AppState>();

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassContainer(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.electricBlue),
              const SizedBox(height: 20),
              Text(
                'Restoring purchases...',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.textPrimary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );

    final success = await appState.restorePurchases();

    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog

    if (success && appState.isPro) {
      _showSuccessDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No previous purchases found'),
          backgroundColor: AppColors.textSecondary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: FrostedGlassCard(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.neonGreen.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.neonGreen,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome to Pro! 🎉',
                style:
                    Theme.of(dialogContext).textTheme.headlineSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'You now have lifetime access to all Pro features. '
                'Enjoy the full Flashback Cam experience!',
                style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext); // Close success dialog
                    Navigator.pop(context); // Close paywall screen
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.electricBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Start Recording',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.recordRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
