import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:nhom4_lap_trinh_mobile/models/signing_request_model.dart';
import 'package:nhom4_lap_trinh_mobile/providers/auth_provider.dart';
import 'package:nhom4_lap_trinh_mobile/providers/theme_provider.dart';
import 'package:nhom4_lap_trinh_mobile/screens/issuer/signing_requests_screen.dart';
import 'package:nhom4_lap_trinh_mobile/screens/notifications/notifications_screen.dart';
import 'package:nhom4_lap_trinh_mobile/services/api_service.dart';
import 'package:nhom4_lap_trinh_mobile/services/folder_batch_validator.dart';

void main() {
  group('FolderBatchValidator', () {
    test('cho phép danh sách chỉ gồm tệp Ảnh', () {
      final result = FolderBatchValidator.validateFilePaths([
        '/storage/emulated/0/HR/a.jpg',
        '/storage/emulated/0/HR/b.PNG',
      ]);
      expect(result.isValid, isTrue);
      expect(result.fileType, 'IMAGE');
      expect(result.filePaths.length, 2);
    });

    test('cho phép danh sách chỉ gồm tệp PDF', () {
      final result = FolderBatchValidator.validateFilePaths([
        '/storage/emulated/0/HR/bang1.pdf',
        '/storage/emulated/0/HR/bang2.PDF',
      ]);
      expect(result.isValid, isTrue);
      expect(result.fileType, 'PDF');
      expect(result.filePaths.length, 2);
    });

    test('chặn thư mục chứa lẫn lộn Ảnh và PDF', () {
      final result = FolderBatchValidator.validateFilePaths([
        '/storage/emulated/0/HR/anh.jpg',
        '/storage/emulated/0/HR/hoso.pdf',
      ]);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('lẫn lộn'));
    });

    test('chặn thư mục rỗng hoặc không có tệp hỗ trợ', () {
      final result = FolderBatchValidator.validateFilePaths([
        '/storage/emulated/0/HR/notes.txt',
      ]);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, isNotNull);
    });
  });

  group('SigningRequestModel', () {
    test('mặc định SLA 24h và giữ nguyên hashAlgorithm khi serialize', () {
      final created = DateTime(2026, 11, 18, 10, 0).millisecondsSinceEpoch;
      final expected = created + const Duration(hours: 24).inMilliseconds;
      final model = SigningRequestModel(
        id: 'req_1',
        requesterUid: 'u1',
        requesterName: 'Nguyễn Văn A',
        requesterEmail: 'a@gmail.com',
        requesterRole: 'student',
        degreeName: 'Bằng Kỹ sư CNTT',
        studentName: 'Nguyễn Văn A',
        studentCode: '0023411914',
        issuerName: 'ĐH Đồng Tháp',
        fileName: 'bang.pdf',
        fileType: 'PDF',
        fileSizeBytes: 20480,
        documentHash:
            '0x2a82f2304fbe3f926d7d1411d9f5430dbb39f7c55764c88e6d4be5e858f5309b',
        hashAlgorithm: 'sha256',
        createdAt: created,
        expectedResolveAt: expected,
      );

      final parsed = SigningRequestModel.fromMap('req_1', model.toMap());
      expect(parsed.hashAlgorithm, 'sha256');
      expect(parsed.estimatedHours, 24);
      expect(parsed.expectedResolveAt - parsed.createdAt,
          const Duration(hours: 24).inMilliseconds);
      expect(parsed.isStudentRequest, isTrue);
    });
  });

  testWidgets('SigningRequestsScreen & NotificationsScreen render an toàn',
      (WidgetTester tester) async {
    Widget wrap(Widget child) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          Provider<ApiService>(create: (_) => ApiService()),
        ],
        child: MaterialApp(home: child),
      );
    }

    await tester.pumpWidget(wrap(const SigningRequestsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Cá nhân (SV)'), findsOneWidget);
    expect(find.text('Nhà tuyển dụng'), findsOneWidget);

    await tester.pumpWidget(wrap(const NotificationsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Thông Báo'), findsOneWidget);
  });
}
