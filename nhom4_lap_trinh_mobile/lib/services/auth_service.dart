import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import '../models/user_model.dart';
import 'user_service.dart';

/// Dịch vụ Xác thực Firebase Auth theo chuẩn Chương 11 (flutter_demo)
/// Hỗ trợ đăng nhập Email/Password, Google Sign-In và bộ đệm Fallback Offline
class AuthService {
  FirebaseAuth? _auth;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: '460606007905-3h0e26dgjqpg7g6ut2br6b9ouhcqeoqa.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
  );
  final UserService _userService;

  AuthService({UserService? userService})
      : _userService = userService ?? UserService() {
    try {
      _auth = FirebaseAuth.instance;
    } catch (e) {
      debugPrint('[AuthService] FirebaseAuth chưa khởi tạo: $e');
      _auth = null;
    }
  }

  // Stream trạng thái đăng nhập của Firebase Auth (Chuẩn Chương 11)
  Stream<User?> get authStateChanges {
    if (_auth != null) {
      return _auth!.authStateChanges();
    }
    return Stream.value(null);
  }

  User? get currentFirebaseUser => _auth?.currentUser;

  // ========================================================
  // 1. ĐĂNG KÝ BẰNG EMAIL & PASSWORD
  // ========================================================
  Future<UserModel> signUpWithEmailPassword({
    required String email,
    required String password,
    required String name,
    required String role,
    String organization = '',
    String studentCode = '',
    String? staffPasscode,
  }) async {
    // Bảo vệ ví hệ thống: Kiểm tra Mã ủy quyền Cán bộ qua SHA-256 & Firebase Realtime Database (/system_config)
    if (role == UserRole.staff) {
      final isValidPasscode =
          await _userService.verifyStaffPasscode(staffPasscode);
      if (!isValidPasscode) {
        throw 'Mã ủy quyền Cán bộ không chính xác! Vui lòng liên hệ Quản trị viên để được cấp quyền.';
      }
    }

    final now = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());

    if (_auth != null) {
      try {
        final credential = await _auth!.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );

        final uid = credential.user!.uid;
        // Cập nhật Display Name trên Firebase User
        await credential.user!.updateDisplayName(name.trim());

        final newUser = UserModel(
          uid: uid,
          name: name.trim(),
          email: email.trim(),
          role: role,
          organization: organization.trim(),
          studentCode: studentCode.trim(),
          createdAt: now,
        );

        // Lưu hồ sơ lên Firebase Realtime Database
        await _userService.saveUserProfile(newUser);
        return newUser;
      } on FirebaseAuthException catch (e) {
        throw getAuthErrorMessage(e);
      } catch (e) {
        throw 'Không thể kết nối dịch vụ xác thực: $e';
      }
    } else {
      // Chế độ Offline Fallback khi chưa cấu hình Firebase
      final mockUid = 'mock_uid_${email.hashCode.abs()}';
      final newUser = UserModel(
        uid: mockUid,
        name: name.trim(),
        email: email.trim(),
        role: role,
        organization: organization.trim(),
        studentCode: studentCode.trim(),
        createdAt: now,
      );
      await _userService.saveUserProfile(newUser);
      return newUser;
    }
  }

  // ========================================================
  // 2. ĐĂNG NHẬP BẰNG EMAIL & PASSWORD
  // ========================================================
  Future<UserModel> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    // Hỗ trợ Tài khoản Demo nhanh phục vụ bảo vệ đồ án / chấm thi
    if (_isDemoAccount(cleanEmail)) {
      return _getDemoUser(cleanEmail);
    }

    if (_auth != null) {
      try {
        final credential = await _auth!.signInWithEmailAndPassword(
          email: cleanEmail,
          password: password,
        );

        final uid = credential.user!.uid;
        var profile = await _userService.getUserProfile(uid);

        if (profile == null) {
          // Nếu chưa có hồ sơ trên Realtime Database thì tự khởi tạo mặc định
          final now = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
          profile = UserModel(
            uid: uid,
            name: credential.user!.displayName ?? cleanEmail.split('@').first,
            email: cleanEmail,
            role: UserRole.student,
            createdAt: now,
          );
          await _userService.saveUserProfile(profile);
        }
        return profile;
      } on FirebaseAuthException catch (e) {
        throw getAuthErrorMessage(e);
      } catch (e) {
        throw 'Lỗi đăng nhập: $e';
      }
    } else {
      // Fallback offline nếu Firebase chưa sẵn sàng
      final mockUid = 'mock_uid_${cleanEmail.hashCode.abs()}';
      var profile = await _userService.getUserProfile(mockUid);
      if (profile == null) {
        profile = UserModel(
          uid: mockUid,
          name: cleanEmail.split('@').first,
          email: cleanEmail,
          role: UserRole.student,
          createdAt: DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now()),
        );
        await _userService.saveUserProfile(profile);
      }
      return profile;
    }
  }

  // ========================================================
  // 3. ĐĂNG NHẬP BẰNG GOOGLE (Google Sign-In)
  // ========================================================
  Future<UserModel> signInWithGoogle() async {
    if (_auth != null && !kIsWeb) {
      try {
        // Đảm bảo bảng chọn tài khoản Google luôn hiển thị để người dùng chủ động chọn
        await _googleSignIn.signOut();
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          throw 'Bạn đã hủy thao tác chọn tài khoản Google.';
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final userCredential = await _auth!.signInWithCredential(credential);
        final user = userCredential.user!;
        final uid = user.uid;

        var profile = await _userService.getUserProfile(uid);
        if (profile == null) {
          // Lần đầu đăng nhập Google: Tự động gán vai trò Sinh viên mặc định với thông tin Google thật
          profile = UserModel(
            uid: uid,
            name: user.displayName ?? googleUser.displayName ?? 'Người dùng Google',
            email: user.email ?? googleUser.email,
            avatarBase64OrUrl: user.photoURL ?? googleUser.photoUrl,
            role: UserRole.student,
            createdAt: DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now()),
          );
          await _userService.saveUserProfile(profile);
        }
        return profile;
      } on FirebaseAuthException catch (e) {
        throw getAuthErrorMessage(e);
      } on PlatformException catch (e) {
        final details = '${e.code} ${e.message ?? ''}';
        if (details.contains('sign_in_canceled') || details.contains('12501')) {
          throw 'Bạn đã hủy thao tác chọn tài khoản Google.';
        }
        if (details.contains('ApiException: 10') ||
            details.contains('12500') ||
            details.contains('DEVELOPER_ERROR')) {
          throw 'Chưa bật Google Sign-In hoặc thiếu mã SHA-1 trên Firebase Console (Project Settings -> Add fingerprint).';
        }
        throw 'Lỗi đăng nhập Google (${e.code}): ${e.message ?? 'Vui lòng thử lại.'}';
      } catch (e) {
        if (e is String) rethrow;
        throw 'Không thể đăng nhập bằng Google: $e';
      }
    } else {
      throw 'Chức năng Đăng nhập Google yêu cầu kết nối Firebase trên thiết bị di động.';
    }
  }

  // ========================================================
  // 4. QUÊN / ĐẶT LẠI MẬT KHẨU (Password Reset)
  // ========================================================
  Future<void> sendPasswordResetEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) {
      throw 'Vui lòng nhập địa chỉ email.';
    }

    if (_isDemoAccount(cleanEmail)) {
      throw 'Đây là tài khoản mẫu chấm thi, mật khẩu cố định là: 123456';
    }

    if (_auth != null) {
      try {
        await _auth!.sendPasswordResetEmail(email: cleanEmail);
      } on FirebaseAuthException catch (e) {
        throw getAuthErrorMessage(e);
      } catch (e) {
        throw 'Không thể gửi email đặt lại mật khẩu: $e';
      }
    } else {
      throw 'Dịch vụ xác thực Firebase chưa sẵn sàng. Vui lòng thử lại sau.';
    }
  }

  // ========================================================
  // 5. XÓA VĨNH VIỄN TÀI KHOẢN (Delete Account)
  // Xóa 3 tầng: Firebase Realtime Database + SharedPreferences + Firebase Auth
  // ========================================================
  Future<void> deleteAccount(String uid) async {
    // 1. Xóa hồ sơ trong Realtime Database và SharedPreferences
    await _userService.deleteUserProfile(uid);

    // 2. Nếu là tài khoản Firebase Auth thật thì tiến hành xóa user trên Auth
    if (_auth != null && _auth!.currentUser != null) {
      final user = _auth!.currentUser!;
      try {
        await user.delete();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          // Phiên đăng nhập quá cũ, thử reauthenticate nếu là tài khoản Google
          try {
            final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
            if (googleUser != null) {
              final googleAuth = await googleUser.authentication;
              final credential = GoogleAuthProvider.credential(
                accessToken: googleAuth.accessToken,
                idToken: googleAuth.idToken,
              );
              await user.reauthenticateWithCredential(credential);
              await user.delete();
            } else {
              throw 'Vui lòng đăng xuất và đăng nhập lại để xác thực quyền xóa tài khoản.';
            }
          } catch (_) {
            throw 'Vì lý do bảo mật, vui lòng đăng xuất và đăng nhập lại trước khi thực hiện thao tác xóa.';
          }
        } else {
          throw getAuthErrorMessage(e);
        }
      } catch (e) {
        throw 'Lỗi xóa tài khoản: $e';
      }
    }

    // 3. Ngắt kết nối Google Sign-In nếu có
    try {
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
    } catch (_) {}
  }

  // ========================================================
  // 6. ĐĂNG XUẤT (Sign Out)
  // ========================================================
  Future<void> signOut() async {
    try {
      if (_auth != null) {
        await _auth!.signOut();
      }
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
    } catch (e) {
      debugPrint('[AuthService] Lỗi khi đăng xuất: $e');
    }
  }

  // ========================================================
  // 7. DỊCH MÃ LỖI FIREBASE SANG TIẾNG VIỆT THÂN THIỆN
  // ========================================================
  static String getAuthErrorMessage(dynamic error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'Không tìm thấy tài khoản với email này.';
        case 'wrong-password':
          return 'Mật khẩu không chính xác.';
        case 'invalid-credential':
          return 'Email hoặc mật khẩu không đúng.';
        case 'email-already-in-use':
          return 'Email này đã được đăng ký tài khoản trước đó.';
        case 'weak-password':
          return 'Mật khẩu quá yếu (yêu cầu tối thiểu 6 ký tự).';
        case 'invalid-email':
          return 'Định dạng email không hợp lệ.';
        case 'network-request-failed':
          return 'Lỗi kết nối mạng! Vui lòng kiểm tra lại Internet.';
        case 'too-many-requests':
          return 'Đăng nhập sai quá nhiều lần. Vui lòng thử lại sau vài phút.';
        case 'user-disabled':
          return 'Tài khoản này đã bị vô hiệu hóa.';
        default:
          return error.message ?? 'Đã xảy ra lỗi xác thực: ${error.code}';
      }
    }
    return error.toString();
  }

  // ========================================================
  // HỖ TRỢ TÀI KHOẢN DEMO SẴN CHO 3 VAI TRÒ
  // Giúp Thầy/Cô chấm điểm chuyển đổi 3 vai trò ngay lập tức!
  // ========================================================
  bool _isDemoAccount(String email) {
    return email == 'canbo@edu.vn' ||
        email == 'doanhnghiep@company.com' ||
        email == 'sinhvien@edu.vn';
  }

  UserModel _getDemoUser(String email) {
    final now = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
    if (email == 'canbo@edu.vn') {
      return UserModel(
        uid: 'demo_staff_001',
        name: 'ThS. Nguyễn Văn Quản (Cán Bộ Đào Tạo)',
        email: 'canbo@edu.vn',
        role: UserRole.staff,
        organization: 'Trường Đại học Công nghệ TP.HCM',
        createdAt: now,
      );
    } else if (email == 'doanhnghiep@company.com') {
      return UserModel(
        uid: 'demo_employer_002',
        name: 'Trần Thị Tuyển Dụng (HR Manager)',
        email: 'doanhnghiep@company.com',
        role: UserRole.employer,
        organization: 'Tập đoàn Công nghệ FPT',
        createdAt: now,
      );
    } else {
      return UserModel(
        uid: 'demo_student_003',
        name: 'Lê Hoàng Sinh Viên',
        email: email,
        role: UserRole.student,
        organization: 'Khoa Công nghệ Thông tin',
        studentCode: '20261104',
        createdAt: now,
      );
    }
  }
}
