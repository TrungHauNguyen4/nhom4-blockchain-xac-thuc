import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/api_service.dart';

void main() async {
  // 1. Đảm bảo các dịch vụ Flutter Core được khởi tạo trước khi chạy app
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Khởi tạo Firebase theo chuẩn Chương 11 (flutter_demo)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('[Main] Firebase Core chạy chế độ offline fallback: $e');
  }

  // 3. Mở khóa xoay màn hình tự do dọc/ngang theo chuẩn Chương 9 (flutter_demo)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // 4. Nạp cấu hình IP Backend & chế độ Mock đã lưu trong SharedPreferences (Chương 12)
  await ApiService.loadSavedConfig();

  runApp(
    // 5. Quản lý State & Dependency Injection bằng MultiProvider chuẩn Chương 7
    MultiProvider(
      providers: [
        Provider<ApiService>(create: (_) => ApiService()),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ],
      child: const CertificateVerifierApp(),
    ),
  );
}

class CertificateVerifierApp extends StatelessWidget {
  const CertificateVerifierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return MaterialApp(
          title: 'Xác Thực Văn Bằng Blockchain',
          debugShowCheckedModeBanner: false,
          theme: ThemeProvider.lightTheme,
          darkTheme: ThemeProvider.darkTheme,
          themeMode: themeProvider.themeMode,
          // Cổng kiểm tra phiên đăng nhập tự động (AuthGate) theo chuẩn Chương 11
          home: const AuthGate(),
        );
      },
    );
  }
}

/// Cổng kiểm tra trạng thái đăng nhập tự động (AuthGate)
/// Điều hướng vào HomeScreen nếu đã đăng nhập, ngược lại hiển thị AuthScreen
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    // Nếu đang nạp phiên đăng nhập từ máy
    if (authProvider.isLoading && authProvider.currentUser == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Đang kiểm tra phiên đăng nhập...',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    // Nếu đã xác thực -> Vào màn hình chính HomeScreen
    if (authProvider.isAuthenticated) {
      return const HomeScreen();
    }

    // Nếu chưa đăng nhập -> Hiển thị màn hình Đăng nhập AuthScreen
    return const AuthScreen();
  }
}
