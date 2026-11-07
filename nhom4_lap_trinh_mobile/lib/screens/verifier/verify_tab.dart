import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/certificate_record.dart';
import '../../models/scan_history_model.dart';
import '../../services/api_service.dart';
import '../../services/db_service.dart';
import '../../services/hash_service.dart';
import '../../widgets/progress_stream_card.dart';
import 'qr_scanner_screen.dart';
import 'verify_detail_screen.dart';

class VerifyTab extends StatefulWidget {
  final VoidCallback? onVaultUpdated;

  const VerifyTab({super.key, this.onVaultUpdated});

  @override
  State<VerifyTab> createState() => _VerifyTabState();
}

class _VerifyTabState extends State<VerifyTab> {
  final ApiService _apiService = ApiService();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _hashInputController = TextEditingController();

  // Luồng tiến trình băm & đối soát cho StreamBuilder
  Stream<VerificationProgress>? _verificationStream;

  // Thông tin file đang nạp trên RAM
  String? _selectedFileName;
  int? _selectedFileSize;
  String? _computedKeccak256;
  String? _computedSha256;

  // Lưu vết phương thức quét hiện tại ('QR', 'FILE', 'HASH') để ghi vào scan_history
  String _currentScanMethod = 'HASH';
  String _currentScanFileName = 'Văn bằng tra cứu';
  String? _lastLoggedHashAndTime;

  @override
  void dispose() {
    _hashInputController.dispose();
    super.dispose();
  }

  // [THAO TÁC 1]: Chọn file PDF/Ảnh từ máy -> Đọc RAM (có fallback File(path) trên Android) -> Băm & Verify
  Future<void> _pickAndVerifyFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        Uint8List? bytes = file.bytes;

        // Sửa lỗi trên Android khi file lớn khiến file.bytes == null bằng cách fallback đọc từ file.path
        if (bytes == null && !kIsWeb && file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        }

        if (!mounted) return;
        if (bytes == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể đọc dữ liệu nhị phân của tệp đã chọn'),
            ),
          );
          return;
        }

        _processBytesVerification(bytes, file.name);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi chọn tệp: $e')),
      );
    }
  }

  // [THAO TÁC 2]: Chọn nhanh Ảnh chứng chỉ từ Thư viện ảnh -> Băm trên RAM & Verify
  Future<void> _pickImageCertificate() async {
    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      _processBytesVerification(bytes, picked.name);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi chọn ảnh chứng chỉ: $e')),
      );
    }
  }

  // Tính toán mã băm Keccak-256 & SHA-256 trên RAM và kích hoạt StreamBuilder
  void _processBytesVerification(Uint8List bytes, String fileName) {
    final keccakHash = HashService.keccak256FromBytes(bytes);
    final sha256Hash = HashService.sha256FromBytes(bytes);

    setState(() {
      _selectedFileName = fileName;
      _selectedFileSize = bytes.lengthInBytes;
      _computedKeccak256 = keccakHash;
      _computedSha256 = sha256Hash;
      _hashInputController.text = keccakHash;
      _currentScanMethod = 'FILE';
      _currentScanFileName = fileName;
      _lastLoggedHashAndTime = null;

      _verificationStream = _verifyFileWithOfflineFallback(
        fileBytes: bytes,
        fileName: fileName,
      );
    });
  }

  // [THAO TÁC 3]: Mở Camera hoặc chọn ảnh QR để quét mã
  Future<void> _scanQrCode() async {
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );

    if (!mounted) return;
    if (scannedCode != null && scannedCode.trim().isNotEmpty) {
      final cleanCode = _extractHashFromQrContent(scannedCode.trim());
      _hashInputController.text = cleanCode;
      _startVerifyHash(
        cleanCode,
        fileName: 'Văn bằng quét mã QR',
        scanMethod: 'QR',
      );
    }
  }

  // Trích xuất mã Hash 0x... nếu mã QR chứa URL hoặc JSON
  String _extractHashFromQrContent(String raw) {
    final regExp = RegExp(r'0x[a-fA-F0-9]{64}');
    final match = regExp.firstMatch(raw);
    if (match != null) {
      return match.group(0)!;
    }
    return raw;
  }

  // [THAO TÁC 4]: Xác minh bằng mã Hash
  void _startVerifyHash(
    String hash, {
    String fileName = 'Văn bằng tra cứu mã Hash',
    String scanMethod = 'HASH',
  }) {
    final clean = hash.trim();
    if (clean.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập mã Data Hash (0x...) để tra cứu')),
      );
      return;
    }

    setState(() {
      if (scanMethod != 'FILE') {
        _selectedFileName = null;
        _selectedFileSize = null;
        _computedKeccak256 = null;
        _computedSha256 = null;
      }
      _currentScanMethod = scanMethod;
      _currentScanFileName = fileName;
      _lastLoggedHashAndTime = null;

      _verificationStream = _verifyHashWithOfflineFallback(
        dataHash: clean,
        fileName: fileName,
      );
    });
  }

  // Bọc luồng verifyFileStream kèm đối chiếu Offline Sqflite nếu mất kết nối Server
  Stream<VerificationProgress> _verifyFileWithOfflineFallback({
    required Uint8List fileBytes,
    required String fileName,
  }) async* {
    await for (final progress in HashService.verifyFileStream(
      fileBytes: fileBytes,
      fileName: fileName,
      apiService: _apiService,
    )) {
      if (progress.step == VerificationStep.error && progress.hash != null) {
        CertificateRecord? offlineCert; try { offlineCert = await DatabaseService.instance.getCertificateByHash(
          progress.hash!,
        ); } catch (_) {}
        if (offlineCert != null && offlineCert.isValid) {
          yield VerificationProgress(
            step: VerificationStep.verifiedValid,
            progress: 1.0,
            statusMessage:
                'Xác thực thành công từ Sổ tay Offline (Chế độ không có mạng)!',
            hash: progress.hash,
            record: offlineCert,
          );
          return;
        }
      }
      yield progress;
    }
  }

  // Bọc luồng verifyHashStream kèm đối chiếu Offline Sqflite nếu mất kết nối Server
  Stream<VerificationProgress> _verifyHashWithOfflineFallback({
    required String dataHash,
    required String fileName,
  }) async* {
    await for (final progress in HashService.verifyHashStream(
      dataHash: dataHash,
      apiService: _apiService,
      fileName: fileName,
    )) {
      if (progress.step == VerificationStep.error) {
        CertificateRecord? offlineCert; try { offlineCert = await DatabaseService.instance.getCertificateByHash(
          dataHash,
        ); } catch (_) {}
        if (offlineCert != null && offlineCert.isValid) {
          yield VerificationProgress(
            step: VerificationStep.verifiedValid,
            progress: 1.0,
            statusMessage:
                'Xác thực thành công từ Sổ tay Offline (Chế độ không có mạng)!',
            hash: dataHash,
            record: offlineCert,
          );
          return;
        }
      }
      yield progress;
    }
  }

  // [CREATE] Tự động ghi nhận lịch sử tra cứu vào bảng scan_history (Sqflite)
  Future<void> _recordScanHistoryOnDone(VerificationProgress data) async {
    final targetHash = (data.hash != null && data.hash!.isNotEmpty)
        ? data.hash!
        : _hashInputController.text.trim();
    if (targetHash.isEmpty) return;

    final signatureKey = '$targetHash-${data.step.name}';
    if (_lastLoggedHashAndTime == signatureKey) return;
    _lastLoggedHashAndTime = signatureKey;

    final bool isValid = data.step == VerificationStep.verifiedValid;
    final CertificateRecord? rec = data.record;

    final historyItem = ScanHistoryModel(
      dataHash: targetHash,
      fileName: rec?.fileName ?? _currentScanFileName,
      scanMethod: _currentScanMethod,
      isValid: isValid,
      issuerName: rec?.issuerName ?? (isValid ? 'Phòng Đào Tạo' : 'Không xác định'),
      studentName: rec?.studentName,
      degreeName: rec?.degreeName,
    );

    try { await DatabaseService.instance.saveScanHistory(historyItem); } catch (e) { debugPrint('[VerifyTab] Bỏ qua lưu scan_history: $e'); }
    widget.onVaultUpdated?.call();
  }

  void _openDetailScreen(VerificationProgress data) {
    final targetHash = (data.hash != null && data.hash!.isNotEmpty)
        ? data.hash!
        : _hashInputController.text.trim();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VerifyDetailScreen(
          record: data.record,
          searchedHash: targetHash.isEmpty ? 'Chưa xác định' : targetHash,
        ),
      ),
    ).then((_) {
      widget.onVaultUpdated?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Bắt buộc bọc OrientationBuilder để tự động chuyển 1 cột dọc <-> 2 cột ngang
    return OrientationBuilder(
      builder: (context, orientation) {
        if (orientation == Orientation.portrait) {
          return _buildPortraitLayout(context);
        } else {
          return _buildLandscapeLayout(context);
        }
      },
    );
  }

  // Giao diện Màn hình Dọc (1 Cột)
  Widget _buildPortraitLayout(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBanner(context),
          const SizedBox(height: 18),
          _buildActionButtons(context),
          const SizedBox(height: 16),
          _buildManualHashCard(context),
          if (_selectedFileName != null) ...[
            const SizedBox(height: 16),
            _buildClientRamHashInfoCard(context),
          ],
          if (_verificationStream != null) ...[
            const SizedBox(height: 16),
            ProgressStreamCard(
              stream: _verificationStream!,
              onCompleted: _recordScanHistoryOnDone,
              onViewDetail: _openDetailScreen,
            ),
          ],
        ],
      ),
    );
  }

  // Giao diện Màn hình Ngang (Chia 2 Cột linh hoạt bằng Row + Expanded)
  Widget _buildLandscapeLayout(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildBanner(context),
                  const SizedBox(height: 14),
                  _buildActionButtons(context),
                  const SizedBox(height: 14),
                  _buildManualHashCard(context),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_selectedFileName != null) ...[
                    _buildClientRamHashInfoCard(context),
                    const SizedBox(height: 14),
                  ],
                  if (_verificationStream != null)
                    ProgressStreamCard(
                      stream: _verificationStream!,
                      onCompleted: _recordScanHistoryOnDone,
                      onViewDetail: _openDetailScreen,
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          children: [
                            Icon(
                              Icons.fact_check_outlined,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Sẵn sàng thẩm định văn bằng',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Chọn Quét mã QR, Chọn File PDF/Ảnh hoặc nhập mã Hash ở cột bên trái để bắt đầu luồng StreamBuilder.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Banner giới thiệu (Bọc FittedBox chống tràn viền)
  Widget _buildBanner(BuildContext context) {
    return Container(
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
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              children: [
                Icon(Icons.security, color: Colors.white, size: 22),
                SizedBox(width: 8),
                Text(
                  'Kiểm Định Văn Bằng & Chứng Chỉ Số Blockchain',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Băm mật mã Keccak-256 / SHA-256 trực tiếp trên RAM thiết bị & đối soát Smart Contract Ethereum Sepolia',
            style: TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  // Các nút thao tác chính: Quét QR, Chọn File PDF/Ảnh, Chọn Ảnh Thư viện
  Widget _buildActionButtons(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.qr_code_scanner, size: 22),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Quét mã QR'),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _scanQrCode,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 22),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Chọn File PDF/Ảnh'),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _pickAndVerifyFile,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.photo_library_outlined, size: 20),
          label: const Text('Chọn Ảnh Văn Bằng từ Thư viện (Băm trên RAM)'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _pickImageCertificate,
        ),
      ],
    );
  }

  // Ô nhập mã Hash thủ công
  Widget _buildManualHashCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tra cứu bằng mã Data Hash (bytes32):',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hashInputController,
              onSubmitted: (val) => _startVerifyHash(val),
              decoration: InputDecoration(
                hintText: '0x...',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_hashInputController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'Xóa',
                        onPressed: () {
                          setState(() {
                            _hashInputController.clear();
                          });
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.search),
                      tooltip: 'Tra cứu',
                      onPressed: () => _startVerifyHash(_hashInputController.text),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Thẻ hiển thị kết quả băm Client-side trên RAM (Keccak-256 & SHA-256)
  Widget _buildClientRamHashInfoCard(BuildContext context) {
    final kb = ((_selectedFileSize ?? 0) / 1024).toStringAsFixed(1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.memory, size: 18, color: Colors.teal),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Đã băm trên RAM: $_selectedFileName ($kb KB)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                ),
              ],
            ),
            if (_computedKeccak256 != null) ...[
              const SizedBox(height: 6),
              Text(
                '• Keccak-256: $_computedKeccak256',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ],
            if (_computedSha256 != null) ...[
              const SizedBox(height: 2),
              Text(
                '• SHA-256: $_computedSha256',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
