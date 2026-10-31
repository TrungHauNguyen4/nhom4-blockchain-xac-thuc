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

  UserService() {
    try {
      _usersRef = FirebaseDatabase.instance.ref().child('users');
    } catch (e) {
      debugPrint('[UserService] Firebase Realtime Database chưa kết nối: $e');
      _usersRef = null;
    }
  }

  // [CREATE / UPDATE] Lưu hoặc cập nhật hồ sơ người dùng lên Firebase Realtime Database & Bộ nhớ máy
  Future<bool> saveUserProfile(UserModel user) async {
    // 1. Luôn lưu vào SharedPreferences làm bộ nhớ đệm an toàn
    await _saveProfileLocally(user);

    // 2. Đồng bộ lên Firebase Realtime Database nếu có kết nối
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
