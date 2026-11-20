import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import '../../widgets/starfield_background.dart';

/// Màn hình Thiết lập giao diện theo mẫu trực quan:
/// - Khung xem trước trực tiếp (Preview)
/// - Chế độ giao diện (Sáng / Tối / Hệ thống) + Công tắc Hiệu ứng nền vũ trụ
/// - Chủ đề biểu tượng (Hiện tại / Tối giản / Dạng thẻ)
/// - Màu chủ đạo
class ThemeCustomizationScreen extends StatelessWidget {
  const ThemeCustomizationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isEffectiveDark(context);
    final accent = themeProvider.accentColor;

    final Widget content = Scaffold(
      backgroundColor: isDark && themeProvider.starfieldEnabled
          ? Colors.transparent
          : null,
      appBar: AppBar(
        title: const Text('Thiết lập giao diện'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPreviewCard(context, themeProvider, isDark, accent),
          const SizedBox(height: 16),
          _buildThemeModeSection(context, themeProvider, isDark, accent),
          const SizedBox(height: 16),
          _buildCardStyleSection(context, themeProvider, isDark, accent),
          const SizedBox(height: 16),
          _buildAccentColorSection(context, themeProvider, isDark, accent),
          const SizedBox(height: 24),
        ],
      ),
    );

    if (isDark && themeProvider.starfieldEnabled) {
      return StarfieldBackground(child: content);
    }
    return content;
  }

  Widget _buildPreviewCard(
    BuildContext context,
    ThemeProvider tp,
    bool isDark,
    Color accent,
  ) {
    final previewItems = const [
      (icon: Icons.verified_user, label: 'Xác thực', color: Colors.blue),
      (icon: Icons.folder_special, label: 'Sổ tay', color: Colors.orange),
      (icon: Icons.inbox, label: 'Yêu cầu', color: Colors.pinkAccent),
      (icon: Icons.person, label: 'Hồ sơ', color: Colors.teal),
    ];

    final cardBg = isDark
        ? const Color.fromRGBO(22, 30, 42, 0.78)
        : Colors.white;
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFD6D4CC);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 158,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cardBorder),
          color: isDark ? const Color(0xFF09070C) : const Color(0xFFECEBE6),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isDark && tp.starfieldEnabled)
              const StarfieldBackground(starCount: 24, driftSpeed: 0.8),
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                  child: Row(
                    children: previewItems.map((item) {
                      final isTileBox = tp.cardStyle != AppCardStyle.minimal;
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 4,
                          ),
                          decoration: isTileBox
                              ? BoxDecoration(
                                  color: cardBg,
                                  borderRadius: BorderRadius.circular(
                                    tp.cardStyle == AppCardStyle.card ? 14 : 10,
                                  ),
                                  border: Border.all(
                                    color: tp.cardStyle == AppCardStyle.card
                                        ? accent.withValues(alpha: 0.45)
                                        : cardBorder,
                                  ),
                                )
                              : null,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: item.color.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  item.icon,
                                  size: 18,
                                  color: item.color,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(growable: false),
                  ),
                ),
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0E141E).withValues(alpha: 0.90)
                        : Colors.white.withValues(alpha: 0.95),
                    border: Border(
                      top: BorderSide(color: cardBorder),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Icon(Icons.home_rounded, color: accent, size: 20),
                      Icon(
                        Icons.calendar_today_outlined,
                        color: isDark ? Colors.white54 : Colors.black45,
                        size: 18,
                      ),
                      Icon(
                        Icons.notifications_none,
                        color: isDark ? Colors.white54 : Colors.black45,
                        size: 20,
                      ),
                      Icon(
                        Icons.person_outline,
                        color: isDark ? Colors.white54 : Colors.black45,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeModeSection(
    BuildContext context,
    ThemeProvider tp,
    bool isDark,
    Color accent,
  ) {
    final modeLabel = tp.themeMode == ThemeMode.light
        ? 'Sáng'
        : (tp.themeMode == ThemeMode.system ? 'Hệ thống' : 'Tối');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Chế độ giao diện',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  modeLabel,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _buildModeSegment(
                    icon: Icons.wb_sunny_outlined,
                    label: 'Sáng',
                    selected: tp.themeMode == ThemeMode.light,
                    isDark: isDark,
                    onTap: () => tp.setThemeMode(ThemeMode.light),
                  ),
                  _buildModeSegment(
                    icon: Icons.nightlight_round,
                    label: 'Tối',
                    selected: tp.themeMode == ThemeMode.dark,
                    isDark: isDark,
                    onTap: () => tp.setThemeMode(ThemeMode.dark),
                  ),
                  _buildModeSegment(
                    icon: Icons.phone_android,
                    label: 'Hệ thống',
                    selected: tp.themeMode == ThemeMode.system,
                    isDark: isDark,
                    onTap: () => tp.setThemeMode(ThemeMode.system),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Hiệu ứng nền vũ trụ',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Sao chuyển động ở trang chủ khi giao diện tối',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: tp.starfieldEnabled,
                  activeThumbColor: Colors.white,
                  activeTrackColor: accent,
                  onChanged: (val) => tp.setStarfieldEnabled(val),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSegment({
    required IconData icon,
    required String label,
    required bool selected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? const Color(0xFF232C3B) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardStyleSection(
    BuildContext context,
    ThemeProvider tp,
    bool isDark,
    Color accent,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chủ đề biểu tượng',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Row(
              children: AppCardStyle.values.map((style) {
                final selected = tp.cardStyle == style;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => tp.setCardStyle(style),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.black.withValues(alpha: 0.03),
                          border: Border.all(
                            color: selected
                                ? accent
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : const Color(0xFFD6D4CC)),
                            width: selected ? 1.8 : 1.0,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: style == AppCardStyle.minimal
                                    ? Colors.transparent
                                    : accent.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                style == AppCardStyle.current
                                    ? Icons.verified_user
                                    : (style == AppCardStyle.minimal
                                        ? Icons.auto_awesome_outlined
                                        : Icons.dashboard_customize),
                                color: selected
                                    ? accent
                                    : (isDark ? Colors.white70 : Colors.black54),
                                size: 22,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              style.labelVi,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: selected ? accent : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccentColorSection(
    BuildContext context,
    ThemeProvider tp,
    bool isDark,
    Color accent,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Màu chủ đạo',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: ThemeProvider.presetAccentColors.map((c) {
                final selected = c.toARGB32() == accent.toARGB32();
                return InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => tp.setAccentColor(c),
                  child: Container(
                    width: 40,
                    height: 40,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: c, width: 2.2)
                          : null,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 20,
                            )
                          : null,
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}
