import 'package:flutter/material.dart';
import 'package:flashback_cam/theme.dart';
import 'package:flashback_cam/widgets/glass_container.dart';

class CameraInstructionsOverlay extends StatefulWidget {
  final VoidCallback onDismiss;

  /// Optional callback when "Don't show again" is selected
  final VoidCallback? onDontShowAgain;

  /// Whether to show the "Don't show again" checkbox
  /// Set to false for manual triggers from the bottom bar
  final bool showDontShowAgain;

  const CameraInstructionsOverlay({
    super.key,
    required this.onDismiss,
    this.onDontShowAgain,
    this.showDontShowAgain = true,
  });

  @override
  State<CameraInstructionsOverlay> createState() =>
      _CameraInstructionsOverlayState();
}

class _CameraInstructionsOverlayState extends State<CameraInstructionsOverlay> {
  bool _dontShowAgain = false;

  void _handleDismiss() {
    if (_dontShowAgain && widget.onDontShowAgain != null) {
      widget.onDontShowAgain!();
    }
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: SingleChildScrollView(
              child: GlassContainer(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header with icon
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            AppColors.electricBlue,
                            AppColors.electricBlue.withOpacity(0.6),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Icon(
                        Icons.videocam_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'How Flashback Cam Works',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Never miss a moment again!',
                      style: TextStyle(
                        color: AppColors.textSecondary.withOpacity(0.8),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),

                    // Step 1
                    _buildStep(
                      stepNumber: '1',
                      icon: Icons.play_circle_outline,
                      title: 'Activate Pre-Roll Buffer',
                      description:
                          'Tap the buffer button to start continuously recording in the background. The camera keeps the last few seconds in memory.',
                      color: AppColors.electricBlue,
                    ),
                    const SizedBox(height: 20),

                    // Step 2
                    _buildStep(
                      stepNumber: '2',
                      icon: Icons.fiber_manual_record,
                      title: 'Tap Record Anytime',
                      description:
                          'When something exciting happens, tap the record button. Your video will include footage from BEFORE you pressed record!',
                      color: AppColors.recordRed,
                    ),
                    const SizedBox(height: 20),

                    // Step 3
                    _buildStep(
                      stepNumber: '3',
                      icon: Icons.history,
                      title: 'Capture the Past',
                      description:
                          'Perfect for spontaneous moments - birthday surprises, wildlife, sports plays, or anything unexpected!',
                      color: AppColors.proGold,
                    ),

                    const SizedBox(height: 24),

                    // Don't show again checkbox (only show when appropriate)
                    if (widget.showDontShowAgain)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _dontShowAgain = !_dontShowAgain);
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: _dontShowAgain
                                      ? AppColors.electricBlue
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: _dontShowAgain
                                        ? AppColors.electricBlue
                                        : Colors.white.withOpacity(0.5),
                                    width: 1.5,
                                  ),
                                ),
                                child: _dontShowAgain
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 14,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "Don't show again",
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Got it button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _handleDismiss,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.electricBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Got It!',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep({
    required String stepNumber,
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Step indicator with icon
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withOpacity(0.5),
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            color: color,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        // Content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  color: AppColors.textSecondary.withOpacity(0.9),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
