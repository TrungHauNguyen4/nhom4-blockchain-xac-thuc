import 'dart:convert';

/// Vai trò người dùng trong hệ thống xác thực văn bằng
class UserRole {
  static const String student = 'student'; // Sinh viên
  static const String employer = 'employer'; // Nhà tuyển dụng
  static const String staff = 'staff'; // Cán bộ đào tạo

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
  final String organization; // Trường học / Doanh nghiệp
  final String studentCode; // MSSV (dành cho sinh viên)
  final String createdAt;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.avatarBase64OrUrl,
    required this.role,
    this.organization = '',
    this.studentCode = '',
    required this.createdAt,
  });

  bool get isStaff => role == UserRole.staff;
  bool get isEmployer => role == UserRole.employer;
  bool get isStudent => role == UserRole.student;

  String get roleTitle => UserRole.getRoleLabel(role);

  // [CREATE / UPDATE] Chuyển đổi sang Map để lưu lên Firebase Realtime Database hoặc SharedPreferences
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'avatarBase64OrUrl': avatarBase64OrUrl,
      'role': role,
      'organization': organization,
      'studentCode': studentCode,
      'createdAt': createdAt,
    };
  }

  // [READ] Khởi tạo từ Map của Firebase Realtime Database
  factory UserModel.fromMap(Map<dynamic, dynamic> map, {String? defaultUid}) {
    return UserModel(
      uid: (map['uid'] ?? defaultUid ?? '').toString(),
      name: (map['name'] ?? 'Người dùng').toString(),
      email: (map['email'] ?? '').toString(),
      avatarBase64OrUrl: map['avatarBase64OrUrl']?.toString(),
      role: (map['role'] ?? UserRole.student).toString(),
      organization: (map['organization'] ?? '').toString(),
      studentCode: (map['studentCode'] ?? '').toString(),
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
    String? organization,
    String? studentCode,
    String? createdAt,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      avatarBase64OrUrl: avatarBase64OrUrl ?? this.avatarBase64OrUrl,
      role: role ?? this.role,
      organization: organization ?? this.organization,
      studentCode: studentCode ?? this.studentCode,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
