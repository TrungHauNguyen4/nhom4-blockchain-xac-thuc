import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/certificate_record.dart';
import '../services/db_service.dart';

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

  Future<void> _checkSavedStatus() async {
    if (widget.record != null) {
      final saved = await DatabaseService.instance.isCertificateSaved(widget.record!.dataHash);
      if (mounted) setState(() => _isSaved = saved);
    }
  }

  Future<void> _toggleSaveOffline() async {
    if (widget.record == null) return;
    setState(() => _isLoading = true);

    try {
      if (_isSaved) {
        // Đã lưu -> Báo người dùng
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Văn bằng này đã có trong Sổ tay Offline')),
        );
      } else {
        await DatabaseService.instance.saveCertificate(widget.record!);
        setState(() => _isSaved = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              content: Text('Đã lưu văn bằng vào Sổ tay Cục bộ (Sqflite)!'),
            ),
          );
        }
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
              tooltip: 'Lưu Offline (Sqflite)',
              onPressed: _isLoading ? null : _toggleSaveOffline,
            ),
        ],
      ),
      // Sử dụng OrientationBuilder để tự động đáp ứng xoay ngang / dọc màn hình
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

  // Giao diện Màn hình Dọc (Portrait)
  Widget _buildPortraitLayout(BuildContext context, bool isValid) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatusHeader(isValid),
          const SizedBox(height: 20),
          _buildDetailsCard(context, isValid),
          const SizedBox(height: 24),
          if (isValid && !_isSaved)
            ElevatedButton.icon(
              icon: const Icon(Icons.download_for_offline),
              label: const Text('Lưu vào Sổ tay Offline (Sqflite)'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _toggleSaveOffline,
            ),
        ],
      ),
    );
  }

  // Giao diện Màn hình Ngang (Landscape - Chia 2 Cột linh hoạt)
  Widget _buildLandscapeLayout(BuildContext context, bool isValid) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildStatusHeader(isValid),
                  const SizedBox(height: 16),
                  if (isValid && !_isSaved)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.download_for_offline),
                      label: const Text('Lưu Offline (Sqflite)'),
                      onPressed: _toggleSaveOffline,
                    ),
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

  // Huy hiệu trạng thái Xác thực
  Widget _buildStatusHeader(bool isValid) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isValid ? Colors.green.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.12),
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
            size: 64,
            color: isValid ? Colors.green : Colors.red,
          ),
          const SizedBox(height: 12),
          Text(
            isValid ? 'VĂN BẰNG HỢP LỆ' : 'CẢNH BÁO BẰNG GIẢ / KHÔNG TỒN TẠI',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isValid ? Colors.green.shade800 : Colors.red.shade800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isValid
                ? 'Chứng chỉ này đã được đối soát chính xác với Sổ cái Blockchain Sepolia'
                : 'Mã băm dữ liệu không khớp với bất kỳ chứng chỉ nào từng được cấp phát.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // Thẻ thông tin chi tiết
  Widget _buildDetailsCard(BuildContext context, bool isValid) {
    if (!isValid) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Mã Hash tra cứu:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              SelectableText(
                widget.searchedHash,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
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
            _buildInfoRow('Tên văn bằng:', record.fileName, icon: Icons.description),
            if (record.degreeName != null && record.degreeName!.isNotEmpty) ...[
              const Divider(),
              _buildInfoRow('Loại văn bằng:', record.degreeName!, icon: Icons.school),
            ],
            if (record.studentName != null && record.studentName!.isNotEmpty) ...[
              const Divider(),
              _buildInfoRow('Người được cấp:', record.studentName!, icon: Icons.person),
            ],
            if (record.studentCode != null && record.studentCode!.isNotEmpty) ...[
              const Divider(),
              _buildInfoRow('Mã sinh viên (MSSV):', record.studentCode!, icon: Icons.badge),
            ],
            const Divider(),
            _buildInfoRow('Đơn vị cấp phát:', record.issuerName, icon: Icons.account_balance),
            const Divider(),
            _buildInfoRow('Thời gian cấp phát:', record.formattedBlockchainDate, icon: Icons.access_time),
            const Divider(),
            _buildCopyableRow('Ví cấp phát (Issuer):', record.signer, 'Địa chỉ Ví Issuer'),
            const Divider(),
            _buildCopyableRow('Mã băm (Data Hash):', record.dataHash, 'Mã Hash Keccak256'),
            if (record.txHash != null && record.txHash!.isNotEmpty) ...[
              const Divider(),
              _buildCopyableRow('Giao dịch (TxHash):', record.txHash!, 'Mã giao dịch Blockchain'),
            ],
            if (widget.isFromOfflineVault) ...[
              const Divider(),
              _buildInfoRow('Thời gian lưu offline:', record.savedAt, icon: Icons.offline_pin),
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
              style: const TextStyle(fontSize: 13),
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
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              IconButton(
                icon: const Icon(Icons.copy, size: 16, color: Colors.blue),
                tooltip: 'Sao chép',
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
                onPressed: () => _copyToClipboard(value, copyLabel),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

