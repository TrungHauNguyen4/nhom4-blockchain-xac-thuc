import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/hash_service.dart';
import '../services/db_service.dart';
import '../models/certificate_record.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../widgets/progress_stream_card.dart';
import 'qr_scanner_screen.dart';
import 'verify_detail_screen.dart';
import 'issuer/issue_certificate_screen.dart';
import 'settings/settings_tab.dart';
import 'auth/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTabIndex = 0;
  HashAlgorithm _selectedAlgorithm = HashAlgorithm.keccak256;

  // Controller nhập Hash thủ công
  final TextEditingController _hashInputController = TextEditingController();

  // Stream tiến trình băm và xác thực cho StreamBuilder
  Stream<VerificationProgress>? _verificationStream;

  // Danh sách chứng chỉ offline
  List<CertificateRecord> _offlineVault = [];
  bool _isLoadingVault = false;

  @override
  void initState() {
    super.initState();
    _loadOfflineVault();
  }

  Future<void> _loadOfflineVault() async {
    setState(() => _isLoadingVault = true);
    try {
      final list = await DatabaseService.instance.getAllCertificates();
      if (!mounted) return;
      setState(() {
        _offlineVault = list;
        _isLoadingVault = false;
      });
    } catch (e) {
      debugPrint('[HomeScreen] Bỏ qua đọc Sqflite trên môi trường không hỗ trợ: $e');
      if (!mounted) return;
      setState(() => _isLoadingVault = false);
    }
  }

  // Thao tác 1: Chọn file PDF/Ảnh từ máy -> Băm Keccak256 trên RAM -> Verify
  Future<void> _pickAndVerifyFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final Uint8List? bytes = file.bytes;

        if (bytes == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Không thể đọc dữ liệu file nhị phân')),
            );
          }
          return;
        }

        if (!mounted) return;
        final apiService = context.read<ApiService>();
        setState(() {
          _verificationStream = HashService.verifyFileStream(
            fileBytes: bytes,
            fileName: file.name,
            apiService: apiService,
            algorithm: _selectedAlgorithm,
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi chọn file: $e')),
      );
    }
  }

  // Thao tác 2: Mở Camera quét mã QR
  Future<void> _scanQrCode() async {
    final scannedHash = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );

    if (scannedHash != null && scannedHash.isNotEmpty) {
      _hashInputController.text = scannedHash;
      _startVerifyHash(scannedHash);
    }
  }

  // Thao tác 3: Bắt đầu xác minh Hash bằng StreamBuilder
  void _startVerifyHash(String hash) {
    final clean = hash.trim();
    if (clean.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập mã băm Keccak-256 (0x...)')),
      );
      return;
    }

    final apiService = context.read<ApiService>();
    setState(() {
      _verificationStream = HashService.verifyHashStream(
        dataHash: clean,
        apiService: apiService,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;
    final isStaff = user?.isStaff ?? false;

    // Danh sách tab linh hoạt theo vai trò người dùng (Staff có thêm Tab Ký số)
    final List<Widget> pages = [
      _buildVerifyTab(),
      _buildVaultTab(),
      if (isStaff) const IssueCertificateScreen(),
      const SettingsTab(),
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
        label: 'Sổ tay Offline',
      ),
      if (isStaff)
        const NavigationDestination(
          icon: Icon(Icons.rate_review_outlined),
          selectedIcon: Icon(Icons.rate_review),
          label: 'Cấp bằng',
        ),
      const NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: 'Cài đặt',
      ),
    ];

    if (_currentTabIndex >= pages.length) {
      _currentTabIndex = 0;
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getTitleForTab(_currentTabIndex, isStaff),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            if (user != null)
              Text(
                '${user.name} • ${user.roleTitle}',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          if (_currentTabIndex == 1)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Làm mới sổ tay',
              onPressed: _loadOfflineVault,
            ),
          // Nút Avatar mở Hồ sơ người dùng
          IconButton(
            tooltip: 'Hồ sơ người dùng',
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white24,
              backgroundImage: _getAvatarImage(user?.avatarBase64OrUrl),
              child: user?.avatarBase64OrUrl == null
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
      body: IndexedStack(
        index: _currentTabIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) {
          setState(() => _currentTabIndex = index);
          if (index == 1) _loadOfflineVault();
        },
        destinations: destinations,
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
          return 'Xác Thực Văn Bằng Số';
        case 1:
          return 'Sổ Tay Văn Bằng (Offline)';
        case 2:
          return 'Ký Số & Cấp Phát Bằng';
        case 3:
          return 'Cài Đặt & Kết Nối';
        default:
          return 'Xác Thực Văn Bằng';
      }
    } else {
      switch (index) {
        case 0:
          return 'Xác Thực Văn Bằng Số';
        case 1:
          return 'Sổ Tay Văn Bằng (Offline)';
        case 2:
          return 'Cài Đặt & Kết Nối';
        default:
          return 'Xác Thực Văn Bằng';
      }
    }
  }

  // ==========================================
  // TAB 1: XÁC THỰC VĂN BẰNG (GỒM STREAMBUILDER)
  // ==========================================
  Widget _buildVerifyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner giới thiệu
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.secondary,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kiểm Định Bằng Cấp Blockchain',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Mọi dữ liệu văn bằng được đối soát trực tiếp với Smart Contract trên mạng Ethereum Sepolia và SQL Server.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tùy chọn thuật toán băm trên RAM
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.memory, size: 20),
                  const SizedBox(width: 8),
                  const Text('Thuật toán băm RAM: ',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const Spacer(),
                  DropdownButton<HashAlgorithm>(
                    value: _selectedAlgorithm,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(
                        value: HashAlgorithm.keccak256,
                        child: Text('Keccak-256 (Mặc định)',
                            style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: HashAlgorithm.sha256,
                        child:
                            Text('SHA-256', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedAlgorithm = val);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2 nút hành động: Quét QR & Chọn File
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Quét Mã QR'),
                  onPressed: _scanQrCode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Chọn File/Ảnh'),
                  onPressed: _pickAndVerifyFile,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Nhập mã Hash thủ công
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tra cứu trực tiếp bằng mã băm Hash:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _hashInputController,
                    decoration: InputDecoration(
                      hintText: '0x...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => _startVerifyHash(_hashInputController.text),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // TIÊU CHÍ BẮT BUỘC: Xử lý thời gian thực bằng StreamBuilder (async*/yield)
          if (_verificationStream != null)
            ProgressStreamCard.verification(
              stream: _verificationStream!,
              onViewVerificationDetail: (data) {
                final targetHash = (data.hash != null && data.hash!.isNotEmpty)
                    ? data.hash!
                    : _hashInputController.text;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => VerifyDetailScreen(
                      record: data.record,
                      searchedHash: targetHash.isEmpty ? 'Chưa xác định' : targetHash,
                    ),
                  ),
                ).then((_) => _loadOfflineVault());
              },
            ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: SỔ TAY VĂN BẰNG OFFLINE (SQFLITE)
  // ==========================================
  Widget _buildVaultTab() {
    if (_isLoadingVault) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_offlineVault.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 70, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('Chưa có văn bằng nào được lưu offline',
                style: TextStyle(fontSize: 15, color: Colors.grey)),
            const SizedBox(height: 6),
            const Text('Hãy xác thực và bấm nút Lưu để xem lại khi không có mạng!',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _offlineVault.length,
      itemBuilder: (context, index) {
        final item = _offlineVault[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.green,
              child: Icon(Icons.verified, color: Colors.white),
            ),
            title: Text(
              item.fileName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Cấp ngày: ${item.formattedBlockchainDate}', style: const TextStyle(fontSize: 12)),
                Text('Hash: ${item.dataHash.substring(0, 14)}...',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => _confirmDelete(item),
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VerifyDetailScreen(
                    record: item,
                    searchedHash: item.dataHash,
                    isFromOfflineVault: true,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(CertificateRecord item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa văn bằng "${item.fileName}" khỏi bộ nhớ máy không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm == true && item.id != null) {
      await DatabaseService.instance.deleteCertificate(item.id!);
      _loadOfflineVault();
    }
  }
}
