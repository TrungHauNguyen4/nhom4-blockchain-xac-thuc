/// Trạng thái xử lý của yêu cầu ký xác nhận tài liệu.
enum SigningRequestStatus {
  pending,
  delayed,
  signed,
  rejected;

  static SigningRequestStatus fromString(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'delayed':
        return SigningRequestStatus.delayed;
      case 'signed':
        return SigningRequestStatus.signed;
      case 'rejected':
        return SigningRequestStatus.rejected;
      case 'pending':
      default:
        return SigningRequestStatus.pending;
    }
  }

  String get value => name;

  String get labelVi {
    switch (this) {
      case SigningRequestStatus.pending:
        return 'Đang chờ xử lý';
      case SigningRequestStatus.delayed:
        return 'Gia hạn xử lý';
      case SigningRequestStatus.signed:
        return 'Đã ký xác nhận';
      case SigningRequestStatus.rejected:
        return 'Bị từ chối';
    }
  }
}

/// Mô hình Yêu cầu ký xác nhận tài liệu (Sinh viên hoặc Nhà tuyển dụng gửi lên Cán bộ ký).
/// Lưu trên Firebase Realtime Database tại `/signing_requests/{id}`.
class SigningRequestModel {
  static const int defaultSlaHours = 24;

  final String id;
  final String? batchId;
  final String requesterUid;
  final String requesterName;
  final String requesterEmail;
  final String requesterRole; // 'student' | 'employer'
  final String requesterStudentCode;
  final String requesterOrganization;

  final String degreeName;
  final String studentName;
  final String studentCode;
  final String issuerName;
  final String fileName;
  final String fileType; // 'IMAGE' | 'PDF'
  final int fileSizeBytes;
  final String documentHash; // 0x... (Keccak-256 hoặc SHA-256 từ byte gốc)
  final String hashAlgorithm; // 'keccak256' | 'sha256'

  final SigningRequestStatus status;
  final int createdAt;
  final int expectedResolveAt;
  final int estimatedHours;
  final String waitReason;

  final String? signedTxHash;
  final int? signedAt;
  final String? signedByUid;
  final String? signedByName;
  final String? rejectionReason;

  const SigningRequestModel({
    required this.id,
    this.batchId,
    required this.requesterUid,
    required this.requesterName,
    required this.requesterEmail,
    required this.requesterRole,
    this.requesterStudentCode = '',
    this.requesterOrganization = '',
    required this.degreeName,
    required this.studentName,
    this.studentCode = '',
    required this.issuerName,
    required this.fileName,
    required this.fileType,
    required this.fileSizeBytes,
    required this.documentHash,
    this.hashAlgorithm = 'keccak256',
    this.status = SigningRequestStatus.pending,
    required this.createdAt,
    required this.expectedResolveAt,
    this.estimatedHours = defaultSlaHours,
    this.waitReason = '',
    this.signedTxHash,
    this.signedAt,
    this.signedByUid,
    this.signedByName,
    this.rejectionReason,
  });

  bool get isStudentRequest => requesterRole == 'student';
  bool get isEmployerRequest => requesterRole == 'employer';

  DateTime get createdDateTime =>
      DateTime.fromMillisecondsSinceEpoch(createdAt);
  DateTime get expectedResolveDateTime =>
      DateTime.fromMillisecondsSinceEpoch(expectedResolveAt);
  DateTime? get signedDateTime => signedAt == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(signedAt!);

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      if (batchId != null && batchId!.isNotEmpty) 'batchId': batchId,
      'requesterUid': requesterUid,
      'requesterName': requesterName,
      'requesterEmail': requesterEmail,
      'requesterRole': requesterRole,
      'requesterStudentCode': requesterStudentCode,
      'requesterOrganization': requesterOrganization,
      'degreeName': degreeName,
      'studentName': studentName,
      'studentCode': studentCode,
      'issuerName': issuerName,
      'fileName': fileName,
      'fileType': fileType,
      'fileSizeBytes': fileSizeBytes,
      'documentHash': documentHash,
      'hashAlgorithm': hashAlgorithm,
      'status': status.value,
      'createdAt': createdAt,
      'expectedResolveAt': expectedResolveAt,
      'estimatedHours': estimatedHours,
      'waitReason': waitReason,
      if (signedTxHash != null) 'signedTxHash': signedTxHash,
      if (signedAt != null) 'signedAt': signedAt,
      if (signedByUid != null) 'signedByUid': signedByUid,
      if (signedByName != null) 'signedByName': signedByName,
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
    };
  }

  factory SigningRequestModel.fromMap(
    String id,
    Map<dynamic, dynamic> map,
  ) {
    final created = (map['createdAt'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final defaultExpected = created +
        const Duration(hours: defaultSlaHours).inMilliseconds;
    return SigningRequestModel(
      id: id,
      batchId: map['batchId']?.toString(),
      requesterUid: map['requesterUid']?.toString() ?? '',
      requesterName: map['requesterName']?.toString() ?? '',
      requesterEmail: map['requesterEmail']?.toString() ?? '',
      requesterRole: map['requesterRole']?.toString() ?? 'student',
      requesterStudentCode: map['requesterStudentCode']?.toString() ?? '',
      requesterOrganization: map['requesterOrganization']?.toString() ?? '',
      degreeName: map['degreeName']?.toString() ?? '',
      studentName: map['studentName']?.toString() ?? '',
      studentCode: map['studentCode']?.toString() ?? '',
      issuerName: map['issuerName']?.toString() ?? '',
      fileName: map['fileName']?.toString() ?? '',
      fileType: map['fileType']?.toString() ?? 'PDF',
      fileSizeBytes: (map['fileSizeBytes'] as num?)?.toInt() ?? 0,
      documentHash: map['documentHash']?.toString() ?? '',
      hashAlgorithm: map['hashAlgorithm']?.toString() ?? 'keccak256',
      status: SigningRequestStatus.fromString(map['status']?.toString()),
      createdAt: created,
      expectedResolveAt:
          (map['expectedResolveAt'] as num?)?.toInt() ?? defaultExpected,
      estimatedHours:
          (map['estimatedHours'] as num?)?.toInt() ?? defaultSlaHours,
      waitReason: map['waitReason']?.toString() ?? '',
      signedTxHash: map['signedTxHash']?.toString(),
      signedAt: (map['signedAt'] as num?)?.toInt(),
      signedByUid: map['signedByUid']?.toString(),
      signedByName: map['signedByName']?.toString(),
      rejectionReason: map['rejectionReason']?.toString(),
    );
  }

  SigningRequestModel copyWith({
    SigningRequestStatus? status,
    int? expectedResolveAt,
    int? estimatedHours,
    String? waitReason,
    String? signedTxHash,
    int? signedAt,
    String? signedByUid,
    String? signedByName,
    String? rejectionReason,
  }) {
    return SigningRequestModel(
      id: id,
      batchId: batchId,
      requesterUid: requesterUid,
      requesterName: requesterName,
      requesterEmail: requesterEmail,
      requesterRole: requesterRole,
      requesterStudentCode: requesterStudentCode,
      requesterOrganization: requesterOrganization,
      degreeName: degreeName,
      studentName: studentName,
      studentCode: studentCode,
      issuerName: issuerName,
      fileName: fileName,
      fileType: fileType,
      fileSizeBytes: fileSizeBytes,
      documentHash: documentHash,
      hashAlgorithm: hashAlgorithm,
      status: status ?? this.status,
      createdAt: createdAt,
      expectedResolveAt: expectedResolveAt ?? this.expectedResolveAt,
      estimatedHours: estimatedHours ?? this.estimatedHours,
      waitReason: waitReason ?? this.waitReason,
      signedTxHash: signedTxHash ?? this.signedTxHash,
      signedAt: signedAt ?? this.signedAt,
      signedByUid: signedByUid ?? this.signedByUid,
      signedByName: signedByName ?? this.signedByName,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }
}
