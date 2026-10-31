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
                child: user.avatarBase64OrUrl == null
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

        // 2. CÀI ĐẶT GIAO DIỆN DARK MODE (LƯU BẰNG SHAREDPREFERENCES)
        Card(
          child: SwitchListTile(
            secondary: Icon(
              themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Chế độ Tối (Dark Theme)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Tự động lưu trạng thái vào SharedPreferences'),
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
                    const Text('Địa Chỉ External REST API (Backend):',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'http://10.0.2.2:3000',
                    helperText:
                        'Android Emulator: 10.0.2.2:3000 | USB/ADB: localhost:3000 | LAN: IP máy',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
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
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.network_check, size: 18),
                      label: const Text('Thử Kết Nối'),
                      onPressed: () async {
                        final apiService = context.read<ApiService>();
                        final ok = await apiService.checkServerHealth();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: ok ? Colors.green : Colors.red,
                            content: Text(ok
                                ? '✅ Kết nối Backend Node.js thành công!'
                                : '❌ Không thể kết nối tới Backend tại ${ApiService.baseUrl}'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                // Chế độ Mock Offline hỗ trợ bảo vệ khi không có mạng
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.cloud_off, color: Colors.orange),
                  title: const Text('Chế độ Giả lập Offline (Mock Mode)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: const Text('Hỗ trợ test giao diện mượt mà không cần bật Server'),
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

        // 4. TIỆN ÍCH THUYẾT TRÌNH BẢO VỆ ĐỒ ÁN (ĐỔI NHANH 3 VAI TRÒ)
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
                      Text(
                        'Chuyển Đổi Nhanh Vai Trò (Trình Chiếu Giáo Viên)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: UserRole.student,
                        label: Text('Sinh Viên', style: TextStyle(fontSize: 11)),
                        icon: Icon(Icons.school, size: 14),
                      ),
                      ButtonSegment(
                        value: UserRole.employer,
                        label: Text('Tuyển Dụng', style: TextStyle(fontSize: 11)),
                        icon: Icon(Icons.business, size: 14),
                      ),
                      ButtonSegment(
                        value: UserRole.staff,
                        label: Text('Cán Bộ', style: TextStyle(fontSize: 11)),
                        icon: Icon(Icons.verified_user, size: 14),
                      ),
                    ],
                    selected: {user.role},
                    onSelectionChanged: (Set<String> newSelection) {
                      authProvider.switchRoleForDemo(newSelection.first);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Đã kích hoạt quyền: ${UserRole.getRoleLabel(newSelection.first)}'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 14),

        // 5. THÔNG TIN HỆ THỐNG
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kiến Trúc & Phân Công Nhóm 4',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                SizedBox(height: 8),
                Text('• Thành viên 1: Backend API, SQL Server, Smart Contract & Core Hash'),
                Text('• Thành viên 2: Firebase Auth, Hồ sơ Phân quyền, Màn hình Ký số & Cài đặt'),
                Text('• Thành viên 3: Luồng Quét QR, Sổ tay Sqflite & Responsive UI'),
                Divider(height: 16),
                Text('• Smart Contract: SignedRecordRegistry.sol (Ethereum Sepolia)'),
                Text('• Backend: Node.js Express + Ethers.js v6'),
                Text('• Database: SQL Server EnterpriseNotaryDB + Firebase RTDB + Sqflite'),
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
