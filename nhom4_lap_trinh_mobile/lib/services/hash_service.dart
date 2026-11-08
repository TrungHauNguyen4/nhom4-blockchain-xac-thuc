import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/digests/keccak.dart';
import 'package:crypto/crypto.dart' as crypto_pkg;
import '../models/certificate_record.dart';
import 'api_service.dart';

/// Tùy chọn thuật toán băm trên RAM máy khách (Client-side Hashing)
/// Mặc định dùng `keccak256` để khớp 100% với `ethers.keccak256` trên Ethereum Sepolia.
enum HashAlgorithm {
  keccak256,
  sha256,
}

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
  // 1. THUẬT TOÁN BĂM KECCAK-256 (Chuẩn Ethereum - Mặc định)
  // Khớp 100% với ethers.keccak256 trên Web & Smart Contract
  // ========================================================
  static String keccak256FromBytes(Uint8List bytes) {
    final digest = KeccakDigest(256);
    final output = digest.process(bytes);
    final hexString =
        output.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '0x$hexString';
  }

  static String keccak256FromString(String text) {
    return keccak256FromBytes(Uint8List.fromList(utf8.encode(text)));
  }

  // ========================================================
  // 2. THUẬT TOÁN BĂM SHA-256 (Tùy chọn theo yêu cầu đề tài)
  // Tính toán trực tiếp trên RAM máy khách
  // ========================================================
  static String sha256FromBytes(Uint8List bytes) {
    final digest = crypto_pkg.sha256.convert(bytes);
    return '0x$digest';
  }

  static String sha256FromString(String text) {
    return sha256FromBytes(Uint8List.fromList(utf8.encode(text)));
  }

  // Hàm băm linh hoạt theo thuật toán được chọn (Keccak-256 hoặc SHA-256)
  static String computeHashFromBytes(
    Uint8List bytes, {
    HashAlgorithm algorithm = HashAlgorithm.keccak256,
  }) {
    switch (algorithm) {
      case HashAlgorithm.sha256:
        return sha256FromBytes(bytes);
      case HashAlgorithm.keccak256:
        return keccak256FromBytes(bytes);
    }
  }

  // ========================================================
  // 3. TIẾN TRÌNH XÁC MINH FILE THỜI GIAN THỰC (StreamBuilder async*/yield)
  // Đọc RAM -> Băm Keccak256/SHA256 -> Gọi REST API -> Trả kết quả
  // ========================================================
  static Stream<VerificationProgress> verifyFileStream({
    required Uint8List fileBytes,
    required String fileName,
    required ApiService apiService,
    HashAlgorithm algorithm = HashAlgorithm.keccak256,
  }) async* {
    String? currentHash;
    try {
      // Giai đoạn 1: Đọc tệp
      yield VerificationProgress(
        step: VerificationStep.readingFile,
        progress: 0.25,
        statusMessage: 'Đang đọc tệp văn bằng trên điện thoại...',
      );
      await Future.delayed(const Duration(milliseconds: 300));

      // Giai đoạn 2: Tạo mã nhận diện tài liệu (Tính đồng thời cả Keccak-256 & SHA-256)
      yield VerificationProgress(
        step: VerificationStep.hashing,
        progress: 0.50,
        statusMessage: 'Đang tạo mã nhận diện văn bằng...',
      );
      final primaryHash = computeHashFromBytes(fileBytes, algorithm: algorithm);
      final fallbackAlgo = algorithm == HashAlgorithm.keccak256
          ? HashAlgorithm.sha256
          : HashAlgorithm.keccak256;
      final secondaryHash =
          computeHashFromBytes(fileBytes, algorithm: fallbackAlgo);
      currentHash = primaryHash;
      await Future.delayed(const Duration(milliseconds: 400));

      // Giai đoạn 3: Đối chiếu với sổ gốc (Tự động kiểm tra cả chuẩn Tiêu chuẩn & Nâng cao)
      yield VerificationProgress(
        step: VerificationStep.queryingBlockchain,
        progress: 0.75,
        statusMessage: 'Đang đối chiếu với hệ thống sổ gốc...',
        hash: currentHash,
      );

      CertificateRecord? record =
          await apiService.verifyHash(primaryHash, fileName: fileName);

      // Nếu không khớp ở thuật toán đầu tiên, tự động đối chiếu tiếp thuật toán thứ hai (SHA-256 <-> Keccak-256)
      if (record == null || !record.isValid) {
        final secondRecord =
            await apiService.verifyHash(secondaryHash, fileName: fileName);
        if (secondRecord != null && secondRecord.isValid) {
          record = secondRecord;
          currentHash = secondaryHash;
        }
      }
      await Future.delayed(const Duration(milliseconds: 300));

      // Giai đoạn 4: Hoàn tất
      if (record != null && record.isValid) {
        yield VerificationProgress(
          step: VerificationStep.verifiedValid,
          progress: 1.0,
          statusMessage: 'Xác thực thành công! Văn bằng hợp lệ.',
          hash: currentHash,
          record: record,
        );
      } else {
        yield VerificationProgress(
          step: VerificationStep.verifiedInvalid,
          progress: 1.0,
          statusMessage:
              'Cảnh báo: Văn bằng chưa được cấp hoặc tệp đã bị chỉnh sửa!',
          hash: currentHash,
        );
      }
    } catch (e, stack) {
      debugPrint('[HashService Error] $e\n$stack');
      yield VerificationProgress(
        step: VerificationStep.error,
        progress: 1.0,
        statusMessage: 'Lỗi trong quá trình kiểm tra',
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
        statusMessage: 'Đang kiểm tra định dạng mã văn bằng...',
        hash: dataHash,
      );
      await Future.delayed(const Duration(milliseconds: 300));

      yield VerificationProgress(
        step: VerificationStep.queryingBlockchain,
        progress: 0.75,
        statusMessage: 'Đang đối chiếu với hệ thống sổ gốc...',
        hash: dataHash,
      );

      final record = await apiService.verifyHash(dataHash, fileName: fileName);
      await Future.delayed(const Duration(milliseconds: 300));

      if (record != null && record.isValid) {
        yield VerificationProgress(
          step: VerificationStep.verifiedValid,
          progress: 1.0,
          statusMessage: 'Xác thực thành công! Văn bằng hợp lệ.',
          hash: dataHash,
          record: record,
        );
      } else {
        yield VerificationProgress(
          step: VerificationStep.verifiedInvalid,
          progress: 1.0,
          statusMessage: 'Không tìm thấy văn bằng này trên hệ thống sổ gốc!',
          hash: dataHash,
        );
      }
    } catch (e, stack) {
      debugPrint('[HashService Error] $e\n$stack');
      yield VerificationProgress(
        step: VerificationStep.error,
        progress: 1.0,
        statusMessage: 'Không thể kết nối đến hệ thống xác thực',
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
    HashAlgorithm algorithm = HashAlgorithm.keccak256,
  }) async* {
    String? currentHash;
    try {
      // Giai đoạn 1: Đọc tệp
      yield NotarizationProgress(
        step: NotarizationStep.readingFile,
        progress: 0.25,
        statusMessage: 'Đang đọc tệp văn bằng trên điện thoại...',
      );
      await Future.delayed(const Duration(milliseconds: 300));

      // Giai đoạn 2: Tạo mã nhận diện
      yield NotarizationProgress(
        step: NotarizationStep.hashing,
        progress: 0.50,
        statusMessage: 'Đang tạo mã bảo mật cho văn bằng...',
      );
      currentHash = computeHashFromBytes(fileBytes, algorithm: algorithm);
      await Future.delayed(const Duration(milliseconds: 400));

      // Giai đoạn 3: Xác nhận và lưu lên sổ gốc
      yield NotarizationProgress(
        step: NotarizationStep.submittingBlockchain,
        progress: 0.75,
        statusMessage: 'Đang xác nhận chữ ký số và lưu vào sổ gốc...',
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
        final blockNumber = res['blockNumber'] is int
            ? res['blockNumber'] as int
            : int.tryParse(res['blockNumber']?.toString() ?? '');
        yield NotarizationProgress(
          step: NotarizationStep.completed,
          progress: 1.0,
          statusMessage: 'Cấp phát và lưu trữ văn bằng thành công!',
          hash: currentHash,
          txHash: txHash,
          blockNumber: blockNumber,
        );
      } else {
        yield NotarizationProgress(
          step: NotarizationStep.error,
          progress: 1.0,
          statusMessage:
              res['error']?.toString() ?? 'Lỗi khi cấp phát văn bằng',
          hash: currentHash,
          errorMessage: res['error']?.toString(),
        );
      }
    } catch (e, stack) {
      debugPrint('[Notarize Error] $e\n$stack');
      yield NotarizationProgress(
        step: NotarizationStep.error,
        progress: 1.0,
        statusMessage: 'Lỗi trong quá trình cấp phát',
        hash: currentHash,
        errorMessage: e.toString(),
      );
    }
  }
}
