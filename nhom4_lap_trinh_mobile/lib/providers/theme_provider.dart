import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider Quản lý Giao diện Sáng/Tối (Light/Dark Mode)
/// Tích hợp lưu trạng thái bền vững qua SharedPreferences theo chuẩn Chương 9 & 12
class ThemeProvider extends ChangeNotifier {
  static const String _prefDarkModeKey = 'is_dark_mode_enabled';

  ThemeMode _themeMode = ThemeMode.system;

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
  // BỘ THEME CHUẨN CÔNG NGHỆ BLOCKCHAIN (Material 3)
  // ========================================================
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E88E5), // Xanh dương công nghệ
      brightness: Brightness.light,
      primary: const Color(0xFF0D47A1),
      secondary: const Color(0xFF00897B),
      surface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Color(0xFF0D47A1),
      foregroundColor: Colors.white,
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF64B5F6),
      brightness: Brightness.dark,
      primary: const Color(0xFF90CAF9),
      secondary: const Color(0xFF4DB6AC),
      surface: const Color(0xFF1E1E2C),
    ),
    scaffoldBackgroundColor: const Color(0xFF12121E),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Color(0xFF1E1E2C),
      foregroundColor: Colors.white,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1E1E2C),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
