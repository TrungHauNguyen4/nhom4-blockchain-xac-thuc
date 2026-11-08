import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/api_service.dart';
import '../auth/profile_screen.dart';

/// Tab Cài Đặt, Cấu Hình IP Backend & Dark Mode (Thành viên 2 phụ trách)
/// Tích hợp SharedPreferences lưu cấu hình bền vững theo chuẩn Chương 9 & 12
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late final TextEditingController _ipController;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: ApiService.baseUrl);
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
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
              Navigator.pop(context);
              context.read<AuthProvider>().logout();
            },
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. THẺ HỒ SƠ CÁ NHÂN NHANH
        if (user != null)
          Card(
            elevation: 2,
            child: ListTile(
              leading: CircleAvatar(
                radius: 26,
                backgroundColor: theme.colorScheme.primaryContainer,
                backgroundImage: _getAvatarImage(user.avatarBase64OrUrl),
                onBackgroundImageError:
                    _getAvatarImage(user.avatarBase64OrUrl) != null
                        ? (_, _) {}
                        : null,
                child: _getAvatarImage(user.avatarBase64OrUrl) == null
                    ? Icon(Icons.person, color: theme.colorScheme.onPrimaryContainer)
                    : null,
              ),
              title: Text(
                user.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.email, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getRoleColor(user.role).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      user.roleTitle,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _getRoleColor(user.role),
                      ),
                    ),
                  ),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                );
              },
            ),
          ),
        const SizedBox(height: 14),

        // 2. CÀI ĐẶT GIAO DIỆN DARK MODE
        Card(
          child: SwitchListTile(
            secondary: Icon(
              themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Giao diện Tối',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Dịu mắt hơn khi sử dụng vào ban đêm'),
            value: themeProvider.isDarkMode,
            onChanged: (val) => themeProvider.toggleTheme(val),
          ),
        ),
        const SizedBox(height: 14),

        // 3. CÀI ĐẶT ĐỊA CHỈ SERVER BACKEND & KIỂM TRA KẾT NỐI
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.dns, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Địa chỉ máy chủ kết nối:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'http://localhost:3000',
                    helperText:
                        'Cắm cáp USB: localhost:3000 | Chung Wi-Fi: IP máy tính',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.save, size: 18),
                      label: const Text('Lưu Địa Chỉ'),
                      onPressed: () async {
                        await ApiService.saveBaseUrl(_ipController.text);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.green,
                            content: Text('Đã lưu địa chỉ máy chủ: ${ApiService.baseUrl}'),
                          ),
                        );
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.network_check, size: 18),
                      label: const Text('Thử Kết Nối'),
                      onPressed: () async {
                        await ApiService.saveBaseUrl(_ipController.text);
                        if (!context.mounted) return;
                        final apiService = context.read<ApiService>();
                        final backendOk = await apiService.checkServerHealth();
                        if (!context.mounted) return;
                        if (backendOk) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Colors.green,
                              content: Text(
                                '✅ Đã kết nối thành công với máy chủ cấp bằng!',
                              ),
                            ),
                          );
                          return;
                        }

                        final sepoliaOk =
                            await apiService.checkSepoliaRpcHealth();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor:
                                sepoliaOk ? Colors.teal : Colors.red,
                            content: Text(
                              sepoliaOk
                                  ? '🌐 Máy tính đang tắt — Đã kết nối trực tiếp sổ gốc trực tuyến (Tra cứu văn bằng hoạt động 100%!)'
                                  : '❌ Không có kết nối mạng (Chỉ xem được các văn bằng đã lưu trên máy)',
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                // Chế độ dùng thử
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.cloud_off, color: Colors.orange),
                  title: const Text('Chế độ dùng thử (Không cần máy chủ)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: const Text('Dùng thử tính năng cấp bằng mẫu khi chưa bật máy tính'),
                  value: ApiService.useMockWhenOffline,
                  onChanged: (val) async {
                    await ApiService.setMockMode(val);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 4. TIỆN ÍCH CHUYỂN ĐỔI NHANH VAI TRÒ
        if (user != null)
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.admin_panel_settings, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Chuyển đổi nhanh vai trò sử dụng',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
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
                            child: Text('Tuyển Dụng', style: TextStyle(fontSize: 11)),
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
                                  'Đã kích hoạt quyền: ${UserRole.getRoleLabel(targetRole)}'),
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
        const SizedBox(height: 14),

        // 5. THÔNG TIN ỨNG DỤNG
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Giới Thiệu Ứng Dụng (Nhóm 4)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                SizedBox(height: 8),
                Text('• Tra cứu văn bằng, chứng chỉ nhanh chóng qua mã QR hoặc tệp PDF/Ảnh.'),
                Text('• Cấp phát văn bằng điện tử có chữ ký số chống làm giả.'),
                Text('• Hỗ trợ lưu văn bằng về điện thoại để xuất trình ngay cả khi không có mạng.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // NÚT ĐĂNG XUẤT
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
        const SizedBox(height: 20),
      ],
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

  Color _getRoleColor(String role) {
    switch (role) {
      case UserRole.staff:
        return const Color(0xFF673AB7);
      case UserRole.employer:
        return const Color(0xFFEF6C00);
      case UserRole.student:
      default:
        return const Color(0xFF2E7D32);
    }
  }
}
