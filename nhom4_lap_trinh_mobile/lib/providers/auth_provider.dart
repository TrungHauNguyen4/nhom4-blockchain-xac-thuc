import 'dart:async';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';

/// Provider Quản lý Trạng thái Xác thực & Phân quyền toàn ứng dụng
/// Sử dụng MultiProvider & ChangeNotifier theo chuẩn Chương 7 (flutter_demo)
class AuthProvider extends ChangeNotifier {
  static const String _sessionPrefPrefix = 'active_session_id_';

  final AuthService _authService;
  final UserService _userService;

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;
  String? _localSessionId;
  StreamSubscription<String?>? _sessionSub;
  bool _isHandlingSessionKick = false;

  AuthProvider({
    AuthService? authService,
    UserService? userService,
    @visibleForTesting UserModel? initialUser,
  })  : _authService = authService ?? AuthService(),
        _userService = userService ?? UserService() {
    if (initialUser != null) {
      _currentUser = initialUser;
    } else {
      _initAuth();
    }
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

  @override
  void dispose() {
    _sessionSub?.cancel();
    super.dispose();
  }

  String _generateSessionId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final rand = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    return '${now}_$rand';
  }

  Future<void> _establishSession(String uid) async {
    final sessionId = _generateSessionId();
    _localSessionId = sessionId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_sessionPrefPrefix$uid', sessionId);
    await _userService.claimActiveSession(uid, sessionId);
    _startSessionWatcher(uid);
  }

  void _startSessionWatcher(String uid) {
    _sessionSub?.cancel();
    _sessionSub = _userService.watchActiveSession(uid).listen((remoteSessionId) {
      if (_isHandlingSessionKick) return;
      if (_currentUser == null || _currentUser!.uid != uid) return;
      if (remoteSessionId != null &&
          _localSessionId != null &&
          remoteSessionId != _localSessionId) {
        _handleRemoteSessionKicked(uid);
      }
    });
  }

  Future<void> _handleRemoteSessionKicked(String uid) async {
    if (_isHandlingSessionKick) return;
    _isHandlingSessionKick = true;
    await _sessionSub?.cancel();
    _sessionSub = null;

    try {
      await _authService.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_logged_in_uid');
      await prefs.remove('$_sessionPrefPrefix$uid');
    } catch (e) {
      debugPrint('[AuthProvider] Lỗi xử lý đăng xuất do trùng thiết bị: $e');
    } finally {
      _localSessionId = null;
      _currentUser = null;
      _errorMessage =
          'Tài khoản này vừa đăng nhập trên thiết bị khác. Phiên hiện tại đã tự động đăng xuất để bảo vệ dữ liệu.';
      _isHandlingSessionKick = false;
      notifyListeners();
    }
  }

  // [INIT] Kiểm tra phiên đăng nhập tự động khi khởi động app
  Future<void> _initAuth() async {
    _isLoading = true;
    notifyListeners();

    try {
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
          if (cachedUser != null && cachedUser.email == 'google_user@gmail.com') {
            await prefs.remove('last_logged_in_uid');
            _currentUser = null;
          } else {
            _currentUser = cachedUser;
          }
        }
      }

      if (_currentUser != null) {
        final uid = _currentUser!.uid;
        final prefs = await SharedPreferences.getInstance();
        final savedSession = prefs.getString('$_sessionPrefPrefix$uid');
        if (savedSession != null && savedSession.isNotEmpty) {
          _localSessionId = savedSession;
          _startSessionWatcher(uid);
        } else {
          await _establishSession(uid);
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
      await _establishSession(user.uid);
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
      await _establishSession(user.uid);
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
      await _establishSession(user.uid);
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
      await _sessionSub?.cancel();
      _sessionSub = null;
      final uid = _currentUser?.uid;
      final sid = _localSessionId;
      if (uid != null && sid != null) {
        await _userService.clearActiveSessionIfMatch(uid, sid);
      }
      await _authService.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_logged_in_uid');
      if (uid != null) {
        await prefs.remove('$_sessionPrefPrefix$uid');
      }
      _localSessionId = null;
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
  // [UPDATE PROFILE] Cập nhật thông tin cá nhân & Portfolio
  // ========================================================
  Future<bool> updateProfile({
    required String name,
    required String organization,
    String? studentCode,
    String? headline,
    String? bio,
    String? phone,
    String? portfolioUrl,
    String? role,
    bool markCompleted = true,
  }) async {
    if (_currentUser == null) return false;

    _isLoading = true;
    notifyListeners();

    final String nextRole =
        (role == UserRole.student || role == UserRole.employer)
            ? role!
            : _currentUser!.role;

    final updated = _currentUser!.copyWith(
      name: name,
      organization: organization,
      studentCode: studentCode ?? _currentUser!.studentCode,
      headline: headline ?? _currentUser!.headline,
      bio: bio ?? _currentUser!.bio,
      phone: phone ?? _currentUser!.phone,
      portfolioUrl: portfolioUrl ?? _currentUser!.portfolioUrl,
      role: nextRole,
      originalRole: nextRole != UserRole.staff ? nextRole : _currentUser!.originalRole,
      isProfileCompleted: markCompleted ? true : _currentUser!.isProfileCompleted,
    );

    final ok = await _userService.saveUserProfile(updated);
    if (ok) {
      _currentUser = updated;
    }
    _isLoading = false;
    notifyListeners();
    return ok;
  }

  /// Bật / Tắt chế độ công khai Portfolio cho người khác xem khi quét văn bằng
  Future<bool> setPortfolioVisibility(bool isPublic) async {
    if (_currentUser == null) return false;
    final updated = _currentUser!.copyWith(isPortfolioPublic: isPublic);
    _currentUser = updated;
    notifyListeners();
    return _userService.saveUserProfile(updated);
  }

  /// Người dùng chọn "Để sau" khi đăng nhập Gmail lần đầu -> không hiện lại popup nữa
  Future<void> dismissFirstTimeOnboarding() async {
    if (_currentUser == null || _currentUser!.isProfileCompleted) return;
    final updated = _currentUser!.copyWith(isProfileCompleted: true);
    _currentUser = updated;
    notifyListeners();
    await _userService.saveUserProfile(updated);
  }

  // ========================================================
  // [UPDATE AVATAR] Cập nhật ảnh đại diện (Base64)
  // ========================================================
  Future<bool> updateAvatar(String base64) async {
    if (_currentUser == null) return false;

    final ok = await _userService.updateAvatar(_currentUser!.uid, base64);
    if (ok) {
      _currentUser = _currentUser!.copyWith(avatarBase64OrUrl: base64);
      await _userService.syncPublicPortfolio(_currentUser!);
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
    final String? preservedOriginalRole =
        (_currentUser!.originalRole != null &&
                _currentUser!.originalRole!.isNotEmpty &&
                _currentUser!.originalRole != UserRole.staff)
            ? _currentUser!.originalRole
            : (_currentUser!.role != UserRole.staff
                ? _currentUser!.role
                : null);

    _currentUser = _currentUser!.copyWith(
      role: UserRole.staff,
      originalRole: preservedOriginalRole,
    );
    await _userService.saveUserProfile(_currentUser!);
    _errorMessage = null;
    notifyListeners();
    return true;
  }

  // ========================================================
  // [REVERT FROM STAFF] Quay về vai trò gốc (Sinh viên / Nhà tuyển dụng).
  // Khi muốn nâng cấp lại lên Cán bộ đào tạo sẽ bắt buộc nhập lại mã ủy quyền.
  // ========================================================
  Future<bool> revertFromStaff({String? fallbackRole}) async {
    if (_currentUser == null || !_currentUser!.isStaff) return false;

    String? targetRole = _currentUser!.originalRole;
    if (targetRole == null ||
        targetRole.isEmpty ||
        targetRole == UserRole.staff) {
      targetRole = fallbackRole;
    }
    if (targetRole != UserRole.student && targetRole != UserRole.employer) {
      return false;
    }

    _currentUser = _currentUser!.copyWith(
      role: targetRole,
      originalRole: targetRole,
    );
    await _userService.saveUserProfile(_currentUser!);
    _errorMessage = null;
    notifyListeners();
    return true;
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
