import 'package:intl/intl.dart';

class CertificateRecord {
  final int? id;
  final String dataHash;
  final String signer;
  final int timestamp;
  final String fileName;
  final String fileType;
  final String? txHash;
  final int? blockNumber;
  final String? studentName;
  final String? studentCode;
  final String? degreeName;
  final String issuerName;
  final String savedAt;

  CertificateRecord({
    this.id,
    required this.dataHash,
    required this.signer,
    required this.timestamp,
    required this.fileName,
    this.fileType = 'PDF',
    this.txHash,
    this.blockNumber,
    this.studentName,
    this.studentCode,
    this.degreeName,
    String? issuerName,
    String? savedAt,
  })  : issuerName = issuerName ?? 'Phòng Đào Tạo',
        savedAt = savedAt ?? DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());

  // Kiểm tra chứng chỉ có tồn tại và hợp lệ trên Blockchain không
  bool get isValid =>
      signer.isNotEmpty &&
      signer.toLowerCase() != '0x0000000000000000000000000000000000000000' &&
      timestamp > 0;

  // Thời gian cấp phát văn bằng được ghi nhận trên Blockchain
  String get formattedBlockchainDate {
    if (timestamp == 0) return 'Chưa ghi nhận';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat('dd/MM/yyyy HH:mm:ss').format(date);
  }

  // Chuyển đổi sang Map để lưu vào SQLite
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'dataHash': dataHash,
      'signer': signer,
      'timestamp': timestamp,
      'fileName': fileName,
      'fileType': fileType,
      'txHash': txHash,
      'blockNumber': blockNumber,
      'studentName': studentName,
      'studentCode': studentCode,
      'degreeName': degreeName,
      'issuerName': issuerName,
      'savedAt': savedAt,
    };
  }

  // Khởi tạo từ Map đọc ra từ SQLite
  factory CertificateRecord.fromMap(Map<String, dynamic> map) {
    return CertificateRecord(
      id: map['id'] as int?,
      dataHash: map['dataHash'] as String? ?? '',
      signer: map['signer'] as String? ?? '',
      timestamp: map['timestamp'] as int? ?? 0,
      fileName: map['fileName'] as String? ?? 'Văn bằng chưa đặt tên',
      fileType: map['fileType'] as String? ?? 'PDF',
      txHash: map['txHash'] as String?,
      blockNumber: map['blockNumber'] as int?,
      studentName: map['studentName'] as String?,
      studentCode: map['studentCode'] as String?,
      degreeName: map['degreeName'] as String?,
      issuerName: map['issuerName'] as String? ?? 'Phòng Đào Tạo',
      savedAt: map['savedAt'] as String?,
    );
  }

  // Khởi tạo từ JSON trả về của Backend API (/api/v1/verify/:hash hoặc /api/v1/certificates)
  factory CertificateRecord.fromJson(Map<String, dynamic> json, {String fileName = 'Văn bằng tra cứu'}) {
    return CertificateRecord(
      id: json['id'] is int ? json['id'] as int : int.tryParse(json['id']?.toString() ?? ''),
      dataHash: json['dataHash'] as String? ?? '',
      signer: json['signer'] as String? ?? '',
      timestamp: json['timestamp'] is int
          ? json['timestamp'] as int
          : int.tryParse(json['timestamp']?.toString() ?? '0') ?? 0,
      fileName: json['fileName'] as String? ?? fileName,
      fileType: json['fileType'] as String? ?? 'PDF',
      txHash: (json['transactionHash'] ?? json['txHash']) as String?,
      blockNumber: json['blockNumber'] is int
          ? json['blockNumber'] as int
          : int.tryParse(json['blockNumber']?.toString() ?? ''),
      studentName: json['studentName'] as String?,
      studentCode: json['studentCode'] as String?,
      degreeName: json['degreeName'] as String?,
      issuerName: json['issuerName'] as String? ?? 'Phòng Đào Tạo',
      savedAt: json['createdAt'] as String?,
    );
  }
}
