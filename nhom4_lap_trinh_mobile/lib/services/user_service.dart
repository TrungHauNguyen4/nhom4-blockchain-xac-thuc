import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

/// Dịch vụ quản lý Hồ sơ & Phân quyền người dùng trên Firebase Realtime Database
/// Tích hợp bộ đệm SharedPreferences để chạy mượt mà ngay cả khi không có mạng
class UserService {
  static const String _userCachePrefix = 'user_profile_cache_';
  DatabaseReference? _usersRef;
  DatabaseReference? _configRef;
  DatabaseReference? _publicPortfoliosRef;

  UserService() {
    try {
      final rootRef = FirebaseDatabase.instance.ref();
      _usersRef = rootRef.child('users');
      _configRef = rootRef.child('system_config');
      _publicPortfoliosRef = rootRef.child('public_portfolios');
    } catch (e) {
      debugPrint('[UserService] Firebase Realtime Database chưa kết nối: $e');
      _usersRef = null;
      _configRef = null;
      _publicPortfoliosRef = null;
    }
  }

  /// Chuẩn hóa MSSV làm khóa an toàn trên Firebase Realtime Database
  static String normalizeStudentKey(String studentCode) {
    return studentCode
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[\s.#$\[\]/]+'), '_');
  }

  /// Kiểm tra Mã ủy quyền Cán bộ động từ nhánh `/system_config/staff_passcode_sha256` trên Firebase Realtime Database
  /// Kết hợp băm một chiều SHA-256 để không lưu mã gốc dạng chữ thuần trong mã nguồn Git.
  Future<bool> verifyStaffPasscode(String? inputPasscode) async {
    if (inputPasscode == null || inputPasscode.trim().isEmpty) return false;

    String? remoteConfigValue;
    if (_configRef != null) {
      try {
        final snapshot = await _configRef!.get().timeout(
              const Duration(seconds: 3),
            );
        if (snapshot.exists && snapshot.value is Map) {
          final map = snapshot.value as Map;
          remoteConfigValue = (map['staff_passcode_sha256'] ??
                  map['staff_passcode'] ??
                  '')
              .toString();
        } else {
          // Tự động khởi tạo nhánh cấu hình băm SHA-256 trên Firebase lần đầu để Admin quản lý từ xa
          unawaited(_configRef!.update({
            'staff_passcode_sha256': UserRole.defaultStaffPasscodeSha256,
          }));
        }
      } catch (e) {
        debugPrint(
            '[UserService] Không thể đọc cấu hình mã ủy quyền từ Firebase, dùng SHA-256 mặc định: $e');
      }
    }

    return UserRole.verifyPasscode(
      inputPasscode,
      remoteConfigValue: remoteConfigValue,
    );
  }

  // [CREATE / UPDATE] Lưu hoặc cập nhật hồ sơ người dùng lên Firebase Realtime Database & Bộ nhớ máy
  Future<bool> saveUserProfile(UserModel user) async {
    // 1. Luôn lưu vào SharedPreferences làm bộ nhớ đệm an toàn
    await _saveProfileLocally(user);

    // 2. Đồng bộ tài khoản lên Firebase Realtime Database bằng update() để giữ nguyên các nhánh phụ như activeSessionId
    if (_usersRef != null) {
      try {
        await _usersRef!.child(user.uid).update(user.toMap());
        await syncPublicPortfolio(user);
        return true;
      } catch (e) {
        debugPrint('[UserService] Lỗi đồng bộ lên Firebase: $e');
      }
    }
    return true;
  }

  /// Đồng bộ thông tin Portfolio công khai (ẩn số điện thoại) theo MSSV lên /public_portfolios.
  /// Nếu người dùng tắt công khai (`isPortfolioPublic == false`), xóa sạch thông tin cá nhân khỏi nhánh công khai.
  Future<void> syncPublicPortfolio(UserModel user) async {
    if (_publicPortfoliosRef == null) return;
    final key = normalizeStudentKey(user.studentCode);
    if (key.isEmpty) return;

    try {
      if (!user.isPortfolioPublic) {
        await _publicPortfoliosRef!.child(key).set(<String, dynamic>{
          'ownerUid': user.uid,
          'studentCode': user.studentCode.trim(),
          'isPortfolioPublic': false,
          'updatedAt': ServerValue.timestamp,
        }).timeout(const Duration(seconds: 4));
        return;
      }

      await _publicPortfoliosRef!.child(key).set(<String, dynamic>{
        'ownerUid': user.uid,
        'name': user.name,
        'email': user.email,
        'avatarBase64OrUrl': user.avatarBase64OrUrl,
        'role': user.role,
        'organization': user.organization,
        'studentCode': user.studentCode.trim(),
        'headline': user.headline,
        'bio': user.bio,
        'portfolioUrl': user.portfolioUrl,
        'isPortfolioPublic': true,
        'createdAt': user.createdAt,
        'updatedAt': ServerValue.timestamp,
      }).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[UserService] Không thể đồng bộ public_portfolios: $e');
    }
  }

  /// Đọc thông tin Portfolio công khai của chủ văn bằng theo MSSV (ẩn số điện thoại)
  Future<UserModel?> getPublicPortfolioByStudentCode(String studentCode) async {
    if (_publicPortfoliosRef == null) return null;
    final key = normalizeStudentKey(studentCode);
    if (key.isEmpty) return null;

    try {
      final snapshot = await _publicPortfoliosRef!
          .child(key)
          .get()
          .timeout(const Duration(seconds: 4));
      if (snapshot.exists && snapshot.value is Map) {
        final raw = Map<String, dynamic>.from(snapshot.value as Map);
        raw['phone'] = ''; // Luôn ẩn số điện thoại trên Portfolio công khai
        return UserModel.fromMap(
          raw,
          defaultUid: raw['ownerUid']?.toString() ?? '',
        );
      }
    } catch (e) {
      debugPrint('[UserService] Lỗi đọc public_portfolios: $e');
    }
    return null;
  }

  // [SINGLE SESSION] Ghi nhận phiên đăng nhập duy nhất của thiết bị hiện tại
  Future<void> claimActiveSession(String uid, String sessionId) async {
    if (_usersRef == null) return;
    try {
      await _usersRef!.child(uid).update({
        'activeSessionId': sessionId,
        'sessionUpdatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('[UserService] Không thể cập nhật activeSessionId: $e');
    }
  }

  // [SINGLE SESSION] Xóa activeSessionId khi người dùng chủ động đăng xuất trên thiết bị hiện tại
  Future<void> clearActiveSessionIfMatch(String uid, String sessionId) async {
    if (_usersRef == null) return;
    try {
      final snap = await _usersRef!.child(uid).child('activeSessionId').get();
      if (snap.exists && snap.value?.toString() == sessionId) {
        await _usersRef!.child(uid).child('activeSessionId').remove();
      }
    } catch (e) {
      debugPrint('[UserService] Lỗi dọn dẹp activeSessionId: $e');
    }
  }

  // [SINGLE SESSION] Lắng nghe thay đổi activeSessionId theo thời gian thực
  Stream<String?> watchActiveSession(String uid) {
    if (_usersRef == null) return const Stream.empty();
    try {
      return _usersRef!.child(uid).child('activeSessionId').onValue.map((event) {
        final val = event.snapshot.value;
        if (val == null) return null;
        final str = val.toString().trim();
        return str.isEmpty ? null : str;
      });
    } catch (e) {
      debugPrint('[UserService] Lỗi mở stream activeSessionId: $e');
      return const Stream.empty();
    }
  }

  // [READ] Lấy thông tin hồ sơ của người dùng theo UID
  Future<UserModel?> getUserProfile(String uid) async {
    // 1. Thử lấy từ Firebase Realtime Database
    if (_usersRef != null) {
      try {
        final snapshot = await _usersRef!.child(uid).get().timeout(
              const Duration(seconds: 4),
            );
        if (snapshot.exists && snapshot.value != null) {
          final data = snapshot.value;
          if (data is Map) {
            final user = UserModel.fromMap(data, defaultUid: uid);
            // Cập nhật lại cache offline
            await _saveProfileLocally(user);
            return user;
          }
        }
      } catch (e) {
        debugPrint('[UserService] Không thể lấy profile từ Firebase, chuyển sang đọc offline: $e');
      }
    }

    // 2. Fallback sang SharedPreferences nếu Firebase không phản hồi
    return await _loadProfileLocally(uid);
  }

  // [UPDATE] Cập nhật ảnh đại diện (Base64) lên Firebase & Offline
  Future<bool> updateAvatar(String uid, String avatarBase64) async {
    final current = await getUserProfile(uid);
    if (current == null) return false;

    final updated = current.copyWith(avatarBase64OrUrl: avatarBase64);
    return await saveUserProfile(updated);
  }

  // [UPDATE] Cập nhật thông tin Họ tên, Đơn vị, Mã SV
  Future<bool> updateDetails({
    required String uid,
    required String name,
    required String organization,
    String? studentCode,
  }) async {
    final current = await getUserProfile(uid);
    if (current == null) return false;

    final updated = current.copyWith(
      name: name,
      organization: organization,
      studentCode: studentCode ?? current.studentCode,
    );
    return await saveUserProfile(updated);
  }

  // [DELETE] Xóa hồ sơ người dùng khỏi Firebase Realtime Database & Bộ nhớ máy
  Future<bool> deleteUserProfile(String uid) async {
    // 1. Xóa cache SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_userCachePrefix$uid');
      if (prefs.getString('last_logged_in_uid') == uid) {
        await prefs.remove('last_logged_in_uid');
      }
    } catch (e) {
      debugPrint('[UserService] Lỗi xóa cache local: $e');
    }

    // 2. Xóa khỏi Firebase Realtime Database
    if (_usersRef != null) {
      try {
        await _usersRef!.child(uid).remove();
        return true;
      } catch (e) {
        debugPrint('[UserService] Lỗi xóa profile trên Firebase: $e');
        return false;
      }
    }
    return true;
  }

  // [REALTIME STREAM] Lắng nghe thay đổi hồ sơ thời gian thực (Chuẩn Chương 11)
  Stream<UserModel?> streamUserProfile(String uid) {
    if (_usersRef != null) {
      try {
        return _usersRef!.child(uid).onValue.map((event) {
          final data = event.snapshot.value;
          if (data is Map) {
            return UserModel.fromMap(data, defaultUid: uid);
          }
          return null;
        });
      } catch (e) {
        debugPrint('[UserService] Lỗi mở stream Firebase: $e');
      }
    }
    // Fallback: trả về stream 1 giá trị từ local
    return Stream.fromFuture(getUserProfile(uid));
  }

  // ========================================================
  // BỘ ĐỆM CỤC BỘ (LOCAL CACHE) QUA SHAREDPREFERENCES
  // ========================================================
  Future<void> _saveProfileLocally(UserModel user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_userCachePrefix${user.uid}', user.toJson());
      // Lưu lại UID gần nhất đã đăng nhập
      await prefs.setString('last_logged_in_uid', user.uid);
    } catch (e) {
      debugPrint('[UserService] Không thể lưu cache offline: $e');
    }
  }

  Future<UserModel?> _loadProfileLocally(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('$_userCachePrefix$uid');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        return UserModel.fromJson(jsonStr);
      }
    } catch (e) {
      debugPrint('[UserService] Không thể đọc cache offline: $e');
    }
    return null;
  }
}
