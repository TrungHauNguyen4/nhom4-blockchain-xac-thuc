import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import '../../services/api_service.dart';
import '../vault/vault_tab.dart';
import 'verify_tab.dart';

class HomeScreen extends StatefulWidget {
  final String userRole; // 'student', 'employer', 'staff' (Tự động mở rộng tab khi TV2 ghép AuthProvider)
  final Widget? issuerTab; // Cho phép TV2 truyền màn hình Cấp phát vào khi role == 'staff'
  final Widget? settingsTab; // Cho phép TV2 truyền SettingsTab riêng vào nếu có

  const HomeScreen({
    super.key,
    this.userRole = 'student',
    this.issuerTab,
    this.settingsTab,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTabIndex = 0;
  final ApiService _apiService = ApiService();
  final GlobalKey<VaultTabState> _vaultKey = GlobalKey<VaultTabState>();

  bool get _hasStaffTab =>
      widget.userRole == 'staff' && widget.issuerTab != null;

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      VerifyTab(
        onVaultUpdated: () {
          _vaultKey.currentState?.reloadData();
        },
      ),
      VaultTab(key: _vaultKey),
      if (_hasStaffTab) widget.issuerTab!,
      widget.settingsTab ?? _buildDefaultSettingsTab(context),
    ];

    final List<NavigationDestination> destinations = [
      const NavigationDestination(
        icon: Icon(Icons.verified_outlined),
        selectedIcon: Icon(Icons.verified),
        label: 'Xác thực',
      ),
      const NavigationDestination(
        icon: Icon(Icons.folder_special_outlined),
        selectedIcon: Icon(Icons.folder_special),
        label: 'Sổ tay & Lịch sử',
      ),
      if (_hasStaffTab)
        const NavigationDestination(
          icon: Icon(Icons.workspace_premium_outlined),
          selectedIcon: Icon(Icons.workspace_premium),
          label: 'Cấp phát',
        ),
      const NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: 'Cài đặt',
      ),
    ];

    final safeIndex = _currentTabIndex >= pages.length ? 0 : _currentTabIndex;

    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(_getTitleForTab(safeIndex)),
        ),
        actions: [
          if (safeIndex == 1)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Làm mới Sổ tay & Lịch sử Offline',
              onPressed: () => _vaultKey.currentState?.reloadData(),
            ),
        ],
      ),
      body: IndexedStack(
        index: safeIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (index) {
          setState(() => _currentTabIndex = index);
          if (index == 1) {
            _vaultKey.currentState?.reloadData();
          }
        },
        destinations: destinations,
      ),
    );
  }

  String _getTitleForTab(int index) {
    if (_hasStaffTab) {
      switch (index) {
        case 0:
          return 'Xác Thực Văn Bằng Số';
        case 1:
          return 'Sổ Tay & Lịch Sử (Offline)';
        case 2:
          return 'Cấp Phát & Ký Số Văn Bằng';
        case 3:
          return 'Cài Đặt & Kết Nối';
      }
    } else {
      switch (index) {
        case 0:
          return 'Xác Thực Văn Bằng Số';
        case 1:
          return 'Sổ Tay & Lịch Sử (Offline)';
        case 2:
          return 'Cài Đặt & Kết Nối';
      }
    }
    return 'Xác Thực Văn Bằng';
  }

  // Tab Cài đặt mặc định (Hỗ trợ OrientationBuilder 1 cột dọc / 2 cột ngang)
  Widget _buildDefaultSettingsTab(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final ipController = TextEditingController(text: ApiService.baseUrl);

    final themeCard = Card(
      child: SwitchListTile(
        secondary: Icon(
          themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: const Text(
          'Chế độ Tối (Dark Theme)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Giao diện bảo vệ mắt và tiết kiệm pin'),
        value: themeProvider.isDarkMode,
        onChanged: (val) => context.read<ThemeProvider>().toggleTheme(val),
      ),
    );

    final serverCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Địa chỉ External REST API (Backend):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                hintText: 'http://10.0.2.2:3000',
                helperText: 'Emulator: 10.0.2.2:3000 | Cáp USB/ADB: localhost:3000',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Lưu Địa Chỉ'),
                  onPressed: () {
                    ApiService.updateBaseUrl(ipController.text);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Đã cập nhật máy chủ: ${ApiService.baseUrl}'),
                      ),
                    );
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('Thử Kết Nối'),
                  onPressed: () async {
                    final ok = await _apiService.checkServerHealth();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: ok ? Colors.green : Colors.red,
                        content: Text(
                          ok
                              ? '✅ Kết nối Backend Node.js thành công!'
                              : '❌ Không thể kết nối tới Backend tại ${ApiService.baseUrl}',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );

    const infoCard = Card(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thông Tin Đề Tài',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            SizedBox(height: 8),
            Text('• Đề tài: Ứng dụng Xác thực Văn bằng Chứng chỉ số Blockchain'),
            Text('• Nền tảng: Flutter & Dart'),
            Text('• Lưu trữ Cục bộ Offline: Sqflite (2 bảng: certificates & scan_history)'),
            Text('• Xử lý Realtime: StreamBuilder (async*/yield)'),
            Text('• Responsive UI: OrientationBuilder (1 cột dọc <-> 2 cột ngang) + FittedBox'),
            Text('• Mạng lưới Blockchain: Ethereum Sepolia Testnet'),
          ],
        ),
      ),
    );

    return OrientationBuilder(
      builder: (context, orientation) {
        if (orientation == Orientation.portrait) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              themeCard,
              const SizedBox(height: 16),
              serverCard,
              const SizedBox(height: 16),
              infoCard,
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      themeCard,
                      const SizedBox(height: 16),
                      serverCard,
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: SingleChildScrollView(
                  child: infoCard,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

