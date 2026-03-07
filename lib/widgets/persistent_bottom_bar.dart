import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flashback_cam/providers/app_state.dart';
import 'package:flashback_cam/theme.dart';
import 'package:flashback_cam/widgets/glass_container.dart';
import 'package:flashback_cam/screens/settings_screen.dart';

/// State machine for the bottom bar
enum BottomBarState {
  /// Default state: Buffer · Settings · How
  defaultState,

  /// Buffer selection state: 10s · 20s · 30s · Close
  bufferSelection,
}

/// Persistent bottom navigation bar with three main actions:
/// - Buffer: morphs into buffer duration selector in-place
/// - Settings: navigates to full settings screen
/// - How It Works: triggers overlay on camera screen
class PersistentBottomBar extends StatefulWidget {
  /// Callback when "How It Works" is tapped
  final VoidCallback onHowItWorksTap;

  /// Callback when paywall should be shown (for locked buffer durations)
  final VoidCallback? onShowPaywall;

  /// Current buffer duration in seconds
  final int selectedBufferSeconds;

  /// Whether we're currently buffering
  final bool isBuffering;

  /// Whether we're currently recording
  final bool isRecording;

  /// Whether we're finalizing
  final bool isFinalizing;

  const PersistentBottomBar({
    super.key,
    required this.onHowItWorksTap,
    this.onShowPaywall,
    required this.selectedBufferSeconds,
    required this.isBuffering,
    required this.isRecording,
    required this.isFinalizing,
  });

  @override
  State<PersistentBottomBar> createState() => _PersistentBottomBarState();
}

class _PersistentBottomBarState extends State<PersistentBottomBar> {
  BottomBarState _currentState = BottomBarState.defaultState;

  void _switchToBufferSelection() {
    setState(() => _currentState = BottomBarState.bufferSelection);
  }

  void _switchToDefault() {
    setState(() => _currentState = BottomBarState.defaultState);
  }

  void _openSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Fixed height for consistent bar size
    const double barHeight = 56.0;

    // Simple approach: show only one bar at a time based on state
    // No animation complexity - just swap between states
    return SizedBox(
      height: barHeight,
      child: _currentState == BottomBarState.defaultState
          ? _buildDefaultBar(context)
          : _buildBufferSelectionBar(context),
    );
  }

  Widget _buildDefaultBar(BuildContext context) {
    final isDisabled = widget.isRecording || widget.isFinalizing;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Buffer button
            _BottomBarButton(
              icon: Icons.timer_outlined,
              label: 'Buffer',
              badge: '${widget.selectedBufferSeconds}s',
              onTap: isDisabled ? null : _switchToBufferSelection,
              isDisabled: isDisabled,
            ),
            // Divider
            Container(
              width: 1,
              height: 24,
              color: Colors.white.withOpacity(0.2),
            ),
            // Settings button
            _BottomBarButton(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () => _openSettings(context),
            ),
            // Divider
            Container(
              width: 1,
              height: 24,
              color: Colors.white.withOpacity(0.2),
            ),
            // How It Works button
            _BottomBarButton(
              icon: Icons.help_outline,
              label: 'How',
              onTap: widget.onHowItWorksTap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBufferSelectionBar(BuildContext context) {
    final appState = context.watch<AppState>();
    final selectedDuration = appState.selectedBufferSeconds;
    final isPro = appState.isPro;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Duration options - uses dynamic list based on device RAM
            ...appState.availableBufferDurations.map((duration) {
              final status = appState.getBufferDurationStatus(duration);
              final isSelected = selectedDuration == duration;
              final isLocked = status == 'locked';
              final isUnlocked = status == 'unlocked';
              final isIncompatible = status == 'incompatible';

              return _BufferDurationOption(
                duration: duration,
                isSelected: isSelected,
                isLocked: isLocked,
                isUnlocked: isUnlocked,
                isIncompatible: isIncompatible,
                isPro: isPro,
                onTap: () => _handleDurationTap(context, appState, duration),
              );
            }),
            // Close button
            _CloseButton(onTap: _switchToDefault),
          ],
        ),
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
        // Return to default state after selection
        _switchToDefault();
        break;

      case 'blocked':
        _showBlockedMessage(context);
        break;

      case 'incompatible':
        _showIncompatibleMessage(context);
        break;

      case 'needs_ad':
      case 'needs_paywall':
        // Show paywall for locked durations
        if (widget.onShowPaywall != null) {
          widget.onShowPaywall!();
        }
        break;
    }
  }

  void _showIncompatibleMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.memory, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('This buffer duration is not supported on your device'),
          ],
        ),
        duration: const Duration(seconds: 3),
        backgroundColor: AppColors.charcoal,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showBlockedMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Change buffer time after saving'),
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
      builder: (dialogContext) => _RewardedAdDialog(
        duration: duration,
        onWatchAd: () async {
          Navigator.pop(dialogContext);

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
            // Return to default state
            _switchToDefault();

            if (context.mounted) {
              _showUnlockSuccessMessage(context, duration);
            }
          } else {
            if (context.mounted) {
              _showAdFailedMessage(context);
            }
          }
        },
        onCancel: () => Navigator.pop(dialogContext),
        onShowPaywall: () {
          Navigator.pop(dialogContext);
          if (widget.onShowPaywall != null) {
            widget.onShowPaywall!();
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
                const Text(
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
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('${duration}s buffer unlocked!'),
          ],
        ),
        duration: const Duration(seconds: 2),
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
        content: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Ad not available. Try again later.'),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.recordRed,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// Individual button in the default bottom bar state
class _BottomBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? badge;
  final VoidCallback? onTap;
  final bool isDisabled;

  const _BottomBarButton({
    required this.icon,
    required this.label,
    this.badge,
    this.onTap,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: isDisabled ? 0.4 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.electricBlue.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      color: AppColors.electricBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Buffer duration option button in selection mode
class _BufferDurationOption extends StatelessWidget {
  final int duration;
  final bool isSelected;
  final bool isLocked;
  final bool isUnlocked;
  final bool isIncompatible;
  final bool isPro;
  final VoidCallback onTap;

  const _BufferDurationOption({
    required this.duration,
    required this.isSelected,
    required this.isLocked,
    required this.isUnlocked,
    required this.isIncompatible,
    required this.isPro,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAvailable = !isLocked || isPro || isUnlocked;
    final isDisabled = isIncompatible;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.electricBlue
              : isDisabled
                  ? Colors.white.withOpacity(0.03)
                  : isAvailable
                      ? Colors.white.withOpacity(0.1)
                      : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? null
              : Border.all(
                  color: Colors.white.withOpacity(isDisabled
                      ? 0.1
                      : isAvailable
                          ? 0.3
                          : 0.15),
                  width: 1,
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Block icon for incompatible durations (device limitation)
            if (isIncompatible && !isPro) ...[
              Icon(
                Icons.block,
                color: Colors.white.withOpacity(0.35),
                size: 14,
              ),
              const SizedBox(width: 4),
            ],
            // Lock icon for locked durations
            if (isLocked && !isPro && !isUnlocked && !isIncompatible) ...[
              Icon(
                Icons.lock_outline,
                color: Colors.white.withOpacity(0.5),
                size: 14,
              ),
              const SizedBox(width: 4),
            ],
            // Unlocked badge (rewarded ad unlock)
            if (isUnlocked && !isPro) ...[
              Icon(
                Icons.play_circle_outline,
                color: AppColors.successGreen,
                size: 14,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              '${duration}s',
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : isDisabled
                        ? Colors.white.withOpacity(0.35)
                        : isAvailable
                            ? Colors.white
                            : Colors.white.withOpacity(0.5),
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Close button to return to default bar state
class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.close,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

/// Dialog for watching rewarded ad to unlock buffer duration
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Lock icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.proGold.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline,
                color: AppColors.proGold,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Unlock ${duration}s Buffer',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Watch a short video to temporarily unlock this buffer duration, or upgrade to Pro for permanent access.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            // Watch ad button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onWatchAd,
                icon: const Icon(Icons.play_circle_outline, size: 20),
                label: const Text('Watch Ad to Unlock'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.electricBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Upgrade button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onShowPaywall,
                icon: Icon(
                  Icons.star,
                  size: 18,
                  color: AppColors.proGold,
                ),
                label: Text(
                  'Upgrade to Pro',
                  style: TextStyle(color: AppColors.proGold),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.proGold.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Cancel button
            TextButton(
              onPressed: onCancel,
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
