import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chủ đề hiển thị biểu tượng / thẻ trong phần Thiết lập giao diện.
enum AppCardStyle {
  current,
  minimal,
  card;

  String get labelVi {
    switch (this) {
      case AppCardStyle.current:
        return 'Hiện tại';
      case AppCardStyle.minimal:
        return 'Tối giản';
      case AppCardStyle.card:
        return 'Dạng thẻ';
    }
  }
}

/// Provider Quản lý Giao diện (Sáng / Tối / Hệ thống), Hiệu ứng nền vũ trụ,
/// Màu chủ đạo và Chủ đề biểu tượng — lưu bền vững qua SharedPreferences.
class ThemeProvider extends ChangeNotifier {
  static const String _prefDarkModeKey = 'is_dark_mode_enabled';
  static const String _prefThemeModeKey = 'theme_mode_setting';
  static const String _prefStarfieldKey = 'starfield_background_enabled';
  static const String _prefAccentColorKey = 'theme_accent_color';
  static const String _prefCardStyleKey = 'theme_card_style';

  static const List<Color> presetAccentColors = <Color>[
    Color(0xFF565C43), // Olive Editorial (Mặc định)
    Color(0xFF2563EB), // Blue
    Color(0xFFF59E0B), // Amber
    Color(0xFF0D9488), // Teal
    Color(0xFF9333EA), // Purple
    Color(0xFF1E3A5F), // Deep Navy
    Color(0xFF0EA5E9), // Sky
    Color(0xFFE11D48), // Crimson Rose
    Color(0xFFFDA4AF), // Soft Rose
    Color(0xFFDC2626), // Red
    Color(0xFFEA580C), // Orange
  ];

  ThemeMode _themeMode = ThemeMode.dark;
  bool _starfieldEnabled = true;
  Color _accentColor = const Color(0xFF565C43);
  AppCardStyle _cardStyle = AppCardStyle.current;

  ThemeProvider() {
    _loadThemeFromPrefs();
  }

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  bool get starfieldEnabled => _starfieldEnabled;
  Color get accentColor => _accentColor;
  AppCardStyle get cardStyle => _cardStyle;

  bool isEffectiveDark(BuildContext context) {
    if (_themeMode == ThemeMode.dark) return true;
    if (_themeMode == ThemeMode.light) return false;
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  }

  Future<void> _loadThemeFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_prefThemeModeKey);
      if (savedMode == 'light') {
        _themeMode = ThemeMode.light;
      } else if (savedMode == 'system') {
        _themeMode = ThemeMode.system;
      } else if (savedMode == 'dark') {
        _themeMode = ThemeMode.dark;
      } else if (prefs.containsKey(_prefDarkModeKey)) {
        final isDark = prefs.getBool(_prefDarkModeKey) ?? true;
        _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      }

      if (prefs.containsKey(_prefStarfieldKey)) {
        _starfieldEnabled = prefs.getBool(_prefStarfieldKey) ?? true;
      }
      if (prefs.containsKey(_prefAccentColorKey)) {
        final colorVal = prefs.getInt(_prefAccentColorKey);
        if (colorVal != null) {
          _accentColor = Color(colorVal);
        }
      }
      final styleRaw = prefs.getString(_prefCardStyleKey);
      if (styleRaw != null) {
        _cardStyle = AppCardStyle.values.firstWhere(
          (e) => e.name == styleRaw,
          orElse: () => AppCardStyle.current,
        );
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[ThemeProvider] Không thể đọc theme từ SharedPreferences: $e');
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = mode == ThemeMode.light
          ? 'light'
          : (mode == ThemeMode.system ? 'system' : 'dark');
      await prefs.setString(_prefThemeModeKey, str);
      await prefs.setBool(_prefDarkModeKey, mode == ThemeMode.dark);
    } catch (e) {
      debugPrint('[ThemeProvider] Không thể lưu theme mode: $e');
    }
  }

  Future<void> toggleTheme(bool isOn) async {
    await setThemeMode(isOn ? ThemeMode.dark : ThemeMode.light);
  }

  Future<void> setStarfieldEnabled(bool enabled) async {
    _starfieldEnabled = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefStarfieldKey, enabled);
    } catch (e) {
      debugPrint('[ThemeProvider] Không thể lưu starfield: $e');
    }
  }

  Future<void> setAccentColor(Color color) async {
    _accentColor = color;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefAccentColorKey, color.toARGB32());
    } catch (e) {
      debugPrint('[ThemeProvider] Không thể lưu màu chủ đạo: $e');
    }
  }

  Future<void> setCardStyle(AppCardStyle style) async {
    _cardStyle = style;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefCardStyleKey, style.name);
    } catch (e) {
      debugPrint('[ThemeProvider] Không thể lưu card style: $e');
    }
  }

  double get _cardBorderRadius {
    switch (_cardStyle) {
      case AppCardStyle.current:
        return 22;
      case AppCardStyle.minimal:
        return 12;
      case AppCardStyle.card:
        return 16;
    }
  }

  ThemeData buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accentColor,
        brightness: Brightness.light,
        primary: _accentColor,
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
          borderRadius: BorderRadius.circular(_cardBorderRadius),
          side: BorderSide(
            color: _cardStyle == AppCardStyle.minimal
                ? const Color(0xFFD6D4CC).withValues(alpha: 0.5)
                : const Color(0xFFD6D4CC),
            width: 1.1,
          ),
        ),
      ),
    );
  }

  ThemeData buildDarkTheme() {
    final useStarCard = _starfieldEnabled;
    final cardColor = useStarCard
        ? const Color.fromRGBO(22, 30, 42, 0.72)
        : const Color(0xFF18181A);
    final cardBorderColor = useStarCard
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFF2C2C30);
    final radius = useStarCard ? 16.0 : _cardBorderRadius;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accentColor,
        brightness: Brightness.dark,
        primary: _accentColor == const Color(0xFF565C43)
            ? const Color(0xFF8E9773)
            : _accentColor,
        onPrimary: Colors.white,
        primaryContainer: _accentColor,
        onPrimaryContainer: const Color(0xFFECEBE6),
        secondary: const Color(0xFFECEBE6),
        onSecondary: const Color(0xFF141416),
        surface: const Color(0xFF161E2A),
        onSurface: Colors.white,
      ),
      scaffoldBackgroundColor:
          useStarCard ? const Color(0xFF09070C) : const Color(0xFF0E0E10),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Color(0xFF141416),
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(
            color: cardBorderColor,
            width: 1.0,
          ),
        ),
      ),
    );
  }

  // Giữ static getter mặc định để tương thích ngược với các widget test cũ.
  static final ThemeData lightTheme = ThemeProvider().buildLightTheme();
  static final ThemeData darkTheme = ThemeProvider().buildDarkTheme();
}
