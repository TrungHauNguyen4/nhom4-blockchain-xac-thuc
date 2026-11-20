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
import 'package:nhom4_lap_trinh_mobile/screens/auth/auth_screen.dart';
import 'package:nhom4_lap_trinh_mobile/screens/auth/profile_screen.dart';
import 'package:nhom4_lap_trinh_mobile/screens/auth/register_screen.dart';
import 'package:nhom4_lap_trinh_mobile/screens/home_screen.dart';
import 'package:nhom4_lap_trinh_mobile/screens/issuer/issue_certificate_screen.dart';
import 'package:nhom4_lap_trinh_mobile/screens/issuer/issued_list_screen.dart';
import 'package:nhom4_lap_trinh_mobile/screens/vault/vault_tab.dart';
import 'package:nhom4_lap_trinh_mobile/screens/verifier/public_portfolio_screen.dart';
import 'package:nhom4_lap_trinh_mobile/screens/verify_detail_screen.dart';
import 'package:nhom4_lap_trinh_mobile/services/api_service.dart';
import 'package:nhom4_lap_trinh_mobile/services/certificate_firebase_service.dart';
import 'package:nhom4_lap_trinh_mobile/services/hash_service.dart';
import 'package:nhom4_lap_trinh_mobile/services/local_file_save_service.dart';
import 'package:nhom4_lap_trinh_mobile/widgets/pagination_controls.dart';
import 'package:nhom4_lap_trinh_mobile/widgets/twinkling_dot_matrix_background.dart';

class _FakeLedgerApiService extends ApiService {
  final Map<String, CertificateRecord> _ledger = {};

  @override
  Future<Map<String, dynamic>> notarizeCertificate({
    required String dataHash,
    required String fileName,
    String fileType = 'PDF',
    String? studentName,
    String? studentCode,
    String? degreeName,
    String? issuerName,
    String? createdByEmail,
  }) async {
    final key = dataHash.trim().toLowerCase();
    if (_ledger.containsKey(key)) {
      return {
        'success': false,
        'isDuplicate': true,
        'error': 'Tài liệu này đã được niêm phong từ trước trên hệ thống!',
        'existingRecord': _ledger[key]!.toMap(),
      };
    }
    const txHash =
        '0xabc123def4567890abc123def4567890abc123def4567890abc123def4567890';
    _ledger[key] = CertificateRecord(
      dataHash: dataHash,
      signer: '0xDF098FcEA905839FA80728D806069BF06b24F145',
      timestamp: 1785382344,
      fileName: fileName,
      fileType: fileType,
      txHash: txHash,
      blockNumber: 6912099,
      studentName: studentName,
      studentCode: studentCode,
      degreeName: degreeName,
      issuerName: issuerName ?? 'Phòng Đào Tạo',
    );
    return {
      'success': true,
      'transactionHash': txHash,
      'blockNumber': 6912099,
    };
  }

  @override
  Future<CertificateRecord?> verifyHash(
    String hash, {
    String fileName = 'Văn bằng kiểm tra',
  }) async {
    return _ledger[hash.trim().toLowerCase()];
  }

  @override
  Future<List<CertificateRecord>> fetchIssuedCertificates({
    String keyword = '',
  }) async {
    final kw = keyword.trim().toLowerCase();
    return _ledger.values.where((c) {
      if (kw.isEmpty) return true;
      return (c.studentCode ?? '').toLowerCase().contains(kw) ||
          (c.studentName ?? '').toLowerCase().contains(kw) ||
          (c.degreeName ?? '').toLowerCase().contains(kw);
    }).toList();
  }
}

AuthProvider _createAuthenticatedTestProvider(UserModel user) {
  SharedPreferences.setMockInitialValues({
    'last_logged_in_uid': user.uid,
    'user_profile_cache_${user.uid}': user.toJson(),
    'active_session_id_${user.uid}': 'test_session_1',
  });
  return AuthProvider(initialUser: user);
}

const UserModel _testStaffUser = UserModel(
  uid: 'uid_staff_test',
  name: 'ThS. Cán Bộ Test',
  email: 'staff.test@dthu.edu.vn',
  role: UserRole.staff,
  organization: 'Trường Đại học Đồng Tháp',
  createdAt: '15/11/2026 09:00:00',
);

const UserModel _testEmployerUser = UserModel(
  uid: 'uid_employer_test',
  name: 'Nguyễn HR Test',
  email: 'hr.test@company.vn',
  role: UserRole.employer,
  organization: 'Công ty Công nghệ Test',
  createdAt: '15/11/2026 09:00:00',
);

const UserModel _testStudentUser = UserModel(
  uid: 'uid_student_test',
  name: 'Trần Sinh Viên Test',
  email: 'sv.test@dthu.edu.vn',
  role: UserRole.student,
  organization: 'Khoa CNTT',
  studentCode: '0023411852',
  createdAt: '15/11/2026 09:00:00',
);

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

  test('TV1 - ApiService lưu/đọc baseUrl qua SharedPreferences hoạt động chính xác', () async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.saveBaseUrl('http://192.168.1.50:3000/');
    await ApiService.loadSavedConfig();

    expect(ApiService.baseUrl, 'http://192.168.1.50:3000');
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

  test('TV2 - AuthProvider không còn đăng nhập tài khoản demo giả lập khi chưa kết nối Firebase', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthProvider();

    final okDemo = await auth.login('canbo@edu.vn', '123456');
    expect(okDemo, isFalse);
    expect(auth.isAuthenticated, isFalse);
    expect(auth.errorMessage, isNotNull);
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('XÁC THỰC VĂN BẰNG'), findsOneWidget);
    expect(find.text('ĐĂNG NHẬP'), findsOneWidget);
    expect(find.text('Đăng ký ngay'), findsOneWidget);
  });

  testWidgets('TV2 - Màn hình IssueCertificateScreen kiểm tra phân quyền Staff, menu Camera/Thư viện và OrientationBuilder', (WidgetTester tester) async {
    final authProvider = _createAuthenticatedTestProvider(_testStaffUser);

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
    final authProvider = _createAuthenticatedTestProvider(_testStaffUser);

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

  testWidgets(
      'Stress Test UI - Toàn bộ màn hình không bị tràn viền (Overflow) trên màn hình hẹp & cỡ chữ lớn (Dark Mode)',
      (WidgetTester tester) async {
    await ApiService.loadSavedConfig();

    final authProvider = _createAuthenticatedTestProvider(_testStaffUser);
    final themeProvider = ThemeProvider();

    Widget wrapWithProviders(Widget child) {
      return MultiProvider(
        providers: [
          Provider<ApiService>(create: (_) => ApiService()),
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ],
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.18)),
          child: MaterialApp(
            themeMode: ThemeMode.dark,
            darkTheme: ThemeData.dark(useMaterial3: true),
            builder: (context, widget) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.18)),
              child: widget!,
            ),
            home: child,
          ),
        ),
      );
    }

    // Màn hình hẹp dọc (340x780 logical px) + chữ phóng to 1.18x
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(340, 780);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final screen in <Widget>[
      const AuthScreen(),
      const RegisterScreen(),
      const ProfileScreen(),
      const IssuedListScreen(),
      const VerifyDetailScreen(
        record: null,
        searchedHash:
            '0x2a82f2304fbe3f926d7d1411d9f5430dbb39f7c55764c88e6d4be5e858f5309b',
      ),
    ]) {
      await tester.pumpWidget(wrapWithProviders(screen));
      if (screen is AuthScreen) {
        await tester.pump(const Duration(milliseconds: 600));
      } else {
        await tester.pumpAndSettle();
      }
      expect(
        tester.takeException(),
        isNull,
        reason: 'Overflow on ${screen.runtimeType}',
      );
    }

    // Kiểm tra cả 4 Tab trên HomeScreen ở chế độ dọc hẹp
    await tester.pumpWidget(wrapWithProviders(const HomeScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    for (final tabLabel in ['Sổ tay & Lịch sử', 'Cấp bằng', 'Cài đặt']) {
      await tester.tap(find.text(tabLabel));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    }

    // Xoay ngang màn hình hẹp (780x340 logical px) kiểm tra 2 cột trên mọi Tab & IssuedListScreen
    tester.view.physicalSize = const Size(780, 340);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    for (final tabLabel in ['Xác thực', 'Sổ tay & Lịch sử', 'Cấp bằng']) {
      await tester.tap(find.text(tabLabel));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    }

    await tester.pumpWidget(wrapWithProviders(const IssuedListScreen()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test(
      'On-Chain Fallback - Giải mã trực tiếp ABI tuple getRecord(bytes32) từ Ethereum Sepolia khi tắt Laptop',
      () {
    const validRawHex =
        '0x'
        '7da94585051c2e102545a639ca12af4d6099f254c24d80b0b263f45b269554b0'
        '000000000000000000000000df098fcea905839fa80728d806069bf06b24f145'
        '000000000000000000000000000000000000000000000000000000006a6ac5c8';

    final decoded = ApiService.decodeOnChainGetRecordResult(
      validRawHex,
      fallbackHash:
          '0x7da94585051c2e102545a639ca12af4d6099f254c24d80b0b263f45b269554b0',
    );
    expect(decoded, isNotNull);
    expect(decoded!.isValid, isTrue);
    expect(
      decoded.signer.toLowerCase(),
      '0xdf098fcea905839fa80728d806069bf06b24f145',
    );
    expect(decoded.timestamp, 1785382344);

    final emptyRawHex = '0x${'0' * 192}';
    final notFound = ApiService.decodeOnChainGetRecordResult(
      emptyRawHex,
      fallbackHash:
          '0x2a82f2304fbe3f926d7d1411d9f5430dbb39f7c55764c88e6d4be5e858f5309b',
    );
    expect(notFound, isNull);
  });

  test(
      'Sign-then-Verify Roundtrip - Ký số file Ảnh & PDF (cả Keccak-256 và SHA-256) rồi kiểm tra lại chính file gốc phải khớp 100%',
      () async {
    final api = _FakeLedgerApiService();

    // 1. Ký số file Ảnh bằng chuẩn Tiêu chuẩn (Keccak-256)
    final imageBytes =
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 5]);
    final signImgEvents = await HashService.notarizeFileStream(
      fileBytes: imageBytes,
      fileName: 'Bang_Tot_Nghiep_Goc.jpg',
      fileType: 'IMAGE',
      apiService: api,
      studentName: 'Nguyễn Văn A',
      studentCode: 'SV001',
      degreeName: 'Kỹ sư CNTT',
      algorithm: HashAlgorithm.keccak256,
    ).toList();
    expect(signImgEvents.last.step, NotarizationStep.completed);

    // Đưa đúng mảng byte của bức ảnh gốc vào verifyFileStream -> Bắt buộc phải báo Hợp lệ
    final verifyImgEvents = await HashService.verifyFileStream(
      fileBytes: imageBytes,
      fileName: 'Bang_Tot_Nghiep_Goc.jpg',
      apiService: api,
    ).toList();
    expect(verifyImgEvents.last.step, VerificationStep.verifiedValid);
    expect(verifyImgEvents.last.hash, signImgEvents.last.hash);

    // 2. Ký số file PDF bằng chuẩn Nâng cao (SHA-256), sau đó kiểm tra lại bằng verifyFileStream mặc định
    final pdfBytes = Uint8List.fromList('%PDF-1.7-VanBangGoc-Nhom4'.codeUnits);
    final signPdfEvents = await HashService.notarizeFileStream(
      fileBytes: pdfBytes,
      fileName: 'Chung_Chi_Goc.pdf',
      fileType: 'PDF',
      apiService: api,
      studentName: 'Trần Thị B',
      studentCode: 'SV002',
      degreeName: 'Chứng chỉ An toàn Thông tin',
      algorithm: HashAlgorithm.sha256,
    ).toList();
    expect(signPdfEvents.last.step, NotarizationStep.completed);

    // verifyFileStream tự động đối soát cả Keccak-256 lẫn SHA-256 nên vẫn nhận diện Hợp lệ 100%
    final verifyPdfEvents = await HashService.verifyFileStream(
      fileBytes: pdfBytes,
      fileName: 'Chung_Chi_Goc.pdf',
      apiService: api,
    ).toList();
    expect(verifyPdfEvents.last.step, VerificationStep.verifiedValid);
    expect(verifyPdfEvents.last.hash, signPdfEvents.last.hash);

    // 3. Nếu file bị chỉnh sửa dù chỉ 1 byte -> Phải báo Cảnh báo giả (verifiedInvalid)
    final tamperedBytes = Uint8List.fromList([...pdfBytes, 0x01]);
    final tamperedEvents = await HashService.verifyFileStream(
      fileBytes: tamperedBytes,
      fileName: 'Chung_Chi_Bi_Sua.pdf',
      apiService: api,
    ).toList();
    expect(tamperedEvents.last.step, VerificationStep.verifiedInvalid);
  });

  test(
      'Google Sign-In Security - Không bao giờ tự động đăng nhập tài khoản giả Lê Hoàng Sinh Viên khi chưa kết nối hoặc hủy chọn',
      () async {
    SharedPreferences.setMockInitialValues({});
    final authProvider = AuthProvider();

    final ok = await authProvider.loginWithGoogle();
    expect(ok, isFalse);
    expect(authProvider.isAuthenticated, isFalse);
    expect(authProvider.currentUser, isNull);
    expect(authProvider.errorMessage, isNotNull);
  });

  test(
      'Password Reset & Account Deletion - Kiểm tra cơ chế quên mật khẩu và xóa tài khoản vĩnh viễn',
      () async {
    // 1. Quên mật khẩu khi chưa kết nối Firebase -> Báo lỗi rõ ràng (không còn tài khoản demo)
    final authProvider = _createAuthenticatedTestProvider(_testStudentUser);
    final resetOk = await authProvider.resetPassword('sv.test@dthu.edu.vn');
    expect(resetOk, isFalse);
    expect(authProvider.errorMessage, isNotNull);

    // 2. Xóa tài khoản từ phiên hiện tại
    expect(authProvider.isAuthenticated, isTrue);
    expect(authProvider.currentUser, isNotNull);

    final deleteOk = await authProvider.deleteAccount();
    expect(deleteOk, isTrue);
    expect(authProvider.isAuthenticated, isFalse);
    expect(authProvider.currentUser, isNull);
  });

  test(
      'Dynamic SHA-256 Staff Passcode - Kiểm tra đối chiếu băm SHA-256 và cấu hình động từ Firebase /system_config',
      () async {
    // 1. Mã sai bị từ chối
    expect(UserRole.verifyPasscode('SAI-MA-123'), isFalse);

    // 2. Mã ủy quyền hợp lệ khớp với SHA-256 một chiều (không cần lưu chữ thuần trong lib/)
    final validCode = ['NHOM4', 'CANBO', '2026'].join('-');
    expect(UserRole.verifyPasscode(validCode), isTrue);

    // 3. Khi Quản trị viên đổi mã mới trên Firebase Realtime Database (/system_config)
    final customHash = UserRole.hashPasscode('TRUONG-DH-MOI-999');
    expect(
      UserRole.verifyPasscode(
        'TRUONG-DH-MOI-999',
        remoteConfigValue: customHash,
      ),
      isTrue,
    );
    expect(
      UserRole.verifyPasscode(
        validCode,
        remoteConfigValue: customHash,
      ),
      isFalse,
    );
  });

  testWidgets(
      'Employer & Student Role Differentiation - Nhà tuyển dụng có Tab Thẩm định HR riêng, chấm trạng thái ứng viên & xuất biên bản HR',
      (WidgetTester tester) async {
    await ApiService.loadSavedConfig();

    final authProvider = _createAuthenticatedTestProvider(_testEmployerUser);
    expect(authProvider.isEmployer, isTrue);

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

    // 1. Nhà tuyển dụng có 4 Tab: Xác thực, Sổ tay & Lịch sử, Thẩm định HR, Cài đặt (không có Cấp bằng)
    expect(find.text('Xác thực'), findsOneWidget);
    expect(find.text('Sổ tay & Lịch sử'), findsOneWidget);
    expect(find.text('Thẩm định HR'), findsOneWidget);
    expect(find.text('Cấp bằng'), findsNothing);

    // 2. Mở Tab Thẩm định HR
    await tester.tap(find.text('Thẩm định HR'));
    await tester.pumpAndSettle();
    expect(
      find.text('TRUNG TÂM THẨM ĐỊNH HỒ SƠ ỨNG VIÊN (HR)'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // Kiểm tra xoay ngang màn hình Tab Thẩm định HR (2 cột)
    tester.view.physicalSize = const Size(2340, 1080);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 3. Kiểm tra VerifyDetailScreen với vai trò Nhà tuyển dụng
    tester.view.physicalSize = const Size(1080, 2340);
    final sampleRecord = CertificateRecord(
      id: 1,
      dataHash:
          '0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
      signer: '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
      timestamp: 1793400000,
      fileName: 'Bang_Tot_Nghiep.pdf',
      txHash:
          '0x9988776655443322110099887766554433221100998877665544332211009988',
      studentName: 'Lê Hoàng Sinh Viên',
      studentCode: 'SV2026001',
      degreeName: 'Bằng Kỹ sư Phần mềm',
      issuerName: 'Phòng Đào Tạo',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>(create: (_) => ApiService()),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ],
        child: MaterialApp(
          home: VerifyDetailScreen(
            record: sampleRecord,
            searchedHash: sampleRecord.dataHash,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('QUYẾT ĐỊNH THẨM ĐỊNH TUYỂN DỤNG (HR)'), findsOneWidget);
    expect(find.text('Lưu Quyết định HR'), findsOneWidget);
    expect(find.text('Xuất Biên bản Thẩm định HR'), findsOneWidget);

    await tester.ensureVisible(find.text('Lưu Quyết định HR'));
    await tester.tap(find.text('Lưu Quyết định HR'));
    await tester.pumpAndSettle();
    expect(find.text('Đã lưu HR'), findsOneWidget);

    await tester.ensureVisible(find.text('Xuất Biên bản Thẩm định HR'));
    await tester.tap(find.text('Xuất Biên bản Thẩm định HR'));
    await tester.pumpAndSettle();
    expect(find.text('BIÊN BẢN THẨM ĐỊNH VĂN BẰNG (HR)'), findsOneWidget);
    expect(find.text('I. ĐƠN VỊ THẨM ĐỊNH'), findsOneWidget);
    expect(find.text('II. HỒ SƠ VĂN BẰNG ỨNG VIÊN'), findsOneWidget);
    expect(find.text('III. KẾT LUẬN TUYỂN DỤNG'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
      'Firebase Certificate Metadata Sync - Ghép đầy đủ Metadata đám mây với kết quả On-Chain Sepolia & an toàn khi chưa khởi tạo Firebase',
      () async {
    const validRawHex =
        '0x'
        '7da94585051c2e102545a639ca12af4d6099f254c24d80b0b263f45b269554b0'
        '000000000000000000000000df098fcea905839fa80728d806069bf06b24f145'
        '000000000000000000000000000000000000000000000000000000006a6ac5c8';

    final cloudMetadata = CertificateRecord(
      dataHash:
          '0x7da94585051c2e102545a639ca12af4d6099f254c24d80b0b263f45b269554b0',
      signer: '0xdf098fcea905839fa80728d806069bf06b24f145',
      timestamp: 1785382344,
      fileName: 'Bang_Ky_Su_CNTT_NguyenVanAn.pdf',
      fileType: 'PDF',
      txHash:
          '0x3a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b',
      blockNumber: 6912450,
      studentName: 'Nguyễn Văn An',
      studentCode: 'SV2026001',
      degreeName: 'Bằng Kỹ sư Công nghệ Thông tin',
      issuerName: 'Trường Đại học Công nghệ - Phòng Đào Tạo',
    );

    final merged = ApiService.decodeOnChainGetRecordResult(
      validRawHex,
      fallbackHash: cloudMetadata.dataHash,
      cachedLocal: cloudMetadata,
    );

    expect(merged, isNotNull);
    expect(merged!.isValid, isTrue);
    expect(merged.studentName, 'Nguyễn Văn An');
    expect(merged.studentCode, 'SV2026001');
    expect(merged.degreeName, 'Bằng Kỹ sư Công nghệ Thông tin');
    expect(merged.issuerName, 'Trường Đại học Công nghệ - Phòng Đào Tạo');
    expect(merged.txHash, cloudMetadata.txHash);

    // Kiểm tra CertificateFirebaseService không crash khi chạy trong môi trường Unit Test (chưa initialize Firebase)
    final fbService = CertificateFirebaseService();
    expect(
      CertificateFirebaseService.normalizeHashKey('ABCD' * 16),
      '0x${'abcd' * 16}',
    );
    expect(await fbService.saveCertificateMetadata(cloudMetadata), isFalse);
    expect(await fbService.getMetadataByHash(cloudMetadata.dataHash), isNull);
    expect(await fbService.fetchAllCertificates(), isEmpty);
  });

  test(
      'Duplicate Notarization Prevention - Ký trùng cùng 1 file với thông tin khác phải báo lỗi isDuplicate và không ghi đè dữ liệu gốc',
      () async {
    final api = _FakeLedgerApiService();
    final sampleBytes = Uint8List.fromList('VanBangGoc_KhongDuocKyTrung'.codeUnits);

    // 1. Ký lần 1 cho Nguyễn Văn A -> Thành công
    final firstEvents = await HashService.notarizeFileStream(
      fileBytes: sampleBytes,
      fileName: 'Bang_Goc.pdf',
      apiService: api,
      studentName: 'Nguyễn Văn A',
      studentCode: 'SV001',
      degreeName: 'Kỹ sư CNTT',
    ).toList();
    expect(firstEvents.last.step, NotarizationStep.completed);
    expect(firstEvents.last.isDuplicate, isFalse);

    // 2. Ký lần 2 cùng file đó nhưng đổi thông tin sang Trần Thị B -> Phải báo trùng & lỗi
    final secondEvents = await HashService.notarizeFileStream(
      fileBytes: sampleBytes,
      fileName: 'Bang_Goc.pdf',
      apiService: api,
      studentName: 'Trần Thị B',
      studentCode: 'SV002',
      degreeName: 'Cử nhân Kinh tế',
    ).toList();
    expect(secondEvents.last.step, NotarizationStep.error);
    expect(secondEvents.last.isDuplicate, isTrue);
    expect(secondEvents.last.existingRecord?['studentName'], 'Nguyễn Văn A');

    // 3. Tra cứu lại mã Hash phải vẫn giữ nguyên thông tin gốc của Nguyễn Văn A
    final verified = await api.verifyHash(firstEvents.last.hash!);
    expect(verified, isNotNull);
    expect(verified!.studentName, 'Nguyễn Văn A');
    expect(verified.studentCode, 'SV001');
  });

  testWidgets(
      'Editorial Login Spatial Card Deck (Phương án B - AutoPlay) - 8 thẻ tự động chuyển động & mở form đăng nhập bằng Spring Physics',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>(create: (_) => ApiService()),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ],
        child: const MaterialApp(home: AuthScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // 1. Hiển thị đủ bộ 8 thẻ Editorial & giao diện tối giản không còn hàng chip chọn chế độ
    expect(find.byType(TwinklingDotMatrixBackground), findsOneWidget);
    expect(find.text('BLOCKCHAIN'), findsOneWidget);
    expect(find.text('SHA-256'), findsOneWidget);
    expect(find.text('CHÍNH CHỦ'), findsOneWidget);
    expect(find.text('Cụm thẻ'), findsNothing);
    expect(find.text('Thác chéo'), findsNothing);

    // 2. Cho bộ đếm thời gian chạy tự động qua các nhịp (Expand -> Diagonal Cascade -> Strip)
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 600));

    // 3. Bấm ĐĂNG NHẬP để kích hoạt Collapse + trượt Form Đăng nhập lên
    await tester.tap(find.text('ĐĂNG NHẬP'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Đăng Nhập Tài Khoản'), findsOneWidget);
    expect(find.text('Khám phá thẻ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Twinkling Dot Matrix Background - Render lưới chấm 60fps trên màn hình dọc & ngang không lỗi',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TwinklingDotMatrixBackground(),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byType(TwinklingDotMatrixBackground), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Xoay ngang màn hình để kiểm tra tái tạo lưới động
    tester.view.physicalSize = const Size(844, 390);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  test(
      'Role Revert & LocalFileSaveService - Quay về vai trò gốc từ Cán bộ & bắt nhập lại mã; đặt tên file/MIME chuẩn byte gốc',
      () async {
    SharedPreferences.setMockInitialValues({});
    final employer = UserModel(
      uid: 'emp_revert_1',
      name: 'HR Test',
      email: 'hr@company.vn',
      role: UserRole.employer,
      createdAt: '2026-01-01',
    );
    final authProvider = _createAuthenticatedTestProvider(employer);

    // 1. Nâng cấp lên Cán bộ -> giữ originalRole là employer
    final validCode = ['NHOM4', 'CANBO', '2026'].join('-');
    final upgraded = await authProvider.upgradeToStaff(validCode);
    expect(upgraded, isTrue);
    expect(authProvider.currentUser?.role, UserRole.staff);
    expect(authProvider.currentUser?.originalRole, UserRole.employer);

    // 2. Quay về vai trò ban đầu -> trở lại employer
    final reverted = await authProvider.revertFromStaff();
    expect(reverted, isTrue);
    expect(authProvider.currentUser?.role, UserRole.employer);
    expect(authProvider.currentUser?.isStaff, isFalse);

    // 3. Muốn lên lại Cán bộ bắt buộc nhập đúng mã ủy quyền
    final wrongReUpgrade = await authProvider.upgradeToStaff('SAI_MA');
    expect(wrongReUpgrade, isFalse);
    expect(authProvider.currentUser?.role, UserRole.employer);

    // 4. Kiểm tra helper lưu file giữ nguyên định dạng/MIME
    expect(
      LocalFileSaveService.buildSignedFileName(
        originalFileName: 'IMG_2026.jpg',
        hash: '0x1234567890abcdef',
        fileType: 'IMAGE',
      ),
      'CertChain_Signed_12345678.jpg',
    );
    expect(
      LocalFileSaveService.inferMimeType('CertChain_Signed_12345678.png', 'IMAGE'),
      'image/png',
    );
  });

  test(
      'HashService Async Isolate - computeBothHashesAsync & computeHashFromBytesAsync khớp 100% kết quả chuẩn',
      () async {
    final sample = Uint8List.fromList(List<int>.generate(4096, (i) => i % 256));
    final syncKeccak = HashService.keccak256FromBytes(sample);
    final syncSha = HashService.sha256FromBytes(sample);

    final both = await HashService.computeBothHashesAsync(sample);
    final asyncSingle = await HashService.computeHashFromBytesAsync(
      sample,
      algorithm: HashAlgorithm.sha256,
    );

    expect(both.keccak256, syncKeccak);
    expect(both.sha256, syncSha);
    expect(asyncSingle, syncSha);
  });

  testWidgets(
      'Portfolio Profile & Google Onboarding - Hiển thị đầy đủ trường Portfolio, cảnh báo thiếu thông tin & nút Để sau',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final googleNewUser = UserModel(
      uid: 'google_uid_1',
      name: 'Nguyễn Google',
      email: 'google@gmail.com',
      role: UserRole.student,
      isProfileCompleted: false,
      createdAt: '17/11/2026',
    );
    expect(googleNewUser.hasMissingPortfolioInfo, isTrue);

    final authProvider = _createAuthenticatedTestProvider(googleNewUser);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>(create: (_) => ApiService()),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 1. Hiện hộp thoại Hoàn tất hồ sơ lần đầu với nút "Để sau"
    expect(find.text('Hoàn tất hồ sơ lần đầu'), findsOneWidget);
    expect(find.text('Để sau'), findsOneWidget);

    // 2. Bấm "Để sau" -> đóng hộp thoại & đánh dấu đã nhắc
    await tester.tap(find.text('Để sau'));
    await tester.pumpAndSettle();
    expect(find.text('Hoàn tất hồ sơ lần đầu'), findsNothing);
    expect(authProvider.currentUser?.isProfileCompleted, isTrue);

    // 3. Mở ProfileScreen -> hiển thị Portfolio & cảnh báo bổ sung thông tin
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>(create: (_) => ApiService()),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hồ Sơ & Portfolio'), findsOneWidget);
    expect(find.text('Hồ sơ Portfolio chưa đầy đủ'), findsOneWidget);
    expect(authProvider.currentUser?.isPortfolioPublic, isFalse);
    await tester.scrollUntilVisible(
      find.text('Công khai Portfolio khi quét văn bằng'),
      200,
    );
    await tester.tap(find.text('Công khai Portfolio khi quét văn bằng'));
    await tester.pumpAndSettle();
    expect(authProvider.currentUser?.isPortfolioPublic, isTrue);
    await tester.scrollUntilVisible(find.text('Giới Thiệu Bản Thân'), 200);
    expect(find.text('Giới Thiệu Bản Thân'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Thông Tin Định Danh & Liên Hệ'),
      200,
    );
    expect(find.text('Thông Tin Định Danh & Liên Hệ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Public Portfolio from VerifyDetailScreen - Mở Portfolio chủ văn bằng (cả khi không có MSSV) & ẩn SĐT',
      (WidgetTester tester) async {
    final validRecord = CertificateRecord(
      dataHash:
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      signer: '0xDF098FcEA905839FA80728D806069BF06b24F145',
      timestamp: 1763340000,
      fileName: 'Bang_Cu_Nhan.pdf',
      studentName: 'Trần Văn A',
      studentCode: '', // Trường hợp chỉ có tên, không có MSSV
      degreeName: 'Cử nhân CNTT',
      issuerName: 'Đại học Đồng Tháp',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VerifyDetailScreen(
          record: validRecord,
          searchedHash: validRecord.dataHash,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Xem Portfolio chủ văn bằng'), findsOneWidget);
    await tester.ensureVisible(find.text('Xem Portfolio chủ văn bằng'));
    await tester.tap(find.text('Xem Portfolio chủ văn bằng'));
    await tester.pumpAndSettle();

    expect(find.byType(PublicPortfolioScreen), findsOneWidget);
    expect(find.text('Trần Văn A'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Cử nhân CNTT'), 250);
    expect(find.text('Cử nhân CNTT'), findsOneWidget);
    expect(find.textContaining('Số điện thoại'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Pagination (7 dòng/trang) & Giữ MSSV khi đổi vai trò - Phân trang chuẩn 7 dòng và không mất MSSV',
      (WidgetTester tester) async {
    // 1. Kiểm tra phân trang 7 dòng/trang với 15 phần tử -> 3 trang (7, 7, 1)
    final items = List<int>.generate(15, (i) => i + 1);
    expect(PaginationControls.computeTotalPages(items.length), 3);
    expect(PaginationControls.slicePage(items, currentPage: 1).length, 7);
    expect(PaginationControls.slicePage(items, currentPage: 2).length, 7);
    expect(PaginationControls.slicePage(items, currentPage: 3), [15]);

    int currentPage = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PaginationControls(
              currentPage: currentPage,
              totalItems: items.length,
              onPageChanged: (p) => setState(() => currentPage = p),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Trang 1 / 3'), findsOneWidget);
    await tester.tap(find.text('Sau'));
    await tester.pumpAndSettle();
    expect(find.text('Trang 2 / 3'), findsOneWidget);

    // 2. Kiểm tra giữ nguyên MSSV khi chuyển từ Sinh viên -> Nhà tuyển dụng -> Sinh viên
    SharedPreferences.setMockInitialValues({});
    final student = UserModel(
      uid: 'sv_keep_code',
      name: 'Sinh Viên Test',
      email: 'sv@dthu.edu.vn',
      role: UserRole.student,
      studentCode: '0023411914',
      organization: 'Đại học Đồng Tháp',
      createdAt: '2026-01-01',
    );
    final authProvider = _createAuthenticatedTestProvider(student);
    await authProvider.updateProfile(
      name: student.name,
      organization: student.organization,
      role: UserRole.employer,
    );
    expect(authProvider.currentUser?.role, UserRole.employer);
    expect(authProvider.currentUser?.studentCode, '0023411914');

    await authProvider.updateProfile(
      name: student.name,
      organization: student.organization,
      role: UserRole.student,
    );
    expect(authProvider.currentUser?.role, UserRole.student);
    expect(authProvider.currentUser?.studentCode, '0023411914');
  });

  testWidgets(
      'Student VaultTab Signed Certificates - Sinh viên xem được mục Đã ký (văn bằng đã được ký xác nhận)',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final fakeApi = _FakeLedgerApiService();
    await fakeApi.notarizeCertificate(
      dataHash:
          '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      fileName: 'Bang_Ky_Su.pdf',
      studentName: 'Sinh Viên Test',
      studentCode: '0023411914',
      degreeName: 'Kỹ sư Khoa học máy tính',
      issuerName: 'Đại học Đồng Tháp',
    );

    final student = UserModel(
      uid: 'sv_vault_1',
      name: 'Sinh Viên Test',
      email: 'sv@dthu.edu.vn',
      role: UserRole.student,
      studentCode: '0023411914',
      organization: 'Đại học Đồng Tháp',
      createdAt: '2026-01-01',
    );
    final authProvider = _createAuthenticatedTestProvider(student);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>.value(value: fakeApi),
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ],
        child: const MaterialApp(home: Scaffold(body: VaultTab())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Đã ký (1)'), findsOneWidget);
    await tester.tap(find.text('Đã ký (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Kỹ sư Khoa học máy tính'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
