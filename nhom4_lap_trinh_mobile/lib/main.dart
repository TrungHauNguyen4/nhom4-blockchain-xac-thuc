import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/theme_provider.dart';
import 'screens/verifier/home_screen.dart';
import 'services/api_service.dart';

void main() async {
  // Đảm bảo các dịch vụ Flutter Core được khởi tạo trước khi chạy app
  WidgetsFlutterBinding.ensureInitialized();

  // Mở khóa xoay màn hình tự do (Dọc & Ngang) theo chuẩn Chương 9 flutter_demo
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiService>(create: (_) => ApiService()),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
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
          home: const HomeScreen(),
        );
      },
    );
  }
}
