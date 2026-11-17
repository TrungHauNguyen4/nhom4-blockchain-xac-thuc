import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/glass_widgets.dart';
import '../auth/profile_screen.dart';
import '../employer/employer_audit_tab.dart';
import '../issuer/issue_certificate_screen.dart';
import '../issuer/issued_list_screen.dart';
import '../settings/settings_tab.dart';
import '../vault/vault_tab.dart';
import 'verify_tab.dart';

/// Khung điều hướng chính kết hợp phân quyền Role (TV2) & các Tab Xác thực / Sổ tay Offline (TV3)
class HomeScreen extends StatefulWidget {
  final String? userRole;
  final Widget? issuerTab;
  final Widget? employerTab;
  final Widget? settingsTab;

  const HomeScreen({
    super.key,
    this.userRole,
    this.issuerTab,
    this.employerTab,
    this.settingsTab,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTabIndex = 0;
  bool _checkedOnboarding = false;
  final GlobalKey<VaultTabState> _vaultKey = GlobalKey<VaultTabState>();
  final GlobalKey<EmployerAuditTabState> _employerAuditKey =
      GlobalKey<EmployerAuditTabState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_checkedOnboarding) {
      final authProvider = Provider.of<AuthProvider?>(context, listen: false);
      final user = authProvider?.currentUser;
      if (authProvider != null && user != null && !user.isProfileCompleted) {
        _checkedOnboarding = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showFirstTimeGoogleOnboardingDialog(user, authProvider);
          }
        });
      }
    }
  }

  void _showFirstTimeGoogleOnboardingDialog(
    UserModel user,
    AuthProvider authProvider,
  ) {
    final nameCtrl = TextEditingController(text: user.name);
    final orgCtrl = TextEditingController(text: user.organization);
    final studentCodeCtrl = TextEditingController(text: user.studentCode);
    final headlineCtrl = TextEditingController(text: user.headline);
    final bioCtrl = TextEditingController(text: user.bio);
    String selectedRole =
        user.isEmployer ? UserRole.employer : UserRole.student;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.waving_hand_rounded, color: Colors.amber),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hoàn tất hồ sơ lần đầu',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tài khoản Google của bạn chưa có đầy đủ thông tin. Hãy bổ sung để hiển thị Portfolio cá nhân chuẩn xác hơn:',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Vai trò của bạn:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Họ và tên',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: orgCtrl,
                    decoration: InputDecoration(
                      labelText: selectedRole == UserRole.employer
                          ? 'Doanh nghiệp / Công ty'
                          : 'Trường học / Đơn vị',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (selectedRole == UserRole.student) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: studentCodeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mã số sinh viên',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
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
                    controller: bioCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Giới thiệu ngắn',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  authProvider.dismissFirstTimeOnboarding();
                },
                child: const Text('Để sau'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final ok = await authProvider.updateProfile(
                    name: nameCtrl.text.trim().isEmpty
                        ? user.name
                        : nameCtrl.text.trim(),
                    organization: orgCtrl.text.trim(),
                    studentCode: selectedRole == UserRole.student
                        ? studentCodeCtrl.text.trim()
                        : null,
                    headline: headlineCtrl.text.trim(),
                    bio: bioCtrl.text.trim(),
                    role: selectedRole,
                    markCompleted: true,
                  );
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? 'Đã cập nhật hồ sơ cá nhân!'
                            : 'Không thể lưu thông tin lúc này.',
                      ),
                      backgroundColor: ok ? Colors.green : Colors.red,
                    ),
                  );
                },
                child: const Text('Lưu thông tin'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider?>(context);
    final user = authProvider?.currentUser;
    final bool isStaff = (user?.isStaff ?? false) || widget.userRole == 'staff';
    final bool isEmployer =
        !isStaff && ((user?.isEmployer ?? false) || widget.userRole == 'employer');

    // Danh sách màn hình linh hoạt theo vai trò:
    // - Cán bộ đào tạo (staff): mở khóa Tab "Cấp bằng"
    // - Nhà tuyển dụng (employer): mở khóa Tab "Thẩm định HR"
    final List<Widget> pages = [
      VerifyTab(
        onVaultUpdated: () {
          _vaultKey.currentState?.reloadData();
          _employerAuditKey.currentState?.reloadAuditData();
        },
      ),
      VaultTab(key: _vaultKey),
      if (isStaff)
        widget.issuerTab ?? const IssueCertificateScreen(isEmbedded: true),
      if (isEmployer)
        widget.employerTab ?? EmployerAuditTab(key: _employerAuditKey),
      widget.settingsTab ?? const SettingsTab(),
    ];

    final List<GlassNavItem> navItems = [
      const GlassNavItem(
        icon: Icons.verified_outlined,
        selectedIcon: Icons.verified,
        label: 'Xác thực',
      ),
      const GlassNavItem(
        icon: Icons.folder_special_outlined,
        selectedIcon: Icons.folder_special,
        label: 'Sổ tay & Lịch sử',
      ),
      if (isStaff)
        const GlassNavItem(
          icon: Icons.workspace_premium_outlined,
          selectedIcon: Icons.workspace_premium,
          label: 'Cấp bằng',
        ),
      if (isEmployer)
        const GlassNavItem(
          icon: Icons.business_center_outlined,
          selectedIcon: Icons.business_center_rounded,
          label: 'Thẩm định HR',
        ),
      const GlassNavItem(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: 'Cài đặt',
      ),
    ];

    final int safeIndex = _currentTabIndex >= pages.length ? 0 : _currentTabIndex;
    final String currentTitle =
        _getTitleForTab(safeIndex, isStaff: isStaff, isEmployer: isEmployer);

    return Scaffold(
      appBar: AppBar(
        centerTitle: user == null,
        title: Column(
          crossAxisAlignment:
              user == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: FittedBox(
                key: ValueKey<String>(currentTitle),
                fit: BoxFit.scaleDown,
                child: Text(
                  currentTitle,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            if (user != null)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${user.name} • ${user.roleTitle}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
          ],
        ),
        actions: [
          if (safeIndex == 1)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Làm mới danh sách đã lưu',
              onPressed: () => _vaultKey.currentState?.reloadData(),
            ),
          if (isStaff && safeIndex == 2)
            IconButton(
              tooltip: 'Danh sách văn bằng đã cấp',
              icon: const Icon(Icons.history_edu),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const IssuedListScreen(),
                  ),
                );
              },
            ),
          if (isEmployer && safeIndex == 2)
            IconButton(
              tooltip: 'Làm mới bảng thẩm định HR',
              icon: const Icon(Icons.refresh),
              onPressed: () => _employerAuditKey.currentState?.reloadAuditData(),
            ),
          if (authProvider != null)
            IconButton(
              tooltip: 'Hồ sơ cá nhân',
              icon: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white24,
                backgroundImage: _getAvatarImage(user?.avatarBase64OrUrl),
                onBackgroundImageError:
                    _getAvatarImage(user?.avatarBase64OrUrl) != null
                        ? (_, _) {}
                        : null,
                child: _getAvatarImage(user?.avatarBase64OrUrl) == null
                    ? const Icon(Icons.person, size: 18, color: Colors.white)
                    : null,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                );
              },
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: GlassScaffoldBackground(
        child: GlassAnimatedIndexedStack(
          index: safeIndex,
          children: pages,
        ),
      ),
      bottomNavigationBar: GlassyBottomNavBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (index) {
          setState(() => _currentTabIndex = index);
          if (index == 1) {
            _vaultKey.currentState?.reloadData();
          } else if (isEmployer && index == 2) {
            _employerAuditKey.currentState?.reloadAuditData();
          }
        },
        items: navItems,
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

  String _getTitleForTab(
    int index, {
    required bool isStaff,
    required bool isEmployer,
  }) {
    if (isStaff) {
      switch (index) {
        case 0:
          return 'Tra Cứu & Xác Thực Văn Bằng';
        case 1:
          return 'Sổ Tay & Lịch Sử Đã Lưu';
        case 2:
          return 'Cấp Phát Văn Bằng Mới';
        case 3:
          return 'Cài Đặt Ứng Dụng';
        default:
          return 'Xác Thực Văn Bằng';
      }
    } else if (isEmployer) {
      switch (index) {
        case 0:
          return 'Tra Cứu & Xác Thực Văn Bằng';
        case 1:
          return 'Sổ Tay & Lịch Sử Đã Lưu';
        case 2:
          return 'Trung Tâm Thẩm Định HR';
        case 3:
          return 'Cài Đặt Ứng Dụng';
        default:
          return 'Xác Thực Văn Bằng';
      }
    } else {
      switch (index) {
        case 0:
          return 'Tra Cứu & Xác Thực Văn Bằng';
        case 1:
          return 'Sổ Tay & Lịch Sử Đã Lưu';
        case 2:
          return 'Cài Đặt Ứng Dụng';
        default:
          return 'Xác Thực Văn Bằng';
      }
    }
  }
}
