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
    final headlineCtrl = TextEditingController(text: user.headline);
    final bioCtrl = TextEditingController(text: user.bio);
    final phoneCtrl = TextEditingController(text: user.phone);
    final portfolioCtrl = TextEditingController(text: user.portfolioUrl);
    String selectedRole = user.role;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Chỉnh sửa Portfolio cá nhân'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!user.isStaff) ...[
                  const Text(
                    'Vai trò hiển thị:',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Sinh viên'),
                        selected: selectedRole == UserRole.student,
                        onSelected: (_) => setDialogState(
                          () => selectedRole = UserRole.student,
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('Nhà tuyển dụng'),
                        selected: selectedRole == UserRole.employer,
                        onSelected: (_) => setDialogState(
                          () => selectedRole = UserRole.employer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Họ và tên',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: headlineCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Chuyên ngành / Chức danh',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: orgCtrl,
                  decoration: InputDecoration(
                    labelText: selectedRole == UserRole.employer
                        ? 'Tên Doanh nghiệp'
                        : 'Trường học / Đơn vị đào tạo',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (selectedRole == UserRole.student || user.isStaff) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: studentCodeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Mã số sinh viên (MSSV)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: bioCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Giới thiệu bản thân',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: portfolioCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Liên kết GitHub / LinkedIn / Portfolio',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () async {
                final authProvider = context.read<AuthProvider>();
                await authProvider.updateProfile(
                  name: nameCtrl.text.trim().isEmpty
                      ? user.name
                      : nameCtrl.text.trim(),
                  organization: orgCtrl.text.trim(),
                  studentCode:
                      (selectedRole == UserRole.student || user.isStaff)
                          ? studentCodeCtrl.text.trim()
                          : null,
                  headline: headlineCtrl.text.trim(),
                  bio: bioCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  portfolioUrl: portfolioCtrl.text.trim(),
                  role: user.isStaff ? null : selectedRole,
                  markCompleted: true,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Lưu thay đổi'),
            ),
          ],
        ),
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
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Hồ Sơ & Portfolio'),
        ),
        actions: [
          IconButton(
            tooltip: 'Chỉnh sửa Portfolio',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _showEditProfileDialog(user),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. PORTFOLIO HERO BANNER
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF031226),
                  Color(0xFF0D2B4E),
                  Color(0xFF18181A),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.7),
                          width: 2.2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 48,
                        backgroundColor: const Color(0xFF0D2B4E),
                        backgroundImage: _getAvatarImage(user.avatarBase64OrUrl),
                        onBackgroundImageError:
                            _getAvatarImage(user.avatarBase64OrUrl) != null
                                ? (_, _) {}
                                : null,
                        child: _getAvatarImage(user.avatarBase64OrUrl) == null
                            ? const Icon(
                                Icons.person,
                                size: 52,
                                color: Color(0xFFECEBE6),
                              )
                            : null,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        radius: 17,
                        backgroundColor: const Color(0xFF1DA1F2),
                        child: IconButton(
                          iconSize: 17,
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
                    color: const Color(0xFFECEBE6),
                  ),
                ),
                if (user.headline.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    user.headline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  user.email,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFFECEBE6).withValues(alpha: 0.78),
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 10),
                _buildRoleBadge(user.role),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFECEBE6),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Cập nhật Portfolio'),
                  ),
                  onPressed: () => _showEditProfileDialog(user),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Nhắc bổ sung thông tin nếu đăng nhập Gmail lần đầu hoặc còn thiếu
          if (user.hasMissingPortfolioInfo) ...[
            Card(
              color: Colors.amber.withValues(alpha: 0.14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: Colors.amber.shade700.withValues(alpha: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Hồ sơ Portfolio chưa đầy đủ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Bạn có thể bổ sung Trường học/Đơn vị, MSSV và Giới thiệu bản thân để trang Portfolio hiển thị chuyên nghiệp hơn.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Bổ sung ngay'),
                        onPressed: () => _showEditProfileDialog(user),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 2. CÔNG TẮC BẬT / TẮT CÔNG KHAI PORTFOLIO KHI QUÉT VĂN BẰNG
          Card(
            child: SwitchListTile(
              secondary: Icon(
                user.isPortfolioPublic
                    ? Icons.public_rounded
                    : Icons.lock_outline_rounded,
                color: user.isPortfolioPublic ? Colors.teal : Colors.grey,
              ),
              title: const Text(
                'Công khai Portfolio khi quét văn bằng',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              subtitle: const Text(
                'Cho phép người xác thực xem giới thiệu, email, liên kết và bằng cấp của bạn (SĐT luôn được ẩn).',
                style: TextStyle(fontSize: 11.5),
              ),
              value: user.isPortfolioPublic,
              onChanged: (val) async {
                final ok = await authProvider.setPortfolioVisibility(val);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: ok ? Colors.teal : Colors.red,
                    content: Text(
                      ok
                          ? (val
                              ? 'Đã bật công khai Portfolio khi người khác quét văn bằng.'
                              : 'Đã ẩn hồ sơ Portfolio cá nhân với người khác.')
                          : 'Không thể cập nhật trạng thái công khai.',
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // 3. GIỚI THIỆU BẢN THÂN (BIO)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.person_pin_outlined,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Giới Thiệu Bản Thân',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Text(
                    user.bio.trim().isNotEmpty
                        ? user.bio
                        : 'Chưa có lời giới thiệu. Nhấn "Cập nhật Portfolio" để thêm mô tả về chuyên môn, mục tiêu nghề nghiệp hoặc thành tích của bạn.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: user.bio.trim().isNotEmpty
                          ? null
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 4. CHI TIẾT HỒ SƠ & LIÊN HỆ
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Thông Tin Định Danh & Liên Hệ',
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
                  if (user.isStudent) ...[
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      Icons.badge,
                      'Mã sinh viên (MSSV)',
                      user.studentCode.isNotEmpty
                          ? user.studentCode
                          : 'Chưa cập nhật',
                    ),
                  ],
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    Icons.phone_outlined,
                    'Số điện thoại',
                    user.phone.isNotEmpty ? user.phone : 'Chưa cập nhật',
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    Icons.link_rounded,
                    'Liên kết Portfolio / GitHub',
                    user.portfolioUrl.isNotEmpty
                        ? user.portfolioUrl
                        : 'Chưa cập nhật',
                  ),
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

          // Thông tin vai trò & Nâng cấp Cán bộ (cố định SV/HR để minh bạch)
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified_user_outlined, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Vai trò tài khoản: ${UserRole.getRoleLabel(user.role)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    user.isStaff
                        ? 'Tài khoản đã được ủy quyền Cán bộ đào tạo (có quyền ký số & cấp phát văn bằng).'
                        : 'Vai trò Sinh viên / Nhà tuyển dụng được cố định theo tài khoản để đảm bảo tính minh bạch.',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (!user.isStaff) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.key_outlined, size: 18),
                        label: const Text('Nâng cấp lên Cán bộ (Nhập mã ủy quyền)'),
                        onPressed: () =>
                            _promptStaffPasscode(context, authProvider),
                      ),
                    ),
                  ],
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
          Flexible(
            child: Text(
              UserRole.getRoleLabel(role),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: text,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
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
