import 'package:intl/intl.dart';

class ScanHistoryModel {
  final int? id;
  final String dataHash;
  final String fileName;
  final String scanMethod; // 'QR', 'FILE', 'HASH'
  final bool isValid;
  final String? issuerName;
  final String? studentName;
  final String? degreeName;
  final String scannedAt;

  ScanHistoryModel({
    this.id,
    required this.dataHash,
    required this.fileName,
    required this.scanMethod,
    required this.isValid,
    this.issuerName,
    this.studentName,
    this.degreeName,
    String? scannedAt,
  }) : scannedAt = scannedAt ?? DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'dataHash': dataHash,
      'fileName': fileName,
      'scanMethod': scanMethod,
      'isValid': isValid ? 1 : 0,
      'issuerName': issuerName,
      'studentName': studentName,
      'degreeName': degreeName,
      'scannedAt': scannedAt,
    };
  }

  factory ScanHistoryModel.fromMap(Map<String, dynamic> map) {
    return ScanHistoryModel(
      id: map['id'] as int?,
      dataHash: map['dataHash'] as String? ?? '',
      fileName: map['fileName'] as String? ?? 'Văn bằng quét',
      scanMethod: map['scanMethod'] as String? ?? 'QR',
      isValid: (map['isValid'] as int? ?? 0) == 1,
      issuerName: map['issuerName'] as String?,
      studentName: map['studentName'] as String?,
      degreeName: map['degreeName'] as String?,
      scannedAt: map['scannedAt'] as String? ?? '',
    );
  }
}

