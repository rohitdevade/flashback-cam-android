import 'package:flutter/material.dart';
import 'package:flashback_cam/theme.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final BorderRadius? borderRadius;
  final bool isDark;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: isDark ? AppColors.darkGlassOverlay : AppColors.glassOverlay,
      borderRadius: borderRadius ?? BorderRadius.circular(16),
      border: Border.all(
        color: isDark ? AppColors.darkGlassBorder : AppColors.glassBorder,
        width: 1,
      ),
    ),
    child: child,
  );
}
