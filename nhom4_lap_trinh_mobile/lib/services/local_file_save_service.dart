import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SavedFileResult {
  final bool success;
  final bool downloadsSaved;
  final bool gallerySaved;
  final String? downloadsPath;
  final String? galleryPath;
  final String? errorMessage;

  const SavedFileResult({
    required this.success,
    this.downloadsSaved = false,
    this.gallerySaved = false,
    this.downloadsPath,
    this.galleryPath,
    this.errorMessage,
  });
}

/// Dịch vụ lưu nguyên vẹn từng byte của tệp/ảnh đã ký số về bộ nhớ máy
/// (vừa lưu vào thư mục Downloads/CertChain vừa thêm vào Thư viện ảnh trên Android).
class LocalFileSaveService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.nhom4_lap_trinh_mobile/media_save',
  );

  static String inferMimeType(String fileName, String fileType) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf') || fileType == 'PDF') return 'application/pdf';
    return 'image/jpeg';
  }

  static String buildSignedFileName({
    required String originalFileName,
    required String hash,
    required String fileType,
  }) {
    final cleanHash = hash.replaceFirst('0x', '');
    final shortHash = cleanHash.length >= 8 ? cleanHash.substring(0, 8) : cleanHash;
    final lower = originalFileName.toLowerCase();
    String ext = '.jpg';
    if (lower.endsWith('.png')) {
      ext = '.png';
    } else if (lower.endsWith('.pdf') || fileType == 'PDF') {
      ext = '.pdf';
    } else if (lower.endsWith('.jpeg')) {
      ext = '.jpeg';
    }
    return 'CertChain_Signed_$shortHash$ext';
  }

  static Future<SavedFileResult> saveToDownloadsAndGallery({
    required Uint8List bytes,
    required String fileName,
    required String fileType,
  }) async {
    final mimeType = inferMimeType(fileName, fileType);

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final dynamic rawResult = await _channel.invokeMethod(
          'saveImageToDownloadsAndGallery',
          <String, dynamic>{
            'bytes': bytes,
            'fileName': fileName,
            'mimeType': mimeType,
          },
        );
        if (rawResult is Map) {
          final bool downloadsSaved = rawResult['downloadsSaved'] == true;
          final bool gallerySaved = rawResult['gallerySaved'] == true;
          return SavedFileResult(
            success: downloadsSaved || gallerySaved,
            downloadsSaved: downloadsSaved,
            gallerySaved: gallerySaved,
            downloadsPath: rawResult['downloadsPath']?.toString(),
            galleryPath: rawResult['galleryPath']?.toString(),
          );
        }
      } on PlatformException catch (e) {
        return SavedFileResult(
          success: false,
          errorMessage: e.message ?? 'Lỗi lưu tệp trên Android',
        );
      } on MissingPluginException {
        // Fallback bên dưới cho môi trường test hoặc nền tảng khác
      }
    }

    try {
      final String? pickedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Lưu tệp đã ký số về máy',
        fileName: fileName,
        bytes: bytes,
      );
      if (pickedPath != null && pickedPath.isNotEmpty) {
        final file = File(pickedPath);
        if (!await file.exists()) {
          await file.writeAsBytes(bytes, flush: true);
        }
        return SavedFileResult(
          success: true,
          downloadsSaved: true,
          downloadsPath: pickedPath,
        );
      }
      return const SavedFileResult(
        success: false,
        errorMessage: 'Đã hủy thao tác lưu tệp.',
      );
    } catch (e) {
      return SavedFileResult(
        success: false,
        errorMessage: 'Không thể lưu tệp: $e',
      );
    }
  }
}
