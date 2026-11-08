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

  UserService() {
    try {
      final rootRef = FirebaseDatabase.instance.ref();
      _usersRef = rootRef.child('users');
      _configRef = rootRef.child('system_config');
    } catch (e) {
      debugPrint('[UserService] Firebase Realtime Database chưa kết nối: $e');
      _usersRef = null;
      _configRef = null;
    }
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

  /// Kiểm tra xem UID có phải là tài khoản mẫu chấm thi (Demo) hay không
  static bool isDemoUid(String uid) => uid.startsWith('demo_');

  // [CREATE / UPDATE] Lưu hoặc cập nhật hồ sơ người dùng lên Firebase Realtime Database & Bộ nhớ máy
  Future<bool> saveUserProfile(UserModel user) async {
    // 1. Luôn lưu vào SharedPreferences làm bộ nhớ đệm an toàn
    await _saveProfileLocally(user);

    // 2. Nếu là tài khoản mẫu chấm thi (demo_...) thì tuyệt đối KHÔNG đẩy lên Firebase Realtime Database thật
    if (isDemoUid(user.uid)) {
      return true;
    }

    // 3. Đồng bộ tài khoản thật lên Firebase Realtime Database nếu có kết nối
    if (_usersRef != null) {
      try {
        await _usersRef!.child(user.uid).set(user.toMap());
        return true;
      } catch (e) {
        debugPrint('[UserService] Lỗi đồng bộ lên Firebase: $e');
      }
    }
    return true;
  }

  // [CLEANUP] Tự động dọn dẹp các nhánh demo_... đã lỡ bị đẩy lên Firebase Realtime Database trước đó
  Future<void> cleanupDemoNodesOnFirebase() async {
    if (_usersRef == null) return;
    const demoUids = [
      'demo_staff_001',
      'demo_employer_002',
      'demo_student_003',
    ];
    for (final demoUid in demoUids) {
      try {
        await _usersRef!.child(demoUid).remove();
      } catch (e) {
        debugPrint('[UserService] Bỏ qua dọn dẹp $demoUid: $e');
      }
    }
  }

  // [READ] Lấy thông tin hồ sơ của người dùng theo UID
  Future<UserModel?> getUserProfile(String uid) async {
    // Nếu là tài khoản Demo thì đọc trực tiếp từ bộ nhớ máy
    if (isDemoUid(uid)) {
      return await _loadProfileLocally(uid);
    }

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

    // 2. Xóa khỏi Firebase Realtime Database nếu là tài khoản thật
    if (_usersRef != null && !isDemoUid(uid)) {
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
