import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 400,
        maxHeight: 400,
        imageQuality: 75,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        final base64String = base64Encode(bytes);

        if (!mounted) return;
        final authProvider = context.read<AuthProvider>();
        final ok = await authProvider.updateAvatar(base64String);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: ok ? Colors.green : Colors.red,
            content: Text(ok
                ? 'Đã cập nhật ảnh đại diện thành công!'
                : 'Không thể cập nhật ảnh đại diện.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi chọn ảnh: $e')),
      );
    }
  }

  void _showAvatarOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Chụp ảnh từ Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickAvatar(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Chọn ảnh từ Thư viện'),
              onTap: () {
                Navigator.pop(context);
                _pickAvatar(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditProfileDialog(UserModel user) {
    final nameCtrl = TextEditingController(text: user.name);
    final orgCtrl = TextEditingController(text: user.organization);
    final studentCodeCtrl = TextEditingController(text: user.studentCode);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chỉnh sửa thông tin'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Họ và tên'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: orgCtrl,
                decoration: InputDecoration(
                  labelText: user.isEmployer
                      ? 'Tên Doanh nghiệp'
                      : 'Trường học / Đơn vị đào tạo',
                ),
              ),
              if (user.isStudent) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: studentCodeCtrl,
                  decoration: const InputDecoration(labelText: 'Mã số sinh viên (MSSV)'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              final authProvider = context.read<AuthProvider>();
              await authProvider.updateProfile(
                name: nameCtrl.text.trim(),
                organization: orgCtrl.text.trim(),
                studentCode: studentCodeCtrl.text.trim(),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Lưu thay đổi'),
          ),
        ],
      ),
    );
  }

  void _promptStaffPasscode(BuildContext context, AuthProvider authProvider) {
    final codeCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Colors.amber),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Kích Hoạt Quyền Cán Bộ',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quyền Cán bộ có thể tiêu tốn phí Gas trên Blockchain. Vui lòng nhập mã ủy quyền bí mật của nhà trường:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(
                labelText: 'Mã ủy quyền Cán bộ',
                prefixIcon: Icon(Icons.key),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              final ok = await authProvider.upgradeToStaff(codeCtrl.text.trim());
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: ok ? Colors.green : Colors.red,
                  content: Text(ok
                      ? 'Đã kích hoạt quyền Cán bộ đào tạo thành công!'
                      : (authProvider.errorMessage ?? 'Mã ủy quyền không chính xác!')),
                ),
              );
            },
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đăng xuất'),
        content: const Text('Bạn có chắc chắn muốn đăng xuất khỏi ứng dụng không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ở lại'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context); // Đóng dialog
              Navigator.pop(context); // Trở về màn hình trước
              context.read<AuthProvider>().logout();
            },
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Xóa tài khoản', style: TextStyle(color: Colors.red)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hành động này sẽ XÓA VĨNH VIỄN:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('• Danh tính tài khoản trên Firebase Authentication.'),
            Text('• Toàn bộ hồ sơ cá nhân trên Firebase Realtime Database.'),
            Text('• Dữ liệu phiên đăng nhập trên thiết bị này.'),
            SizedBox(height: 12),
            Text(
              'Lưu ý: Các văn bằng đã được ghi lên Blockchain Ethereum Sepolia trước đó vẫn sẽ được bảo toàn tính bất biến.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy bỏ'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx); // Đóng dialog
              final auth = context.read<AuthProvider>();
              final ok = await auth.deleteAccount();
              if (!mounted) return;
              if (ok) {
                Navigator.pop(context); // Thoát khỏi ProfileScreen
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: Colors.green,
                    content: Text('Đã xóa vĩnh viễn tài khoản thành công!'),
                  ),
                );
              } else if (auth.errorMessage != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.red.shade700,
                    content: Text(auth.errorMessage!),
                  ),
                );
              }
            },
            child: const Text('Xác nhận Xóa'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hồ Sơ Cá Nhân')),
        body: const Center(child: Text('Chưa có thông tin người dùng')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hồ Sơ Cá Nhân'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _showEditProfileDialog(user),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header: Ảnh đại diện & Tên
          Center(
            child: Column(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 54,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      backgroundImage: _getAvatarImage(user.avatarBase64OrUrl),
                      onBackgroundImageError:
                          _getAvatarImage(user.avatarBase64OrUrl) != null
                              ? (_, _) {}
                              : null,
                      child: _getAvatarImage(user.avatarBase64OrUrl) == null
                          ? Icon(
                              Icons.person,
                              size: 58,
                              color: theme.colorScheme.onPrimaryContainer,
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: theme.colorScheme.primary,
                        child: IconButton(
                          iconSize: 18,
                          color: Colors.white,
                          icon: const Icon(Icons.camera_alt),
                          onPressed: _showAvatarOptions,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  user.name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                _buildRoleBadge(user.role),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Chi tiết hồ sơ
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Thông Tin Tài Khoản',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const Divider(height: 20),
                  _buildInfoRow(
                    Icons.account_balance,
                    user.isEmployer ? 'Đơn vị / Doanh nghiệp' : 'Trường đào tạo',
                    user.organization.isNotEmpty
                        ? user.organization
                        : 'Chưa cập nhật',
                  ),
                  if (user.isStudent && user.studentCode.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      Icons.badge,
                      'Mã sinh viên (MSSV)',
                      user.studentCode,
                    ),
                  ],
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    Icons.calendar_today,
                    'Thời điểm tạo tài khoản',
                    user.createdAt,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    Icons.security,
                    'Mã tài khoản',
                    user.uid,
                    monospace: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Chuyển đổi nhanh vai trò sử dụng
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.swap_horiz, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Chuyển đổi nhanh vai trò sử dụng',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                      segments: const [
                        ButtonSegment(
                          value: UserRole.student,
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Sinh Viên', style: TextStyle(fontSize: 11)),
                          ),
                          icon: Icon(Icons.school, size: 14),
                        ),
                        ButtonSegment(
                          value: UserRole.employer,
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Doanh Nghiệp', style: TextStyle(fontSize: 11)),
                          ),
                          icon: Icon(Icons.business, size: 14),
                        ),
                        ButtonSegment(
                          value: UserRole.staff,
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Cán Bộ', style: TextStyle(fontSize: 11)),
                          ),
                          icon: Icon(Icons.verified_user, size: 14),
                        ),
                      ],
                      selected: {user.role},
                      onSelectionChanged: (Set<String> newSelection) {
                        final targetRole = newSelection.first;
                        if (targetRole == UserRole.staff && !user.isStaff) {
                          _promptStaffPasscode(context, authProvider);
                        } else {
                          authProvider.switchRoleForDemo(targetRole);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Đã chuyển sang vai trò: ${UserRole.getRoleLabel(targetRole)}'),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Nút Đăng xuất
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.redAccent),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('ĐĂNG XUẤT TÀI KHOẢN'),
            onPressed: _confirmLogout,
          ),
          const SizedBox(height: 10),

          // Nút Xóa tài khoản vĩnh viễn
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade600,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.delete_forever_outlined, size: 18),
            label: const Text(
              'Xóa vĩnh viễn tài khoản',
              style: TextStyle(
                decoration: TextDecoration.underline,
                fontSize: 12,
              ),
            ),
            onPressed: _confirmDeleteAccount,
          ),
        ],
      ),
    );
  }

  ImageProvider? _getAvatarImage(String? avatar) {
    if (avatar == null || avatar.isEmpty) return null;
    if (avatar.startsWith('http://') || avatar.startsWith('https://')) {
      return NetworkImage(avatar);
    }
    try {
      final bytes = base64Decode(avatar);
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  Widget _buildRoleBadge(String role) {
    Color bg;
    Color text = Colors.white;
    IconData icon;

    switch (role) {
      case UserRole.staff:
        bg = const Color(0xFF673AB7); // Tím công quyền
        icon = Icons.verified_user;
        break;
      case UserRole.employer:
        bg = const Color(0xFFEF6C00); // Cam doanh nghiệp
        icon = Icons.business_center;
        break;
      case UserRole.student:
      default:
        bg = const Color(0xFF2E7D32); // Xanh lá học sinh
        icon = Icons.school;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: text),
          const SizedBox(width: 6),
          Text(
            UserRole.getRoleLabel(role),
            style: TextStyle(
              color: text,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value,
      {bool monospace = false}) {
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: mutedColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: mutedColor),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: monospace ? 'monospace' : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
