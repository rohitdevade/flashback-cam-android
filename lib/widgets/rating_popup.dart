import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flashback_cam/theme.dart';
import 'package:flashback_cam/widgets/frosted_glass_card.dart';

/// Rating popup widget that asks users for their rating
/// Shows 1-5 stars and handles rating-based actions
class RatingPopup extends StatefulWidget {
  final VoidCallback onHighRating;
  final VoidCallback onLowRating;
  final VoidCallback onDismiss;

  const RatingPopup({
    super.key,
    required this.onHighRating,
    required this.onLowRating,
    required this.onDismiss,
  });

  @override
  State<RatingPopup> createState() => _RatingPopupState();
}

class _RatingPopupState extends State<RatingPopup>
    with SingleTickerProviderStateMixin {
  int _selectedRating = 0;
  bool _showCloseButton = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();

    // Show close button after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showCloseButton = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onStarTap(int rating) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedRating = rating;
    });
  }

  void _submitRating() {
    HapticFeedback.mediumImpact();

    if (_selectedRating >= 4) {
      widget.onHighRating();
    } else {
      widget.onLowRating();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: FrostedGlassCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Close button - appears after 3 seconds
                Align(
                  alignment: Alignment.topRight,
                  child: AnimatedOpacity(
                    opacity: _showCloseButton ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: IgnorePointer(
                      ignoring: !_showCloseButton,
                      child: GestureDetector(
                        onTap: widget.onDismiss,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.glassWhite,
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
                ),

                const SizedBox(height: 8),

                // App icon or emoji
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.electricBlue, AppColors.neonCyan],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.electricBlue.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.videocam_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),

                const SizedBox(height: 24),

                // Title
                Text(
                  'Enjoying Flashback Cam?',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                // Subtitle
                Text(
                  'Your feedback helps us improve!\nHow would you rate your experience?',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 28),

                // Star rating
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    final starNumber = index + 1;
                    final isSelected = starNumber <= _selectedRating;

                    return GestureDetector(
                      onTap: () => _onStarTap(starNumber),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          isSelected
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: isSelected
                              ? AppColors.proGold
                              : AppColors.textTertiary,
                          size: isSelected ? 44 : 40,
                        ),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 28),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _selectedRating > 0 ? _submitRating : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedRating > 0
                          ? AppColors.electricBlue
                          : AppColors.glassWhite,
                      foregroundColor: _selectedRating > 0
                          ? Colors.white
                          : AppColors.textTertiary,
                      disabledBackgroundColor: AppColors.glassWhite,
                      disabledForegroundColor: AppColors.textTertiary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      _selectedRating > 0
                          ? 'Submit Rating'
                          : 'Tap a star to rate',
                      style: const TextStyle(
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
      ),
    );
  }
}

/// Shows the rating popup dialog
/// Returns true if user gave a high rating
Future<bool?> showRatingPopup(BuildContext context) async {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (dialogContext) => RatingPopup(
      onHighRating: () => Navigator.of(dialogContext).pop(true),
      onLowRating: () => Navigator.of(dialogContext).pop(false),
      onDismiss: () => Navigator.of(dialogContext).pop(null),
    ),
  );
}
