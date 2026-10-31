import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nhom4_lap_trinh_mobile/main.dart';
import 'package:nhom4_lap_trinh_mobile/providers/theme_provider.dart';
import 'package:nhom4_lap_trinh_mobile/services/api_service.dart';
import 'package:nhom4_lap_trinh_mobile/services/hash_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('HashService Keccak-256 & SHA-256 khớp chuẩn mật mã', () {
    // Chuỗi rỗng "" trong Ethereum Keccak-256 phải ra đúng hằng số chuẩn c5d246...
    final emptyKeccak = HashService.keccak256FromString('');
    expect(
      emptyKeccak,
      '0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470',
    );

    // Chuỗi rỗng "" trong SHA-256 phải ra đúng hằng số chuẩn e3b0c4...
    final emptySha256 = HashService.sha256FromString('');
    expect(
      emptySha256,
      '0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  });

  test('ApiService lưu/đọc baseUrl qua SharedPreferences & notarizeFileStream hoạt động', () async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.saveBaseUrl('http://192.168.1.50:3000/');
    await ApiService.setMockMode(true);
    await ApiService.loadSavedConfig();

    expect(ApiService.baseUrl, 'http://192.168.1.50:3000');
    expect(ApiService.useMockWhenOffline, isTrue);

    final api = ApiService();
    final sampleBytes = Uint8List.fromList([1, 2, 3, 4]);
    final events = await HashService.notarizeFileStream(
      fileBytes: sampleBytes,
      fileName: 'bang_mau.pdf',
      apiService: api,
      studentName: 'Nguyễn Văn A',
      studentCode: 'SV001',
      degreeName: 'Kỹ sư CNTT',
    ).toList();

    expect(events.length, 4);
    expect(events.last.step, NotarizationStep.completed);
    expect(events.last.txHash, isNotNull);
  });

  testWidgets('Khung MultiProvider & giao diện chính khởi chạy ổn định', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>(create: (_) => ApiService()),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ],
        child: const CertificateVerifierApp(),
      ),
    );
    await tester.pump();
    expect(find.text('Xác Thực Văn Bằng Số'), findsOneWidget);
  });
}
