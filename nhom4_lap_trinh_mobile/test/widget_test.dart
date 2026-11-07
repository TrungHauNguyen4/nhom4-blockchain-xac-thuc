import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nhom4_lap_trinh_mobile/main.dart';
import 'package:nhom4_lap_trinh_mobile/models/certificate_record.dart';
import 'package:nhom4_lap_trinh_mobile/models/scan_history_model.dart';
import 'package:nhom4_lap_trinh_mobile/models/user_model.dart';
import 'package:nhom4_lap_trinh_mobile/providers/auth_provider.dart';
import 'package:nhom4_lap_trinh_mobile/providers/theme_provider.dart';
import 'package:nhom4_lap_trinh_mobile/screens/home_screen.dart';
import 'package:nhom4_lap_trinh_mobile/screens/issuer/issue_certificate_screen.dart';
import 'package:nhom4_lap_trinh_mobile/screens/verify_detail_screen.dart';
import 'package:nhom4_lap_trinh_mobile/services/api_service.dart';
import 'package:nhom4_lap_trinh_mobile/services/hash_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ========================================================
  // KIỂM THỬ THÀNH VIÊN 1: MẬT MÃ RAM & CORE SERVICES
  // ========================================================
  test('TV1 - HashService Keccak-256 & SHA-256 khớp chuẩn mật mã', () {
    final emptyKeccak = HashService.keccak256FromString('');
    expect(
      emptyKeccak,
      '0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470',
    );

    final emptySha256 = HashService.sha256FromString('');
    expect(
      emptySha256,
      '0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  });

  test('TV1 - ApiService lưu/đọc baseUrl qua SharedPreferences & notarizeFileStream hoạt động', () async {
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

  // ========================================================
  // KIỂM THỬ THÀNH VIÊN 2: AUTH, PHÂN QUYỀN & KÝ SỐ
  // ========================================================
  test('TV2 - UserModel chuyển đổi JSON & phân quyền 3 vai trò chính xác', () {
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

    final json = staff.toJson();
    final fromJson = UserModel.fromJson(json);
    expect(fromJson.uid, staff.uid);
    expect(fromJson.name, staff.name);
    expect(fromJson.role, staff.role);
    expect(fromJson.organization, staff.organization);
  });

  test('TV2 - AuthProvider xử lý đăng nhập tài khoản demo và đổi vai trò mượt mà', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthProvider();

    final okStaff = await auth.login('canbo@edu.vn', '123456');
    expect(okStaff, isTrue);
    expect(auth.isAuthenticated, isTrue);
    expect(auth.isStaff, isTrue);
    expect(auth.currentUser?.role, UserRole.staff);

    auth.switchRoleForDemo(UserRole.employer);
    expect(auth.isEmployer, isTrue);
    expect(auth.currentUser?.roleTitle, 'Nhà tuyển dụng');

    await auth.logout();
    expect(auth.isAuthenticated, isFalse);
    expect(auth.currentUser, isNull);
  });

  testWidgets('TV2 - Khung MultiProvider & AuthGate hiển thị màn hình Auth khi chưa đăng nhập', (WidgetTester tester) async {
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

    expect(find.text('XÁC THỰC VĂN BẰNG'), findsOneWidget);
    expect(find.text('ĐĂNG NHẬP'), findsOneWidget);
    expect(find.text('Đăng ký ngay'), findsOneWidget);
  });

  testWidgets('TV2 - Màn hình IssueCertificateScreen kiểm tra phân quyền Staff, menu Camera/Thư viện và OrientationBuilder', (WidgetTester tester) async {
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

    expect(find.text('Bước 1: Chọn Tài Liệu / Ảnh Cần Ký Số'), findsOneWidget);
    expect(find.text('Bước 2: Thông Tin Sinh Viên & Bằng Cấp'), findsOneWidget);

    await tester.tap(find.text('Chụp / Chọn Ảnh'));
    await tester.pumpAndSettle();
    expect(find.text('Chụp ảnh bằng cấp trực tiếp từ Camera'), findsOneWidget);
    expect(find.text('Chọn ảnh bằng cấp từ Thư viện máy'), findsOneWidget);
  });

  // ========================================================
  // KIỂM THỬ THÀNH VIÊN 3: SỔ TAY OFFLINE, LỊCH SỬ & RESPONSIVE UI
  // ========================================================
  test('TV3 - ScanHistoryModel & CertificateRecord chuyển đổi Map Sqflite chính xác', () {
    final history = ScanHistoryModel(
      id: 10,
      dataHash: '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
      fileName: 'Bang_Ky_Su.pdf',
      scanMethod: 'QR',
      isValid: true,
      issuerName: 'Đại học Đồng Tháp',
      studentName: 'Nguyễn Phi Long',
      degreeName: 'Cử nhân CNTT',
    );

    final map = history.toMap();
    final restored = ScanHistoryModel.fromMap(map);
    expect(restored.isValid, isTrue);
    expect(restored.scanMethod, 'QR');
    expect(restored.studentName, 'Nguyễn Phi Long');
  });

  testWidgets('TV3 + TV2 - HomeScreen tích hợp VerifyTab, VaultTab, Phân quyền Tab & xoay ngang OrientationBuilder không tràn viền', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final authProvider = AuthProvider();
    await authProvider.login('canbo@edu.vn', '123456');

    // Kiểm tra chế độ màn hình dọc (Portrait)
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>(create: (_) => ApiService()),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Staff có đủ 4 tab: Xác thực, Sổ tay & Lịch sử, Cấp bằng, Cài đặt
    expect(find.text('Xác thực'), findsOneWidget);
    expect(find.text('Sổ tay & Lịch sử'), findsOneWidget);
    expect(find.text('Cấp bằng'), findsOneWidget);
    expect(find.text('Cài đặt'), findsOneWidget);

    // Chuyển sang Tab Sổ tay & Lịch sử của TV3
    await tester.tap(find.text('Sổ tay & Lịch sử'));
    await tester.pumpAndSettle();

    // Xoay ngang màn hình (Landscape) để kiểm tra OrientationBuilder 2 cột không tràn pixel
    tester.view.physicalSize = const Size(2340, 1080);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV3 - VerifyDetailScreen hiển thị chứng nhận hợp lệ, mã QR và xoay ngang mượt mà', (WidgetTester tester) async {
    final sampleRecord = CertificateRecord(
      id: 1,
      dataHash: '0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
      signer: '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
      timestamp: 1793400000,
      fileName: 'Bang_Tot_Nghiep.pdf',
      txHash: '0x9988776655443322110099887766554433221100998877665544332211009988',
      studentName: 'Trần Thị B',
      studentCode: 'SV2026999',
      degreeName: 'Bằng Cử nhân Công nghệ Thông tin',
      issuerName: 'Phòng Đào Tạo',
    );

    tester.view.physicalSize = const Size(2340, 1080); // Landscape
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: VerifyDetailScreen(
          record: sampleRecord,
          searchedHash: sampleRecord.dataHash,
          isFromOfflineVault: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trần Thị B'), findsOneWidget);
    expect(find.text('Bằng Cử nhân Công nghệ Thông tin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
