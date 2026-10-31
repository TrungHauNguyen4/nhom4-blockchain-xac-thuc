import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/certificate_record.dart';
import '../../services/api_service.dart';

/// Màn hình Danh sách Văn bằng đã cấp phát (Đọc từ SQL Server Backend)
/// Sử dụng FutureBuilder theo chuẩn Chương 12 (flutter_demo)
class IssuedListScreen extends StatefulWidget {
  const IssuedListScreen({super.key});

  @override
  State<IssuedListScreen> createState() => _IssuedListScreenState();
}

class _IssuedListScreenState extends State<IssuedListScreen> {
  final TextEditingController _searchController = TextEditingController();
  late Future<List<CertificateRecord>> _certificatesFuture;

  @override
  void initState() {
    super.initState();
    _loadCertificates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadCertificates([String keyword = '']) {
    final apiService = context.read<ApiService>();
    setState(() {
      _certificatesFuture = apiService.fetchIssuedCertificates(keyword: keyword);
    });
  }

  void _showCertificateDetailModal(CertificateRecord item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    item.degreeName ?? item.fileName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.issuerName ?? 'Đơn vị đào tạo',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),

                  // Mã QR của văn bằng
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
                      data: item.dataHash,
                      version: QrVersions.auto,
                      size: 180,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Thông tin chi tiết
                  _buildDetailItem('Họ và tên:', item.studentName ?? 'N/A'),
                  _buildDetailItem('Mã số sinh viên:', item.studentCode ?? 'N/A'),
                  _buildDetailItem('Ngày cấp niêm phong:', item.formattedBlockchainDate),
                  _buildDetailItem('Người ký (Signer):', item.signer, mono: true),
                  _buildDetailItem('Mã băm (DataHash):', item.dataHash, mono: true),
                  if (item.txHash != null)
                    _buildDetailItem('Mã giao dịch (TxHash):', item.txHash!, mono: true),
                  if (item.blockNumber != null)
                    _buildDetailItem('Block Number:', '#${item.blockNumber}'),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailItem(String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sổ Bộ Văn Bằng Đã Ký'),
      ),
      body: Column(
        children: [
          // Thanh tìm kiếm
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm theo Tên SV, MSSV, Tên bằng...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _loadCertificates();
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onSubmitted: (val) => _loadCertificates(val),
            ),
          ),

          // Danh sách văn bằng hiển thị bằng FutureBuilder (Chuẩn Chương 12)
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                _loadCertificates(_searchController.text);
                await _certificatesFuture;
              },
              child: FutureBuilder<List<CertificateRecord>>(
                future: _certificatesFuture,
                builder: (context, snapshot) {
                  // Trạng thái 1: Đang nạp dữ liệu
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Đang truy vấn dữ liệu từ SQL Server...'),
                        ],
                      ),
                    );
                  }

                  // Trạng thái 2: Có lỗi xảy ra
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.cloud_off, size: 60, color: Colors.redAccent),
                          const SizedBox(height: 12),
                          Text('Lỗi kết nối máy chủ: ${snapshot.error}'),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => _loadCertificates(),
                            child: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    );
                  }

                  final list = snapshot.data ?? [];

                  // Trạng thái 3: Danh sách rỗng
                  if (list.isEmpty) {
                    return ListView(
                      children: const [
                        SizedBox(height: 80),
                        Center(
                          child: Column(
                            children: [
                              Icon(Icons.inbox_outlined, size: 70, color: Colors.grey),
                              SizedBox(height: 12),
                              Text('Chưa có văn bằng nào trong sổ bộ lưu trữ',
                                  style: TextStyle(color: Colors.grey, fontSize: 15)),
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                  // Trạng thái 4: Hiển thị danh sách
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final item = list[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        elevation: 2,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF673AB7).withValues(alpha: 0.15),
                            child: const Icon(Icons.verified, color: Color(0xFF673AB7)),
                          ),
                          title: Text(
                            item.studentName ?? item.fileName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (item.degreeName != null)
                                Text(
                                  item.degreeName!,
                                  style: const TextStyle(fontSize: 13, color: Colors.blueAccent),
                                ),
                              Text(
                                'MSSV: ${item.studentCode ?? 'N/A'} • Ngày: ${item.formattedBlockchainDate}',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                          trailing: const Icon(Icons.qr_code_2, size: 28),
                          onTap: () => _showCertificateDetailModal(item),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
