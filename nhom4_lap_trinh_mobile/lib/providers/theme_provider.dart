import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider Quản lý Giao diện Sáng/Tối (Light/Dark Mode)
/// Tích hợp lưu trạng thái bền vững qua SharedPreferences theo chuẩn Chương 9 & 12
class ThemeProvider extends ChangeNotifier {
  static const String _prefDarkModeKey = 'is_dark_mode_enabled';

  ThemeMode _themeMode = ThemeMode.dark;

  ThemeProvider() {
    _loadThemeFromPrefs();
  }

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  // [READ] Đọc trạng thái Theme đã lưu trong SharedPreferences khi mở app
  Future<void> _loadThemeFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_prefDarkModeKey)) {
        final isDark = prefs.getBool(_prefDarkModeKey) ?? false;
        _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[ThemeProvider] Không thể đọc theme từ SharedPreferences: $e');
    }
  }

  // [UPDATE] Chuyển đổi Theme và lưu ngay vào SharedPreferences
  Future<void> toggleTheme(bool isOn) async {
    _themeMode = isOn ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefDarkModeKey, isOn);
    } catch (e) {
      debugPrint('[ThemeProvider] Không thể lưu theme vào SharedPreferences: $e');
    }
  }

  // ========================================================
  // BỘ THEME PHONG CÁCH EDITORIAL MINIMALIST (Material 3)
  // Đồng bộ toàn hệ thống: #0E0E10 • #18181A • #565C43 • #ECEBE6
  // ========================================================
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF565C43),
      brightness: Brightness.light,
      primary: const Color(0xFF565C43),
      onPrimary: const Color(0xFFECEBE6),
      secondary: const Color(0xFF3E4230),
      surface: const Color(0xFFF7F6F2),
      onSurface: const Color(0xFF141416),
    ),
    scaffoldBackgroundColor: const Color(0xFFECEBE6),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Color(0xFF18181A),
      foregroundColor: Color(0xFFECEBE6),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFFF7F6F2),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xFFD6D4CC), width: 1.1),
      ),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF565C43),
      brightness: Brightness.dark,
      primary: const Color(0xFF8E9773),
      onPrimary: const Color(0xFF0E0E10),
      primaryContainer: const Color(0xFF565C43),
      onPrimaryContainer: const Color(0xFFECEBE6),
      secondary: const Color(0xFFECEBE6),
      onSecondary: const Color(0xFF141416),
      surface: const Color(0xFF18181A),
      onSurface: const Color(0xFFECEBE6),
    ),
    scaffoldBackgroundColor: const Color(0xFF0E0E10),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Color(0xFF141416),
      foregroundColor: Color(0xFFECEBE6),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF18181A),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10), width: 1.1),
      ),
    ),
  );
}
