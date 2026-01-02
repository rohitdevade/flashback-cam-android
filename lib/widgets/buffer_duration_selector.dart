import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flashback_cam/providers/app_state.dart';
import 'package:flashback_cam/theme.dart';
import 'package:flashback_cam/widgets/glass_container.dart';

/// Compact buffer duration selector for the camera preview screen
/// Shows horizontal chips: 10s | 20s | 30s
/// Handles gating logic for free vs pro users
class BufferDurationSelector extends StatelessWidget {
  /// Callback when paywall should be shown
  final VoidCallback? onShowPaywall;

  const BufferDurationSelector({
    super.key,
    this.onShowPaywall,
  });

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final selectedDuration = appState.selectedBufferSeconds;
    final isPro = appState.isPro;

    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Buffer icon
          Icon(
            Icons.timer_outlined,
            color: Colors.white.withOpacity(0.7),
            size: 16,
          ),
          const SizedBox(width: 8),
          // Duration chips - uses dynamic list based on device RAM
          ...appState.availableBufferDurations.map((duration) {
            final status = appState.getBufferDurationStatus(duration);
            final isSelected = selectedDuration == duration;
            final isLocked = status == 'locked';
            final isUnlocked = status == 'unlocked';

            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _BufferDurationChip(
                duration: duration,
                isSelected: isSelected,
                isLocked: isLocked,
                isUnlocked: isUnlocked,
                isPro: isPro,
                onTap: () => _handleDurationTap(context, appState, duration),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _handleDurationTap(
    BuildContext context,
    AppState appState,
    int duration,
  ) async {
    // Check if selection is blocked (recording/processing)
    if (!appState.canSelectBufferDuration(duration)) {
      _showBlockedMessage(context);
      return;
    }

    final result = appState.trySelectBufferDuration(duration);

    switch (result) {
      case 'success':
        // Duration is available, change it
        await appState.changeBufferDuration(duration);
        break;

      case 'blocked':
        _showBlockedMessage(context);
        break;

      case 'needs_ad':
        // Show rewarded ad dialog
        _showRewardedAdDialog(context, appState, duration);
        break;

      case 'needs_paywall':
        // Show paywall
        if (onShowPaywall != null) {
          onShowPaywall!();
        }
        break;
    }
  }

  void _showBlockedMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            const Text('Change buffer time after saving'),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.charcoal,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showRewardedAdDialog(
    BuildContext context,
    AppState appState,
    int duration,
  ) {
    showDialog(
      context: context,
      builder: (context) => _RewardedAdDialog(
        duration: duration,
        onWatchAd: () async {
          Navigator.pop(context);

          // Show loading indicator
          _showLoadingOverlay(context);

          // Show rewarded ad
          final success = await appState.showRewardedAdForBuffer(duration);

          // Hide loading
          if (context.mounted) {
            Navigator.of(context, rootNavigator: true).pop();
          }

          if (success) {
            // Change to the unlocked duration
            await appState.changeBufferDuration(duration);

            if (context.mounted) {
              _showUnlockSuccessMessage(context, duration);
            }
          } else {
            if (context.mounted) {
              _showAdFailedMessage(context);
            }
          }
        },
        onCancel: () => Navigator.pop(context),
        onShowPaywall: () {
          Navigator.pop(context);
          if (onShowPaywall != null) {
            onShowPaywall!();
          }
        },
      ),
    );
  }

  void _showLoadingOverlay(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: Center(
          child: GlassContainer(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: AppColors.electricBlue,
                  strokeWidth: 2,
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading ad...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showUnlockSuccessMessage(BuildContext context, int duration) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('${duration}s buffer unlocked for this save'),
          ],
        ),
        duration: const Duration(seconds: 3),
        backgroundColor: AppColors.successGreen,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showAdFailedMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            const Text('Ad not available. Please try again.'),
          ],
        ),
        duration: const Duration(seconds: 3),
        backgroundColor: AppColors.recordRed,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// Individual duration chip
class _BufferDurationChip extends StatelessWidget {
  final int duration;
  final bool isSelected;
  final bool isLocked;
  final bool isUnlocked;
  final bool isPro;
  final VoidCallback onTap;

  const _BufferDurationChip({
    required this.duration,
    required this.isSelected,
    required this.isLocked,
    required this.isUnlocked,
    required this.isPro,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.vibrantPurple
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.vibrantPurple
                : isUnlocked
                    ? AppColors.successGreen.withOpacity(0.5)
                    : Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Lock icon for locked durations
            if (isLocked && !isSelected)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.lock,
                  size: 12,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            // Unlock badge for rewarded unlock
            if (isUnlocked && isSelected)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.stars,
                  size: 12,
                  color: Colors.amber,
                ),
              ),
            // Duration text
            Text(
              '${duration}s',
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : isLocked
                        ? Colors.white.withOpacity(0.5)
                        : Colors.white.withOpacity(0.9),
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog for rewarded ad prompt
class _RewardedAdDialog extends StatelessWidget {
  final int duration;
  final VoidCallback onWatchAd;
  final VoidCallback onCancel;
  final VoidCallback onShowPaywall;

  const _RewardedAdDialog({
    required this.duration,
    required this.onWatchAd,
    required this.onCancel,
    required this.onShowPaywall,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassContainer(
        padding: const EdgeInsets.all(24),
        borderRadius: BorderRadius.circular(20),
        isDark: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.vibrantPurple.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_circle_outline,
                size: 40,
                color: AppColors.vibrantPurple,
              ),
            ),
            const SizedBox(height: 20),
            // Title
            Text(
              'Unlock ${duration}s Buffer',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            // Description
            Text(
              'Watch a short ad to unlock the ${duration}s buffer for this moment.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            // Note about one-time use
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Valid for one save only',
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Watch Ad button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onWatchAd,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.vibrantPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.play_arrow, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Watch Ad',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Go Pro option
            TextButton(
              onPressed: onShowPaywall,
              child: Text(
                'Or unlock all buffers forever',
                style: TextStyle(
                  color: AppColors.electricBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // Cancel
            TextButton(
              onPressed: onCancel,
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Badge shown when rewarded buffer is active
class RewardedBufferBadge extends StatelessWidget {
  final int duration;

  const RewardedBufferBadge({
    super.key,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.successGreen.withOpacity(0.8),
            AppColors.successGreen,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.successGreen.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.stars,
            size: 14,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            '${duration}s unlocked for this save',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
