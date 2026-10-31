import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'services/api_service.dart';

void main() async {
  // Đảm bảo các dịch vụ Flutter Core được khởi tạo trước khi chạy app
  WidgetsFlutterBinding.ensureInitialized();

  // Mở khóa xoay màn hình tự do dọc/ngang theo chuẩn Chương 9 (flutter_demo)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Nạp cấu hình IP Backend & chế độ Mock đã lưu trong SharedPreferences
  await ApiService.loadSavedConfig();

  runApp(
    // Quản lý State & Dependency Injection bằng MultiProvider chuẩn Chương 7
    MultiProvider(
      providers: [
        Provider<ApiService>(create: (_) => ApiService()),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        // TV2 sẽ bổ sung ChangeNotifierProvider<AuthProvider> tại đây
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
          // TV2 sẽ bọc StreamBuilder<User?> (FirebaseAuth.authStateChanges) tại home
          home: const HomeScreen(),
        );
      },
    );
  }
}
