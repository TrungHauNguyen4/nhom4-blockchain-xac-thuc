import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Lớp nền bầu trời sao động (Animated Starfield Background) tối ưu 60fps.
///
/// Có thể tùy chỉnh trực tiếp:
/// - [starCount]: số lượng hạt sao (khuyến nghị 35–50).
/// - [driftSpeed]: hệ số tốc độ trôi lên trên (1.0 = 4–10 px/giây).
/// - [brightness]: độ sáng tổng thể của các hạt sao (0.0 – 1.0).
/// - [glowColor] & [glowOpacity]: vùng sáng tỏa nhẹ ở 1/3 phía trên màn hình.
class StarfieldBackground extends StatefulWidget {
  final int starCount;
  final double driftSpeed;
  final double brightness;
  final Color glowColor;
  final double glowOpacity;
  final Widget? child;

  const StarfieldBackground({
    super.key,
    this.starCount = 42,
    this.driftSpeed = 1.0,
    this.brightness = 1.0,
    this.glowColor = const Color(0xFF6B1822),
    this.glowOpacity = 0.20,
    this.child,
  });

  @override
  State<StarfieldBackground> createState() => _StarfieldBackgroundState();
}

class _StarfieldBackgroundState extends State<StarfieldBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _elapsedSeconds = 0.0;
  late List<_StarParticle> _stars;

  @override
  void initState() {
    super.initState();
    _stars = _generateStars(widget.starCount);
    _ticker = createTicker((elapsed) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds = elapsed.inMicroseconds / 1000000.0;
      });
    })..start();
  }

  @override
  void didUpdateWidget(covariant StarfieldBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.starCount != widget.starCount) {
      _stars = _generateStars(widget.starCount);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  List<_StarParticle> _generateStars(int count) {
    final safeCount = count.clamp(1, 150);
    final rng = math.Random(4207);
    return List<_StarParticle>.generate(safeCount, (i) {
      final diameter = 1.0 + rng.nextDouble() * 1.5; // 1.0px -> 2.5px
      return _StarParticle(
        seedX: rng.nextDouble(),
        seedY: rng.nextDouble(),
        radius: diameter / 2.0,
        color: rng.nextBool()
            ? const Color(0xFFFFFFFF)
            : const Color(0xFFDCEBFF),
        hasGlow: diameter >= 1.85,
        glowBlur: 2.0 + rng.nextDouble() * 2.0, // 2px -> 4px
        twinklePeriod: 3.0 + rng.nextDouble() * 4.0, // 3s -> 7s
        twinklePhase: rng.nextDouble() * math.pi * 2.0,
        driftPxPerSec: 4.0 + rng.nextDouble() * 6.0, // 4 -> 10 px/s
      );
    }, growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Lớp nền cố định + Vùng sáng tỏa + Hệ thống hạt sao (không chặn chạm)
        IgnorePointer(
          child: RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF09070C),
                        Color(0xFF0E1724),
                        Color(0xFF0B121D),
                      ],
                      stops: [0.0, 0.52, 1.0],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.0, -0.45),
                      radius: 0.95,
                      colors: [
                        widget.glowColor.withValues(
                          alpha: widget.glowOpacity.clamp(0.0, 0.5),
                        ),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                CustomPaint(
                  painter: _StarfieldPainter(
                    stars: _stars,
                    elapsedSeconds: _elapsedSeconds,
                    driftSpeedMultiplier: widget.driftSpeed,
                    brightness: widget.brightness.clamp(0.0, 1.0),
                  ),
                  size: Size.infinite,
                ),
              ],
            ),
          ),
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _StarParticle {
  final double seedX;
  final double seedY;
  final double radius;
  final Color color;
  final bool hasGlow;
  final double glowBlur;
  final double twinklePeriod;
  final double twinklePhase;
  final double driftPxPerSec;

  const _StarParticle({
    required this.seedX,
    required this.seedY,
    required this.radius,
    required this.color,
    required this.hasGlow,
    required this.glowBlur,
    required this.twinklePeriod,
    required this.twinklePhase,
    required this.driftPxPerSec,
  });
}

class _StarfieldPainter extends CustomPainter {
  final List<_StarParticle> stars;
  final double elapsedSeconds;
  final double driftSpeedMultiplier;
  final double brightness;

  const _StarfieldPainter({
    required this.stars,
    required this.elapsedSeconds,
    required this.driftSpeedMultiplier,
    required this.brightness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final paint = Paint()..style = PaintingStyle.fill;
    final glowPaint = Paint()..style = PaintingStyle.fill;

    for (final star in stars) {
      // 1. Chuyển động trôi chậm lên trên & vòng lặp vô tận với X ngẫu nhiên mới
      final totalDrift =
          star.driftPxPerSec * driftSpeedMultiplier * elapsedSeconds;
      final initialY = star.seedY * size.height;
      final rawY = initialY - totalDrift;
      final wrapCount = (rawY < 0) ? ((-rawY / size.height).floor() + 1) : 0;
      double y = rawY % size.height;
      if (y < 0) y += size.height;

      // Golden-ratio hash theo số lần wrap để vị trí X ngẫu nhiên khi xuất hiện lại ở đáy
      final normX = (star.seedX + wrapCount * 0.61803398875) % 1.0;
      final x = normX * size.width;

      // 2. Nhấp nháy mượt mà 0.1 -> 0.85 theo easeInOut
      final cyclePos =
          ((elapsedSeconds / star.twinklePeriod) +
              (star.twinklePhase / (math.pi * 2.0))) %
          1.0;
      final pingPong = cyclePos < 0.5 ? cyclePos * 2.0 : (1.0 - cyclePos) * 2.0;
      final eased = Curves.easeInOut.transform(pingPong.clamp(0.0, 1.0));
      final opacity = (0.10 + eased * 0.75) * brightness;

      if (star.hasGlow) {
        glowPaint
          ..color = star.color.withValues(alpha: (opacity * 0.55).clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, star.glowBlur);
        canvas.drawCircle(Offset(x, y), star.radius * 1.6, glowPaint);
      }

      paint.color = star.color.withValues(alpha: opacity.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), star.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter oldDelegate) {
    return oldDelegate.elapsedSeconds != elapsedSeconds ||
        oldDelegate.brightness != brightness ||
        oldDelegate.driftSpeedMultiplier != driftSpeedMultiplier ||
        oldDelegate.stars != stars;
  }
}
