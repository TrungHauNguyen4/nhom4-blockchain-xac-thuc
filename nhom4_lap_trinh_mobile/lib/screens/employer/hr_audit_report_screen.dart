import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/certificate_record.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/db_service.dart';
import '../../services/hr_review_service.dart';
import '../verifier/verify_detail_screen.dart';

/// Màn hình chuyên biệt hiển thị Biên Bản Thẩm Định HR (Hạng mục 1A)
/// Tách bạch hoàn toàn khỏi màn hình Kết quả kiểm tra (VerifyDetailScreen)
class HrAuditReportScreen extends StatefulWidget {
  final String hashKey;
  final Map<String, dynamic> reviewData;
  final CertificateRecord? initialRecord;

  const HrAuditReportScreen({
    super.key,
    required this.hashKey,
    required this.reviewData,
    this.initialRecord,
  });

  @override
  State<HrAuditReportScreen> createState() => _HrAuditReportScreenState();
}

class _HrAuditReportScreenState extends State<HrAuditReportScreen> {
  late Map<String, dynamic> _reviewData;
  CertificateRecord? _record;
  bool _isOpeningDetail = false;

  @override
  void initState() {
    super.initState();
    _reviewData = Map<String, dynamic>.from(widget.reviewData);
    _record = widget.initialRecord;
  }

  String get _dataHash =>
      (_reviewData['dataHash'] ?? widget.hashKey).toString().trim();

  String get _status => (_reviewData['status'] ?? 'APPROVED').toString();

  bool get _isValid {
    if (_record != null) return _record!.isValid;
    return _reviewData['isValid'] == true;
  }

  String _formatBlockchainTimestamp(dynamic rawTs) {
    if (_record != null && _record!.timestamp > 0) {
      return _record!.formattedBlockchainDate;
    }
    final ts = rawTs is int ? rawTs : int.tryParse((rawTs ?? '').toString());
    if (ts == null || ts <= 0) return 'N/A';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }

  String _buildReportText(
    String evaluatorOrg,
    String evaluatorName,
    String evaluatorEmail,
  ) {
    String statusLabel;
    switch (_status) {
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
        statusLabel = _status;
    }

    final studentName =
        _record?.studentName ?? _reviewData['studentName']?.toString() ?? 'N/A';
    final studentCode =
        _record?.studentCode ?? _reviewData['studentCode']?.toString() ?? 'N/A';
    final degreeName =
        _record?.degreeName ??
        _reviewData['degreeName']?.toString() ??
        _reviewData['fileName']?.toString() ??
        'N/A';
    final issuerName =
        _record?.issuerName ?? _reviewData['issuerName']?.toString() ?? 'N/A';
    final txHash = _record?.txHash ?? _reviewData['txHash']?.toString();
    final updatedAt = (_reviewData['updatedAt'] ?? '').toString();
    final note = (_reviewData['note'] ?? '').toString().trim();

    return [
      '=== BIÊN BẢN THẨM ĐỊNH VĂN BẰNG BLOCKCHAIN (HR) ===',
      'Thời gian lập / cập nhật: ${updatedAt.isNotEmpty ? updatedAt : DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
      'Đơn vị thẩm định: $evaluatorOrg',
      'Chuyên viên thẩm định: $evaluatorName ($evaluatorEmail)',
      '---------------------------------------------------',
      'KẾT QUẢ ĐỐI SOÁT SỔ GỐC: ${_isValid ? "HỢP LỆ (CHÍNH CHỦ)" : "CẢNH BÁO KHÔNG TỒN TẠI / BẰNG GIẢ"}',
      'Họ tên ứng viên: $studentName',
      'Mã số sinh viên: $studentCode',
      'Tên văn bằng: $degreeName',
      'Đơn vị cấp phát: $issuerName',
      'Ngày cấp trên Blockchain: ${_formatBlockchainTimestamp(_reviewData['timestamp'])}',
      'Mã băm văn bằng (Hash): $_dataHash',
      if (txHash != null && txHash.isNotEmpty) 'Mã giao dịch (TxHash): $txHash',
      '---------------------------------------------------',
      'QUYẾT ĐỊNH TUYỂN DỤNG HR: $statusLabel',
      'Ghi chú phỏng vấn: ${note.isEmpty ? "(Không có)" : note}',
      '===================================================',
    ].join('\n');
  }

  Future<void> _openVerifyDetailScreen() async {
    if (_isOpeningDetail) return;
    setState(() => _isOpeningDetail = true);

    try {
      CertificateRecord? resolved = _record ??
          await DatabaseService.instance.getCertificateByHash(_dataHash);

      if (resolved == null && mounted) {
        try {
          final api =
              Provider.of<ApiService?>(context, listen: false) ?? ApiService();
          resolved = await api.verifyHash(
            _dataHash,
            fileName:
                (_reviewData['fileName'] ?? 'Văn bằng thẩm định').toString(),
          );
        } catch (_) {}
      }

      if (resolved == null && _isValid) {
        final signer = (_reviewData['signer'] ?? '').toString();
        final ts = _reviewData['timestamp'] is int
            ? _reviewData['timestamp'] as int
            : int.tryParse((_reviewData['timestamp'] ?? '0').toString()) ?? 0;
        if (signer.isNotEmpty && ts > 0) {
          resolved = CertificateRecord(
            dataHash: _dataHash,
            signer: signer,
            timestamp: ts,
            fileName:
                (_reviewData['fileName'] ?? 'Văn bằng thẩm định').toString(),
            fileType: (_reviewData['fileType'] ?? 'DOCUMENT').toString(),
            txHash: _reviewData['txHash']?.toString(),
            blockNumber: _reviewData['blockNumber'] is int
                ? _reviewData['blockNumber'] as int
                : int.tryParse((_reviewData['blockNumber'] ?? '').toString()),
            studentName: _reviewData['studentName']?.toString(),
            studentCode: _reviewData['studentCode']?.toString(),
            degreeName: _reviewData['degreeName']?.toString(),
            issuerName: _reviewData['issuerName']?.toString(),
          );
        }
      }

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VerifyDetailScreen(
            record: resolved,
            searchedHash: _dataHash,
            isFromOfflineVault: resolved != null,
          ),
        ),
      );

      // Tải lại quyết định HR mới nhất sau khi người dùng có thể đã chỉnh sửa
      if (!mounted) return;
      final uid = Provider.of<AuthProvider?>(context, listen: false)
          ?.currentUser
          ?.uid;
      final latestMap = await HrReviewService().fetchReviews(uid: uid);
      final normalized = HrReviewService().normalizeHashKey(widget.hashKey);
      if (mounted && latestMap.containsKey(normalized)) {
        setState(() {
          _reviewData = latestMap[normalized]!;
          if (resolved != null) _record = resolved;
        });
      }
    } finally {
      if (mounted) setState(() => _isOpeningDetail = false);
    }
  }

  Future<void> _confirmDeleteReview() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa biên bản thẩm định?'),
        content: const Text(
          'Biên bản thẩm định HR của văn bằng này sẽ bị xóa khỏi danh sách đã thẩm định trên hệ thống.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final uid = Provider.of<AuthProvider?>(context, listen: false)
        ?.currentUser
        ?.uid;
    await HrReviewService().deleteReview(uid: uid, hashKey: widget.hashKey);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hrUser = Provider.of<AuthProvider?>(context)?.currentUser;

    final evaluatorOrg =
        hrUser?.organization.trim().isNotEmpty == true
            ? hrUser!.organization.trim()
            : 'Bộ phận Tuyển dụng HR';
    final evaluatorName =
        hrUser?.name.trim().isNotEmpty == true
            ? hrUser!.name.trim()
            : 'HR Verifier';
    final evaluatorEmail = hrUser?.email ?? '';

    final studentName =
        _record?.studentName ??
        _reviewData['studentName']?.toString() ??
        'Chưa định danh';
    final studentCode =
        _record?.studentCode ?? _reviewData['studentCode']?.toString() ?? '';
    final degreeName =
        _record?.degreeName ??
        _reviewData['degreeName']?.toString() ??
        _reviewData['fileName']?.toString() ??
        'Văn bằng kiểm tra';
    final issuerName =
        _record?.issuerName ??
        _reviewData['issuerName']?.toString() ??
        'Không xác định';
    final txHash = _record?.txHash ?? _reviewData['txHash']?.toString();
    final updatedAt = (_reviewData['updatedAt'] ?? '').toString();
    final hrNote = (_reviewData['note'] ?? '').toString().trim();

    Color statusColor;
    String statusShortLabel;
    IconData statusIcon;
    switch (_status) {
      case 'APPROVED':
        statusColor = Colors.green;
        statusShortLabel = 'ĐẠT THẨM ĐỊNH';
        statusIcon = Icons.check_circle_outline;
        break;
      case 'PENDING':
        statusColor = Colors.orange;
        statusShortLabel = 'CHỜ BỔ SUNG';
        statusIcon = Icons.hourglass_bottom_rounded;
        break;
      case 'REJECTED':
        statusColor = Colors.redAccent;
        statusShortLabel = 'TỪ CHỐI HỒ SƠ';
        statusIcon = Icons.cancel_outlined;
        break;
      default:
        statusColor = Colors.blueGrey;
        statusShortLabel = _status;
        statusIcon = Icons.info_outline;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Biên Bản Thẩm Định HR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: 'Xóa biên bản thẩm định',
            onPressed: _confirmDeleteReview,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header Biên bản chính thức
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  colors: [Color(0xFF18181A), Color(0xFF565C43)],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'BIÊN BẢN THẨM ĐỊNH VĂN BẰNG (HR)',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                        if (updatedAt.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Cập nhật: $updatedAt',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 2. Banner Kết quả đối soát Blockchain
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _isValid
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _isValid
                      ? Colors.green.withValues(alpha: 0.5)
                      : Colors.red.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isValid ? Icons.verified : Icons.gpp_bad,
                    color: _isValid ? Colors.green : Colors.red,
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isValid
                              ? 'KẾT QUẢ ĐỐI SOÁT: HỢP LỆ (CHÍNH CHỦ)'
                              : 'KẾT QUẢ ĐỐI SOÁT: KHÔNG TỒN TẠI',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _isValid
                                ? (isDark
                                    ? Colors.greenAccent
                                    : Colors.green.shade800)
                                : Colors.redAccent,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Đối chiếu trực tiếp từ sổ gốc điện tử Blockchain',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 3. I. ĐƠN VỊ THẨM ĐỊNH
            _buildSectionTitle('I. ĐƠN VỊ THẨM ĐỊNH'),
            const SizedBox(height: 6),
            _buildInfoCard(isDark, [
              _buildRow('Đơn vị tuyển dụng', evaluatorOrg),
              _buildRow('Chuyên viên HR', evaluatorName),
              if (evaluatorEmail.isNotEmpty) _buildRow('Email', evaluatorEmail),
            ]),
            const SizedBox(height: 14),

            // 4. II. THÔNG TIN VĂN BẰNG & ỨNG VIÊN
            _buildSectionTitle('II. THÔNG TIN VĂN BẰNG & ỨNG VIÊN'),
            const SizedBox(height: 6),
            _buildInfoCard(isDark, [
              _buildRow('Họ tên ứng viên', studentName),
              if (studentCode.isNotEmpty) _buildRow('Mã số sinh viên', studentCode),
              _buildRow('Tên văn bằng', degreeName),
              _buildRow('Đơn vị cấp phát', issuerName),
              _buildRow(
                'Ngày cấp Blockchain',
                _formatBlockchainTimestamp(_reviewData['timestamp']),
              ),
              _buildRow('Mã băm (Hash)', _dataHash, monospace: true),
              if (txHash != null && txHash.isNotEmpty)
                _buildRow('Mã giao dịch (Tx)', txHash, monospace: true),
            ]),
            const SizedBox(height: 14),

            // 5. III. QUYẾT ĐỊNH TUYỂN DỤNG HR
            _buildSectionTitle('III. QUYẾT ĐỊNH TUYỂN DỤNG HR'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(statusIcon, color: statusColor, size: 20),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          statusShortLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Ghi chú phỏng vấn / Thẩm định:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hrNote.isEmpty ? '(Không có ghi chú)' : hrNote,
                    style: const TextStyle(fontSize: 13.5, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: _isOpeningDetail
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fact_check_outlined, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Xem / Sửa gốc'),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isOpeningDetail ? null : _openVerifyDetailScreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 18),
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
                    final reportText = _buildReportText(
                      evaluatorOrg,
                      evaluatorName,
                      evaluatorEmail,
                    );
                    Clipboard.setData(ClipboardData(text: reportText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Colors.teal,
                        content: Text('Đã sao chép Biên bản thẩm định HR!'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
        color: Color(0xFF8E9773),
      ),
    );
  }

  Widget _buildInfoCard(bool isDark, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool monospace = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: monospace ? 11.5 : 12.5,
                fontWeight: FontWeight.w600,
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
