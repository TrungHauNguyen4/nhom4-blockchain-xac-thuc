import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/certificate_record.dart';
import '../../models/signing_request_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/folder_batch_validator.dart';
import '../../services/hash_service.dart';
import '../../services/signing_request_service.dart';
import '../../utils/verify_navigation_helper.dart';
import '../verifier/verify_detail_screen.dart';

/// Phân tách danh sách tệp đã băm thành nhóm đã ký sẵn trên Blockchain và nhóm chưa ký cần gửi.
({List<T> signed, List<T> unsigned}) partitionBySignedStatus<T>(
  List<T> items,
  bool Function(T item) isSigned,
) {
  final signed = <T>[];
  final unsigned = <T>[];
  for (final item in items) {
    if (isSigned(item)) {
      signed.add(item);
    } else {
      unsigned.add(item);
    }
  }
  return (signed: signed, unsigned: unsigned);
}

class _PreparedHashedFile {
  final String fileName;
  final String fileType; // 'IMAGE' | 'PDF'
  final int fileSizeBytes;
  final String documentHash;
  final CertificateRecord? existingRecord;
  final TextEditingController degreeNameController;

  _PreparedHashedFile({
    required this.fileName,
    required this.fileType,
    required this.fileSizeBytes,
    required this.documentHash,
    this.existingRecord,
    required String defaultDegreeName,
  }) : degreeNameController = TextEditingController(text: defaultDegreeName);

  bool get isAlreadySigned => existingRecord != null;

  void dispose() => degreeNameController.dispose();
}

/// Màn hình gửi yêu cầu xác nhận/ký tài liệu dành cho Sinh viên (đơn lẻ) và
/// Nhà tuyển dụng (gửi Folder / nhiều tệp cùng loại) + Theo dõi trạng thái 24h.
class SubmitSigningRequestScreen extends StatefulWidget {
  final int initialTabIndex;

  const SubmitSigningRequestScreen({super.key, this.initialTabIndex = 0});

  @override
  State<SubmitSigningRequestScreen> createState() =>
      _SubmitSigningRequestScreenState();
}

class _SubmitSigningRequestScreenState extends State<SubmitSigningRequestScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _service = SigningRequestService();
  final _formKey = GlobalKey<FormState>();

  final _studentNameController = TextEditingController();
  final _studentCodeController = TextEditingController();
  final _issuerNameController = TextEditingController();

  HashAlgorithm _selectedAlgorithm = HashAlgorithm.keccak256;
  final List<_PreparedHashedFile> _preparedFiles = <_PreparedHashedFile>[];
  String? _selectedFolderPath;
  bool _isHashing = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = context.read<AuthProvider>().currentUser;
      if (user == null) return;
      if (user.isStudent) {
        _studentNameController.text = user.name;
        _studentCodeController.text = user.studentCode;
      }
      _issuerNameController.text = user.organization.trim().isNotEmpty
          ? user.organization.trim()
          : 'Trường Đại học Đồng Tháp';
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _studentNameController.dispose();
    _studentCodeController.dispose();
    _issuerNameController.dispose();
    for (final f in _preparedFiles) {
      f.dispose();
    }
    super.dispose();
  }

  void _clearPreparedFiles() {
    for (final f in _preparedFiles) {
      f.dispose();
    }
    _preparedFiles.clear();
  }

  Future<void> _pickSingleFileForStudent() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        _showSnack('Không thể đọc dữ liệu tệp gốc.', isError: true);
        return;
      }

      final fileType =
          FolderBatchValidator.detectFileType(file.name) ?? 'PDF';
      await _hashAndSetPreparedFiles([
        (name: file.name, type: fileType, bytes: bytes),
      ]);
      setState(() => _selectedFolderPath = null);
    } catch (e) {
      _showSnack('Lỗi chọn tệp: $e', isError: true);
    }
  }

  Future<void> _pickFolderForEmployer() async {
    try {
      final dirPath = await FilePicker.platform.getDirectoryPath();
      if (dirPath == null || dirPath.trim().isEmpty) return;

      final validation =
          await FolderBatchValidator.validateDirectory(dirPath.trim());
      if (!validation.isValid) {
        _showSnack(
          validation.errorMessage ?? 'Thư mục không hợp lệ.',
          isError: true,
        );
        return;
      }

      final rawItems = <({String name, String type, Uint8List bytes})>[];
      for (final filePath in validation.filePaths) {
        final bytes = await File(filePath).readAsBytes();
        rawItems.add((
          name: p.basename(filePath),
          type: validation.fileType!,
          bytes: bytes,
        ));
      }

      await _hashAndSetPreparedFiles(rawItems);
      setState(() => _selectedFolderPath = dirPath.trim());
    } catch (e) {
      _showSnack('Lỗi đọc thư mục: $e', isError: true);
    }
  }

  Future<void> _pickMultipleFilesForEmployer() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final namesOrPaths = result.files
          .map((f) => f.path ?? f.name)
          .toList(growable: false);
      final validation = FolderBatchValidator.validateFilePaths(namesOrPaths);
      if (!validation.isValid) {
        _showSnack(
          validation.errorMessage ?? 'Danh sách tệp không hợp lệ.',
          isError: true,
        );
        return;
      }

      final rawItems = <({String name, String type, Uint8List bytes})>[];
      for (final file in result.files) {
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        }
        if (bytes == null || bytes.isEmpty) continue;
        rawItems.add((
          name: file.name,
          type: validation.fileType!,
          bytes: bytes,
        ));
      }

      if (rawItems.isEmpty) {
        _showSnack('Không đọc được dữ liệu byte gốc của tệp.', isError: true);
        return;
      }

      await _hashAndSetPreparedFiles(rawItems);
      setState(() => _selectedFolderPath = null);
    } catch (e) {
      _showSnack('Lỗi chọn nhiều tệp: $e', isError: true);
    }
  }

  Future<void> _hashAndSetPreparedFiles(
    List<({String name, String type, Uint8List bytes})> items,
  ) async {
    setState(() => _isHashing = true);
    final apiService = Provider.of<ApiService?>(context, listen: false) ??
        ApiService();
    try {
      final prepared = <_PreparedHashedFile>[];
      for (final item in items) {
        final both = await HashService.computeBothHashesAsync(item.bytes);
        final hash = _selectedAlgorithm == HashAlgorithm.sha256
            ? both.sha256
            : both.keccak256;
        CertificateRecord? existing;
        try {
          existing = await apiService.verifyHash(hash, fileName: item.name);
        } catch (_) {
          existing = null;
        }
        final baseTitle = p.basenameWithoutExtension(item.name).trim();
        prepared.add(
          _PreparedHashedFile(
            fileName: item.name,
            fileType: item.type,
            fileSizeBytes: item.bytes.lengthInBytes,
            documentHash: hash,
            existingRecord: existing,
            defaultDegreeName: baseTitle.isEmpty ? item.name : baseTitle,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _clearPreparedFiles();
        _preparedFiles.addAll(prepared);
      });
    } finally {
      if (mounted) {
        setState(() => _isHashing = false);
      }
    }
  }

  Future<void> _submitRequests() async {
    if (_preparedFiles.isEmpty) {
      _showSnack('Vui lòng chọn tệp hoặc thư mục cần gửi yêu cầu ký.',
          isError: true);
      return;
    }
    final partitioned = partitionBySignedStatus(
      _preparedFiles,
      (f) => f.isAlreadySigned,
    );
    final unsignedFiles = partitioned.unsigned;
    if (unsignedFiles.isEmpty) {
      _showSnack(
        'Tất cả tệp đã được ký xác nhận trước đây, không cần gửi chờ ký.',
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;

    setState(() => _isSubmitting = true);
    try {
      final algoKey = _selectedAlgorithm == HashAlgorithm.sha256
          ? 'sha256'
          : 'keccak256';
      final issuerName = _issuerNameController.text.trim();
      final studentName = _studentNameController.text.trim();
      final studentCode = _studentCodeController.text.trim();

      if (user.isEmployer) {
        await _service.submitBatchRequests(
          requesterUid: user.uid,
          requesterName: user.name,
          requesterEmail: user.email,
          requesterOrganization: user.organization,
          issuerName: issuerName,
          items: unsignedFiles
              .map(
                (f) => (
                  degreeName: f.degreeNameController.text.trim().isEmpty
                      ? f.fileName
                      : f.degreeNameController.text.trim(),
                  studentName: studentName.isEmpty
                      ? 'Hồ sơ từ ${user.organization.isEmpty ? user.name : user.organization}'
                      : studentName,
                  studentCode: studentCode,
                  fileName: f.fileName,
                  fileType: f.fileType,
                  fileSizeBytes: f.fileSizeBytes,
                  documentHash: f.documentHash,
                  hashAlgorithm: algoKey,
                ),
              )
              .toList(growable: false),
        );
      } else {
        final f = unsignedFiles.first;
        await _service.submitRequest(
          requesterUid: user.uid,
          requesterName: user.name,
          requesterEmail: user.email,
          requesterRole: 'student',
          requesterStudentCode: user.studentCode,
          requesterOrganization: user.organization,
          degreeName: f.degreeNameController.text.trim().isEmpty
              ? f.fileName
              : f.degreeNameController.text.trim(),
          studentName: studentName.isEmpty ? user.name : studentName,
          studentCode: studentCode.isEmpty ? user.studentCode : studentCode,
          issuerName: issuerName,
          fileName: f.fileName,
          fileType: f.fileType,
          fileSizeBytes: f.fileSizeBytes,
          documentHash: f.documentHash,
          hashAlgorithm: algoKey,
        );
      }

      if (!mounted) return;
      _showSnack(
        'Đã gửi ${unsignedFiles.length} yêu cầu ký mới. Thời gian xử lý mặc định trong vòng 24 giờ.',
      );
      setState(() {
        _clearPreparedFiles();
        _selectedFolderPath = null;
      });
      _tabController.animateTo(1);
    } catch (e) {
      _showSnack('Gửi yêu cầu thất bại: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.teal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final isEmployer = user?.isEmployer ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yêu Cầu Ký Tài Liệu'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.tealAccent,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.upload_file), text: 'Gửi yêu cầu mới'),
            Tab(icon: Icon(Icons.history_edu), text: 'Yêu cầu đã gửi'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _KeepAliveTabWrapper(
            child: _buildSubmitTab(isEmployer: isEmployer),
          ),
          _MyRequestsTabView(
            uid: user?.uid ?? '',
            service: _service,
            onCopyHash: () => _showSnack('Đã sao chép mã Hash.'),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitTab({required bool isEmployer}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified_user, color: Colors.teal),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tệp gốc được băm trực tiếp trên thiết bị (không nén ảnh) nên 100% không bị biến đổi. Dự kiến xử lý trong 24 giờ.',
                      style: TextStyle(fontSize: 12.5, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Thuật toán băm (Hash)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<HashAlgorithm>(
              segments: const [
                ButtonSegment(
                  value: HashAlgorithm.keccak256,
                  label: Text('Keccak-256 (Mặc định)'),
                  icon: Icon(Icons.bolt, size: 16),
                ),
                ButtonSegment(
                  value: HashAlgorithm.sha256,
                  label: Text('SHA-256'),
                  icon: Icon(Icons.security, size: 16),
                ),
              ],
              selected: <HashAlgorithm>{_selectedAlgorithm},
              onSelectionChanged: _preparedFiles.isNotEmpty
                  ? null
                  : (value) {
                      setState(() => _selectedAlgorithm = value.first);
                    },
            ),
            if (_preparedFiles.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Chọn lại tệp/thư mục nếu muốn đổi thuật toán băm.',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 16),
            if (!isEmployer)
              ElevatedButton.icon(
                onPressed: _isHashing ? null : _pickSingleFileForStudent,
                icon: const Icon(Icons.attach_file),
                label: const Text('Chọn Ảnh hoặc PDF gốc để băm & gửi ký'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              )
            else ...[
              ElevatedButton.icon(
                onPressed: _isHashing ? null : _pickFolderForEmployer,
                icon: const Icon(Icons.folder_open),
                label: const Text('Chọn Folder (chỉ Ảnh hoặc chỉ PDF)'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _isHashing ? null : _pickMultipleFilesForEmployer,
                icon: const Icon(Icons.file_copy_outlined),
                label: const Text(
                  'Dự phòng: Chọn nhiều tệp cùng loại (Ảnh hoặc PDF)',
                ),
              ),
              if (_selectedFolderPath != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Thư mục: $_selectedFolderPath',
                    style: const TextStyle(fontSize: 12, color: Colors.teal),
                  ),
                ),
            ],
            if (_isHashing) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Đang tính mã Hash & kiểm tra văn bằng đã ký...',
                ),
              ),
            ],
            if (_preparedFiles.isNotEmpty) ...[
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  final partitioned = partitionBySignedStatus(
                    _preparedFiles,
                    (f) => f.isAlreadySigned,
                  );
                  final signedCount = partitioned.signed.length;
                  final unsignedCount = partitioned.unsigned.length;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Đã chuẩn bị ${_preparedFiles.length} tệp (${_preparedFiles.first.fileType})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (signedCount > 0) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.teal.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            unsignedCount == 0
                                ? 'Tất cả $signedCount tệp đều đã được ký xác nhận trước đây. Bạn có thể bấm Xem kết quả xác thực ngay bên dưới (không cần gửi lại).'
                                : '$signedCount tệp đã ký trước đây (sẽ tự động bỏ qua) • $unsignedCount tệp mới sẽ được gửi chờ ký.',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.teal,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              ..._preparedFiles.map((f) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                f.fileType == 'IMAGE'
                                    ? Icons.image
                                    : Icons.picture_as_pdf,
                                color: f.fileType == 'IMAGE'
                                    ? Colors.blue
                                    : Colors.redAccent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  f.fileName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                '${(f.fileSizeBytes / 1024).toStringAsFixed(1)} KB',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          if (f.isAlreadySigned) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.green.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.verified,
                                        size: 17,
                                        color: Colors.green,
                                      ),
                                      SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Đã được ký xác nhận trước đây',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if ((f.existingRecord?.degreeName ?? '')
                                      .isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Văn bằng: ${f.existingRecord!.degreeName}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  if ((f.existingRecord?.issuerName ?? '')
                                      .isNotEmpty)
                                    Text(
                                      'Đơn vị cấp: ${f.existingRecord!.issuerName}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  const SizedBox(height: 4),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => VerifyDetailScreen(
                                              record: f.existingRecord,
                                              searchedHash: f.documentHash,
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.open_in_new,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'Xem kết quả xác thực',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: f.degreeNameController,
                              decoration: const InputDecoration(
                                labelText: 'Tên tài liệu / văn bằng',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Vui lòng nhập tên tài liệu'
                                  : null,
                            ),
                          ],
                          const SizedBox(height: 6),
                          SelectableText(
                            'Hash: ${f.documentHash}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                              color: Colors.teal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _studentNameController,
              decoration: InputDecoration(
                labelText: isEmployer
                    ? 'Tên ứng viên / nhóm hồ sơ (tuỳ chọn)'
                    : 'Họ và tên sinh viên',
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                if (!isEmployer && (v == null || v.trim().isEmpty)) {
                  return 'Vui lòng nhập họ tên';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _studentCodeController,
              decoration: InputDecoration(
                labelText: isEmployer
                    ? 'Mã số sinh viên / Mã hồ sơ (tuỳ chọn)'
                    : 'Mã số sinh viên (MSSV)',
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                if (!isEmployer && (v == null || v.trim().isEmpty)) {
                  return 'Vui lòng nhập MSSV';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _issuerNameController,
              decoration: const InputDecoration(
                labelText: 'Đơn vị / Cơ quan ký xác nhận',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Vui lòng nhập đơn vị ký'
                  : null,
            ),
            const SizedBox(height: 20),
            Builder(
              builder: (context) {
                final pendingCount = _preparedFiles
                    .where((f) => !f.isAlreadySigned)
                    .length;
                final allSigned =
                    _preparedFiles.isNotEmpty && pendingCount == 0;
                return ElevatedButton.icon(
                  onPressed: (_isSubmitting || _isHashing || pendingCount == 0)
                      ? null
                      : _submitRequests,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(allSigned ? Icons.verified : Icons.send),
                  label: Text(
                    _isSubmitting
                        ? 'Đang gửi yêu cầu...'
                        : allSigned
                            ? 'Tất cả tệp đã được ký trước đây'
                            : 'Gửi yêu cầu ký ($pendingCount tệp mới)',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _KeepAliveTabWrapper extends StatefulWidget {
  final Widget child;

  const _KeepAliveTabWrapper({required this.child});

  @override
  State<_KeepAliveTabWrapper> createState() => _KeepAliveTabWrapperState();
}

class _KeepAliveTabWrapperState extends State<_KeepAliveTabWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _MyRequestsTabView extends StatefulWidget {
  final String uid;
  final SigningRequestService service;
  final VoidCallback onCopyHash;

  const _MyRequestsTabView({
    required this.uid,
    required this.service,
    required this.onCopyHash,
  });

  @override
  State<_MyRequestsTabView> createState() => _MyRequestsTabViewState();
}

class _MyRequestsTabViewState extends State<_MyRequestsTabView>
    with AutomaticKeepAliveClientMixin {
  Stream<List<SigningRequestModel>>? _stream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  @override
  void didUpdateWidget(covariant _MyRequestsTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _initStream();
    }
  }

  void _initStream() {
    _stream = widget.uid.isEmpty
        ? null
        : widget.service.streamMyRequests(widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.uid.isEmpty || _stream == null) {
      return const Center(child: Text('Vui lòng đăng nhập để xem yêu cầu.'));
    }

    return StreamBuilder<List<SigningRequestModel>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.redAccent,
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Không thể tải danh sách yêu cầu: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => setState(_initStream),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data ?? const <SigningRequestModel>[];
        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Bạn chưa gửi yêu cầu ký tài liệu nào.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final fmt = DateFormat('dd/MM/yyyy HH:mm');
        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = items[index];
            final Color statusColor;
            switch (item.status) {
              case SigningRequestStatus.signed:
                statusColor = Colors.teal;
                break;
              case SigningRequestStatus.delayed:
                statusColor = Colors.orange;
                break;
              case SigningRequestStatus.rejected:
                statusColor = Colors.redAccent;
                break;
              case SigningRequestStatus.pending:
                statusColor = Colors.blue;
                break;
            }

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.degreeName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Chip(
                          label: Text(
                            item.status.labelVi,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          backgroundColor: statusColor.withValues(alpha: 0.12),
                          side: BorderSide.none,
                        ),
                      ],
                    ),
                    Text(
                      'Tệp: ${item.fileName} (${item.fileType}) • ${item.hashAlgorithm.toUpperCase()}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Gửi lúc: ${fmt.format(item.createdDateTime)} • Dự kiến (${item.estimatedHours}h): ${fmt.format(item.expectedResolveDateTime)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    if (item.waitReason.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Thông báo chờ: ${item.waitReason}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                    if (item.rejectionReason != null &&
                        item.rejectionReason!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Lý do từ chối: ${item.rejectionReason}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Hash: ${item.documentHash}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Sao chép mã Hash',
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: item.documentHash),
                            );
                            widget.onCopyHash();
                          },
                        ),
                        if (item.status == SigningRequestStatus.signed)
                          TextButton.icon(
                            onPressed: () => openVerifyByHash(
                              context,
                              item.documentHash,
                              fileName: item.fileName,
                            ),
                            icon: const Icon(Icons.verified, size: 16),
                            label: const Text('Kiểm tra'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
