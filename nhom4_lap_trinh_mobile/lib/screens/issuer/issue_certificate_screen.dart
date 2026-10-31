import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/hash_service.dart';
import '../../widgets/progress_stream_card.dart';
import 'issued_list_screen.dart';

/// Màn hình Cấp phát & Ký số Văn bằng dành riêng cho Cán bộ đào tạo
/// Xây dựng theo Mục 2.2 và Mục 6 (kehoach.md)
class IssueCertificateScreen extends StatefulWidget {
  const IssueCertificateScreen({super.key});

  @override
  State<IssueCertificateScreen> createState() => _IssueCertificateScreenState();
}

class _IssueCertificateScreenState extends State<IssueCertificateScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controller thông tin văn bằng
  final _studentNameController = TextEditingController();
  final _studentCodeController = TextEditingController();
  final _degreeNameController = TextEditingController();
  final _issuerNameController = TextEditingController();

  // Dữ liệu file đã chọn trên RAM
  Uint8List? _selectedFileBytes;
  String? _selectedFileName;
  String _selectedFileType = 'PDF'; // 'PDF' hoặc 'IMAGE'
  bool _isImagePreview = false;

  // Tùy chọn thuật toán băm
  HashAlgorithm _selectedAlgorithm = HashAlgorithm.keccak256;

  // Stream tiến trình ký số cho StreamBuilder
  Stream<NotarizationProgress>? _notarizeStream;

  // Kết quả sau khi ký thành công
  NotarizationProgress? _completedProgress;

  @override
  void initState() {
    super.initState();
    // Tự động điền đơn vị cấp bằng từ Hồ sơ Cán bộ đào tạo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().currentUser;
      if (user != null && user.organization.isNotEmpty) {
        _issuerNameController.text = user.organization;
      } else {
        _issuerNameController.text = 'Trường Đại học Công nghệ';
      }
    });
  }

  @override
  void dispose() {
    _studentNameController.dispose();
    _studentCodeController.dispose();
    _degreeNameController.dispose();
    _issuerNameController.dispose();
    super.dispose();
  }

  // ========================================================
  // THAO TÁC 1: Chọn Ảnh bằng cấp (Camera hoặc Thư viện)
  // ========================================================
  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() {
          _selectedFileBytes = bytes;
          _selectedFileName = file.name;
          _selectedFileType = 'IMAGE';
          _isImagePreview = true;
          _notarizeStream = null;
          _completedProgress = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi chọn ảnh: $e')),
      );
    }
  }

  // ========================================================
  // THAO TÁC 2: Chọn Tài liệu PDF / File từ Bộ nhớ máy
  // ========================================================
  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final bytes = file.bytes;

        if (bytes == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể đọc dữ liệu file trên RAM')),
          );
          return;
        }

        final isImg = file.extension == 'png' ||
            file.extension == 'jpg' ||
            file.extension == 'jpeg';

        setState(() {
          _selectedFileBytes = bytes;
          _selectedFileName = file.name;
          _selectedFileType = isImg ? 'IMAGE' : 'PDF';
          _isImagePreview = isImg;
          _notarizeStream = null;
          _completedProgress = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi chọn tài liệu: $e')),
      );
    }
  }

  // ========================================================
  // TIẾN TRÌNH KÝ SỐ BLOCKCHAIN THỜI GIAN THỰC (StreamBuilder)
  // ========================================================
  void _startNotarization() {
    if (_selectedFileBytes == null || _selectedFileName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Vui lòng chọn Ảnh hoặc File PDF văn bằng trước khi ký'),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final apiService = context.read<ApiService>();
    final user = context.read<AuthProvider>().currentUser;

    setState(() {
      _completedProgress = null;
      _notarizeStream = HashService.notarizeFileStream(
        fileBytes: _selectedFileBytes!,
        fileName: _selectedFileName!,
        apiService: apiService,
        fileType: _selectedFileType,
        studentName: _studentNameController.text.trim(),
        studentCode: _studentCodeController.text.trim(),
        degreeName: _degreeNameController.text.trim(),
        issuerName: _issuerNameController.text.trim(),
        createdByEmail: user?.email,
        algorithm: _selectedAlgorithm,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = context.watch<AuthProvider>().currentUser;

    // Kiểm tra quyền: Chỉ vai trò Cán bộ đào tạo mới được ký
    if (user == null || !user.isStaff) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cấp Phát & Ký Số')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_person, size: 70, color: Colors.amber.shade700),
                const SizedBox(height: 16),
                const Text(
                  'Quyền truy cập bị giới hạn',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Chức năng Ký số và Niêm phong văn bằng lên Blockchain chỉ dành cho Cán bộ đào tạo (Staff).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ký Số Văn Bằng (Cán Bộ)'),
        actions: [
          IconButton(
            tooltip: 'Sổ bộ văn bằng đã ký',
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
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Khung Chọn Nguồn Tài Liệu (Ảnh hoặc PDF)
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.upload_file,
                                color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            const Text(
                              'Bước 1: Chọn Tài Liệu / Ảnh Cần Ký Số',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 8),
                                  backgroundColor: theme.colorScheme.primary,
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.photo_camera, size: 20),
                                label: const Text('Chụp / Chọn Ảnh',
                                    style: TextStyle(fontSize: 12)),
                                onPressed: () => _pickImage(ImageSource.gallery),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 8),
                                ),
                                icon: const Icon(Icons.picture_as_pdf,
                                    size: 20, color: Colors.redAccent),
                                label: const Text('Tài Liệu PDF',
                                    style: TextStyle(fontSize: 12)),
                                onPressed: _pickDocument,
                              ),
                            ),
                          ],
                        ),

                        // Khung xem trước file đã chọn
                        if (_selectedFileBytes != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                if (_isImagePreview)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.memory(
                                      _selectedFileBytes!,
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                else
                                  const Icon(Icons.description,
                                      size: 40, color: Colors.blue),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedFileName ?? 'Tài liệu',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        'Loại: $_selectedFileType • Dung lượng: ${(_selectedFileBytes!.lengthInBytes / 1024).toStringAsFixed(1)} KB',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.check_circle,
                                    color: Colors.green),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Nhập Thông Tin Văn Bằng
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.badge, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            const Text(
                              'Bước 2: Thông Tin Sinh Viên & Bằng Cấp',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _studentNameController,
                          decoration: const InputDecoration(
                            labelText: 'Họ và tên sinh viên *',
                            hintText: 'VD: Trần Minh Trí',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Vui lòng nhập họ tên sinh viên';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _studentCodeController,
                          decoration: const InputDecoration(
                            labelText: 'Mã số sinh viên (MSSV) *',
                            hintText: 'VD: 20261104',
                            prefixIcon: Icon(Icons.numbers),
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Vui lòng nhập mã sinh viên';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _degreeNameController,
                          decoration: const InputDecoration(
                            labelText: 'Tên văn bằng / Chứng chỉ *',
                            hintText: 'VD: Bằng Kỹ sư Công nghệ Thông tin',
                            prefixIcon: Icon(Icons.workspace_premium),
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Vui lòng nhập tên văn bằng';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _issuerNameController,
                          decoration: const InputDecoration(
                            labelText: 'Đơn vị cấp phát *',
                            hintText: 'VD: Trường Đại học Công nghệ TP.HCM',
                            prefixIcon: Icon(Icons.account_balance),
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Vui lòng nhập đơn vị cấp phát';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Chọn thuật toán băm
                        Row(
                          children: [
                            const Text('Mã băm: ',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('Keccak-256 (Chuẩn Sepolia)',
                                  style: TextStyle(fontSize: 11)),
                              selected:
                                  _selectedAlgorithm == HashAlgorithm.keccak256,
                              onSelected: (_) {
                                setState(() {
                                  _selectedAlgorithm = HashAlgorithm.keccak256;
                                });
                              },
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              label: const Text('SHA-256',
                                  style: TextStyle(fontSize: 11)),
                              selected:
                                  _selectedAlgorithm == HashAlgorithm.sha256,
                              onSelected: (_) {
                                setState(() {
                                  _selectedAlgorithm = HashAlgorithm.sha256;
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Nút Ký số
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF673AB7), // Tím ký số
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.lock_clock),
                    label: const Text(
                      'KÝ SỐ VÀ NIÊM PHONG LÊN BLOCKCHAIN',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _startNotarization,
                  ),
                ),
                const SizedBox(height: 16),

                // 3. TIẾN TRÌNH STREAMBUILDER (Thực hiện theo Mục 2.2 kehoach.md)
                if (_notarizeStream != null)
                  ProgressStreamCard.notarization(
                    stream: _notarizeStream!,
                    onNotarizationCompleted: (progress) {
                      setState(() {
                        _completedProgress = progress;
                      });
                    },
                  ),

                // 4. BIÊN LAI KÝ SỐ & MÃ QR XUẤT RA (qr_flutter)
                if (_completedProgress != null &&
                    _completedProgress!.step == NotarizationStep.completed) ...[
                  const SizedBox(height: 16),
                  _buildSuccessReceiptCard(_completedProgress!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Khung Biên lai kết quả ký số kèm Mã QR
  Widget _buildSuccessReceiptCard(NotarizationProgress progress) {
    final theme = Theme.of(context);
    final hash = progress.hash ?? '';
    final txHash = progress.txHash ?? '0x...';

    return Card(
      elevation: 4,
      color: Colors.green.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.green, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.verified, color: Colors.green, size: 28),
                const SizedBox(width: 8),
                Text(
                  'VĂN BẰNG ĐÃ ĐƯỢC NIÊM PHONG',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.green.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            // Mã QR Sinh Tự Động (qr_flutter)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: QrImageView(
                data: hash,
                version: QrVersions.auto,
                size: 180,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Mã QR chứng thực văn bằng',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
            const Text(
              'Sinh viên hoặc Nhà tuyển dụng có thể dùng app quét mã này để kiểm tra',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 16),

            // Chi tiết kỹ thuật
            _buildReceiptRow('Sinh viên:', _studentNameController.text),
            _buildReceiptRow('Văn bằng:', _degreeNameController.text),
            _buildReceiptRow('Đơn vị cấp:', _issuerNameController.text),
            _buildReceiptRow('TxHash:', txHash, isMono: true),
            _buildReceiptRow('DataHash:', hash, isMono: true),
            if (progress.blockNumber != null)
              _buildReceiptRow('Block Number:', '#${progress.blockNumber}'),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value, {bool isMono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontFamily: isMono ? 'monospace' : null,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
