import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nhom4_lap_trinh_mobile/providers/auth_provider.dart';
import 'package:nhom4_lap_trinh_mobile/providers/theme_provider.dart';
import 'package:nhom4_lap_trinh_mobile/screens/requests/submit_signing_request_screen.dart';
import 'package:nhom4_lap_trinh_mobile/screens/settings/theme_customization_screen.dart';
import 'package:nhom4_lap_trinh_mobile/services/api_service.dart';
import 'package:nhom4_lap_trinh_mobile/widgets/starfield_background.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('StarfieldBackground render mượt không lỗi và không chặn chạm',
      (WidgetTester tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StarfieldBackground(
            starCount: 42,
            driftSpeed: 1.0,
            brightness: 1.0,
            child: Center(
              child: ElevatedButton(
                onPressed: () => tapped = true,
                child: const Text('Bấm thử'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('Bấm thử'));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ThemeCustomizationScreen chuyển Sáng/Tối/Hệ thống, Trời sao, Kiểu thẻ & Màu',
      (WidgetTester tester) async {
    final themeProvider = ThemeProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: const MaterialApp(home: ThemeCustomizationScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Thiết lập giao diện'), findsOneWidget);
    expect(find.text('Hiệu ứng nền vũ trụ'), findsOneWidget);

    await tester.tap(find.text('Sáng'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(themeProvider.themeMode, ThemeMode.light);

    await tester.tap(find.text('Hệ thống'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(themeProvider.themeMode, ThemeMode.system);

    await tester.tap(find.text('Tối'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(themeProvider.themeMode, ThemeMode.dark);

    await tester.tap(find.text('Dạng thẻ'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(themeProvider.cardStyle, AppCardStyle.card);

    final starSwitch = find.byType(Switch);
    await tester.tap(starSwitch);
    await tester.pump(const Duration(milliseconds: 100));
    expect(themeProvider.starfieldEnabled, isFalse);
  });

  testWidgets('SubmitSigningRequestScreen chuyển tab qua lại liên tục không bị trắng/lỗi',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          Provider<ApiService>(create: (_) => ApiService()),
        ],
        child: MaterialApp(
          theme: ThemeProvider.lightTheme,
          home: const SubmitSigningRequestScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Yêu cầu đã gửi'));
      await tester.pumpAndSettle();
      expect(find.text('Vui lòng đăng nhập để xem yêu cầu.'), findsOneWidget);

      await tester.tap(find.text('Gửi yêu cầu mới'));
      await tester.pumpAndSettle();
      expect(find.text('Thuật toán băm (Hash)'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
