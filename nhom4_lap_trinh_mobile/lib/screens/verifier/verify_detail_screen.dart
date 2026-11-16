import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/certificate_record.dart';
import '../../providers/auth_provider.dart';
import '../../services/db_service.dart';
import '../../services/hr_review_service.dart';

class VerifyDetailScreen extends StatefulWidget {
  final CertificateRecord? record;
  final String searchedHash;
  final bool isFromOfflineVault;

  const VerifyDetailScreen({
    super.key,
    required this.record,
    required this.searchedHash,
    this.isFromOfflineVault = false,
  });

  @override
  State<VerifyDetailScreen> createState() => _VerifyDetailScreenState();
}

class _VerifyDetailScreenState extends State<VerifyDetailScreen> {
  bool _isSaved = false;
  bool _isLoading = false;

  // Trạng thái thẩm định HR (dành cho role Nhà tuyển dụng)
  String _hrStatus = 'APPROVED'; // APPROVED, PENDING, REJECTED
  bool _hasSavedHrReview = false;
  final TextEditingController _hrNoteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkSavedStatus();
    _loadHrReview();
  }

  @override
  void dispose() {
    _hrNoteController.dispose();
    super.dispose();
  }

  final HrReviewService _hrReviewService = HrReviewService();

  String get _effectiveHashKey =>
      _hrReviewService.normalizeHashKey(
        widget.record?.dataHash ?? widget.searchedHash,
      );

  Future<void> _loadHrReview() async {
    try {
      final uid = Provider.of<AuthProvider?>(context, listen: false)
          ?.currentUser
          ?.uid;
      final reviews = await _hrReviewService.fetchReviews(uid: uid);
      final item = reviews[_effectiveHashKey];
      if (item != null && mounted) {
        setState(() {
          _hrStatus = (item['status'] ?? 'APPROVED').toString();
          _hrNoteController.text = (item['note'] ?? '').toString();
          _hasSavedHrReview = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveHrReview() async {
    try {
      final uid = Provider.of<AuthProvider?>(context, listen: false)
          ?.currentUser
          ?.uid;
      final now = DateTime.now();
      final formattedNow =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final record = widget.record;
      final reviewPayload = {
        'dataHash': record?.dataHash ?? widget.searchedHash,
        'status': _hrStatus,
        'note': _hrNoteController.text.trim(),
        'signer': record?.signer ?? '',
        'timestamp': record?.timestamp ?? 0,
        'fileName': record?.fileName ?? 'Văn bằng kiểm tra',
        'fileType': record?.fileType ?? 'DOCUMENT',
        'txHash': record?.txHash,
        'blockNumber': record?.blockNumber,
        'studentName': record?.studentName ?? 'Ứng viên chưa định danh',
        'studentCode': record?.studentCode ?? '',
        'degreeName': record?.degreeName ?? record?.fileName ?? 'Hồ sơ kiểm tra',
        'issuerName': record?.issuerName ?? '',
        'isValid': record != null && record.isValid,
        'updatedAt': formattedNow,
      };

      await _hrReviewService.saveReview(
        uid: uid,
        hashKey: _effectiveHashKey,
        reviewData: reviewPayload,
      );

      // Tự động lưu văn bằng hợp lệ vào Sổ tay Offline để khi mở lại từ Trung tâm Thẩm định HR luôn đủ thông tin & QR
      if (record != null && record.isValid) {
        await DatabaseService.instance.saveCertificate(record);
      }

      if (!mounted) return;
      setState(() {
        _hasSavedHrReview = true;
        if (record != null && record.isValid) {
          _isSaved = true;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.teal,
          content: Text('Đã lưu quyết định thẩm định HR vào hồ sơ tuyển dụng!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể lưu đánh giá HR: $e')),
      );
    }
  }

  void _showHrAuditReportDialog(BuildContext context) {
    final auth = Provider.of<AuthProvider?>(context, listen: false);
    final hrUser = auth?.currentUser;
    final record = widget.record;
    final bool isValid = record != null && record.isValid;

    String statusLabel;
    switch (_hrStatus) {
      case 'APPROVED':
        statusLabel = 'ĐẠT THẨM ĐỊNH (ĐỦ ĐIỀU KIỆN TUYỂN DỤNG)';
        break;
      case 'PENDING':
        statusLabel = 'CHỜ BỔ SUNG HỒ SƠ GỐC';
        break;
      case 'REJECTED':
        statusLabel = 'TỪ CHỐI HỒ SƠ';
        break;
      default:
        statusLabel = _hrStatus;
    }

    final now = DateTime.now();
    final timeStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final reportText = [
      '=== BIÊN BẢN THẨM ĐỊNH VĂN BẰNG BLOCKCHAIN (HR) ===',
      'Thời gian lập: $timeStr',
      'Đơn vị thẩm định: ${hrUser?.organization ?? "Bộ phận Tuyển dụng HR"}',
      'Chuyên viên thẩm định: ${hrUser?.name ?? "HR Verifier"} (${hrUser?.email ?? ""})',
      '---------------------------------------------------',
      'KẾT QUẢ ĐỐI SOÁT SỔ GỐC: ${isValid ? "HỢP LỆ (CHÍNH CHỦ)" : "CẢNH BÁO KHÔNG TỒN TẠI / BẰNG GIẢ"}',
      'Họ tên ứng viên: ${record?.studentName ?? "N/A"}',
      'Mã số sinh viên: ${record?.studentCode ?? "N/A"}',
      'Tên văn bằng: ${record?.degreeName ?? record?.fileName ?? "N/A"}',
      'Đơn vị cấp phát: ${record?.issuerName ?? "N/A"}',
      'Ngày cấp trên Blockchain: ${record?.formattedBlockchainDate ?? "N/A"}',
      'Mã băm văn bằng (Hash): ${record?.dataHash ?? widget.searchedHash}',
      if (record?.txHash != null && record!.txHash!.isNotEmpty)
        'Mã giao dịch (TxHash): ${record.txHash}',
      '---------------------------------------------------',
      'QUYẾT ĐỊNH TUYỂN DỤNG HR: $statusLabel',
      'Ghi chú phỏng vấn: ${_hrNoteController.text.trim().isEmpty ? "(Không có)" : _hrNoteController.text.trim()}',
      '===================================================',
    ].join('\n');

    final String hrNote = _hrNoteController.text.trim();
    Color statusColor;
    String statusShortLabel;
    switch (_hrStatus) {
      case 'APPROVED':
        statusColor = Colors.green;
        statusShortLabel = 'ĐẠT THẨM ĐỊNH';
        break;
      case 'PENDING':
        statusColor = Colors.orange;
        statusShortLabel = 'CHỜ BỔ SUNG';
        break;
      case 'REJECTED':
        statusColor = Colors.redAccent;
        statusShortLabel = 'TỪ CHỐI HỒ SƠ';
        break;
      default:
        statusColor = Colors.blueGrey;
        statusShortLabel = _hrStatus;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Header Biên bản chính thức
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF18181A), Color(0xFF565C43)],
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.verified_user_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'BIÊN BẢN THẨM ĐỊNH VĂN BẰNG (HR)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Ngày lập: $timeStr',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        tooltip: 'Đóng',
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),

                // 2. Nội dung chi tiết dạng Phiếu hành chính
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Banner Kết quả đối soát Blockchain
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isValid
                                ? Colors.green.withValues(alpha: 0.12)
                                : Colors.red.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isValid
                                  ? Colors.green.withValues(alpha: 0.5)
                                  : Colors.red.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isValid ? Icons.verified : Icons.gpp_bad,
                                color: isValid ? Colors.green : Colors.red,
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isValid
                                          ? 'KẾT QUẢ ĐỐI SOÁT: HỢP LỆ (CHÍNH CHỦ)'
                                          : 'KẾT QUẢ ĐỐI SOÁT: KHÔNG TỒN TẠI',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12.5,
                                        color: isValid
                                            ? (isDark
                                                ? Colors.greenAccent
                                                : Colors.green.shade800)
                                            : Colors.redAccent,
                                      ),
                                    ),
                                    const Text(
                                      'Đối chiếu trực tiếp từ sổ gốc điện tử Blockchain',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Thông tin Đơn vị & Chuyên viên HR
                        _buildReportSectionTitle('I. ĐƠN VỊ THẨM ĐỊNH'),
                        const SizedBox(height: 6),
                        _buildReportCardContainer(
                          ctx,
                          children: [
                            _buildReportRow(
                              'Đơn vị HR:',
                              hrUser?.organization.trim().isNotEmpty == true
                                  ? hrUser!.organization
                                  : 'Bộ phận Tuyển dụng HR',
                            ),
                            const Divider(height: 12),
                            _buildReportRow(
                              'Chuyên viên:',
                              hrUser?.name ?? 'HR Verifier',
                            ),
                            if (hrUser?.email != null &&
                                hrUser!.email.isNotEmpty) ...[
                              const Divider(height: 12),
                              _buildReportRow('Email HR:', hrUser.email),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Thông tin Ứng viên & Văn bằng
                        _buildReportSectionTitle('II. HỒ SƠ VĂN BẰNG ỨNG VIÊN'),
                        const SizedBox(height: 6),
                        _buildReportCardContainer(
                          ctx,
                          children: [
                            _buildReportRow(
                              'Họ tên ứng viên:',
                              record?.studentName ?? 'N/A',
                            ),
                            const Divider(height: 12),
                            _buildReportRow(
                              'Mã số sinh viên:',
                              record?.studentCode ?? 'N/A',
                            ),
                            const Divider(height: 12),
                            _buildReportRow(
                              'Tên văn bằng:',
                              record?.degreeName ?? record?.fileName ?? 'N/A',
                            ),
                            const Divider(height: 12),
                            _buildReportRow(
                              'Đơn vị cấp phát:',
                              record?.issuerName ?? 'N/A',
                            ),
                            const Divider(height: 12),
                            _buildReportRow(
                              'Ngày cấp gốc:',
                              record?.formattedBlockchainDate ?? 'N/A',
                            ),
                            const Divider(height: 12),
                            const Text(
                              'Mã băm định danh (DataHash):',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(ctx)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: SelectableText(
                                record?.dataHash ?? widget.searchedHash,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            if (record?.txHash != null &&
                                record!.txHash!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const Text(
                                'Mã giao dịch (TxHash):',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SelectableText(
                                  record.txHash!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Quyết định Tuyển dụng
                        _buildReportSectionTitle('III. KẾT LUẬN TUYỂN DỤNG'),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      statusShortLabel,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Ghi chú phỏng vấn: ${hrNote.isEmpty ? "Không có ghi chú thêm." : hrNote}',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. Thanh nút hành động dưới đáy
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Đóng'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.copy_rounded, size: 17),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Sao chép Biên bản'),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF565C43),
                            foregroundColor: const Color(0xFFECEBE6),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _copyToClipboard(
                              reportText,
                              'Biên bản thẩm định HR',
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReportSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
        color: Colors.blueGrey,
      ),
    );
  }

  Widget _buildReportCardContainer(
    BuildContext ctx, {
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(ctx)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.blueGrey.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildReportRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // [READ] Kiểm tra chứng chỉ đã có trong Sổ tay Sqflite chưa
  Future<void> _checkSavedStatus() async {
    if (widget.record != null) {
      final saved = await DatabaseService.instance.isCertificateSaved(
        widget.record!.dataHash,
      );
      if (mounted) setState(() => _isSaved = saved);
    }
  }

  // [CREATE / DELETE] Lưu hoặc xóa văn bằng khỏi Sổ tay Offline (Sqflite)
  Future<void> _toggleSaveOffline() async {
    if (widget.record == null) return;
    setState(() => _isLoading = true);

    try {
      if (_isSaved) {
        await DatabaseService.instance.deleteCertificateByHash(
          widget.record!.dataHash,
        );
        if (!mounted) return;
        setState(() => _isSaved = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã xóa văn bằng khỏi bộ nhớ máy.'),
          ),
        );
      } else {
        await DatabaseService.instance.saveCertificate(widget.record!);
        if (!mounted) return;
        setState(() => _isSaved = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('Đã lưu văn bằng về máy! Bạn có thể mở xem ngay cả khi tắt mạng.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã sao chép $label')),
    );
  }

  // Hiển thị hộp thoại phóng to mã QR để Sinh viên xuất trình khi phỏng vấn
  void _showFullScreenQr(String dataHash, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                'Quét mã QR này để đối soát trực tiếp trên Blockchain',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: dataHash,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                dataHash,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Đóng'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isValid = widget.record != null && widget.record!.isValid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kết Quả Kiểm Tra'),
        actions: [
          if (isValid)
            IconButton(
              icon: Icon(
                _isSaved ? Icons.bookmark : Icons.bookmark_border,
                color: _isSaved ? Colors.amberAccent : Colors.white,
              ),
              tooltip: _isSaved
                  ? 'Bỏ lưu trên máy'
                  : 'Lưu về máy (Xem khi không có mạng)',
              onPressed: _isLoading ? null : _toggleSaveOffline,
            ),
        ],
      ),
      // Sử dụng OrientationBuilder để tự động đáp ứng xoay ngang (2 cột) / dọc (1 cột)
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isPortrait =
              MediaQuery.orientationOf(context) == Orientation.portrait;
          if (isPortrait) {
            return _buildPortraitLayout(context, isValid);
          } else {
            return _buildLandscapeLayout(context, isValid);
          }
        },
      ),
    );
  }

  // Giao diện Màn hình Dọc (Portrait - 1 Cột)
  Widget _buildPortraitLayout(BuildContext context, bool isValid) {
    final isEmployer =
        Provider.of<AuthProvider?>(context)?.currentUser?.isEmployer ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatusHeader(isValid),
          const SizedBox(height: 16),
          _buildDetailsCard(context, isValid),
          if (isEmployer) ...[
            const SizedBox(height: 16),
            _buildEmployerActionCard(context, isValid),
          ],
          if (isValid) ...[
            const SizedBox(height: 16),
            _buildQrCertificateCard(context),
            const SizedBox(height: 20),
            _buildSaveOfflineButton(),
          ],
        ],
      ),
    );
  }

  // Giao diện Màn hình Ngang (Landscape - Chia 2 Cột linh hoạt bằng Row + Expanded)
  Widget _buildLandscapeLayout(BuildContext context, bool isValid) {
    final isEmployer =
        Provider.of<AuthProvider?>(context)?.currentUser?.isEmployer ?? false;

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
                  _buildStatusHeader(isValid),
                  if (isValid) ...[
                    const SizedBox(height: 16),
                    _buildQrCertificateCard(context),
                    const SizedBox(height: 16),
                    _buildSaveOfflineButton(),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDetailsCard(context, isValid),
                  if (isEmployer) ...[
                    const SizedBox(height: 16),
                    _buildEmployerActionCard(context, isValid),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Khối Nghiệp vụ Thẩm định Tuyển dụng dành riêng cho Nhà tuyển dụng (Employer / HR)
  Widget _buildEmployerActionCard(BuildContext context, bool isValid) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.business_center_rounded, color: Colors.teal),
                const SizedBox(width: 8),
                const Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'QUYẾT ĐỊNH THẨM ĐỊNH TUYỂN DỤNG (HR)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: Colors.teal,
                      ),
                    ),
                  ),
                ),
                if (_hasSavedHrReview)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Đã lưu HR',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text(
                    'Đạt thẩm định',
                    style: TextStyle(fontSize: 12),
                  ),
                  selected: _hrStatus == 'APPROVED',
                  selectedColor: Colors.green.withValues(alpha: 0.22),
                  onSelected: (_) => setState(() => _hrStatus = 'APPROVED'),
                ),
                ChoiceChip(
                  label: const Text(
                    'Chờ bổ sung',
                    style: TextStyle(fontSize: 12),
                  ),
                  selected: _hrStatus == 'PENDING',
                  selectedColor: Colors.orange.withValues(alpha: 0.22),
                  onSelected: (_) => setState(() => _hrStatus = 'PENDING'),
                ),
                ChoiceChip(
                  label: const Text(
                    'Từ chối',
                    style: TextStyle(fontSize: 12),
                  ),
                  selected: _hrStatus == 'REJECTED',
                  selectedColor: Colors.redAccent.withValues(alpha: 0.22),
                  onSelected: (_) => setState(() => _hrStatus = 'REJECTED'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hrNoteController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Ghi chú phỏng vấn / Nhận xét của HR',
                hintText:
                    'VD: Bằng chính chủ, ứng viên đạt vòng thẩm định hồ sơ...',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  onPressed: _saveHrReview,
                  icon: const Icon(Icons.task_alt_rounded, size: 18),
                  label: const Text('Lưu Quyết định HR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showHrAuditReportDialog(context),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('Xuất Biên bản Thẩm định HR'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Nút Lưu / Xóa khỏi Sổ tay Offline
  Widget _buildSaveOfflineButton() {
    return ElevatedButton.icon(
      icon: Icon(_isSaved ? Icons.bookmark_added : Icons.download_for_offline),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          _isSaved
              ? 'Đã lưu trên máy (Nhấn để bỏ lưu)'
              : 'Lưu về máy (Xem khi không có mạng)',
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _isSaved ? Colors.teal : null,
        foregroundColor: _isSaved ? Colors.white : null,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: _isLoading ? null : _toggleSaveOffline,
    );
  }

  // Huy hiệu trạng thái Xác thực (Bọc FittedBox chống tràn viền theo chuẩn Chương 9 flutter_demo)
  Widget _buildStatusHeader(bool isValid) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isValid
            ? Colors.green.withValues(alpha: 0.12)
            : Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isValid ? Colors.green : Colors.red,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Icon(
            isValid ? Icons.verified : Icons.gpp_bad,
            size: 60,
            color: isValid ? Colors.green : Colors.red,
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              isValid
                  ? 'VĂN BẰNG HỢP LỆ (CHÍNH CHỦ)'
                  : 'CẢNH BÁO BẰNG GIẢ / KHÔNG TỒN TẠI',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? (isValid ? Colors.greenAccent : Colors.redAccent)
                    : (isValid ? Colors.green.shade800 : Colors.red.shade800),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isValid
                ? 'Văn bằng này đã được đối chiếu trùng khớp với sổ gốc điện tử của nhà trường'
                : 'Mã nhận diện không khớp với bất kỳ văn bằng nào từng được cấp phát trên hệ thống.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          if (widget.isFromOfflineVault) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.offline_pin, size: 15, color: Colors.orange),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Đang mở từ bộ nhớ máy',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Khung hiển thị Mã QR của Văn bằng để xuất trình Offline
  Widget _buildQrCertificateCard(BuildContext context) {
    final record = widget.record!;
    final title =
        (record.degreeName != null && record.degreeName!.trim().isNotEmpty)
            ? record.degreeName!
            : record.fileName;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.qr_code_2, color: Colors.blueAccent),
                      SizedBox(width: 8),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Mã QR Định Danh Văn Bằng',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.fullscreen, size: 18),
                  label: const Text('Phóng to'),
                  onPressed: () => _showFullScreenQr(record.dataHash, title),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showFullScreenQr(record.dataHash, title),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: QrImageView(
                  data: record.dataHash,
                  version: QrVersions.auto,
                  size: 150,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sinh viên có thể lưu Offline để xuất trình mã QR này khi đi phỏng vấn',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // Thẻ thông tin chi tiết văn bằng
  Widget _buildDetailsCard(BuildContext context, bool isValid) {
    if (!isValid) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Thông tin mã văn bằng đã kiểm tra:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildCopyableRow(
                'Mã văn bằng tra cứu:',
                widget.searchedHash,
                'Mã văn bằng tra cứu',
              ),
              const SizedBox(height: 12),
              const Text(
                'Gợi ý kiểm tra:\n'
                '• Đảm bảo file PDF/Ảnh là bản gốc do trường cấp (chưa bị chỉnh sửa hay cắt ghép).\n'
                '• Kiểm tra lại mã QR hoặc mã số văn bằng (0x...).',
                style: TextStyle(fontSize: 12.5, color: Colors.grey, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    final record = widget.record!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'THÔNG TIN CHI TIẾT VĂN BẰNG',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 0.5,
                color: Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 10),
            _buildInfoRow('Tệp / Hồ sơ:', record.fileName,
                icon: Icons.description_outlined),
            if (record.degreeName != null &&
                record.degreeName!.trim().isNotEmpty) ...[
              const Divider(),
              _buildInfoRow('Tên văn bằng:', record.degreeName!,
                  icon: Icons.school_outlined),
            ],
            if (record.studentName != null &&
                record.studentName!.trim().isNotEmpty) ...[
              const Divider(),
              _buildInfoRow('Họ tên sinh viên:', record.studentName!,
                  icon: Icons.person_outline),
            ],
            if (record.studentCode != null &&
                record.studentCode!.trim().isNotEmpty) ...[
              const Divider(),
              _buildInfoRow('Mã số sinh viên:', record.studentCode!,
                  icon: Icons.badge_outlined),
            ],
            const Divider(),
            _buildInfoRow('Đơn vị cấp phát:', record.issuerName,
                icon: Icons.account_balance_outlined),
            const Divider(),
            _buildInfoRow('Loại định dạng:', record.fileType,
                icon: Icons.insert_drive_file_outlined),
            const Divider(),
            _buildInfoRow('Ngày cấp:', record.formattedBlockchainDate,
                icon: Icons.access_time),
            if (record.blockNumber != null) ...[
              const Divider(),
              _buildInfoRow('Số hồ sơ lưu trữ:', '#${record.blockNumber}',
                  icon: Icons.layers_outlined),
            ],
            const Divider(),
            _buildCopyableRow('Mã định danh đơn vị cấp:', record.signer,
                'Mã định danh đơn vị cấp'),
            const Divider(),
            _buildCopyableRow('Mã số văn bằng:', record.dataHash,
                'Mã số văn bằng'),
            if (record.txHash != null && record.txHash!.trim().isNotEmpty) ...[
              const Divider(),
              _buildCopyableRow('Mã giao dịch xác thực:',
                  record.txHash!, 'Mã giao dịch xác thực'),
            ],
            if (widget.isFromOfflineVault) ...[
              const Divider(),
              _buildInfoRow('Thời điểm lưu trên máy:', record.savedAt,
                  icon: Icons.offline_pin_outlined),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: Colors.blueGrey),
            const SizedBox(width: 8),
          ],
          Flexible(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCopyableRow(String label, String value, String copyLabel) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 16, color: Colors.blue),
                tooltip: 'Sao chép',
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
                onPressed: () => _copyToClipboard(value, copyLabel),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}
