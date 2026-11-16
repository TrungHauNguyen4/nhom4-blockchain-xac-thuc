import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../models/certificate_record.dart';

/// Dịch vụ đồng bộ Metadata văn bằng lên Firebase Realtime Database (/certificates)
/// giúp các thiết bị khác vẫn xem được đầy đủ Tên SV, MSSV, Tên bằng, Đơn vị cấp, TxHash
/// ngay cả khi Backend Laptop đã tắt (kết hợp xác thực gốc On-Chain Ethereum Sepolia).
class CertificateFirebaseService {
  DatabaseReference? _certsRef;

  CertificateFirebaseService() {
    try {
      _certsRef = FirebaseDatabase.instance.ref().child('certificates');
    } catch (e) {
      debugPrint(
        '[CertificateFirebaseService] Firebase Realtime Database chưa kết nối: $e',
      );
      _certsRef = null;
    }
  }

  static String normalizeHashKey(String dataHash) {
    final clean = dataHash.trim().toLowerCase();
    if (!clean.startsWith('0x') && clean.length == 64) {
      return '0x$clean';
    }
    return clean;
  }

  /// [CREATE / UPDATE] Lưu Metadata văn bằng lên Firebase Realtime Database (/certificates/{dataHash})
  Future<bool> saveCertificateMetadata(
    CertificateRecord record, {
    String? createdByEmail,
  }) async {
    if (_certsRef == null) return false;
    final key = normalizeHashKey(record.dataHash);
    if (key.isEmpty) return false;

    try {
      final payload = <String, dynamic>{
        'dataHash': key,
        'signer': record.signer,
        'timestamp': record.timestamp,
        'fileName': record.fileName,
        'fileType': record.fileType,
        'txHash': record.txHash,
        'blockNumber': record.blockNumber,
        'studentName': record.studentName,
        'studentCode': record.studentCode,
        'degreeName': record.degreeName,
        'issuerName': record.issuerName,
        'createdAt': record.savedAt,
        if (createdByEmail != null && createdByEmail.trim().isNotEmpty)
          'createdByEmail': createdByEmail.trim(),
      };

      await _certsRef!.child(key).set(payload).timeout(
            const Duration(seconds: 4),
          );
      return true;
    } catch (e) {
      debugPrint(
        '[CertificateFirebaseService] Lỗi đồng bộ metadata lên Firebase: $e',
      );
      return false;
    }
  }

  /// [READ] Lấy Metadata văn bằng theo mã băm từ Firebase Realtime Database
  Future<CertificateRecord?> getMetadataByHash(String dataHash) async {
    if (_certsRef == null) return null;
    final key = normalizeHashKey(dataHash);
    if (key.isEmpty) return null;

    try {
      final snapshot = await _certsRef!.child(key).get().timeout(
            const Duration(seconds: 4),
          );
      if (snapshot.exists && snapshot.value is Map) {
        final rawMap = Map<String, dynamic>.from(snapshot.value as Map);
        return CertificateRecord.fromJson(
          rawMap,
          fileName: rawMap['fileName']?.toString() ?? 'Văn bằng xác thực On-Chain',
        );
      }
    } catch (e) {
      debugPrint(
        '[CertificateFirebaseService] Không thể đọc metadata từ Firebase: $e',
      );
    }
    return null;
  }

  /// [READ] Lấy danh sách văn bằng từ Firebase (hỗ trợ lọc từ khóa cho HR & Danh sách đã cấp khi tắt Laptop)
  Future<List<CertificateRecord>> fetchAllCertificates({
    String keyword = '',
  }) async {
    if (_certsRef == null) return [];

    try {
      final snapshot = await _certsRef!.get().timeout(
            const Duration(seconds: 5),
          );
      if (!snapshot.exists || snapshot.value is! Map) return [];

      final Map<dynamic, dynamic> rawMap = snapshot.value as Map;
      final List<CertificateRecord> items = [];

      rawMap.forEach((key, value) {
        if (value is Map) {
          final map = Map<String, dynamic>.from(value);
          map['dataHash'] ??= key.toString();
          items.add(
            CertificateRecord.fromJson(
              map,
              fileName: map['fileName']?.toString() ?? 'Văn bằng đã cấp',
            ),
          );
        }
      });

      // Sắp xếp mới nhất lên đầu theo timestamp
      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final cleanKw = keyword.trim().toLowerCase();
      if (cleanKw.isEmpty) return items;

      return items.where((cert) {
        return (cert.studentName ?? '').toLowerCase().contains(cleanKw) ||
            (cert.studentCode ?? '').toLowerCase().contains(cleanKw) ||
            (cert.degreeName ?? '').toLowerCase().contains(cleanKw) ||
            cert.issuerName.toLowerCase().contains(cleanKw) ||
            cert.fileName.toLowerCase().contains(cleanKw) ||
            cert.dataHash.toLowerCase().contains(cleanKw);
      }).toList();
    } catch (e) {
      debugPrint(
        '[CertificateFirebaseService] Lỗi tải danh sách từ Firebase: $e',
      );
      return [];
    }
  }

  /// [SYNC] Đồng bộ hàng loạt danh sách văn bằng cũ từ SQL Server lên Firebase Realtime Database
  Future<int> syncCertificatesBatch(List<CertificateRecord> records) async {
    if (_certsRef == null || records.isEmpty) return 0;

    int syncedCount = 0;
    for (final cert in records) {
      final ok = await saveCertificateMetadata(cert);
      if (ok) syncedCount++;
    }
    return syncedCount;
  }
}
