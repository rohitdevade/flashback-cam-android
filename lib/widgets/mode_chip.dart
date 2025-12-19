import 'package:flutter/material.dart';
import 'package:flashback_cam/theme.dart';

class ModeChip extends StatelessWidget {
  final String label;
  final String? suffix;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isLocked;
  final bool isUnsupported;
  final String? unsupportedMessage;
  final VoidCallback? onLockedTap;

  const ModeChip({
    super.key,
    required this.label,
    this.suffix,
    required this.isSelected,
    required this.onTap,
    this.isLocked = false,
    this.isUnsupported = false,
    this.unsupportedMessage,
    this.onLockedTap,
  });

  void _showUnsupportedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.charcoal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.warningOrange, size: 24),
            const SizedBox(width: 12),
            Text(
              'Not Supported',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Text(
          unsupportedMessage ?? '$label is not supported by your device.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(
                color: AppColors.electricBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDisabled = isUnsupported;

    return GestureDetector(
      onTap: isDisabled
          ? () => _showUnsupportedDialog(context)
          : (isLocked ? (onLockedTap ?? onTap) : onTap),
      child: Opacity(
        opacity: isDisabled ? 0.4 : 1.0,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected && !isDisabled
                ? AppColors.vibrantPurple
                : (isDark ? AppColors.cardDark : AppColors.cardLight),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected && !isDisabled
                  ? AppColors.vibrantPurple
                  : (isDark ? AppColors.borderDark : AppColors.borderLight),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLocked && !isDisabled)
                Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.lock,
                      size: 14, color: AppColors.textSecondary),
                ),
              if (isDisabled)
                Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.block,
                      size: 14, color: AppColors.textSecondary),
                ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected && !isDisabled
                      ? Colors.white
                      : (isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary),
                ),
              ),
              if (suffix != null)
                Padding(
                  padding: EdgeInsets.only(left: 2),
                  child: Text(
                    suffix!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isSelected && !isDisabled
                          ? Colors.white.withOpacity(0.8)
                          : (isDark
                              ? AppColors.textSecondary
                              : AppColors.textSecondary),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
