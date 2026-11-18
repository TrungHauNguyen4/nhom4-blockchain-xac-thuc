/// Loại thông báo In-App gửi tới người yêu cầu ký tài liệu.
enum AppNotificationType {
  signingCompleted,
  signingDelayed,
  signingRejected,
  general;

  static AppNotificationType fromString(String? raw) {
    switch (raw?.trim()) {
      case 'signingCompleted':
      case 'signing_completed':
        return AppNotificationType.signingCompleted;
      case 'signingDelayed':
      case 'signing_delayed':
        return AppNotificationType.signingDelayed;
      case 'signingRejected':
      case 'signing_rejected':
        return AppNotificationType.signingRejected;
      default:
        return AppNotificationType.general;
    }
  }
}

/// Mô hình Thông báo In-App lưu trên Firebase Realtime Database tại `/notifications/{uid}/{id}`.
class AppNotificationModel {
  final String id;
  final String recipientUid;
  final String title;
  final String body;
  final AppNotificationType type;
  final String? relatedRequestId;
  final String? documentHash;
  final String? hashAlgorithm;
  final String? txHash;
  final bool isRead;
  final int createdAt;

  const AppNotificationModel({
    required this.id,
    required this.recipientUid,
    required this.title,
    required this.body,
    this.type = AppNotificationType.general,
    this.relatedRequestId,
    this.documentHash,
    this.hashAlgorithm,
    this.txHash,
    this.isRead = false,
    required this.createdAt,
  });

  DateTime get createdDateTime =>
      DateTime.fromMillisecondsSinceEpoch(createdAt);

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'recipientUid': recipientUid,
      'title': title,
      'body': body,
      'type': type.name,
      if (relatedRequestId != null) 'relatedRequestId': relatedRequestId,
      if (documentHash != null) 'documentHash': documentHash,
      if (hashAlgorithm != null) 'hashAlgorithm': hashAlgorithm,
      if (txHash != null) 'txHash': txHash,
      'isRead': isRead,
      'createdAt': createdAt,
    };
  }

  factory AppNotificationModel.fromMap(
    String id,
    Map<dynamic, dynamic> map,
  ) {
    return AppNotificationModel(
      id: id,
      recipientUid: map['recipientUid']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      type: AppNotificationType.fromString(map['type']?.toString()),
      relatedRequestId: map['relatedRequestId']?.toString(),
      documentHash: map['documentHash']?.toString(),
      hashAlgorithm: map['hashAlgorithm']?.toString(),
      txHash: map['txHash']?.toString(),
      isRead: map['isRead'] == true,
      createdAt: (map['createdAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}
