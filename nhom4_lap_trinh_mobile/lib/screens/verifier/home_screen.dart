import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../widgets/glass_widgets.dart';
import '../auth/profile_screen.dart';
import '../issuer/issue_certificate_screen.dart';
import '../issuer/issued_list_screen.dart';
import '../settings/settings_tab.dart';
import '../vault/vault_tab.dart';
import 'verify_tab.dart';

/// Khung điều hướng chính kết hợp phân quyền Role (TV2) & các Tab Xác thực / Sổ tay Offline (TV3)
class HomeScreen extends StatefulWidget {
  final String? userRole;
  final Widget? issuerTab;
  final Widget? settingsTab;

  const HomeScreen({
    super.key,
    this.userRole,
    this.issuerTab,
    this.settingsTab,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTabIndex = 0;
  final GlobalKey<VaultTabState> _vaultKey = GlobalKey<VaultTabState>();

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider?>(context);
    final user = authProvider?.currentUser;
    final bool isStaff = (user?.isStaff ?? false) || widget.userRole == 'staff';

    // Danh sách màn hình linh hoạt theo vai trò (Cán bộ đào tạo mở khóa thêm Tab Cấp bằng)
    final List<Widget> pages = [
      VerifyTab(
        onVaultUpdated: () {
          _vaultKey.currentState?.reloadData();
        },
      ),
      VaultTab(key: _vaultKey),
      if (isStaff)
        widget.issuerTab ?? const IssueCertificateScreen(isEmbedded: true),
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
      const GlassNavItem(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: 'Cài đặt',
      ),
    ];

    final int safeIndex = _currentTabIndex >= pages.length ? 0 : _currentTabIndex;

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
                key: ValueKey<String>(_getTitleForTab(safeIndex, isStaff)),
                fit: BoxFit.scaleDown,
                child: Text(
                  _getTitleForTab(safeIndex, isStaff),
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

  String _getTitleForTab(int index, bool isStaff) {
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
