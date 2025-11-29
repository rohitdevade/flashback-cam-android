import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flashback_cam/providers/app_state.dart';
import 'package:flashback_cam/theme.dart';
import 'package:flashback_cam/screens/pro_upgrade_screen.dart';

/// A frosted glass dialog offering a 7-day free trial
/// User can dismiss this dialog without starting the trial
class FreeTrialDialog extends StatefulWidget {
  final VoidCallback onDismiss;
  final VoidCallback? onTrialStarted;

  const FreeTrialDialog({
    super.key,
    required this.onDismiss,
    this.onTrialStarted,
  });

  @override
  State<FreeTrialDialog> createState() => _FreeTrialDialogState();
}

class _FreeTrialDialogState extends State<FreeTrialDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  bool _isStartingTrial = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startTrial() async {
    if (_isStartingTrial) return;

    setState(() => _isStartingTrial = true);

    final appState = context.read<AppState>();
    final success = await appState.startFreeTrial();

    if (!mounted) return;

    if (success) {
      widget.onTrialStarted?.call();
      _showSuccessAndDismiss();
    } else {
      setState(() => _isStartingTrial = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to start trial. Please try again.'),
          backgroundColor: AppColors.recordRed,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _showSuccessAndDismiss() {
    // Show a success dialog before dismissing
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _buildSuccessDialog(ctx),
    );
  }

  Widget _buildSuccessDialog(BuildContext ctx) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.neonGreen.withValues(alpha: 0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.neonGreen.withValues(alpha: 0.2),
                  blurRadius: 30,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Success icon with glow
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.neonGreen.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.neonGreen.withValues(alpha: 0.3),
                        blurRadius: 20,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: AppColors.neonGreen,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  'Trial Activated! 🎉',
                  style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),

                // Description
                Text(
                  'Enjoy all Pro features free for 7 days!',
                  style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Features unlocked
                Text(
                  '4K Video • Extended Buffer • No Ads',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: AppColors.electricBlue,
                        fontWeight: FontWeight.w500,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),

                // Auto-renewal reminder
                Text(
                  'Monthly plan starts after trial',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Got it button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop(); // Close success dialog
                      widget.onDismiss(); // Close trial dialog
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.neonGreen,
                      foregroundColor: AppColors.deepCharcoal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Start Recording!',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            color: AppColors.deepCharcoal,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _goToUpgradeScreen() {
    widget.onDismiss();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProUpgradeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // Dismissible backdrop
            GestureDetector(
              onTap: widget.onDismiss,
              child: Container(
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ),
            // Dialog content
            Center(
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _buildDialogContent(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogContent() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppColors.electricBlue.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.electricBlue.withValues(alpha: 0.15),
                blurRadius: 30,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Close button in top right
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 8),
                  child: IconButton(
                    onPressed: widget.onDismiss,
                    icon: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Gift icon with glow effect
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.electricBlue.withValues(alpha: 0.2),
                            AppColors.neonCyan.withValues(alpha: 0.1),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                                AppColors.electricBlue.withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.card_giftcard,
                        color: AppColors.electricBlue,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [AppColors.electricBlue, AppColors.neonCyan],
                      ).createShader(bounds),
                      child: Text(
                        '7 Days Free',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Subtitle
                    Text(
                      'Try Pro Monthly',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: 6),

                    // Price info - fetched from Google Play
                    Builder(
                      builder: (context) {
                        final appState = context.watch<AppState>();
                        final monthlyPrice = appState.subscriptionService
                                .getProductDetails('monthly')
                                ?.price ??
                            '\$9.99';
                        return Text(
                          'Then $monthlyPrice/month',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.electricBlue,
                                    fontWeight: FontWeight.w600,
                                  ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),

                    // Features list
                    _buildFeatureRow(Icons.movie_filter, '4K Video Recording'),
                    _buildFeatureRow(Icons.timer, 'Extended Buffer (10+ sec)'),
                    _buildFeatureRow(Icons.block, 'Ad-Free Experience'),
                    _buildFeatureRow(Icons.speed, 'Faster Processing'),

                    const SizedBox(height: 24),

                    // Start Trial Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isStartingTrial ? null : _startTrial,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.electricBlue,
                          foregroundColor: AppColors.deepCharcoal,
                          disabledBackgroundColor:
                              AppColors.electricBlue.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: _isStartingTrial
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppColors.deepCharcoal,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.play_arrow_rounded,
                                      size: 22),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Start Free Trial',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: AppColors.deepCharcoal,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // See all plans link
                    TextButton(
                      onPressed: _goToUpgradeScreen,
                      child: Text(
                        'See all plans',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.electricBlue,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Disclaimer - Legally compliant with Google Play Billing and EU consumer protection
                    Builder(
                      builder: (context) {
                        final appState = context.watch<AppState>();
                        final monthlyPrice = appState.subscriptionService
                                .getProductDetails('monthly')
                                ?.price ??
                            '\$9.99';
                        return Text(
                          '7-day free trial. After the trial, your subscription auto-renews at $monthlyPrice/month. Cancel anytime in Google Play.',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textTertiary,
                                    height: 1.4,
                                  ),
                          textAlign: TextAlign.center,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: AppColors.neonGreen,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          const Icon(
            Icons.check,
            color: AppColors.neonGreen,
            size: 18,
          ),
        ],
      ),
    );
  }
}
