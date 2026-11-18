import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../models/notification_model.dart';
import '../models/signing_request_model.dart';

/// Dịch vụ quản lý Yêu cầu ký tài liệu (`/signing_requests`) và
/// Thông báo In-App (`/notifications/{uid}`) trên Firebase Realtime Database.
class SigningRequestService {
  DatabaseReference? _requestsRef;
  DatabaseReference? _notificationsRef;

  SigningRequestService() {
    try {
      final root = FirebaseDatabase.instance.ref();
      _requestsRef = root.child('signing_requests');
      _notificationsRef = root.child('notifications');
    } catch (e) {
      debugPrint(
        '[SigningRequestService] Firebase Realtime Database chưa kết nối: $e',
      );
      _requestsRef = null;
      _notificationsRef = null;
    }
  }

  static String normalizeHash(String rawHash) {
    final clean = rawHash.trim().toLowerCase();
    if (!clean.startsWith('0x') && clean.length == 64) {
      return '0x$clean';
    }
    return clean;
  }

  /// Gửi 1 yêu cầu ký xác nhận tài liệu (mặc định SLA 24h).
  Future<SigningRequestModel> submitRequest({
    String? batchId,
    required String requesterUid,
    required String requesterName,
    required String requesterEmail,
    required String requesterRole,
    String requesterStudentCode = '',
    String requesterOrganization = '',
    required String degreeName,
    required String studentName,
    String studentCode = '',
    required String issuerName,
    required String fileName,
    required String fileType,
    required int fileSizeBytes,
    required String documentHash,
    String hashAlgorithm = 'keccak256',
  }) async {
    final ref = _requestsRef;
    if (ref == null) {
      throw StateError('Chưa kết nối Firebase Realtime Database.');
    }

    final newRef = ref.push();
    final id = newRef.key!;
    final now = DateTime.now().millisecondsSinceEpoch;
    final expected =
        now + const Duration(hours: SigningRequestModel.defaultSlaHours).inMilliseconds;

    final model = SigningRequestModel(
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
      documentHash: normalizeHash(documentHash),
      hashAlgorithm: hashAlgorithm,
      status: SigningRequestStatus.pending,
      createdAt: now,
      expectedResolveAt: expected,
      estimatedHours: SigningRequestModel.defaultSlaHours,
    );

    await newRef.set(model.toMap()).timeout(const Duration(seconds: 6));
    return model;
  }

  /// Gửi nhiều yêu cầu ký theo lô (dành cho Nhà tuyển dụng gửi Folder / nhiều file).
  Future<List<SigningRequestModel>> submitBatchRequests({
    required String requesterUid,
    required String requesterName,
    required String requesterEmail,
    String requesterOrganization = '',
    required String issuerName,
    required List<({
      String degreeName,
      String studentName,
      String studentCode,
      String fileName,
      String fileType,
      int fileSizeBytes,
      String documentHash,
      String hashAlgorithm,
    })> items,
  }) async {
    final batchId = 'batch_${DateTime.now().millisecondsSinceEpoch}';
    final results = <SigningRequestModel>[];
    for (final item in items) {
      final created = await submitRequest(
        batchId: batchId,
        requesterUid: requesterUid,
        requesterName: requesterName,
        requesterEmail: requesterEmail,
        requesterRole: 'employer',
        requesterOrganization: requesterOrganization,
        degreeName: item.degreeName,
        studentName: item.studentName,
        studentCode: item.studentCode,
        issuerName: issuerName,
        fileName: item.fileName,
        fileType: item.fileType,
        fileSizeBytes: item.fileSizeBytes,
        documentHash: item.documentHash,
        hashAlgorithm: item.hashAlgorithm,
      );
      results.add(created);
    }
    return results;
  }

  /// Lắng nghe toàn bộ yêu cầu ký (dành cho Cán bộ ký / Issuer), mới nhất lên đầu.
  Stream<List<SigningRequestModel>> streamAllRequests() {
    final ref = _requestsRef;
    if (ref == null) {
      return Stream.value(const <SigningRequestModel>[]);
    }
    return ref.onValue.map((event) => _parseRequestSnapshot(event.snapshot));
  }

  /// Lắng nghe danh sách yêu cầu của riêng một người gửi (Sinh viên hoặc HR).
  Stream<List<SigningRequestModel>> streamMyRequests(String uid) {
    final ref = _requestsRef;
    if (ref == null || uid.trim().isEmpty) {
      return Stream.value(const <SigningRequestModel>[]);
    }
    return ref
        .orderByChild('requesterUid')
        .equalTo(uid.trim())
        .onValue
        .map((event) => _parseRequestSnapshot(event.snapshot));
  }

  List<SigningRequestModel> _parseRequestSnapshot(DataSnapshot snapshot) {
    if (!snapshot.exists || snapshot.value is! Map) {
      return const <SigningRequestModel>[];
    }
    final raw = snapshot.value as Map<dynamic, dynamic>;
    final list = <SigningRequestModel>[];
    raw.forEach((key, value) {
      if (value is Map) {
        list.add(SigningRequestModel.fromMap(key.toString(), value));
      }
    });
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Cán bộ ký thiết lập thời gian chờ lâu hơn 24h (khi hệ thống quá tải) & gửi thông báo.
  Future<void> updateWaitEstimate({
    required SigningRequestModel request,
    required int estimatedHours,
    String waitReason = '',
  }) async {
    final ref = _requestsRef;
    if (ref == null) {
      throw StateError('Chưa kết nối Firebase Realtime Database.');
    }

    final safeHours = estimatedHours < 1 ? 24 : estimatedHours;
    final newExpected =
        request.createdAt + Duration(hours: safeHours).inMilliseconds;
    final cleanReason = waitReason.trim().isEmpty
        ? 'Hệ thống đang quá tải, dự kiến xử lý trong $safeHours giờ.'
        : waitReason.trim();

    await ref.child(request.id).update(<String, dynamic>{
      'status': SigningRequestStatus.delayed.value,
      'estimatedHours': safeHours,
      'expectedResolveAt': newExpected,
      'waitReason': cleanReason,
    }).timeout(const Duration(seconds: 6));

    await _sendNotification(
      recipientUid: request.requesterUid,
      title: 'Cập nhật thời gian xử lý: ${request.degreeName}',
      body:
          'Yêu cầu ký tài liệu "${request.fileName}" được cập nhật thời gian chờ dự kiến: $safeHours giờ. Lý do: $cleanReason',
      type: AppNotificationType.signingDelayed,
      relatedRequestId: request.id,
      documentHash: request.documentHash,
      hashAlgorithm: request.hashAlgorithm,
    );
  }

  /// Đánh dấu yêu cầu đã được ký lên Blockchain & tự động gửi thông báo kèm mã kiểm tra.
  Future<void> markRequestSigned({
    required SigningRequestModel request,
    required String txHash,
    required String signedByUid,
    required String signedByName,
  }) async {
    final ref = _requestsRef;
    if (ref == null) {
      throw StateError('Chưa kết nối Firebase Realtime Database.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await ref.child(request.id).update(<String, dynamic>{
      'status': SigningRequestStatus.signed.value,
      'signedTxHash': txHash,
      'signedAt': now,
      'signedByUid': signedByUid,
      'signedByName': signedByName,
    }).timeout(const Duration(seconds: 6));

    await _sendNotification(
      recipientUid: request.requesterUid,
      title: 'Đã ký xác nhận: ${request.degreeName}',
      body:
          'Tài liệu "${request.fileName}" đã được $signedByName ký số lên Blockchain. Dùng mã Hash bên dưới để kiểm tra xác thực.',
      type: AppNotificationType.signingCompleted,
      relatedRequestId: request.id,
      documentHash: request.documentHash,
      hashAlgorithm: request.hashAlgorithm,
      txHash: txHash,
    );
  }

  /// Từ chối yêu cầu ký & gửi thông báo cho người gửi.
  Future<void> markRequestRejected({
    required SigningRequestModel request,
    required String reason,
    required String signedByUid,
    required String signedByName,
  }) async {
    final ref = _requestsRef;
    if (ref == null) {
      throw StateError('Chưa kết nối Firebase Realtime Database.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final cleanReason = reason.trim().isEmpty
        ? 'Thông tin tài liệu chưa hợp lệ.'
        : reason.trim();

    await ref.child(request.id).update(<String, dynamic>{
      'status': SigningRequestStatus.rejected.value,
      'rejectionReason': cleanReason,
      'signedAt': now,
      'signedByUid': signedByUid,
      'signedByName': signedByName,
    }).timeout(const Duration(seconds: 6));

    await _sendNotification(
      recipientUid: request.requesterUid,
      title: 'Yêu cầu ký bị từ chối: ${request.degreeName}',
      body: 'Tài liệu "${request.fileName}" không được duyệt. Lý do: $cleanReason',
      type: AppNotificationType.signingRejected,
      relatedRequestId: request.id,
      documentHash: request.documentHash,
      hashAlgorithm: request.hashAlgorithm,
    );
  }

  Future<void> _sendNotification({
    required String recipientUid,
    required String title,
    required String body,
    required AppNotificationType type,
    String? relatedRequestId,
    String? documentHash,
    String? hashAlgorithm,
    String? txHash,
  }) async {
    final ref = _notificationsRef;
    if (ref == null || recipientUid.trim().isEmpty) return;

    final userNotifRef = ref.child(recipientUid.trim()).push();
    final notif = AppNotificationModel(
      id: userNotifRef.key!,
      recipientUid: recipientUid.trim(),
      title: title,
      body: body,
      type: type,
      relatedRequestId: relatedRequestId,
      documentHash: documentHash,
      hashAlgorithm: hashAlgorithm,
      txHash: txHash,
      isRead: false,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await userNotifRef.set(notif.toMap()).timeout(const Duration(seconds: 5));
  }

  /// Lắng nghe thông báo In-App của người dùng (mới nhất lên đầu).
  Stream<List<AppNotificationModel>> streamNotifications(String uid) {
    final ref = _notificationsRef;
    if (ref == null || uid.trim().isEmpty) {
      return Stream.value(const <AppNotificationModel>[]);
    }
    return ref.child(uid.trim()).onValue.map((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value is! Map) {
        return const <AppNotificationModel>[];
      }
      final raw = snap.value as Map<dynamic, dynamic>;
      final list = <AppNotificationModel>[];
      raw.forEach((key, value) {
        if (value is Map) {
          list.add(AppNotificationModel.fromMap(key.toString(), value));
        }
      });
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<void> markNotificationRead(String uid, String notificationId) async {
    final ref = _notificationsRef;
    if (ref == null || uid.trim().isEmpty) return;
    await ref
        .child(uid.trim())
        .child(notificationId)
        .update(<String, dynamic>{'isRead': true});
  }

  Future<void> markAllNotificationsRead(String uid) async {
    final ref = _notificationsRef;
    if (ref == null || uid.trim().isEmpty) return;
    final snap = await ref.child(uid.trim()).get();
    if (!snap.exists || snap.value is! Map) return;
    final updates = <String, dynamic>{};
    (snap.value as Map<dynamic, dynamic>).forEach((key, value) {
      if (value is Map && value['isRead'] != true) {
        updates['$key/isRead'] = true;
      }
    });
    if (updates.isNotEmpty) {
      await ref.child(uid.trim()).update(updates);
    }
  }
}
