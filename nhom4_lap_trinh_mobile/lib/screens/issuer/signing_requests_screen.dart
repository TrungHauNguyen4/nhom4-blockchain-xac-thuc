import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/signing_request_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/signing_request_service.dart';
import '../../widgets/pagination_controls.dart';

/// Màn hình Tiếp nhận & Xử lý Yêu cầu Ký Tài liệu dành cho Cán bộ ký (Issuer).
/// - Phân 2 chỉ mục: Cá nhân (Sinh viên) & Nhà tuyển dụng (Doanh nghiệp).
/// - Phân trang 7 dòng/trang ở cả 2 chỉ mục.
/// - Hỗ trợ thiết lập thời gian chờ (> 24h) khi quá tải & xác nhận 2 bước trước khi ký.
class SigningRequestsScreen extends StatefulWidget {
  final bool isEmbedded;

  const SigningRequestsScreen({super.key, this.isEmbedded = false});

  @override
  State<SigningRequestsScreen> createState() => _SigningRequestsScreenState();
}

class _SigningRequestsScreenState extends State<SigningRequestsScreen>
    with SingleTickerProviderStateMixin {
  static const int _itemsPerPage = 7;

  late final TabController _tabController;
  final _service = SigningRequestService();

  int _studentPage = 1;
  int _employerPage = 1;
  String _statusFilter = 'all'; // 'all' | 'pending' | 'signed'
  final Set<String> _processingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<SigningRequestModel> _applyStatusFilter(
    List<SigningRequestModel> items,
  ) {
    if (_statusFilter == 'pending') {
      return items
          .where(
            (e) =>
                e.status == SigningRequestStatus.pending ||
                e.status == SigningRequestStatus.delayed,
          )
          .toList(growable: false);
    }
    if (_statusFilter == 'signed') {
      return items
          .where((e) => e.status == SigningRequestStatus.signed)
          .toList(growable: false);
    }
    return items;
  }

  Future<void> _confirmAndSignRequest(SigningRequestModel req) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.verified_user, color: Colors.teal),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Xác nhận Ký số & Ghi Blockchain',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Bấm "Hủy" hoặc nút Quay lại sẽ KHÔNG tự động ký. Chỉ khi bấm "Xác nhận Ký số", tài liệu mới được ghi lên Blockchain.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 10),
              Text('• Tài liệu: ${req.degreeName}'),
              Text('• Tệp gốc: ${req.fileName} (${req.fileType})'),
              Text('• Người gửi: ${req.requesterName} (${req.requesterEmail})'),
              if (req.studentName.isNotEmpty)
                Text('• Sinh viên/Ứng viên: ${req.studentName}'),
              if (req.studentCode.isNotEmpty)
                Text('• MSSV/Mã HS: ${req.studentCode}'),
              Text('• Đơn vị ký: ${req.issuerName}'),
              Text('• Thuật toán: ${req.hashAlgorithm.toUpperCase()}'),
              const SizedBox(height: 6),
              SelectableText(
                '• Hash: ${req.documentHash}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  color: Colors.teal,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Xác nhận Ký số'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _processingIds.add(req.id));
    try {
      final apiService = context.read<ApiService>();
      final issuerUser = context.read<AuthProvider>().currentUser;
      final result = await apiService.notarizeCertificate(
        dataHash: req.documentHash,
        fileName: req.fileName,
        fileType: req.fileType,
        studentName: req.studentName,
        studentCode: req.studentCode,
        degreeName: req.degreeName,
        issuerName: req.issuerName,
        createdByEmail: issuerUser?.email,
      );

      final isSuccess = result['success'] == true;
      final isDuplicate = result['isDuplicate'] == true;
      if (!isSuccess && !isDuplicate) {
        throw StateError(
          result['message']?.toString() ?? 'Không thể ghi lên Blockchain.',
        );
      }

      final txHash = (result['txHash'] ??
              (result['existingRecord'] is Map
                  ? (result['existingRecord'] as Map)['txHash']
                  : null) ??
              '')
          .toString();

      await _service.markRequestSigned(
        request: req,
        txHash: txHash,
        signedByUid: issuerUser?.uid ?? '',
        signedByName: issuerUser?.name ?? req.issuerName,
      );

      if (!mounted) return;
      _showSnack(
        isDuplicate
            ? 'Mã Hash đã có trên Blockchain. Đã cập nhật trạng thái & gửi thông báo về người gửi.'
            : 'Đã ký số lên Blockchain & gửi thông báo về cho người gửi!',
      );
    } catch (e) {
      _showSnack('Lỗi ký số: $e', isError: true);
    } finally {
      if (mounted) setState(() => _processingIds.remove(req.id));
    }
  }

  Future<void> _showDelayDialog(SigningRequestModel req) async {
    int selectedHours = req.estimatedHours > 24 ? req.estimatedHours : 48;
    final hoursCtrl = TextEditingController(text: '$selectedHours');
    final reasonCtrl = TextEditingController(
      text: req.waitReason.isNotEmpty
          ? req.waitReason
          : 'Hệ thống đang quá tải yêu cầu xác thực, dự kiến xử lý lâu hơn 24 giờ.',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Thiết lập thời gian chờ (> 24h)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Chọn thời gian dự kiến phản hồi cho người gửi:',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [36, 48, 72].map((h) {
                    return ChoiceChip(
                      label: Text('${h}h'),
                      selected: selectedHours == h,
                      onSelected: (_) {
                        setDialogState(() {
                          selectedHours = h;
                          hoursCtrl.text = '$h';
                        });
                      },
                    );
                  }).toList(growable: false),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: hoursCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Số giờ dự kiến (ví dụ: 48)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Lý do / Ghi chú gửi tới người yêu cầu',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Gửi thông báo chờ'),
            ),
          ],
        ),
      ),
    );

    final hours = int.tryParse(hoursCtrl.text.trim()) ?? selectedHours;
    final reason = reasonCtrl.text.trim();
    hoursCtrl.dispose();
    reasonCtrl.dispose();

    if (confirmed != true || !mounted) return;
    setState(() => _processingIds.add(req.id));
    try {
      await _service.updateWaitEstimate(
        request: req,
        estimatedHours: hours,
        waitReason: reason,
      );
      _showSnack('Đã cập nhật thời gian chờ ${hours}h & gửi thông báo.');
    } catch (e) {
      _showSnack('Không thể cập nhật thời gian chờ: $e', isError: true);
    } finally {
      if (mounted) setState(() => _processingIds.remove(req.id));
    }
  }

  Future<void> _showRejectDialog(SigningRequestModel req) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Từ chối yêu cầu ký'),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Lý do từ chối',
            hintText: 'Ví dụ: Sai MSSV hoặc chưa đủ thông tin đối chiếu',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Từ chối'),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();

    if (confirmed != true || !mounted) return;
    setState(() => _processingIds.add(req.id));
    try {
      final issuerUser = context.read<AuthProvider>().currentUser;
      await _service.markRequestRejected(
        request: req,
        reason: reason,
        signedByUid: issuerUser?.uid ?? '',
        signedByName: issuerUser?.name ?? req.issuerName,
      );
      _showSnack('Đã từ chối yêu cầu và thông báo tới người gửi.');
    } catch (e) {
      _showSnack('Lỗi từ chối yêu cầu: $e', isError: true);
    } finally {
      if (mounted) setState(() => _processingIds.remove(req.id));
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : Colors.teal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        SliverToBoxAdapter(
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(
                        icon: Icon(Icons.school_outlined),
                        text: 'Cá nhân (SV)'),
                    Tab(
                      icon: Icon(Icons.business_outlined),
                      text: 'Nhà tuyển dụng',
                    ),
                  ],
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('all', 'Tất cả'),
                        const SizedBox(width: 8),
                        _buildFilterChip('pending', 'Đang chờ / Gia hạn'),
                        const SizedBox(width: 8),
                        _buildFilterChip('signed', 'Đã ký'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      body: StreamBuilder<List<SigningRequestModel>>(
        stream: _service.streamAllRequests(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data ?? const <SigningRequestModel>[];
          final studentList = _applyStatusFilter(
            all.where((e) => e.isStudentRequest).toList(growable: false),
          );
          final employerList = _applyStatusFilter(
            all.where((e) => e.isEmployerRequest).toList(growable: false),
          );

          return TabBarView(
            controller: _tabController,
            children: [
              _buildPagedRequestList(
                items: studentList,
                currentPage: _studentPage,
                onPageChanged: (p) => setState(() => _studentPage = p),
                emptyMessage:
                    'Chưa có yêu cầu ký nào từ tài khoản Cá nhân (Sinh viên).',
              ),
              _buildPagedRequestList(
                items: employerList,
                currentPage: _employerPage,
                onPageChanged: (p) => setState(() => _employerPage = p),
                emptyMessage: 'Chưa có yêu cầu ký nào từ Nhà tuyển dụng.',
              ),
            ],
          );
        },
      ),
    );

    if (widget.isEmbedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Tiếp Nhận Yêu Cầu Ký')),
      body: body,
    );
  }

  Widget _buildFilterChip(String value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _statusFilter == value,
      onSelected: (_) {
        setState(() {
          _statusFilter = value;
          _studentPage = 1;
          _employerPage = 1;
        });
      },
    );
  }

  Widget _buildPagedRequestList({
    required List<SigningRequestModel> items,
    required int currentPage,
    required ValueChanged<int> onPageChanged,
    required String emptyMessage,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyMessage, textAlign: TextAlign.center),
        ),
      );
    }

    final totalPages = PaginationControls.computeTotalPages(
      items.length,
      pageSize: _itemsPerPage,
    );
    final safePage = currentPage.clamp(1, totalPages);
    final pagedItems = PaginationControls.slicePage<SigningRequestModel>(
      items,
      currentPage: safePage,
      pageSize: _itemsPerPage,
    );

    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ...pagedItems.map((req) {
          final isProcessing = _processingIds.contains(req.id);
          final canAct = req.status == SigningRequestStatus.pending ||
              req.status == SigningRequestStatus.delayed;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          req.degreeName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Chip(
                        label: Text(
                          req.status.labelVi,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Người gửi: ${req.requesterName} (${req.requesterEmail})',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  if (req.requesterOrganization.isNotEmpty)
                    Text(
                      'Đơn vị gửi: ${req.requesterOrganization}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  if (req.studentName.isNotEmpty || req.studentCode.isNotEmpty)
                    Text(
                      'SV/Hồ sơ: ${req.studentName}${req.studentCode.isNotEmpty ? ' • MSSV: ${req.studentCode}' : ''}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  Text(
                    'Tệp: ${req.fileName} (${req.fileType}) • ${req.hashAlgorithm.toUpperCase()}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    'Gửi: ${fmt.format(req.createdDateTime)} • Hạn (${req.estimatedHours}h): ${fmt.format(req.expectedResolveDateTime)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Hash: ${req.documentHash}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Sao chép Hash',
                        icon: const Icon(Icons.copy, size: 17),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: req.documentHash),
                          );
                          _showSnack('Đã sao chép Hash.');
                        },
                      ),
                    ],
                  ),
                  if (canAct) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ElevatedButton.icon(
                          onPressed: isProcessing
                              ? null
                              : () => _confirmAndSignRequest(req),
                          icon: isProcessing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.verified, size: 16),
                          label: const Text('Ký & Ghi Blockchain'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: isProcessing
                              ? null
                              : () => _showDelayDialog(req),
                          icon: const Icon(Icons.schedule, size: 16),
                          label: const Text('Hẹn > 24h'),
                        ),
                        TextButton.icon(
                          onPressed: isProcessing
                              ? null
                              : () => _showRejectDialog(req),
                          icon: const Icon(
                            Icons.cancel_outlined,
                            size: 16,
                            color: Colors.redAccent,
                          ),
                          label: const Text(
                            'Từ chối',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
        PaginationControls(
          currentPage: safePage,
          totalItems: items.length,
          pageSize: _itemsPerPage,
          onPageChanged: onPageChanged,
        ),
      ],
    );
  }
}
