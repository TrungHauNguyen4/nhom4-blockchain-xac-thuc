import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nhom4_lap_trinh_mobile/main.dart';
import 'package:nhom4_lap_trinh_mobile/providers/theme_provider.dart';
import 'package:nhom4_lap_trinh_mobile/services/api_service.dart';

void main() {
  testWidgets('App starts test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>(create: (_) => ApiService()),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ],
        child: const CertificateVerifierApp(),
      ),
    );
    expect(find.text('Xác thực'), findsOneWidget);
  });
}
