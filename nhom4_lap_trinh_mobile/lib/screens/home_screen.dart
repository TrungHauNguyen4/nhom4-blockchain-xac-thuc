import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/hash_service.dart';
import '../services/db_service.dart';
import '../models/certificate_record.dart';
import '../providers/theme_provider.dart';
import '../widgets/progress_stream_card.dart';
import 'qr_scanner_screen.dart';
import 'verify_detail_screen.dart';

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
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );

    if (!mounted) return;
    if (scannedCode != null && scannedCode.isNotEmpty) {
      _hashInputController.text = scannedCode;
      _startVerifyHash(scannedCode, fileName: 'Văn bằng quét QR');
    }
  }

  // Thao tác 3: Xác minh bằng mã Hash
  void _startVerifyHash(String hash, {String fileName = 'Văn bằng tra cứu'}) {
    final clean = hash.trim();
    if (clean.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập mã Hash')),
      );
      return;
    }

    final apiService = context.read<ApiService>();
    setState(() {
      _verificationStream = HashService.verifyHashStream(
        dataHash: clean,
        apiService: apiService,
        fileName: fileName,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getTitleForTab(_currentTabIndex)),
        actions: [
          if (_currentTabIndex == 1)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Làm mới sổ tay',
              onPressed: _loadOfflineVault,
            ),
        ],
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          _buildVerifyTab(),
          _buildVaultTab(),
          _buildSettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) {
          setState(() => _currentTabIndex = index);
          if (index == 1) _loadOfflineVault();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.verified_outlined),
            selectedIcon: Icon(Icons.verified),
            label: 'Xác thực',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_special_outlined),
            selectedIcon: Icon(Icons.folder_special),
            label: 'Sổ tay Offline',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Cài đặt',
          ),
        ],
      ),
    );
  }

  String _getTitleForTab(int index) {
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
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 6),
                Text(
                  'Băm dữ liệu an toàn trên RAM máy khách & Đối soát sổ cái Ethereum Sepolia',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Hai nút thao tác chính: Camera QR và Tải File
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner, size: 24),
                  label: const Text('Quét mã QR'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _scanQrCode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.upload_file, size: 24),
                  label: const Text('Chọn File Bằng'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _pickAndVerifyFile,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Tùy chọn thuật toán băm trên RAM (Keccak-256 mặc định / SHA-256)
          Row(
            children: [
              const Text(
                'Thuật toán băm RAM: ',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Keccak-256'),
                selected: _selectedAlgorithm == HashAlgorithm.keccak256,
                onSelected: (_) {
                  setState(() => _selectedAlgorithm = HashAlgorithm.keccak256);
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('SHA-256'),
                selected: _selectedAlgorithm == HashAlgorithm.sha256,
                onSelected: (_) {
                  setState(() => _selectedAlgorithm = HashAlgorithm.sha256);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Ô nhập mã Hash thủ công
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Hoặc nhập mã Data Hash (bytes32):',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
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

  // ==========================================
  // TAB 3: CÀI ĐẶT & KẾT NỐI (DARK MODE & IP)
  // ==========================================
  Widget _buildSettingsTab() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final ipController = TextEditingController(text: ApiService.baseUrl);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Cài đặt Dark Mode
        Card(
          child: SwitchListTile(
            secondary: Icon(
              themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Chế độ Tối (Dark Theme)', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Bảo vệ mắt và tiết kiệm pin'),
            value: themeProvider.isDarkMode,
            onChanged: (val) => themeProvider.toggleTheme(val),
          ),
        ),
        const SizedBox(height: 16),

        // Cài đặt địa chỉ Server Backend
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Địa chỉ External REST API (Backend):',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: ipController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'http://10.0.2.2:3000',
                    helperText: 'Android Emulator: 10.0.2.2:3000 | Cáp USB/ADB: localhost:3000',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton(
                      child: const Text('Lưu Địa Chỉ'),
                      onPressed: () async {
                        await ApiService.saveBaseUrl(ipController.text);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Đã lưu máy chủ: ${ApiService.baseUrl}')),
                        );
                      },
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      child: const Text('Thử Kết Nối'),
                      onPressed: () async {
                        final apiService = context.read<ApiService>();
                        final ok = await apiService.checkServerHealth();
                        if (!mounted) return;
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
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Giới thiệu đề tài
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Thông Tin Đề Tài', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                SizedBox(height: 8),
                Text('• Đề tài: Ứng dụng Xác thực Văn bằng Chứng chỉ số Blockchain'),
                Text('• Nền tảng: Flutter & Dart'),
                Text('• Lưu trữ Cục bộ: Sqflite'),
                Text('• Xử lý Realtime: StreamBuilder (async*/yield)'),
                Text('• Mạng lưới Blockchain: Ethereum Sepolia Testnet'),
                Text('• Kiến trúc: BaaS Client-Server (REST API ngoài)'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
