import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flashback_cam/theme.dart';

class RecordButton extends StatefulWidget {
  final bool isRecording;
  final VoidCallback onTap;
  final double bufferProgress;
  final int selectedBufferSeconds;
  final bool isEnabled;

  const RecordButton({
    super.key,
    required this.isRecording,
    required this.onTap,
    required this.bufferProgress,
    required this.selectedBufferSeconds,
    this.isEnabled = true,
  });

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton>
    with TickerProviderStateMixin {
  late AnimationController _breathController;
  late AnimationController _sweepController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 3),
    );

    _sweepController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    );

    if (widget.isEnabled) {
      _breathController.repeat(reverse: true);
      _sweepController.repeat();
    } else {
      _breathController.value = 0.0;
      _sweepController.value = 0.0;
    }

    _pulseController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1500),
    );

    _updatePulseAnimation();
  }

  @override
  void didUpdateWidget(RecordButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isRecording != widget.isRecording) {
      _updatePulseAnimation();
    }
    if (oldWidget.isEnabled != widget.isEnabled) {
      if (widget.isEnabled) {
        _breathController.repeat(reverse: true);
        _sweepController.repeat();
      } else {
        _breathController
          ..stop()
          ..value = 0.0;
        _sweepController
          ..stop()
          ..value = 0.0;
      }
    }
  }

  void _updatePulseAnimation() {
    if (widget.isRecording) {
      _pulseController.repeat();
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _breathController.dispose();
    _sweepController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: widget.isEnabled ? widget.onTap : null,
        child: AnimatedBuilder(
          animation: Listenable.merge(
              [_breathController, _sweepController, _pulseController]),
          builder: (context, child) {
            final breathScale = widget.isEnabled && !widget.isRecording
                ? 1.0 + (_breathController.value * 0.03)
                : 1.0;
            final pulseScale = widget.isRecording
                ? 1.0 + (sin(_pulseController.value * 2 * pi) * 0.08)
                : 1.0;

            return Opacity(
              opacity: widget.isEnabled ? 1.0 : 0.3,
              child: Container(
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Buffer ring - always visible but changes based on state
                    CustomPaint(
                      size: Size(80, 80),
                      painter: BufferRingPainter(
                        progress: widget.bufferProgress,
                        sweepProgress: _sweepController.value,
                        color: AppColors.electricBlue,
                        isRecording: widget.isRecording,
                        selectedBufferSeconds: widget.selectedBufferSeconds,
                        isEnabled: widget.isEnabled,
                      ),
                    ),
                    // Outer ring (pulsing when recording)
                    Transform.scale(
                      scale: pulseScale,
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 200),
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(
                              alpha: widget.isRecording ? 0.1 : 0.2),
                          border: widget.isRecording
                              ? Border.all(
                                  color: AppColors.recordRed
                                      .withValues(alpha: 0.3),
                                  width: 2,
                                )
                              : null,
                        ),
                      ),
                    ),
                    // Main button (breathing when idle)
                    Transform.scale(
                      scale: breathScale,
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 200),
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.isRecording
                              ? AppColors.recordRed
                              : Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: (widget.isRecording
                                      ? AppColors.recordRed
                                      : AppColors.electricBlue)
                                  .withValues(alpha: 0.4),
                              blurRadius: widget.isRecording ? 20 : 16,
                              spreadRadius: widget.isRecording ? 4 : 2,
                            ),
                          ],
                        ),
                        child: widget.isRecording
                            ? Center(
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.fiber_manual_record,
                                color: AppColors.electricBlue,
                                size: 16,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
}

class BufferRingPainter extends CustomPainter {
  final double progress;
  final double sweepProgress;
  final Color color;
  final bool isRecording;
  final int selectedBufferSeconds;
  final bool isEnabled;

  BufferRingPainter({
    required this.progress,
    required this.color,
    required this.selectedBufferSeconds,
    this.sweepProgress = 0.0,
    this.isRecording = false,
    this.isEnabled = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    if (!isEnabled) {
      _drawDisabledRing(canvas, center, radius);
      return;
    }

    if (isRecording) {
      // When recording, show pre-roll + recording progress
      _drawRecordingRing(canvas, center, radius);
    } else {
      // When idle, show continuous buffer sweep
      _drawBufferSweep(canvas, center, radius);
    }
  }

  void _drawDisabledRing(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, paint);
  }

  void _drawRecordingRing(Canvas canvas, Offset center, double radius) {
    // Draw pre-roll portion (solid)
    final preRollPaint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      preRollPaint,
    );
  }

  void _drawBufferSweep(Canvas canvas, Offset center, double radius) {
    // Draw buffer progress (filled portion)
    final bufferPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      bufferPaint,
    );

    // Draw sweeping indicator
    final sweepPaint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final sweepAngle = -pi / 2 + (2 * pi * sweepProgress);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      sweepAngle - pi / 8,
      pi / 4,
      false,
      sweepPaint,
    );
  }

  @override
  bool shouldRepaint(BufferRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.sweepProgress != sweepProgress ||
      oldDelegate.isRecording != isRecording ||
      oldDelegate.isEnabled != isEnabled;
}
