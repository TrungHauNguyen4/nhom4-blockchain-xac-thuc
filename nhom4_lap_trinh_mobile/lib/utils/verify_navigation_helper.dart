import 'package:flutter/material.dart';
import '../screens/verifier/verify_detail_screen.dart';
import '../services/api_service.dart';

/// Tra cứu mã Hash trực tiếp từ Backend/Sepolia và mở màn hình [VerifyDetailScreen].
Future<void> openVerifyByHash(
  BuildContext context,
  String hash, {
  String fileName = 'Tài liệu đã ký',
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final record = await ApiService().verifyHash(hash, fileName: fileName);
    if (navigator.canPop()) {
      navigator.pop();
    }
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => VerifyDetailScreen(
          record: record,
          searchedHash: hash,
        ),
      ),
    );
  } catch (e) {
    if (navigator.canPop()) {
      navigator.pop();
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text('Không thể kiểm tra mã Hash lúc này: $e'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }
}
