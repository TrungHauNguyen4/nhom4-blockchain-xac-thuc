import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/certificate_record.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/db_service.dart';
import '../../services/hr_review_service.dart';
import '../verifier/verify_detail_screen.dart';
import 'hr_audit_report_screen.dart';

/// Màn hình chuyên biệt dành riêng cho Nhà tuyển dụng (Employer / HR):
/// 1. Bảng thống kê KPI Thẩm định hồ sơ (Tổng lượt quét, Hợp lệ, Cảnh báo giả, Đã duyệt tuyển)
/// 2. Tra cứu toàn bộ văn bằng của ứng viên theo MSSV / Họ tên từ sổ gốc
/// 3. Danh sách ứng viên đã được HR chấm trạng thái tuyển dụng & ghi chú phỏng vấn
class EmployerAuditTab extends StatefulWidget {
  const EmployerAuditTab({super.key});

  @override
  State<EmployerAuditTab> createState() => EmployerAuditTabState();
}

class EmployerAuditTabState extends State<EmployerAuditTab> {
  static const String hrReviewsPrefKey = HrReviewService.legacyPrefKey;
  final HrReviewService _hrReviewService = HrReviewService();

  final TextEditingController _candidateSearchController =
      TextEditingController();

  bool _isLoadingStats = false;
  bool _isSearchingCandidates = false;
  String? _searchError;

  int _totalScans = 0;
  int _validScans = 0;
  int _invalidScans = 0;

  List<CertificateRecord> _candidateCertificates = [];
  Map<String, Map<String, dynamic>> _hrReviews = {};
  String _reviewFilter = 'ALL'; // ALL, APPROVED, PENDING, REJECTED

  @override
  void initState() {
    super.initState();
    reloadAuditData();
  }

  @override
  void dispose() {
    _candidateSearchController.dispose();
    super.dispose();
  }

  /// Tải lại thống kê quét từ Sqflite và danh sách đánh giá HR từ SharedPreferences
  Future<void> reloadAuditData() async {
    if (!mounted) return;
    setState(() => _isLoadingStats = true);
    final uid = Provider.of<AuthProvider?>(context, listen: false)
        ?.currentUser
        ?.uid;

    try {
      final history = await DatabaseService.instance.getAllScanHistory();
      final total = history.length;
      final valid = history.where((e) => e.isValid).length;
      final invalid = total - valid;

      final loadedReviews = await _hrReviewService.fetchReviews(uid: uid);

      if (!mounted) return;
      setState(() {
        _totalScans = total;
        _validScans = valid;
        _invalidScans = invalid;
        _hrReviews = loadedReviews;
        _isLoadingStats = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    }
  }

  /// Tra cứu danh sách văn bằng của ứng viên theo MSSV hoặc Họ tên từ sổ gốc
  Future<void> _searchCandidatePortfolio() async {
    if (!mounted) return;
    final keyword = _candidateSearchController.text.trim();
    setState(() {
      _isSearchingCandidates = true;
      _searchError = null;
    });

    try {
      final api = Provider.of<ApiService?>(context, listen: false) ?? ApiService();
      final results = await api.fetchIssuedCertificates(keyword: keyword);
      if (!mounted) return;
      setState(() {
        _candidateCertificates = results;
        _isSearchingCandidates = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchError = 'Không thể tra cứu sổ gốc lúc này: $e';
        _isSearchingCandidates = false;
      });
    }
  }

  Future<void> _deleteHrReview(String dataHash) async {
    final key = _hrReviewService.normalizeHashKey(dataHash);
    final updated = Map<String, Map<String, dynamic>>.from(_hrReviews);
    updated.remove(key);

    final uid = Provider.of<AuthProvider?>(context, listen: false)
        ?.currentUser
        ?.uid;
    await _hrReviewService.deleteReview(uid: uid, hashKey: key);

    if (!mounted) return;
    setState(() {
      _hrReviews = updated;
    });
  }

  int get _approvedCount => _hrReviews.values
      .where((item) => item['status'] == 'APPROVED')
      .length;

  List<MapEntry<String, Map<String, dynamic>>> get _filteredReviews {
    final entries = _hrReviews.entries.toList();
    entries.sort((a, b) {
      final timeA = (a.value['updatedAt'] ?? '').toString();
      final timeB = (b.value['updatedAt'] ?? '').toString();
      return timeB.compareTo(timeA);
    });

    if (_reviewFilter == 'ALL') return entries;
    return entries
        .where((e) => (e.value['status'] ?? 'APPROVED') == _reviewFilter)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider?>(context);
    final orgName = auth?.currentUser?.organization.trim().isNotEmpty == true
        ? auth!.currentUser!.organization
        : 'Đơn vị Tuyển dụng / HR';

    return OrientationBuilder(
      builder: (context, orientation) {
        final isPortrait =
            MediaQuery.orientationOf(context) == Orientation.portrait;

        if (isPortrait) {
          return RefreshIndicator(
            onRefresh: () async {
              await reloadAuditData();
              if (_candidateCertificates.isNotEmpty ||
                  _candidateSearchController.text.trim().isNotEmpty) {
                await _searchCandidatePortfolio();
              }
            },
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _buildCompanyBanner(orgName),
                const SizedBox(height: 12),
                _buildKpiGrid(context, isPortrait: true),
                const SizedBox(height: 16),
                _buildCandidateLookupCard(context),
                const SizedBox(height: 16),
                _buildReviewedCandidatesCard(context),
                const SizedBox(height: 24),
              ],
            ),
          );
        }

        // Giao diện 2 cột khi xoay ngang (Landscape)
        return Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCompanyBanner(orgName),
                      const SizedBox(height: 12),
                      _buildKpiGrid(context, isPortrait: false),
                      const SizedBox(height: 14),
                      _buildReviewedCandidatesCard(context),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 6,
                child: SingleChildScrollView(
                  child: _buildCandidateLookupCard(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompanyBanner(String orgName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF18181A), const Color(0xFF2B2F22)]
              : [const Color(0xFF565C43), const Color(0xFF18181A)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.business_center_rounded,
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
                    'TRUNG TÂM THẨM ĐỊNH HỒ SƠ ỨNG VIÊN (HR)',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  orgName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Làm mới số liệu HR',
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _isLoadingStats ? null : reloadAuditData,
          ),
        ],
      ),
    );
  }

  Widget _buildKpiGrid(BuildContext context, {required bool isPortrait}) {
    final items = [
      _KpiItemData(
        label: 'Tổng lượt thẩm định',
        value: '$_totalScans',
        icon: Icons.qr_code_scanner,
        color: Colors.blue,
      ),
      _KpiItemData(
        label: 'Văn bằng Hợp lệ',
        value: '$_validScans',
        icon: Icons.verified_rounded,
        color: Colors.green,
      ),
      _KpiItemData(
        label: 'Cảnh báo bằng giả',
        value: '$_invalidScans',
        icon: Icons.gpp_bad_rounded,
        color: Colors.redAccent,
      ),
      _KpiItemData(
        label: 'Ứng viên Đạt tuyển',
        value: '$_approvedCount',
        icon: Icons.how_to_reg_rounded,
        color: Colors.teal,
      ),
    ];

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildKpiTile(items[0])),
            const SizedBox(width: 10),
            Expanded(child: _buildKpiTile(items[1])),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _buildKpiTile(items[2])),
            const SizedBox(width: 10),
            Expanded(child: _buildKpiTile(items[3])),
          ],
        ),
      ],
    );
  }

  Widget _buildKpiTile(_KpiItemData data) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF18181A)
            : const Color(0xFFF7F6F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: data.color.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: data.color.withValues(alpha: 0.15),
            child: Icon(data.icon, color: data.color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    data.value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: data.color,
                    ),
                  ),
                ),
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCandidateLookupCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.person_search_rounded, color: Colors.blueAccent),
                SizedBox(width: 8),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Tra Cứu Hồ Sơ Văn Bằng Ứng Viên (Theo MSSV / Họ Tên)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Nhập Mã số sinh viên (VD: SV2026...) hoặc Họ tên ứng viên để đối chiếu toàn bộ bằng cấp đã được nhà trường ký số.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _candidateSearchController,
                    onSubmitted: (_) => _searchCandidatePortfolio(),
                    decoration: InputDecoration(
                      hintText: 'Nhập MSSV, tên ứng viên hoặc tên bằng...',
                      prefixIcon: const Icon(Icons.search, size: 19),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      suffixIcon: _candidateSearchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 17),
                              onPressed: () {
                                _candidateSearchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed:
                      _isSearchingCandidates ? null : _searchCandidatePortfolio,
                  icon: _isSearchingCandidates
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.manage_search, size: 18),
                  label: const Text('Tra cứu'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
            if (_searchError != null) ...[
              const SizedBox(height: 8),
              Text(
                _searchError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            if (_candidateCertificates.isEmpty && !_isSearchingCandidates)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Nhấn "Tra cứu" để liệt kê các văn bằng của ứng viên từ hệ thống nhà trường hoặc Sổ tay Offline.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              )
            else
              ..._candidateCertificates.map(_buildCandidateCertificateTile),
          ],
        ),
      ),
    );
  }

  Widget _buildCandidateCertificateTile(CertificateRecord cert) {
    final review = _hrReviews[cert.dataHash.trim().toLowerCase()];
    final status = (review?['status'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.25)),
      ),
      child: ListTile(
        dense: true,
        leading: const CircleAvatar(
          radius: 18,
          backgroundColor: Color(0x1F2196F3),
          child: Icon(Icons.school_rounded, color: Colors.blue, size: 18),
        ),
        title: Text(
          cert.degreeName?.trim().isNotEmpty == true
              ? cert.degreeName!
              : cert.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        subtitle: Text(
          '${cert.studentName ?? "Chưa rõ tên"} • MSSV: ${cert.studentCode ?? "N/A"}\nĐơn vị: ${cert.issuerName}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: status.isNotEmpty
            ? _buildStatusBadge(status)
            : const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VerifyDetailScreen(
                record: cert,
                searchedHash: cert.dataHash,
              ),
            ),
          ).then((_) => reloadAuditData());
        },
      ),
    );
  }

  Widget _buildReviewedCandidatesCard(BuildContext context) {
    final entries = _filteredReviews;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.fact_check_outlined, color: Colors.teal),
                      SizedBox(width: 8),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Danh Sách Ứng Viên Đã Đánh Giá Tuyển Dụng',
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
                Text(
                  '${_hrReviews.length} hồ sơ',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('ALL', 'Tất cả'),
                  const SizedBox(width: 6),
                  _buildFilterChip('APPROVED', 'Đạt thẩm định'),
                  const SizedBox(width: 6),
                  _buildFilterChip('PENDING', 'Chờ bổ sung'),
                  const SizedBox(width: 6),
                  _buildFilterChip('REJECTED', 'Từ chối'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (entries.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 18,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Chưa có hồ sơ ứng viên nào được đánh dấu.\nSau khi quét QR hoặc tra cứu văn bằng, bạn có thể chấm "Đạt thẩm định / Chờ bổ sung / Từ chối" ngay trên màn hình Kết quả.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              )
            else
              ...entries.map((entry) => _buildReviewedItemTile(entry.key, entry.value)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String code, String label) {
    final selected = _reviewFilter == code;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11.5)),
      selected: selected,
      onSelected: (_) => setState(() => _reviewFilter = code),
    );
  }

  Future<void> _openHrAuditReport(
    String hashKey,
    Map<String, dynamic> data,
  ) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HrAuditReportScreen(
          hashKey: hashKey,
          reviewData: data,
        ),
      ),
    );
    if (mounted) {
      await reloadAuditData();
    }
  }

  Widget _buildReviewedItemTile(String hashKey, Map<String, dynamic> data) {
    final status = (data['status'] ?? 'APPROVED').toString();
    final studentName = (data['studentName'] ?? 'Ứng viên').toString();
    final studentCode = (data['studentCode'] ?? '').toString();
    final degreeName = (data['degreeName'] ?? 'Văn bằng đã kiểm tra').toString();
    final note = (data['note'] ?? '').toString();
    final updatedAt = (data['updatedAt'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.25)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openHrAuditReport(hashKey, data),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildStatusBadge(status),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    studentCode.isNotEmpty
                        ? '$studentName ($studentCode)'
                        : studentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 17, color: Colors.grey),
                  tooltip: 'Xóa đánh giá này',
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  onPressed: () => _deleteHrReview(hashKey),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              degreeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            if (note.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Ghi chú HR: $note',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                  color: Colors.blueGrey,
                ),
              ),
            ],
            if (updatedAt.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Cập nhật: $updatedAt',
                style: const TextStyle(fontSize: 10.5, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;
    switch (status) {
      case 'APPROVED':
        color = Colors.green;
        label = 'Đạt thẩm định';
        break;
      case 'PENDING':
        color = Colors.orange;
        label = 'Chờ bổ sung';
        break;
      case 'REJECTED':
        color = Colors.redAccent;
        label = 'Từ chối';
        break;
      default:
        color = Colors.blueGrey;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _KpiItemData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiItemData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}
