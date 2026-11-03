import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/certificate_record.dart';
import '../../services/db_service.dart';

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

  @override
  void initState() {
    super.initState();
    _checkSavedStatus();
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
            content: Text('Đã xóa văn bằng khỏi Sổ tay Offline (Sqflite).'),
          ),
        );
      } else {
        await DatabaseService.instance.saveCertificate(widget.record!);
        if (!mounted) return;
        setState(() => _isSaved = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('Đã lưu văn bằng vào Sổ tay Cục bộ (Sqflite)!'),
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
        child: Padding(
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
                  size: 230,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                dataHash,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey),
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
        title: const Text('Kết Quả Kiểm Định'),
        actions: [
          if (isValid)
            IconButton(
              icon: Icon(
                _isSaved ? Icons.bookmark : Icons.bookmark_border,
                color: _isSaved ? Colors.amberAccent : Colors.white,
              ),
              tooltip: _isSaved ? 'Bỏ lưu khỏi Sổ tay Offline' : 'Lưu vào Sổ tay Offline (Sqflite)',
              onPressed: _isLoading ? null : _toggleSaveOffline,
            ),
        ],
      ),
      // Sử dụng OrientationBuilder để tự động đáp ứng xoay ngang (2 cột) / dọc (1 cột)
      body: OrientationBuilder(
        builder: (context, orientation) {
          if (orientation == Orientation.portrait) {
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatusHeader(isValid),
          const SizedBox(height: 16),
          _buildDetailsCard(context, isValid),
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
              child: _buildDetailsCard(context, isValid),
            ),
          ),
        ],
      ),
    );
  }

  // Nút Lưu / Xóa khỏi Sổ tay Offline
  Widget _buildSaveOfflineButton() {
    return ElevatedButton.icon(
      icon: Icon(_isSaved ? Icons.bookmark_added : Icons.download_for_offline),
      label: Text(
        _isSaved
            ? 'Đã lưu trong Sổ tay Offline (Nhấn để bỏ lưu)'
            : 'Lưu vào Sổ tay Offline (Sqflite)',
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _isSaved ? Colors.teal : null,
        foregroundColor: _isSaved ? Colors.white : null,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: _isLoading ? null : _toggleSaveOffline,
    );
  }

  // Huy hiệu trạng thái Xác thực (Bọc FittedBox chống tràn viền theo chuẩn Chương 9 flutter_demo)
  Widget _buildStatusHeader(bool isValid) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isValid
            ? Colors.green.withValues(alpha: 0.12)
            : Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
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
              isValid ? 'VĂN BẰNG HỢP LỆ (CHÍNH CHỦ)' : 'CẢNH BÁO BẰNG GIẢ / KHÔNG TỒN TẠI',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isValid ? Colors.green.shade800 : Colors.red.shade800,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isValid
                ? 'Chứng chỉ này đã được đối soát chính xác với Sổ cái Blockchain Ethereum Sepolia'
                : 'Mã băm dữ liệu không khớp với bất kỳ chứng chỉ nào từng được cấp phát trên Blockchain.',
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
                  Text(
                    'Đang xem từ Sổ tay Offline (Sqflite)',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
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
    final title = (record.degreeName != null && record.degreeName!.trim().isNotEmpty)
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
                const Row(
                  children: [
                    Icon(Icons.qr_code_2, color: Colors.blueAccent),
                    SizedBox(width: 8),
                    Text(
                      'Mã QR Định Danh Văn Bằng',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
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
                  Text(
                    'Thông tin mã băm đã kiểm tra:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildCopyableRow(
                'Mã Hash tra cứu (Keccak-256):',
                widget.searchedHash,
                'Mã Hash tra cứu',
              ),
              const SizedBox(height: 12),
              const Text(
                'Gợi ý kiểm tra:\n'
                '• Đảm bảo file PDF/Ảnh là bản gốc do trường cấp (chưa bị chỉnh sửa hay nén lại).\n'
                '• Kiểm tra lại mã QR hoặc chuỗi Data Hash (0x...).',
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
              'THÔNG TIN CHỨNG CHỈ & BLOCKCHAIN',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 0.5,
                color: Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 10),
            _buildInfoRow('Tệp / Hồ sơ:', record.fileName, icon: Icons.description_outlined),
            if (record.degreeName != null && record.degreeName!.trim().isNotEmpty) ...[
              const Divider(),
              _buildInfoRow('Tên văn bằng:', record.degreeName!, icon: Icons.school_outlined),
            ],
            if (record.studentName != null && record.studentName!.trim().isNotEmpty) ...[
              const Divider(),
              _buildInfoRow('Họ tên sinh viên:', record.studentName!, icon: Icons.person_outline),
            ],
            if (record.studentCode != null && record.studentCode!.trim().isNotEmpty) ...[
              const Divider(),
              _buildInfoRow('Mã số sinh viên:', record.studentCode!, icon: Icons.badge_outlined),
            ],
            const Divider(),
            _buildInfoRow('Đơn vị cấp phát:', record.issuerName, icon: Icons.account_balance_outlined),
            const Divider(),
            _buildInfoRow('Loại định dạng:', record.fileType, icon: Icons.insert_drive_file_outlined),
            const Divider(),
            _buildInfoRow('Ngày cấp (On-chain):', record.formattedBlockchainDate, icon: Icons.access_time),
            if (record.blockNumber != null) ...[
              const Divider(),
              _buildInfoRow('Số thứ tự Khối (Block):', '#${record.blockNumber}', icon: Icons.layers_outlined),
            ],
            const Divider(),
            _buildCopyableRow('Địa chỉ Ví đơn vị cấp (Signer):', record.signer, 'Địa chỉ Ví Signer'),
            const Divider(),
            _buildCopyableRow('Mã băm tài liệu (Data Hash):', record.dataHash, 'Mã Hash Keccak256'),
            if (record.txHash != null && record.txHash!.trim().isNotEmpty) ...[
              const Divider(),
              _buildCopyableRow('Mã giao dịch (TxHash Sepolia):', record.txHash!, 'Mã giao dịch TxHash'),
            ],
            if (widget.isFromOfflineVault) ...[
              const Divider(),
              _buildInfoRow('Thời điểm lưu Offline:', record.savedAt, icon: Icons.offline_pin_outlined),
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
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
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
