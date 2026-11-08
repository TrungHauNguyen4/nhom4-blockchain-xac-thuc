import 'dart:ui';
import 'package:flutter/material.dart';

class GlassNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const GlassNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// Thanh điều hướng viên thuốc kính mờ (Glassy Navigation Tabs V7)
/// - Tích hợp hiệu ứng trượt ngang liên tục (Sliding Pill Indicator) chuẩn Framer Motion.
/// - Chế độ Tối (Dark Mode): Viên thuốc đang chọn màu trắng phát sáng (Glow White Pill).
/// - Chế độ Sáng (Light Mode): Viên thuốc đang chọn màu đen than (Obsidian Pill).
class GlassyBottomNavBar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<GlassNavItem> items;

  const GlassyBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.items,
  });

  @override
  State<GlassyBottomNavBar> createState() => _GlassyBottomNavBarState();
}

class _GlassyBottomNavBarState extends State<GlassyBottomNavBar> {
  int? _pressedIndex;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = widget.items.isEmpty ? 1 : widget.items.length;
    final safeSelected = widget.selectedIndex.clamp(0, count - 1);

    return RepaintBoundary(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                height: 64,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF282834).withValues(alpha: 0.80)
                      : const Color(0xFFE8ECF2).withValues(alpha: 0.90),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.92),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: isDark ? 0.42 : 0.10),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final tabWidth = constraints.maxWidth / count;
                    final pillLeft = safeSelected * tabWidth;

                    return Stack(
                      children: [
                        // Lớp 1: Viên thuốc trượt ngang liên tục (Sliding Pill Indicator)
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                          left: pillLeft + 2,
                          top: 0,
                          bottom: 0,
                          width: (tabWidth - 4).clamp(0.0, constraints.maxWidth),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: isDark
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFFFFFFFF),
                                        Color(0xFFF3EFEA),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    )
                                  : const LinearGradient(
                                      colors: [
                                        Color(0xFF282A37),
                                        Color(0xFF15161F),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                if (isDark)
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.34),
                                    blurRadius: 16,
                                    spreadRadius: 0.5,
                                  )
                                else
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.24),
                                    blurRadius: 12,
                                    offset: const Offset(0, 3),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        // Lớp 2: Danh sách các nút Tab với hiệu ứng phóng/thu đàn hồi
                        Row(
                          children: List.generate(widget.items.length, (index) {
                            final item = widget.items[index];
                            final isSelected = index == safeSelected;
                            final isPressed = _pressedIndex == index;

                            final Color activeTextColor =
                                isDark ? const Color(0xFF16161E) : Colors.white;
                            final Color inactiveTextColor = isDark
                                ? Colors.white.withValues(alpha: 0.72)
                                : const Color(0xFF4A5060);

                            return Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapDown: (_) =>
                                    setState(() => _pressedIndex = index),
                                onTapUp: (_) =>
                                    setState(() => _pressedIndex = null),
                                onTapCancel: () =>
                                    setState(() => _pressedIndex = null),
                                onTap: () => widget.onDestinationSelected(index),
                                child: AnimatedScale(
                                  scale: isPressed
                                      ? 0.93
                                      : (isSelected ? 1.03 : 1.0),
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOutCubic,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                    alignment: Alignment.center,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: TweenAnimationBuilder<Color?>(
                                        duration:
                                            const Duration(milliseconds: 240),
                                        curve: Curves.easeOutCubic,
                                        tween: ColorTween(
                                          end: isSelected
                                              ? activeTextColor
                                              : inactiveTextColor,
                                        ),
                                        builder: (context, color, _) {
                                          final resolvedColor = color ??
                                              (isSelected
                                                  ? activeTextColor
                                                  : inactiveTextColor);
                                          return Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                isSelected
                                                    ? item.selectedIcon
                                                    : item.icon,
                                                size: 18,
                                                color: resolvedColor,
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                item.label,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: isSelected
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                  color: resolvedColor,
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bộ chuyển trang mượt giữa các Tab (Fade + Subtle Slide + Scale)
/// Giữ nguyên 100% trạng thái (State) và tính tương thích của IndexedStack
class GlassAnimatedIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const GlassAnimatedIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  @override
  State<GlassAnimatedIndexedStack> createState() =>
      _GlassAnimatedIndexedStackState();
}

class _GlassAnimatedIndexedStackState extends State<GlassAnimatedIndexedStack> {
  int _prevIndex = 0;
  int _direction = 1;

  @override
  void initState() {
    super.initState();
    _prevIndex = widget.index;
  }

  @override
  void didUpdateWidget(covariant GlassAnimatedIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      _direction = widget.index > oldWidget.index ? 1 : -1;
      _prevIndex = widget.index;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(_prevIndex),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final double dx = (1.0 - value) * 14.0 * _direction;
        final double scale = 0.988 + (0.012 * value);
        final double opacity = (0.35 + (0.65 * value)).clamp(0.0, 1.0);

        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(dx, 0),
            child: Transform.scale(
              scale: scale,
              child: child,
            ),
          ),
        );
      },
      child: IndexedStack(
        index: widget.index,
        children: widget.children,
      ),
    );
  }
}

/// Thẻ kính mờ hiện đại (GlassCard - chuẩn rounded-2xl kèm hiệu ứng nhấn đàn hồi)
class GlassCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? tintColor;
  final Color? borderColor;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.tintColor,
    this.borderColor,
    this.onTap,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBg = isDark
        ? const Color(0xFF222433).withValues(alpha: 0.78)
        : Colors.white.withValues(alpha: 0.92);
    final defaultBorder = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.95);

    return AnimatedScale(
      scale: _isPressed ? 0.975 : 1.0,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: Container(
        margin: widget.margin,
        decoration: BoxDecoration(
          color: widget.tintColor ?? defaultBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: widget.borderColor ?? defaultBorder,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.26 : 0.06),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: widget.onTap != null
              ? InkWell(
                  onTapDown: (_) => setState(() => _isPressed = true),
                  onTapUp: (_) => setState(() => _isPressed = false),
                  onTapCancel: () => setState(() => _isPressed = false),
                  onTap: widget.onTap,
                  child: Padding(padding: widget.padding, child: widget.child),
                )
              : Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );
  }
}

/// Nền chuyển sắc chiều sâu giúp làm nổi bật hiệu ứng Kính mờ (Glassmorphism)
class GlassScaffoldBackground extends StatelessWidget {
  final Widget child;

  const GlassScaffoldBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [
                  Color(0xFF0F111A),
                  Color(0xFF171A28),
                  Color(0xFF121521),
                ]
              : const [
                  Color(0xFFF2F5FA),
                  Color(0xFFE9EFF8),
                  Color(0xFFF5F7FB),
                ],
        ),
      ),
      child: child,
    );
  }
}
