import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/certificate_record.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/db_service.dart';
import '../../services/hash_service.dart';
import '../../services/local_file_save_service.dart';
import '../../widgets/progress_stream_card.dart';
import '../verifier/verify_detail_screen.dart';
import 'issued_list_screen.dart';

/// Màn hình Cấp phát & Ký số Văn bằng dành riêng cho Cán bộ đào tạo
/// Xây dựng theo Mục 2.2, Mục 3.4 (OrientationBuilder + FittedBox) và Mục 6 (kehoach.md)
class IssueCertificateScreen extends StatefulWidget {
  final bool isEmbedded;

  const IssueCertificateScreen({super.key, this.isEmbedded = false});

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

  // Stream tiến trình ký số an toàn (Broadcast để không lỗi khi xoay màn hình / chuyển tab)
  StreamController<NotarizationProgress>? _notarizeController;
  StreamSubscription<NotarizationProgress>? _notarizeSub;
  Stream<NotarizationProgress>? _notarizeStream;
  bool _isNotarizing = false;

  // Kết quả sau khi ký thành công hoặc lỗi trùng lặp
  NotarizationProgress? _completedProgress;
  NotarizationProgress? _errorProgress;
  bool _isSavingSignedFile = false;
  SavedFileResult? _lastSavedResult;

  @override
  void initState() {
    super.initState();
    // Tự động điền đơn vị cấp bằng từ Hồ sơ Cán bộ đào tạo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
    _notarizeSub?.cancel();
    _notarizeController?.close();
    _studentNameController.dispose();
    _studentCodeController.dispose();
    _degreeNameController.dispose();
    _issuerNameController.dispose();
    super.dispose();
  }

  void _disposeActiveStream() {
    _notarizeSub?.cancel();
    _notarizeSub = null;
    _notarizeController?.close();
    _notarizeController = null;
  }

  bool get _hasUnsavedDraftOrInProgress {
    if (_isNotarizing) return true;
    if (_completedProgress != null) return false;
    return _selectedFileBytes != null ||
        _studentNameController.text.trim().isNotEmpty ||
        _studentCodeController.text.trim().isNotEmpty ||
        _degreeNameController.text.trim().isNotEmpty;
  }

  Future<void> _confirmExitScreen() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _isNotarizing
              ? 'Đang xử lý ký số Blockchain'
              : 'Chưa hoàn tất cấp văn bằng',
        ),
        content: Text(
          _isNotarizing
              ? 'Hệ thống đang gửi giao dịch ký số. Bạn có chắc muốn rời khỏi màn hình này không?'
              : 'Bạn đã chọn tài liệu hoặc nhập thông tin nhưng chưa bấm cấp bằng. Bạn có muốn thoát không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ở lại'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Thoát'),
          ),
        ],
      ),
    );

    if (shouldExit == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  // ========================================================
  // THAO TÁC 1: Chọn Ảnh bằng cấp (Camera hoặc Thư viện)
  // ========================================================
  void _showImageSourceOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text('Chụp ảnh bằng cấp trực tiếp từ Camera'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green),
              title: const Text('Chọn ảnh bằng cấp từ Thư viện máy'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      // QUAN TRỌNG: Không truyền maxWidth / maxHeight / imageQuality để giữ nguyên 100%
      // chuỗi byte nhị phân gốc của bức ảnh (tránh bị Android tự động resize thành scaled_...jpg
      // gây lệch mã Hash khi đối chiếu lại với bức ảnh gốc trên máy).
      final XFile? file = await picker.pickImage(
        source: source,
      );

      if (file != null) {
        final Uint8List bytes = (!kIsWeb && file.path.isNotEmpty)
            ? await File(file.path).readAsBytes()
            : await file.readAsBytes();
        if (!mounted) return;
        _disposeActiveStream();
        setState(() {
          _selectedFileBytes = bytes;
          _selectedFileName = file.name;
          _selectedFileType = 'IMAGE';
          _isImagePreview = true;
          _notarizeStream = null;
          _completedProgress = null;
          _errorProgress = null;
          _isNotarizing = false;
          _lastSavedResult = null;
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
  // (Có fallback đọc File(file.path) trên Android khi file lớn)
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
        Uint8List? bytes = file.bytes;

        // Fallback đọc từ đường dẫn vật lý nếu trên Android file lớn làm file.bytes == null
        if (bytes == null && !kIsWeb && file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        }

        if (bytes == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể đọc dữ liệu file trên RAM')),
          );
          return;
        }

        final ext = (file.extension ?? '').toLowerCase();
        final isImg = ext == 'png' || ext == 'jpg' || ext == 'jpeg';

        if (!mounted) return;
        _disposeActiveStream();
        setState(() {
          _selectedFileBytes = bytes;
          _selectedFileName = file.name;
          _selectedFileType = isImg ? 'IMAGE' : 'PDF';
          _isImagePreview = isImg;
          _notarizeStream = null;
          _completedProgress = null;
          _errorProgress = null;
          _isNotarizing = false;
          _lastSavedResult = null;
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
  // TIẾN TRÌNH KÝ SỐ BLOCKCHAIN THỜI GIAN THỰC (Broadcast Stream)
  // ========================================================
  Future<void> _confirmAndStartNotarization() async {
    if (_isNotarizing) return;

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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.verified_user_outlined, color: Color(0xFF565C43)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Xác nhận Ký số Văn bằng',
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
              'Dữ liệu sau khi niêm phong lên Blockchain sẽ không thể sửa đổi. Vui lòng kiểm tra kỹ:',
              style: TextStyle(fontSize: 12.5, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Text('• Tệp: $_selectedFileName', style: const TextStyle(fontSize: 13)),
            Text(
              '• Sinh viên: ${_studentNameController.text.trim()} (${_studentCodeController.text.trim()})',
              style: const TextStyle(fontSize: 13),
            ),
            Text(
              '• Văn bằng: ${_degreeNameController.text.trim()}',
              style: const TextStyle(fontSize: 13),
            ),
            Text(
              '• Đơn vị cấp: ${_issuerNameController.text.trim()}',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.check_circle_outline, size: 17),
            label: const Text('Xác nhận Ký số'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF565C43),
              foregroundColor: const Color(0xFFECEBE6),
            ),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _startNotarization();
    }
  }

  void _startNotarization() {
    if (_isNotarizing || _selectedFileBytes == null || _selectedFileName == null) {
      return;
    }

    final apiService = context.read<ApiService>();
    final user = context.read<AuthProvider>().currentUser;
    final studentName = _studentNameController.text.trim();
    final studentCode = _studentCodeController.text.trim();
    final degreeName = _degreeNameController.text.trim();
    final issuerName = _issuerNameController.text.trim();
    final fileName = _selectedFileName!;
    final fileType = _selectedFileType;

    _disposeActiveStream();
    final controller = StreamController<NotarizationProgress>.broadcast();

    setState(() {
      _isNotarizing = true;
      _completedProgress = null;
      _errorProgress = null;
      _notarizeController = controller;
      _notarizeStream = controller.stream;
    });

    final sourceStream = HashService.notarizeFileStream(
      fileBytes: _selectedFileBytes!,
      fileName: fileName,
      apiService: apiService,
      fileType: fileType,
      studentName: studentName,
      studentCode: studentCode,
      degreeName: degreeName,
      issuerName: issuerName,
      createdByEmail: user?.email,
      algorithm: _selectedAlgorithm,
    );

    _notarizeSub = sourceStream.listen(
      (progress) {
        if (!controller.isClosed) {
          controller.add(progress);
        }
        if (!mounted) return;

        if (progress.step == NotarizationStep.completed) {
          setState(() {
            _isNotarizing = false;
            _completedProgress = progress;
            _errorProgress = null;
          });
          // Chỉ lưu vào Sổ tay Offline Sqflite khi ký mới THÀNH CÔNG thực sự
          if (progress.hash != null) {
            DatabaseService.instance.saveCertificate(
              CertificateRecord(
                dataHash: progress.hash!,
                signer: '0xDF098FcEA905839FA80728D806069BF06b24F145',
                timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                fileName: fileName,
                fileType: fileType,
                txHash: progress.txHash,
                blockNumber: progress.blockNumber,
                studentName: studentName,
                studentCode: studentCode,
                degreeName: degreeName,
                issuerName: issuerName,
              ),
            );
          }
        } else if (progress.step == NotarizationStep.error) {
          setState(() {
            _isNotarizing = false;
            _errorProgress = progress;
          });
        }
      },
      onError: (e) {
        if (!controller.isClosed) {
          controller.addError(e);
        }
        if (mounted) {
          setState(() => _isNotarizing = false);
        }
      },
      onDone: () {
        if (!controller.isClosed) {
          controller.close();
        }
        if (mounted && _isNotarizing) {
          setState(() => _isNotarizing = false);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Quyền truy cập bị giới hạn',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
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

    // TIÊU CHÍ BẮT BUỘC (Mục 3.4 kehoach.md): Dùng OrientationBuilder chuyển đổi 1 cột dọc <-> 2 cột ngang
    // Dùng MediaQuery.orientationOf(context) bên trong để khi bật bàn phím ảo (viewInsets thu hẹp chiều cao)
    // không bị đổi nhầm sang chế độ ngang gây đóng mở bàn phím liên tục.
    final content = SafeArea(
      top: !widget.isEmbedded,
      child: OrientationBuilder(
        builder: (context, orientation) {
          final isLandscape =
              MediaQuery.orientationOf(context) == Orientation.landscape;

          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: isLandscape
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cột 1 (Trái): Chọn Tài liệu & Nhập Thông tin Văn bằng
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildStep1FileSelectionCard(),
                              const SizedBox(height: 16),
                              _buildStep2MetadataFormCard(),
                              const SizedBox(height: 16),
                              _buildSignActionButton(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Cột 2 (Phải): Tiến trình StreamBuilder & Biên lai Mã QR
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildStreamAndReceiptSection(
                                showPlaceholderWhenIdle: true,
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildStep1FileSelectionCard(),
                        const SizedBox(height: 16),
                        _buildStep2MetadataFormCard(),
                        const SizedBox(height: 16),
                        _buildSignActionButton(),
                        const SizedBox(height: 16),
                        _buildStreamAndReceiptSection(
                          showPlaceholderWhenIdle: false,
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );

    if (widget.isEmbedded) {
      return content;
    }

    return PopScope(
      canPop: !_hasUnsavedDraftOrInProgress,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _confirmExitScreen();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('Ký Số Văn Bằng (Cán Bộ)'),
          ),
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
        body: content,
      ),
    );
  }

  // Bước 1: Khung Chọn Nguồn Tài Liệu (Ảnh hoặc PDF)
  Widget _buildStep1FileSelectionCard() {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.upload_file, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Bước 1: Chọn Tài Liệu / Ảnh Cần Ký Số',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
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
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Chụp / Chọn Ảnh',
                          style: TextStyle(fontSize: 12)),
                    ),
                    onPressed: _showImageSourceOptions,
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
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Tài Liệu PDF',
                          style: TextStyle(fontSize: 12)),
                    ),
                    onPressed: _pickDocument,
                  ),
                ),
              ],
            ),

            // Khung xem trước file đã chọn (Hỗ trợ xem trước ảnh lớn theo Mục 2.2 Bước D)
            if (_selectedFileBytes != null) ...[
              const SizedBox(height: 14),
              if (_isImagePreview) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    color: Colors.black12,
                    child: Image.memory(
                      _selectedFileBytes!,
                      height: 160,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox(
                        height: 120,
                        child: Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 44,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isImagePreview ? Icons.image : Icons.description,
                      size: 36,
                      color: _isImagePreview ? Colors.teal : Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedFileName ?? 'Tài liệu',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Loại: $_selectedFileType • Dung lượng: ${(_selectedFileBytes!.lengthInBytes / 1024).toStringAsFixed(1)} KB',
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.check_circle, color: Colors.green),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Bước 2: Nhập Thông Tin Văn Bằng
  Widget _buildStep2MetadataFormCard() {
    final theme = Theme.of(context);
    return Card(
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
                const Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Bước 2: Thông Tin Sinh Viên & Bằng Cấp',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _studentNameController,
              decoration: const InputDecoration(
                labelText: 'Họ và tên sinh viên *',
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

            // Chọn chuẩn bảo mật
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                const Text('Chuẩn bảo mật: ',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ChoiceChip(
                  label: const Text('Tiêu chuẩn (Khuyên dùng)',
                      style: TextStyle(fontSize: 11)),
                  selected: _selectedAlgorithm == HashAlgorithm.keccak256,
                  onSelected: (_) {
                    setState(() {
                      _selectedAlgorithm = HashAlgorithm.keccak256;
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('Nâng cao (SHA-256)', style: TextStyle(fontSize: 11)),
                  selected: _selectedAlgorithm == HashAlgorithm.sha256,
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
    );
  }

  // Nút Ký số
  Widget _buildSignActionButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF565C43),
          foregroundColor: const Color(0xFFECEBE6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: _isNotarizing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.verified_outlined),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _isNotarizing
                ? 'ĐANG KÝ SỐ LÊN BLOCKCHAIN...'
                : 'XÁC NHẬN & CẤP MÃ QR VĂN BẰNG',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        onPressed: _isNotarizing ? null : _confirmAndStartNotarization,
      ),
    );
  }

  // Khối hiển thị StreamBuilder & Biên lai Mã QR
  Widget _buildStreamAndReceiptSection({required bool showPlaceholderWhenIdle}) {
    if (_notarizeStream == null && _completedProgress == null) {
      if (!showPlaceholderWhenIdle) return const SizedBox.shrink();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.qr_code_2_rounded,
                  size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Khu Vực Hiển Thị Tiến Trình & Mã QR',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Sau khi chọn Ảnh/PDF và bấm nút Xác nhận ở cột bên trái, tiến trình xử lý và mã QR văn bằng sẽ xuất hiện tại đây.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_notarizeStream != null)
            ProgressStreamCard.notarization(
              stream: _notarizeStream!,
            ),
          if (_completedProgress != null &&
              _completedProgress!.step == NotarizationStep.completed) ...[
            const SizedBox(height: 16),
            _buildSuccessReceiptCard(_completedProgress!),
          ],
          if (_errorProgress != null && _errorProgress!.isDuplicate) ...[
            const SizedBox(height: 16),
            _buildDuplicateWarningCard(_errorProgress!),
          ],
        ],
      ),
    );
  }

  Future<void> _saveSignedFileToDevice(String hash) async {
    final bytes = _selectedFileBytes;
    if (bytes == null || _isSavingSignedFile) return;

    setState(() => _isSavingSignedFile = true);
    final fileName = LocalFileSaveService.buildSignedFileName(
      originalFileName: _selectedFileName ?? 'signed_certificate.jpg',
      hash: hash,
      fileType: _selectedFileType,
    );

    final result = await LocalFileSaveService.saveToDownloadsAndGallery(
      bytes: bytes,
      fileName: fileName,
      fileType: _selectedFileType,
    );

    if (!mounted) return;
    setState(() {
      _isSavingSignedFile = false;
      _lastSavedResult = result;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? 'Đã lưu tệp gốc vào Downloads/CertChain${result.gallerySaved ? " & Thư viện ảnh" : ""}. Khi kiểm tra lại hãy dùng mục "Chọn File" để không bị đổi byte!'
              : (result.errorMessage ?? 'Không thể lưu tệp về máy.'),
        ),
        backgroundColor: result.success ? Colors.green.shade700 : Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  // Thẻ cảnh báo khi Cán bộ chọn trùng tài liệu đã từng niêm phong
  Widget _buildDuplicateWarningCard(NotarizationProgress progress) {
    final existing = progress.existingRecord;
    final oldStudent = existing?['studentName']?.toString();
    final oldCode = existing?['studentCode']?.toString();
    final oldDegree = existing?['degreeName']?.toString();

    return Card(
      color: Colors.orange.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Colors.orange, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'TÀI LIỆU ĐÃ TỒN TẠI (TRÙNG MÃ BĂM)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              progress.errorMessage ??
                  'File này đã được niêm phong trên Blockchain từ trước nên hệ thống từ chối ký đè và không lưu vào Sổ tay.',
              style: const TextStyle(fontSize: 13),
            ),
            if (oldStudent != null || oldDegree != null) ...[
              const Divider(height: 20),
              const Text(
                'Thông tin văn bằng gốc đang lưu trên hệ thống:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
              ),
              const SizedBox(height: 4),
              if (oldDegree != null && oldDegree.isNotEmpty)
                Text('• Văn bằng: $oldDegree', style: const TextStyle(fontSize: 12.5)),
              if (oldStudent != null && oldStudent.isNotEmpty)
                Text(
                  '• Sinh viên: $oldStudent${(oldCode != null && oldCode.isNotEmpty) ? " ($oldCode)" : ""}',
                  style: const TextStyle(fontSize: 12.5),
                ),
            ],
            const SizedBox(height: 10),
            const Text(
              'Gợi ý: Vui lòng chọn một file Ảnh/PDF gốc khác nếu bạn muốn cấp văn bằng mới cho sinh viên khác.',
              style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  // Khung Biên lai kết quả ký số kèm Mã QR
  Widget _buildSuccessReceiptCard(NotarizationProgress progress) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hash = progress.hash ?? '';
    final txHash = progress.txHash ?? '0x...';
    final primaryTextColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;

    return Card(
      elevation: 4,
      color: isDark
          ? Colors.green.withValues(alpha: 0.14)
          : Colors.green.shade50,
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
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'VĂN BẰNG ĐÃ ĐƯỢC NIÊM PHONG',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isDark ? Colors.greenAccent : Colors.green.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
            Text(
              'Mã QR chứng thực văn bằng',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: primaryTextColor,
              ),
            ),
            Text(
              'Sinh viên hoặc Nhà tuyển dụng có thể dùng app quét mã này để kiểm tra',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: secondaryTextColor),
            ),
            const SizedBox(height: 16),

            // Chi tiết văn bằng
            _buildReceiptRow('Sinh viên:', _studentNameController.text, primaryTextColor),
            _buildReceiptRow('Văn bằng:', _degreeNameController.text, primaryTextColor),
            _buildReceiptRow('Đơn vị cấp:', _issuerNameController.text, primaryTextColor),
            _buildReceiptRow('Mã giao dịch:', txHash, primaryTextColor, isMono: true),
            _buildReceiptRow('Mã văn bằng:', hash, primaryTextColor, isMono: true),
            if (progress.blockNumber != null)
              _buildReceiptRow('Số hồ sơ:', '#${progress.blockNumber}', primaryTextColor),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (_selectedFileBytes != null)
                  ElevatedButton.icon(
                    icon: _isSavingSignedFile
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download_outlined, size: 18),
                    label: Text(
                      _isSavingSignedFile
                          ? 'Đang lưu...'
                          : (_selectedFileType == 'IMAGE'
                              ? 'Lưu ảnh đã ký về máy'
                              : 'Lưu tệp đã ký về máy'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _isSavingSignedFile
                        ? null
                        : () => _saveSignedFileToDevice(hash),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 17),
                  label: const Text('Sao chép mã văn bằng'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: hash));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Đã sao chép mã số văn bằng vào bộ nhớ tạm'),
                      ),
                    );
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: const Text('Kiểm tra thử tệp vừa cấp'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final certRecord = CertificateRecord(
                      dataHash: hash,
                      signer: '0xDF098FcEA905839FA80728D806069BF06b24F145',
                      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                      fileName: _selectedFileName ?? 'Van_Bang_Moi.pdf',
                      fileType: _selectedFileType,
                      txHash: progress.txHash,
                      blockNumber: progress.blockNumber,
                      studentName: _studentNameController.text.trim(),
                      studentCode: _studentCodeController.text.trim(),
                      degreeName: _degreeNameController.text.trim(),
                      issuerName: _issuerNameController.text.trim(),
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VerifyDetailScreen(
                          record: certRecord,
                          searchedHash: hash,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            if (_lastSavedResult != null && _lastSavedResult!.success) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.amber.shade700.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: isDark
                              ? Colors.amberAccent
                              : Colors.amber.shade900,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Đã lưu tệp gốc: ${_lastSavedResult!.downloadsPath ?? "Downloads/CertChain"}'
                            '${_lastSavedResult!.gallerySaved ? " & Thư viện ảnh (${_lastSavedResult!.galleryPath})" : ""}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                              color: primaryTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hướng dẫn kiểm tra: Hãy dùng mục "Chọn File" để mở tệp gốc trong thư mục Downloads/CertChain nhằm giữ nguyên 100% byte. Không chọn qua app Gallery/Zalo/Messenger chế độ thường vì có thể bị nén lại làm đổi mã Hash.',
                      style: TextStyle(
                        fontSize: 11,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value, Color textColor,
      {bool isMono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: textColor,
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
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
