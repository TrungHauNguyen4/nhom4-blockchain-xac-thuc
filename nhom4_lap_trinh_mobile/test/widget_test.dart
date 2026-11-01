import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nhom4_lap_trinh_mobile/main.dart';
import 'package:nhom4_lap_trinh_mobile/models/user_model.dart';
import 'package:nhom4_lap_trinh_mobile/providers/auth_provider.dart';
import 'package:nhom4_lap_trinh_mobile/providers/theme_provider.dart';
import 'package:nhom4_lap_trinh_mobile/screens/issuer/issue_certificate_screen.dart';
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

  test('UserModel chuyển đổi JSON & phân quyền 3 vai trò chính xác', () {
    const staff = UserModel(
      uid: 'staff_123',
      name: 'ThS. Nguyễn Văn A',
      email: 'canbo@edu.vn',
      role: UserRole.staff,
      organization: 'Đại học Bách Khoa',
      createdAt: '31/10/2026 12:00:00',
    );

    expect(staff.isStaff, isTrue);
    expect(staff.isEmployer, isFalse);
    expect(staff.isStudent, isFalse);
    expect(staff.roleTitle, 'Cán bộ đào tạo');

    // Test serialization
    final json = staff.toJson();
    final fromJson = UserModel.fromJson(json);
    expect(fromJson.uid, staff.uid);
    expect(fromJson.name, staff.name);
    expect(fromJson.role, staff.role);
    expect(fromJson.organization, staff.organization);
  });

  test('AuthProvider xử lý đăng nhập tài khoản demo và đổi vai trò mượt mà', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthProvider();

    // Đăng nhập cán bộ
    final okStaff = await auth.login('canbo@edu.vn', '123456');
    expect(okStaff, isTrue);
    expect(auth.isAuthenticated, isTrue);
    expect(auth.isStaff, isTrue);
    expect(auth.currentUser?.role, UserRole.staff);

    // Chuyển nhanh sang nhà tuyển dụng để demo
    auth.switchRoleForDemo(UserRole.employer);
    expect(auth.isEmployer, isTrue);
    expect(auth.currentUser?.roleTitle, 'Nhà tuyển dụng');

    // Đăng xuất
    await auth.logout();
    expect(auth.isAuthenticated, isFalse);
    expect(auth.currentUser, isNull);
  });

  testWidgets('Khung MultiProvider & AuthGate khởi chạy hiển thị màn hình Auth khi chưa đăng nhập', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>(create: (_) => ApiService()),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ],
        child: const CertificateVerifierApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Khi chưa đăng nhập phải thấy giao diện AuthScreen
    expect(find.text('XÁC THỰC VĂN BẰNG'), findsOneWidget);
    expect(find.text('ĐĂNG NHẬP'), findsOneWidget);
    expect(find.text('Đăng ký ngay'), findsOneWidget);
  });

  testWidgets('Màn hình IssueCertificateScreen kiểm tra phân quyền Staff, menu Camera/Thư viện và OrientationBuilder', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final authProvider = AuthProvider();
    await authProvider.login('canbo@edu.vn', '123456');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>(create: (_) => ApiService()),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ],
        child: const MaterialApp(
          home: IssueCertificateScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Kiểm tra hiển thị đầy đủ các bước cho Cán bộ đào tạo
    expect(find.text('Bước 1: Chọn Tài Liệu / Ảnh Cần Ký Số'), findsOneWidget);
    expect(find.text('Bước 2: Thông Tin Sinh Viên & Bằng Cấp'), findsOneWidget);

    // Bấm nút Chụp / Chọn Ảnh phải mở BottomSheet có cả Camera và Thư viện
    await tester.tap(find.text('Chụp / Chọn Ảnh'));
    await tester.pumpAndSettle();
    expect(find.text('Chụp ảnh bằng cấp trực tiếp từ Camera'), findsOneWidget);
    expect(find.text('Chọn ảnh bằng cấp từ Thư viện máy'), findsOneWidget);
  });
}
