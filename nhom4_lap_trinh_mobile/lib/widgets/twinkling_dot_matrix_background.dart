import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Nền động lưới ma trận điểm nhấp nháy ("Twinkling Dot Matrix Grid")
/// vẽ trực tiếp bằng [CustomPainter] ở 60fps với mức tiêu thụ tài nguyên tối thiểu.
class TwinklingDotMatrixBackground extends StatefulWidget {
  final Color backgroundColor;
  final Color dimColor;
  final Color primaryGlowColor;
  final Color secondaryGlowColor;
  final double spacing;
  final double dotRadius;
  final bool enableAnimation;

  const TwinklingDotMatrixBackground({
    super.key,
    this.backgroundColor = const Color(0xFF031226),
    this.dimColor = const Color(0xFF0D2B4E),
    this.primaryGlowColor = const Color(0xFF1DA1F2),
    this.secondaryGlowColor = const Color(0xFF38BDF8),
    this.spacing = 24.0,
    this.dotRadius = 1.4,
    this.enableAnimation = true,
  });

  @override
  State<TwinklingDotMatrixBackground> createState() =>
      _TwinklingDotMatrixBackgroundState();
}

class _DotSpec {
  final double x;
  final double y;
  final double phase;
  final double angularVelocity;
  final bool isCyanCandidate;
  final bool useSecondaryCyan;

  const _DotSpec({
    required this.x,
    required this.y,
    required this.phase,
    required this.angularVelocity,
    required this.isCyanCandidate,
    required this.useSecondaryCyan,
  });
}

class _TwinklingDotMatrixBackgroundState
    extends State<TwinklingDotMatrixBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _elapsedSeconds = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _elapsedSeconds.value = elapsed.inMicroseconds / 1000000.0;
    });
    if (widget.enableAnimation) {
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(covariant TwinklingDotMatrixBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enableAnimation && !_ticker.isActive) {
      _ticker.start();
    } else if (!widget.enableAnimation && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsedSeconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ColoredBox(
        color: widget.backgroundColor,
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _DotMatrixPainter(
              elapsedSeconds: _elapsedSeconds,
              dimColor: widget.dimColor,
              primaryGlowColor: widget.primaryGlowColor,
              secondaryGlowColor: widget.secondaryGlowColor,
              spacing: widget.spacing,
              dotRadius: widget.dotRadius,
            ),
          ),
        ),
      ),
    );
  }
}

class _DotMatrixPainter extends CustomPainter {
  final ValueNotifier<double> elapsedSeconds;
  final Color dimColor;
  final Color primaryGlowColor;
  final Color secondaryGlowColor;
  final double spacing;
  final double dotRadius;

  final Paint _dotPaint = Paint()..style = PaintingStyle.fill;
  final Paint _glowPaint = Paint()..style = PaintingStyle.fill;

  int _cachedCols = -1;
  int _cachedRows = -1;
  double _cachedSpacing = -1;
  List<_DotSpec> _dots = const [];

  _DotMatrixPainter({
    required this.elapsedSeconds,
    required this.dimColor,
    required this.primaryGlowColor,
    required this.secondaryGlowColor,
    required this.spacing,
    required this.dotRadius,
  }) : super(repaint: elapsedSeconds);

  void _ensureGrid(Size size) {
    if (size.isEmpty || spacing <= 0) {
      _dots = const [];
      return;
    }

    final int cols = (size.width / spacing).floor() + 1;
    final int rows = (size.height / spacing).floor() + 1;

    if (cols == _cachedCols &&
        rows == _cachedRows &&
        spacing == _cachedSpacing) {
      return;
    }

    _cachedCols = cols;
    _cachedRows = rows;
    _cachedSpacing = spacing;

    final double offsetX = (size.width - (cols - 1) * spacing) * 0.5;
    final double offsetY = (size.height - (rows - 1) * spacing) * 0.5;

    final math.Random rng = math.Random(20261115);
    final List<_DotSpec> generated = <_DotSpec>[];

    for (int r = 0; r < rows; r++) {
      final double y = offsetY + r * spacing;
      for (int c = 0; c < cols; c++) {
        final double x = offsetX + c * spacing;
        final double cycleSeconds = 2.5 + rng.nextDouble() * 2.5; // 2.5s - 5.0s
        final double phase = rng.nextDouble() * math.pi * 2.0;
        // ~38% chấm thuộc nhóm có khả năng sáng cyan -> tại mọi thời điểm có ~20-25% chấm sáng rực
        final bool isCyanCandidate = rng.nextDouble() < 0.38;
        final bool useSecondaryCyan = rng.nextBool();

        generated.add(
          _DotSpec(
            x: x,
            y: y,
            phase: phase,
            angularVelocity: (math.pi * 2.0) / cycleSeconds,
            isCyanCandidate: isCyanCandidate,
            useSecondaryCyan: useSecondaryCyan,
          ),
        );
      }
    }

    _dots = generated;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _ensureGrid(size);
    if (_dots.isEmpty) return;

    final double t = elapsedSeconds.value;
    final double glowRadius = dotRadius * 2.4;

    for (int i = 0; i < _dots.length; i++) {
      final _DotSpec dot = _dots[i];
      final double wave =
          0.5 + 0.5 * math.sin(t * dot.angularVelocity + dot.phase);

      if (dot.isCyanCandidate) {
        final double opacity = 0.12 + 0.88 * wave;
        final Color activeColor =
            dot.useSecondaryCyan ? secondaryGlowColor : primaryGlowColor;

        if (wave > 0.42) {
          final double glowStrength = ((wave - 0.42) / 0.58).clamp(0.0, 1.0);
          _glowPaint.color =
              activeColor.withValues(alpha: 0.22 * glowStrength);
          canvas.drawCircle(Offset(dot.x, dot.y), glowRadius, _glowPaint);

          _dotPaint.color = Color.lerp(dimColor, activeColor, glowStrength)!
              .withValues(alpha: opacity);
        } else {
          _dotPaint.color = dimColor.withValues(alpha: opacity);
        }
      } else {
        // Nhóm chấm nền dao động nhẹ ở mức mờ để giữ độ tương phản cao cho chữ
        final double opacity = 0.12 + 0.26 * wave;
        _dotPaint.color = dimColor.withValues(alpha: opacity);
      }

      canvas.drawCircle(Offset(dot.x, dot.y), dotRadius, _dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DotMatrixPainter oldDelegate) {
    return oldDelegate.dimColor != dimColor ||
        oldDelegate.primaryGlowColor != primaryGlowColor ||
        oldDelegate.secondaryGlowColor != secondaryGlowColor ||
        oldDelegate.spacing != spacing ||
        oldDelegate.dotRadius != dotRadius;
  }
}
