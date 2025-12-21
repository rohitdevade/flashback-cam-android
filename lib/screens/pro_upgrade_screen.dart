import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flashback_cam/providers/app_state.dart';
import 'package:flashback_cam/theme.dart';
import 'package:flashback_cam/widgets/glass_container.dart';
import 'package:flashback_cam/widgets/frosted_glass_card.dart';
import 'package:flashback_cam/services/subscription_service.dart';

class ProUpgradeScreen extends StatefulWidget {
  const ProUpgradeScreen({super.key});

  @override
  State<ProUpgradeScreen> createState() => _ProUpgradeScreenState();
}

class _ProUpgradeScreenState extends State<ProUpgradeScreen>
    with TickerProviderStateMixin {
  String _selectedTier = 'yearly';
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;
  StreamSubscription<PurchaseResult>? _purchaseSubscription;
  bool _billingInitialized = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
    _pulseController.repeat(reverse: true);

    // COLD START: Initialize billing when screen opens
    _initializeBilling();
  }

  /// COLD START: Lazy initialize billing when paywall opens
  Future<void> _initializeBilling() async {
    final appState = context.read<AppState>();
    await appState.subscriptionService.ensureBillingInitialized();
    if (mounted) {
      setState(() => _billingInitialized = true);
    }
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepCharcoal,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              _buildTopBar(context),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      _buildProHero(),
                      const SizedBox(height: 40),
                      _buildFeaturesList(),
                      const SizedBox(height: 40),
                      _buildPricingSection(),
                      const SizedBox(height: 32),
                      _buildPurchaseButton(),
                      const SizedBox(height: 20),
                      _buildDisclaimer(),
                      const SizedBox(height: 40),
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
      padding: const EdgeInsets.all(20),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.close, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Upgrade to Pro',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProHero() {
    return ScaleTransition(
      scale: _pulseAnimation,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.electricBlue, AppColors.neonCyan],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.electricBlue.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            const Icon(
              Icons.workspace_premium,
              size: 80,
              color: Colors.white,
            ),
            const SizedBox(height: 20),
            Text(
              'Unlock Pro Power',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Record in 4K & 60fps*, 30s pre-roll, no ads\n*Device support required',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.4,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesList() {
    final features = [
      {
        'icon': Icons.video_settings,
        'title': '4K Recording',
        'desc': 'Ultra-HD video (device support required)'
      },
      {
        'icon': Icons.speed,
        'title': '60 FPS',
        'desc': 'Smooth playback (device support required)'
      },
      {
        'icon': Icons.history,
        'title': 'Up to 30s Pre-roll',
        'desc': 'Extended buffer time'
      },
      {
        'icon': Icons.block,
        'title': 'No Ads',
        'desc': 'Distraction-free experience'
      },
      {
        'icon': Icons.high_quality,
        'title': 'High Bitrate',
        'desc': 'Maximum quality output'
      },
    ];

    return Column(
      children: [
        Text(
          'PRO FEATURES',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.electricBlue,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
        ),
        const SizedBox(height: 20),
        GlassContainer(
          padding: const EdgeInsets.all(0),
          child: Column(
            children: features.asMap().entries.map((entry) {
              final index = entry.key;
              final feature = entry.value;
              return Column(
                children: [
                  _buildFeatureItem(
                    feature['icon'] as IconData,
                    feature['title'] as String,
                    feature['desc'] as String,
                  ),
                  if (index < features.length - 1)
                    const Divider(height: 1, color: AppColors.glassBorder),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.electricBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: AppColors.electricBlue,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.check_circle,
            color: AppColors.neonGreen,
            size: 24,
          ),
        ],
      ),
    );
  }

  Widget _buildPricingSection() {
    final appState = context.watch<AppState>();
    final subscriptionService = appState.subscriptionService;

    // Only fetch products after billing is initialized
    final monthlyProduct = _billingInitialized
        ? subscriptionService.getProductDetails('monthly')
        : null;
    final yearlyProduct = _billingInitialized
        ? subscriptionService.getProductDetails('yearly')
        : null;
    final lifetimeProduct = _billingInitialized
        ? subscriptionService.getProductDetails('lifetime')
        : null;

    return Column(
      children: [
        Text(
          'CHOOSE YOUR PLAN',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.electricBlue,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
        ),
        const SizedBox(height: 20),
        _buildPricingCard(
          tier: 'monthly',
          label: 'Monthly',
          price: monthlyProduct?.price ?? 'Loading...',
          period: 'per month',
          originalPrice: null,
        ),
        const SizedBox(height: 12),
        _buildPricingCard(
          tier: 'yearly',
          label: 'Yearly',
          price: yearlyProduct?.price ?? 'Loading...',
          period: 'per year',
          originalPrice: null,
        ),
        const SizedBox(height: 12),
        _buildPricingCard(
          tier: 'lifetime',
          label: 'Lifetime',
          price: lifetimeProduct?.price ?? 'Loading...',
          period: 'one-time payment',
          originalPrice: null,
        ),
      ],
    );
  }

  Widget _buildPricingCard({
    required String tier,
    required String label,
    required String price,
    required String period,
    String? originalPrice,
    String? badge,
    bool isPopular = false,
  }) {
    final isSelected = _selectedTier == tier;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _selectedTier = tier);
      },
      child: Stack(
        children: [
          GlassContainer(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.electricBlue
                          : AppColors.textSecondary,
                      width: 2,
                    ),
                    color: isSelected
                        ? AppColors.electricBlue
                        : Colors.transparent,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        period,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      price,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: AppColors.electricBlue,
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    if (originalPrice != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        originalPrice,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              decoration: TextDecoration.lineThrough,
                            ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (badge != null)
            Positioned(
              top: -8,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isPopular ? AppColors.proGold : AppColors.neonGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPurchaseButton() {
    return Container(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: () => _purchase(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.electricBlue,
          foregroundColor: AppColors.deepCharcoal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.flash_on, size: 24),
            const SizedBox(width: 12),
            Text(
              'Start Pro Experience',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.deepCharcoal,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisclaimer() {
    return Builder(
      builder: (context) {
        final appState = context.watch<AppState>();
        final subscriptionService = appState.subscriptionService;

        // Get the price for the selected tier
        final selectedProduct =
            subscriptionService.getProductDetails(_selectedTier);
        final selectedPrice =
            selectedProduct?.price ?? 'the selected plan\'s price';

        // Determine the billing period text
        String billingPeriod;
        if (_selectedTier == 'monthly') {
          billingPeriod = '/month';
        } else if (_selectedTier == 'yearly') {
          billingPeriod = '/year';
        } else {
          billingPeriod = ''; // Lifetime has no renewal
        }

        // Show appropriate disclaimer based on plan type
        final disclaimerText = _selectedTier == 'lifetime'
            ? 'One-time purchase. No subscription or recurring charges. All purchases are processed securely by Google Play.'
            : 'Your subscription auto-renews at $selectedPrice$billingPeriod until canceled. Cancel anytime in Google Play. Manage subscriptions in Google Play settings.';

        return Text(
          disclaimerText,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
                height: 1.4,
              ),
          textAlign: TextAlign.center,
        );
      },
    );
  }

  void _purchase(BuildContext context) async {
    final appState = context.read<AppState>();

    // Listen for purchase result BEFORE initiating purchase
    _purchaseSubscription?.cancel();
    _purchaseSubscription =
        appState.subscriptionService.purchaseResultStream.listen((result) {
      if (!mounted) return;

      // Close any loading dialog that might be open
      Navigator.of(context, rootNavigator: true).popUntil((route) {
        return route is! DialogRoute;
      });

      switch (result) {
        case PurchaseResult.success:
          _showSuccessDialog(context);
          break;
        case PurchaseResult.cancelled:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Purchase was cancelled.'),
              backgroundColor: AppColors.textSecondary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
          break;
        case PurchaseResult.error:
          _showErrorDialog(context, 'Purchase failed. Please try again.');
          break;
        case PurchaseResult.verificationFailed:
          _showErrorDialog(context,
              'Purchase verification failed. Please contact support if you were charged.');
          break;
        case PurchaseResult.pending:
          // Keep showing loading - purchase is being processed
          break;
      }
    });

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassContainer(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.electricBlue),
              const SizedBox(height: 20),
              Text(
                'Opening payment...',
                style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                      color: AppColors.textPrimary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final initiated = await appState.purchasePro(_selectedTier);

      if (!mounted) return;

      // If purchase flow couldn't start, close dialog and show error
      if (!initiated) {
        Navigator.pop(context); // Close loading dialog
        _purchaseSubscription?.cancel();
        _showErrorDialog(
            context, 'Could not start purchase. Please try again.');
      } else {
        // Close loading dialog - Google Play will show its own UI
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      _purchaseSubscription?.cancel();
      _showErrorDialog(context, 'Purchase failed: ${e.toString()}');
    }
  }

  void _showSuccessDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
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
                  Icons.check_circle,
                  color: AppColors.neonGreen,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Welcome to Pro! 🎉',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'You now have access to all Pro features. Enjoy the premium Flashback Cam experience!',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); // Close success dialog
                    Navigator.pop(context); // Close upgrade screen
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.electricBlue,
                    foregroundColor: AppColors.deepCharcoal,
                  ),
                  child: const Text('Get Started'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showErrorDialog(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.recordRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
