import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto_pkg;

/// Vai trò người dùng trong hệ thống xác thực văn bằng
class UserRole {
  static const String student = 'student'; // Sinh viên
  static const String employer = 'employer'; // Nhà tuyển dụng
  static const String staff = 'staff'; // Cán bộ đào tạo

  /// Mã băm SHA-256 một chiều của Mã ủy quyền Cán bộ Đào tạo mặc định.
  /// Tuyệt đối không lưu mã gốc dạng chữ thuần (plain-text) trong mã nguồn trên Git
  /// để chống dịch ngược APK và chống tạo tài khoản Cán bộ trái phép làm cạn ví ETH.
  static const String defaultStaffPasscodeSha256 =
      '327cc519e54795f4361806908d5038fd5ca2328e7db16d0aa451c2e9eb864488';

  /// Băm chuỗi mã ủy quyền sang chuẩn SHA-256 (64 ký tự hex chữ thường)
  static String hashPasscode(String rawPasscode) {
    final bytes = utf8.encode(rawPasscode.trim());
    return crypto_pkg.sha256.convert(bytes).toString().toLowerCase();
  }

  /// Kiểm tra mã ủy quyền người dùng nhập vào với mã băm SHA-256 (hoặc giá trị cấu hình từ Firebase)
  static bool verifyPasscode(String? inputPasscode, {String? remoteConfigValue}) {
    if (inputPasscode == null || inputPasscode.trim().isEmpty) return false;
    final inputHash = hashPasscode(inputPasscode);

    final target = (remoteConfigValue ?? '').trim();
    if (target.isEmpty) {
      return inputHash == defaultStaffPasscodeSha256;
    }

    // Nếu trên Firebase lưu chuỗi SHA-256 (64 ký tự hex) thì so sánh trực tiếp mã băm
    final isSha256Hex = RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(target);
    if (isSha256Hex) {
      return inputHash == target.toLowerCase();
    }

    // Nếu Quản trị viên nhập mã mới trực tiếp trên Firebase Console thì băm cả hai để đối chiếu an toàn
    return inputHash == hashPasscode(target);
  }

  static String getRoleLabel(String? role) {
    switch (role) {
      case staff:
        return 'Cán bộ đào tạo';
      case employer:
        return 'Nhà tuyển dụng';
      case student:
      default:
        return 'Sinh viên';
    }
  }
}

/// Model Người dùng đồng bộ giữa Firebase Auth & Firebase Realtime Database
class UserModel {
  final String uid;
  final String name;
  final String email;
  final String? avatarBase64OrUrl;
  final String role; // 'student' | 'employer' | 'staff'
  final String? originalRole; // Vai trò gốc trước khi nâng cấp lên 'staff'
  final String organization; // Trường học / Doanh nghiệp
  final String studentCode; // MSSV (dành cho sinh viên)
  final String headline; // Chuyên ngành / Chức danh
  final String bio; // Giới thiệu bản thân (Portfolio)
  final String phone; // Số điện thoại liên hệ
  final String portfolioUrl; // Liên kết GitHub / LinkedIn / Website
  final bool isProfileCompleted; // Đã hoàn tất bổ sung thông tin lần đầu
  final bool isPortfolioPublic; // Cho phép người khác xem Portfolio khi quét văn bằng
  final String createdAt;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.avatarBase64OrUrl,
    required this.role,
    this.originalRole,
    this.organization = '',
    this.studentCode = '',
    this.headline = '',
    this.bio = '',
    this.phone = '',
    this.portfolioUrl = '',
    this.isProfileCompleted = true,
    this.isPortfolioPublic = false,
    required this.createdAt,
  });

  bool get isStaff => role == UserRole.staff;
  bool get isEmployer => role == UserRole.employer;
  bool get isStudent => role == UserRole.student;

  bool get hasMissingPortfolioInfo =>
      organization.trim().isEmpty ||
      (isStudent && studentCode.trim().isEmpty) ||
      bio.trim().isEmpty;

  String get roleTitle => UserRole.getRoleLabel(role);

  // [CREATE / UPDATE] Chuyển đổi sang Map để lưu lên Firebase Realtime Database hoặc SharedPreferences
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'avatarBase64OrUrl': avatarBase64OrUrl,
      'role': role,
      if (originalRole != null && originalRole!.isNotEmpty)
        'originalRole': originalRole,
      'organization': organization,
      'studentCode': studentCode,
      'headline': headline,
      'bio': bio,
      'phone': phone,
      'portfolioUrl': portfolioUrl,
      'isProfileCompleted': isProfileCompleted,
      'isPortfolioPublic': isPortfolioPublic,
      'createdAt': createdAt,
    };
  }

  // [READ] Khởi tạo từ Map của Firebase Realtime Database
  factory UserModel.fromMap(Map<dynamic, dynamic> map, {String? defaultUid}) {
    final org = (map['organization'] ?? '').toString();
    return UserModel(
      uid: (map['uid'] ?? defaultUid ?? '').toString(),
      name: (map['name'] ?? 'Người dùng').toString(),
      email: (map['email'] ?? '').toString(),
      avatarBase64OrUrl: map['avatarBase64OrUrl']?.toString(),
      role: (map['role'] ?? UserRole.student).toString(),
      originalRole: map['originalRole']?.toString(),
      organization: org,
      studentCode: (map['studentCode'] ?? '').toString(),
      headline: (map['headline'] ?? '').toString(),
      bio: (map['bio'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      portfolioUrl: (map['portfolioUrl'] ?? '').toString(),
      isProfileCompleted: map['isProfileCompleted'] is bool
          ? map['isProfileCompleted'] as bool
          : org.trim().isNotEmpty,
      isPortfolioPublic: map['isPortfolioPublic'] is bool
          ? map['isPortfolioPublic'] as bool
          : false,
      createdAt: (map['createdAt'] ?? '').toString(),
    );
  }

  // Chuyển đổi sang JSON String để lưu offline
  String toJson() => jsonEncode(toMap());

  factory UserModel.fromJson(String source) =>
      UserModel.fromMap(jsonDecode(source) as Map<String, dynamic>);

  UserModel copyWith({
    String? uid,
    String? name,
    String? email,
    String? avatarBase64OrUrl,
    String? role,
    String? originalRole,
    String? organization,
    String? studentCode,
    String? headline,
    String? bio,
    String? phone,
    String? portfolioUrl,
    bool? isProfileCompleted,
    bool? isPortfolioPublic,
    String? createdAt,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      avatarBase64OrUrl: avatarBase64OrUrl ?? this.avatarBase64OrUrl,
      role: role ?? this.role,
      originalRole: originalRole ?? this.originalRole,
      organization: organization ?? this.organization,
      studentCode: studentCode ?? this.studentCode,
      headline: headline ?? this.headline,
      bio: bio ?? this.bio,
      phone: phone ?? this.phone,
      portfolioUrl: portfolioUrl ?? this.portfolioUrl,
      isProfileCompleted: isProfileCompleted ?? this.isProfileCompleted,
      isPortfolioPublic: isPortfolioPublic ?? this.isPortfolioPublic,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
