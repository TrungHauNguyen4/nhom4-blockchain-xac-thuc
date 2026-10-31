import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/digests/keccak.dart';
import 'package:crypto/crypto.dart' as crypto_pkg;
import '../models/certificate_record.dart';
import 'api_service.dart';

enum VerificationStep {
  readingFile,
  hashing,
  queryingBlockchain,
  verifiedValid,
  verifiedInvalid,
  error,
}

class VerificationProgress {
  final VerificationStep step;
  final double progress; // 0.0 -> 1.0
  final String statusMessage;
  final String? hash;
  final CertificateRecord? record;
  final String? errorMessage;

  VerificationProgress({
    required this.step,
    required this.progress,
    required this.statusMessage,
    this.hash,
    this.record,
    this.errorMessage,
  });
}

enum NotarizationStep {
  readingFile,
  hashing,
  submittingBlockchain,
  completed,
  error,
}

class NotarizationProgress {
  final NotarizationStep step;
  final double progress; // 0.0 -> 1.0
  final String statusMessage;
  final String? hash;
  final String? txHash;
  final int? blockNumber;
  final String? errorMessage;

  NotarizationProgress({
    required this.step,
    required this.progress,
    required this.statusMessage,
    this.hash,
    this.txHash,
    this.blockNumber,
    this.errorMessage,
  });
}

class HashService {
  // ========================================================
  // 1. THUẬT TOÁN BĂM KECCAK-256 (Chuẩn Ethereum)
  // Khớp 100% với ethers.keccak256 trên Web & Smart Contract
  // ========================================================
  static String keccak256FromBytes(Uint8List bytes) {
    final digest = KeccakDigest(256);
    final output = digest.process(bytes);
    final hexString = output.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '0x$hexString';
  }

  static String keccak256FromString(String text) {
    return keccak256FromBytes(Uint8List.fromList(utf8.encode(text)));
  }

  // ========================================================
  // 2. THUẬT TOÁN BĂM SHA-256 (Theo yêu cầu đề tài)
  // Tính toán trực tiếp trên RAM máy khách
  // ========================================================
  static String sha256FromBytes(Uint8List bytes) {
    final digest = crypto_pkg.sha256.convert(bytes);
    return '0x$digest';
  }

  static String sha256FromString(String text) {
    return sha256FromBytes(Uint8List.fromList(utf8.encode(text)));
  }

  // ========================================================
  // 3. TIẾN TRÌNH XÁC MINH FILE THỜI GIAN THỰC (StreamBuilder async*/yield)
  // Đọc RAM -> Băm Keccak256 -> Gọi REST API -> Trả kết quả
  // ========================================================
  static Stream<VerificationProgress> verifyFileStream({
    required Uint8List fileBytes,
    required String fileName,
    required ApiService apiService,
  }) async* {
    String? currentHash;
    try {
      // Giai đoạn 1: Nạp file vào RAM
      yield VerificationProgress(
        step: VerificationStep.readingFile,
        progress: 0.25,
        statusMessage: 'Đang nạp file vào bộ nhớ RAM...',
      );
      await Future.delayed(const Duration(milliseconds: 300));

      // Giai đoạn 2: Tính toán mã băm Keccak-256 an toàn
      yield VerificationProgress(
        step: VerificationStep.hashing,
        progress: 0.50,
        statusMessage: 'Đang băm mật mã Keccak-256 trên thiết bị...',
      );
      currentHash = keccak256FromBytes(fileBytes);
      await Future.delayed(const Duration(milliseconds: 400));

      // Giai đoạn 3: Đối soát với Sổ cái Blockchain qua REST API
      yield VerificationProgress(
        step: VerificationStep.queryingBlockchain,
        progress: 0.75,
        statusMessage: 'Đang đối soát Smart Contract mạng Sepolia & CSDL...',
        hash: currentHash,
      );

      final record = await apiService.verifyHash(currentHash, fileName: fileName);
      await Future.delayed(const Duration(milliseconds: 300));

      // Giai đoạn 4: Hoàn tất
      if (record != null && record.isValid) {
        yield VerificationProgress(
          step: VerificationStep.verifiedValid,
          progress: 1.0,
          statusMessage: 'Xác thực thành công! Văn bằng chính chủ.',
          hash: currentHash,
          record: record,
        );
      } else {
        yield VerificationProgress(
          step: VerificationStep.verifiedInvalid,
          progress: 1.0,
          statusMessage: 'Cảnh báo: Văn bằng chưa từng được niêm phong hoặc đã bị chỉnh sửa!',
          hash: currentHash,
        );
      }
    } catch (e, stack) {
      debugPrint('[HashService Error] $e\n$stack');
      yield VerificationProgress(
        step: VerificationStep.error,
        progress: 1.0,
        statusMessage: 'Lỗi trong quá trình kiểm định',
        hash: currentHash,
        errorMessage: e.toString(),
      );
    }
  }

  // ========================================================
  // 4. TIẾN TRÌNH XÁC MINH THEO MÃ HASH / QR (StreamBuilder)
  // ========================================================
  static Stream<VerificationProgress> verifyHashStream({
    required String dataHash,
    required ApiService apiService,
    String fileName = 'Văn bằng tra cứu',
  }) async* {
    try {
      yield VerificationProgress(
        step: VerificationStep.hashing,
        progress: 0.40,
        statusMessage: 'Đang chuẩn hóa định dạng mã Hash...',
        hash: dataHash,
      );
      await Future.delayed(const Duration(milliseconds: 300));

      yield VerificationProgress(
        step: VerificationStep.queryingBlockchain,
        progress: 0.75,
        statusMessage: 'Đang đối soát Sổ cái Blockchain qua REST API...',
        hash: dataHash,
      );

      final record = await apiService.verifyHash(dataHash, fileName: fileName);
      await Future.delayed(const Duration(milliseconds: 300));

      if (record != null && record.isValid) {
        yield VerificationProgress(
          step: VerificationStep.verifiedValid,
          progress: 1.0,
          statusMessage: 'Xác thực thành công! Văn bằng chính chủ.',
          hash: dataHash,
          record: record,
        );
      } else {
        yield VerificationProgress(
          step: VerificationStep.verifiedInvalid,
          progress: 1.0,
          statusMessage: 'Không tìm thấy chứng chỉ tương ứng trên Blockchain!',
          hash: dataHash,
        );
      }
    } catch (e, stack) {
      debugPrint('[HashService Error] $e\n$stack');
      yield VerificationProgress(
        step: VerificationStep.error,
        progress: 1.0,
        statusMessage: 'Không thể kết nối đến máy chủ Blockchain',
        errorMessage: e.toString(),
      );
    }
  }

  // ========================================================
  // 5. TIẾN TRÌNH CẤP PHÁT / KÝ SỐ FILE THỜI GIAN THỰC (NOTARIZE)
  // Dành cho Cán bộ đào tạo (TV2) lắp vào StreamBuilder
  // ========================================================
  static Stream<NotarizationProgress> notarizeFileStream({
    required Uint8List fileBytes,
    required String fileName,
    required ApiService apiService,
    String fileType = 'PDF',
    String? studentName,
    String? studentCode,
    String? degreeName,
    String? issuerName,
    String? createdByEmail,
  }) async* {
    String? currentHash;
    try {
      // Giai đoạn 1: Đọc nhị phân vào RAM
      yield NotarizationProgress(
        step: NotarizationStep.readingFile,
        progress: 0.25,
        statusMessage: 'Đang tải file vào bộ nhớ RAM thiết bị...',
      );
      await Future.delayed(const Duration(milliseconds: 300));

      // Giai đoạn 2: Tính toán mã băm Keccak-256 ngay trên RAM
      yield NotarizationProgress(
        step: NotarizationStep.hashing,
        progress: 0.50,
        statusMessage: 'Đang băm mật mã Keccak-256 trên RAM điện thoại...',
      );
      currentHash = keccak256FromBytes(fileBytes);
      await Future.delayed(const Duration(milliseconds: 400));

      // Giai đoạn 3: Ký số và đẩy lên Ethereum Sepolia
      yield NotarizationProgress(
        step: NotarizationStep.submittingBlockchain,
        progress: 0.75,
        statusMessage: 'Đang ký số ECDSA & đẩy lên Smart Contract Sepolia...',
        hash: currentHash,
      );

      final res = await apiService.notarizeCertificate(
        dataHash: currentHash,
        fileName: fileName,
        fileType: fileType,
        studentName: studentName,
        studentCode: studentCode,
        degreeName: degreeName,
        issuerName: issuerName,
        createdByEmail: createdByEmail,
      );

      if (res['success'] == true) {
        final txHash = res['transactionHash'] as String?;
        final blockNumber = res['blockNumber'] as int?;
        yield NotarizationProgress(
          step: NotarizationStep.completed,
          progress: 1.0,
          statusMessage: 'Niêm phong văn bằng lên Blockchain thành công!',
          hash: currentHash,
          txHash: txHash,
          blockNumber: blockNumber,
        );
      } else {
        yield NotarizationProgress(
          step: NotarizationStep.error,
          progress: 1.0,
          statusMessage: res['error'] ?? 'Lỗi khi ký số văn bằng',
          hash: currentHash,
          errorMessage: res['error']?.toString(),
        );
      }
    } catch (e, stack) {
      debugPrint('[Notarize Error] $e\n$stack');
      yield NotarizationProgress(
        step: NotarizationStep.error,
        progress: 1.0,
        statusMessage: 'Lỗi trong quá trình niêm phong',
        hash: currentHash,
        errorMessage: e.toString(),
      );
    }
  }
}
