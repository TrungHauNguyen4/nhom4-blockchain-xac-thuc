import 'dart:io';
import 'package:path/path.dart' as p;

/// Kết quả kiểm tra tính hợp lệ & đồng nhất loại tệp trong Folder hoặc danh sách file.
class FolderValidationResult {
  final bool isValid;
  final String? fileType; // 'IMAGE' | 'PDF'
  final List<String> filePaths;
  final String? errorMessage;

  const FolderValidationResult({
    required this.isValid,
    this.fileType,
    this.filePaths = const <String>[],
    this.errorMessage,
  });
}

/// Kiểm tra quy tắc bắt buộc cho Nhà tuyển dụng:
/// - Chỉ chấp nhận Ảnh (.jpg, .jpeg, .png) hoặc PDF (.pdf).
/// - Toàn bộ tệp trong Folder/lô phải CÙNG MỘT LOẠI (tất cả là Ảnh hoặc tất cả là PDF).
/// - Nếu lẫn lộn cả Ảnh và PDF hoặc không có tệp hợp lệ thì chặn và báo lỗi rõ ràng.
class FolderBatchValidator {
  static const Set<String> imageExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
  };
  static const Set<String> pdfExtensions = <String>{'.pdf'};

  static String? detectFileType(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    if (imageExtensions.contains(ext)) return 'IMAGE';
    if (pdfExtensions.contains(ext)) return 'PDF';
    return null;
  }

  /// Quét toàn bộ tệp cấp 1 bên trong [directoryPath] và kiểm tra đồng nhất.
  static Future<FolderValidationResult> validateDirectory(
    String directoryPath,
  ) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) {
      return const FolderValidationResult(
        isValid: false,
        errorMessage: 'Thư mục không tồn tại hoặc không thể truy cập.',
      );
    }

    final filePaths = <String>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          final base = p.basename(entity.path);
          if (base.startsWith('.')) continue;
          filePaths.add(entity.path);
        }
      }
    } catch (e) {
      return FolderValidationResult(
        isValid: false,
        errorMessage:
            'Thiết bị hạn chế đọc trực tiếp thư mục này ($e). Vui lòng dùng nút "Chọn nhiều file cùng loại".',
      );
    }

    return validateFilePaths(filePaths);
  }

  /// Kiểm tra danh sách đường dẫn tệp (dùng chung cho Folder và fallback chọn nhiều file).
  static FolderValidationResult validateFilePaths(List<String> rawPaths) {
    final imagePaths = <String>[];
    final pdfPaths = <String>[];
    final unsupportedNames = <String>[];

    for (final path in rawPaths) {
      final type = detectFileType(path);
      if (type == 'IMAGE') {
        imagePaths.add(path);
      } else if (type == 'PDF') {
        pdfPaths.add(path);
      } else {
        unsupportedNames.add(p.basename(path));
      }
    }

    if (imagePaths.isEmpty && pdfPaths.isEmpty) {
      final extra = unsupportedNames.isEmpty
          ? ''
          : ' (Tìm thấy tệp không hỗ trợ: ${unsupportedNames.take(3).join(', ')})';
      return FolderValidationResult(
        isValid: false,
        errorMessage:
            'Không tìm thấy tệp Ảnh (.jpg/.jpeg/.png) hoặc PDF (.pdf) hợp lệ$extra.',
      );
    }

    if (imagePaths.isNotEmpty && pdfPaths.isNotEmpty) {
      return FolderValidationResult(
        isValid: false,
        errorMessage:
            'Thư mục đang chứa lẫn lộn ${imagePaths.length} tệp Ảnh và ${pdfPaths.length} tệp PDF. '
            'Vui lòng chỉ gửi thư mục chứa CÙNG MỘT LOẠI tệp (chỉ Ảnh hoặc chỉ PDF).',
      );
    }

    if (imagePaths.isNotEmpty) {
      imagePaths.sort();
      return FolderValidationResult(
        isValid: true,
        fileType: 'IMAGE',
        filePaths: imagePaths,
      );
    }

    pdfPaths.sort();
    return FolderValidationResult(
      isValid: true,
      fileType: 'PDF',
      filePaths: pdfPaths,
    );
  }
}
