import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';

/// Provider Quản lý Trạng thái Xác thực & Phân quyền toàn ứng dụng
/// Sử dụng MultiProvider & ChangeNotifier theo chuẩn Chương 7 (flutter_demo)
class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final UserService _userService;

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  AuthProvider({
    AuthService? authService,
    UserService? userService,
  })  : _authService = authService ?? AuthService(),
        _userService = userService ?? UserService() {
    _initAuth();
  }

  /// Stream lắng nghe trạng thái phiên đăng nhập từ FirebaseAuth (Chuẩn Chương 11)
  Stream<User?> get authStateChanges => _authService.authStateChanges;

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool get isStaff => _currentUser?.isStaff ?? false;
  bool get isEmployer => _currentUser?.isEmployer ?? false;
  bool get isStudent => _currentUser?.isStudent ?? true;
  String get role => _currentUser?.role ?? UserRole.student;

  // [INIT] Kiểm tra phiên đăng nhập tự động khi khởi động app
  Future<void> _initAuth() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Dọn sạch các node demo_... cũ bị đẩy nhầm lên Firebase Realtime Database
      unawaited(_userService.cleanupDemoNodesOnFirebase());

      // 1. Kiểm tra Firebase User hiện tại
      final firebaseUser = _authService.currentFirebaseUser;
      if (firebaseUser != null) {
        _currentUser = await _userService.getUserProfile(firebaseUser.uid);
      } else {
        // 2. Thử đọc lại phiên đăng nhập đã lưu trong SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final lastUid = prefs.getString('last_logged_in_uid');
        if (lastUid != null && lastUid.isNotEmpty) {
          final cachedUser = await _userService.getUserProfile(lastUid);
          // Nếu phiên cũ là tài khoản giả google_user@gmail.com do lỗi trước đó thì tự động xóa bỏ
          if (cachedUser != null && cachedUser.email == 'google_user@gmail.com') {
            await prefs.remove('last_logged_in_uid');
            _currentUser = null;
          } else {
            _currentUser = cachedUser;
          }
        }
      }
    } catch (e) {
      debugPrint('[AuthProvider] Lỗi nạp phiên đăng nhập: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ========================================================
  // [LOGIN] Đăng nhập Email & Mật khẩu
  // ========================================================
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.signInWithEmailPassword(
        email: email,
        password: password,
      );
      _currentUser = user;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ========================================================
  // [REGISTER] Đăng ký tài khoản mới & phân quyền vai trò
  // ========================================================
  Future<bool> register({
    required String email,
    required String password,
    required String name,
    required String role,
    String organization = '',
    String studentCode = '',
    String? staffPasscode,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.signUpWithEmailPassword(
        email: email,
        password: password,
        name: name,
        role: role,
        organization: organization,
        studentCode: studentCode,
        staffPasscode: staffPasscode,
      );
      _currentUser = user;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ========================================================
  // [GOOGLE SIGN IN] Đăng nhập Google một chạm
  // ========================================================
  Future<bool> loginWithGoogle() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.signInWithGoogle();
      _currentUser = user;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ========================================================
  // [PASSWORD RESET] Gửi email đặt lại mật khẩu
  // ========================================================
  Future<bool> resetPassword(String email) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.sendPasswordResetEmail(email);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ========================================================
  // [DELETE ACCOUNT] Xóa vĩnh viễn tài khoản (3 Tầng)
  // ========================================================
  Future<bool> deleteAccount() async {
    if (_currentUser == null) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.deleteAccount(_currentUser!.uid);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_logged_in_uid');
      _currentUser = null;
      _errorMessage = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ========================================================
  // [LOGOUT] Đăng xuất
  // ========================================================
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _authService.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_logged_in_uid');
      _currentUser = null;
      _errorMessage = null;
    } catch (e) {
      debugPrint('[AuthProvider] Lỗi đăng xuất: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ========================================================
  // [UPDATE PROFILE] Cập nhật thông tin cá nhân
  // ========================================================
  Future<bool> updateProfile({
    required String name,
    required String organization,
    String? studentCode,
  }) async {
    if (_currentUser == null) return false;

    _isLoading = true;
    notifyListeners();

    final ok = await _userService.updateDetails(
      uid: _currentUser!.uid,
      name: name,
      organization: organization,
      studentCode: studentCode,
    );

    if (ok) {
      _currentUser = _currentUser!.copyWith(
        name: name,
        organization: organization,
        studentCode: studentCode ?? _currentUser!.studentCode,
      );
    }
    _isLoading = false;
    notifyListeners();
    return ok;
  }

  // ========================================================
  // [UPDATE AVATAR] Cập nhật ảnh đại diện (Base64)
  // ========================================================
  Future<bool> updateAvatar(String base64) async {
    if (_currentUser == null) return false;

    final ok = await _userService.updateAvatar(_currentUser!.uid, base64);
    if (ok) {
      _currentUser = _currentUser!.copyWith(avatarBase64OrUrl: base64);
      notifyListeners();
    }
    return ok;
  }

  // ========================================================
  // [UPGRADE TO STAFF] Xác thực mã ủy quyền bảo mật (SHA-256 + Firebase /system_config) để cấp quyền Cán bộ
  // ========================================================
  Future<bool> upgradeToStaff(String passcode) async {
    if (_currentUser == null) return false;
    final isValid = await _userService.verifyStaffPasscode(passcode);
    if (!isValid) {
      _errorMessage = 'Mã ủy quyền Cán bộ không đúng! Vui lòng liên hệ Quản trị viên.';
      notifyListeners();
      return false;
    }
    _currentUser = _currentUser!.copyWith(role: UserRole.staff);
    await _userService.saveUserProfile(_currentUser!);
    _errorMessage = null;
    notifyListeners();
    return true;
  }

  // ========================================================
  // [DEMO ROLE SWITCHER] Đổi nhanh vai trò khi thuyết trình / chấm điểm
  // ========================================================
  void switchRoleForDemo(String newRole) {
    if (_currentUser == null) return;
    _currentUser = _currentUser!.copyWith(role: newRole);
    _userService.saveUserProfile(_currentUser!);
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
