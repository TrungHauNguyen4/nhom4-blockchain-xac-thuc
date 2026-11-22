import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/certificate_record.dart';
import '../../models/scan_history_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/db_service.dart';
import '../../widgets/certificate_card.dart';
import '../../widgets/pagination_controls.dart';
import '../requests/submit_signing_request_screen.dart';
import '../verifier/verify_detail_screen.dart';

class VaultTab extends StatefulWidget {
  const VaultTab({super.key});

  @override
  State<VaultTab> createState() => VaultTabState();
}

class VaultTabState extends State<VaultTab> {
  final TextEditingController _searchController = TextEditingController();

  List<CertificateRecord> _certificates = [];
  List<ScanHistoryModel> _scanHistory = [];
  List<CertificateRecord> _mySignedCerts = [];
  bool _isLoading = false;
  String _historyFilter = 'ALL'; // 'ALL', 'VALID', 'INVALID', 'QR', 'FILE'
  int _certPage = 1;
  int _historyPage = 1;
  int _signedPage = 1;

  @override
  void initState() {
    super.initState();
    reloadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // [READ] Tải hoặc tìm kiếm dữ liệu Offline từ Sqflite & văn bằng đã ký cho Sinh viên
  Future<void> reloadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _certPage = 1;
      _historyPage = 1;
      _signedPage = 1;
    });

    final keyword = _searchController.text.trim();
    final certs = await DatabaseService.instance.searchCertificates(keyword);
    final history = await DatabaseService.instance.searchScanHistory(keyword);

    List<CertificateRecord> signedCerts = [];
    if (mounted) {
      final currentUser =
          Provider.of<AuthProvider?>(context, listen: false)?.currentUser;
      if (currentUser != null && currentUser.isStudent) {
        final studentCode = currentUser.studentCode.trim();
        final studentName = currentUser.name.trim();
        final lookup = studentCode.isNotEmpty ? studentCode : studentName;
        if (lookup.isNotEmpty) {
          try {
            final api = Provider.of<ApiService?>(context, listen: false) ??
                ApiService();
            final fetched = await api.fetchIssuedCertificates(keyword: lookup);
            final lowerCode = studentCode.toLowerCase();
            final lowerName = studentName.toLowerCase();
            final lowerKw = keyword.toLowerCase();

            signedCerts = fetched.where((c) {
              final matchesOwner = studentCode.isNotEmpty
                  ? (c.studentCode ?? '').trim().toLowerCase() == lowerCode
                  : (c.studentName ?? '').trim().toLowerCase() == lowerName;
              if (!matchesOwner) return false;
              if (lowerKw.isEmpty) return true;
              return (c.degreeName ?? '').toLowerCase().contains(lowerKw) ||
                  c.fileName.toLowerCase().contains(lowerKw) ||
                  c.issuerName.toLowerCase().contains(lowerKw) ||
                  (c.studentCode ?? '').toLowerCase().contains(lowerKw) ||
                  (c.studentName ?? '').toLowerCase().contains(lowerKw);
            }).toList();
          } catch (_) {}
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _certificates = certs;
      _scanHistory = history;
      _mySignedCerts = signedCerts;
      _isLoading = false;
    });
  }

  // Lọc danh sách lịch sử theo bộ lọc chip
  List<ScanHistoryModel> get _filteredHistory {
    return _scanHistory.where((item) {
      switch (_historyFilter) {
        case 'VALID':
          return item.isValid;
        case 'INVALID':
          return !item.isValid;
        case 'QR':
          return item.scanMethod.toUpperCase() == 'QR';
        case 'FILE':
          return item.scanMethod.toUpperCase() == 'FILE';
        default:
          return true;
      }
    }).toList();
  }

  // [DELETE] Xác nhận xóa 1 văn bằng trong Sổ tay Offline
  Future<void> _confirmDeleteCertificate(CertificateRecord item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text(
          'Bạn có chắc muốn xóa văn bằng "${item.degreeName ?? item.fileName}" khỏi Sổ tay Offline không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm == true && item.id != null) {
      await DatabaseService.instance.deleteCertificate(item.id!);
      reloadData();
    }
  }

  // [DELETE] Xác nhận xóa toàn bộ lịch sử tra cứu
  Future<void> _confirmClearHistory() async {
    if (_scanHistory.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa toàn bộ lịch sử'),
        content: const Text(
          'Bạn có muốn xóa toàn bộ lịch sử quét mã QR và tra cứu Offline không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xóa tất cả'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService.instance.clearScanHistory();
      reloadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = Provider.of<AuthProvider?>(context)?.currentUser;
    final String? myStudentCode = (currentUser != null &&
            currentUser.isStudent &&
            currentUser.studentCode.trim().isNotEmpty)
        ? currentUser.studentCode.trim()
        : null;
    final bool isFilteringMyStudentCode = myStudentCode != null &&
        _searchController.text.trim().toLowerCase() ==
            myStudentCode.toLowerCase();

    final bool isStudent = currentUser?.isStudent ?? false;

    return DefaultTabController(
      key: ValueKey<String>('vault_tabs_${isStudent ? 3 : 2}'),
      length: isStudent ? 3 : 2,
      child: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => reloadData(),
                          decoration: InputDecoration(
                            hintText: 'Tìm theo Tên SV, MSSV, Văn bằng...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF222536).withValues(alpha: 0.85)
                                : Colors.white.withValues(alpha: 0.90),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.14)
                                    : const Color(0xFFDCE4F0),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.14)
                                    : const Color(0xFFDCE4F0),
                              ),
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      reloadData();
                                    },
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton.icon(
                        onPressed: reloadData,
                        icon: const Icon(Icons.search, size: 17),
                        label: const Text('Tìm'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      PopupMenuButton<String>(
                        tooltip: 'Tùy chọn sổ tay',
                        icon: const Icon(Icons.more_vert),
                        onSelected: (value) {
                          if (value == 'clear_history') {
                            _confirmClearHistory();
                          } else if (value == 'refresh') {
                            reloadData();
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'refresh',
                            child: Row(
                              children: [
                                Icon(Icons.refresh, size: 18),
                                SizedBox(width: 8),
                                Flexible(child: Text('Làm mới danh sách')),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'clear_history',
                            child: Row(
                              children: [
                                Icon(Icons.delete_sweep_outlined,
                                    size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Flexible(
                                    child: Text('Xóa toàn bộ lịch sử tra cứu')),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (myStudentCode != null || isStudent) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (myStudentCode != null)
                            ActionChip(
                              avatar: Icon(
                                isFilteringMyStudentCode
                                    ? Icons.check_circle
                                    : Icons.school_outlined,
                                size: 16,
                                color: isFilteringMyStudentCode
                                    ? Colors.teal
                                    : Colors.blueAccent,
                              ),
                              label: Text(
                                isFilteringMyStudentCode
                                    ? 'Đang lọc văn bằng của tôi ($myStudentCode) • Nhấn để bỏ lọc'
                                    : '🎓 Văn bằng của tôi (MSSV: $myStudentCode)',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onPressed: () {
                                if (isFilteringMyStudentCode) {
                                  _searchController.clear();
                                } else {
                                  _searchController.text = myStudentCode;
                                }
                                reloadData();
                              },
                            ),
                          if (isStudent)
                            ActionChip(
                              avatar: const Icon(
                                Icons.send_and_archive,
                                size: 16,
                                color: Colors.teal,
                              ),
                              label: const Text(
                                'Gửi yêu cầu ký tài liệu',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const SubmitSigningRequestScreen(),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _VaultTabBarHeaderDelegate(
              height: 58,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF18181A)
                        : const Color(0xFFF7F6F2),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.12)
                          : const Color(0xFFD6D4CC),
                    ),
                  ),
                  child: TabBar(
                    dividerColor: Colors.transparent,
                    splashFactory: NoSplash.splashFactory,
                    overlayColor: WidgetStateProperty.all(Colors.transparent),
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicatorAnimation: TabIndicatorAnimation.elastic,
                    indicator: BoxDecoration(
                      color: isDark
                          ? const Color(0xFFECEBE6)
                          : const Color(0xFF565C43),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.18)
                              : Colors.black.withValues(alpha: 0.15),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    labelColor: isDark
                        ? const Color(0xFF141416)
                        : const Color(0xFFECEBE6),
                    unselectedLabelColor:
                        isDark ? Colors.white70 : const Color(0xFF5C5B57),
                    tabs: [
                      Tab(
                        height: 38,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.bookmark_added_outlined, size: 17),
                              const SizedBox(width: 6),
                              Text(
                                'Sổ tay (${_certificates.length})',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Tab(
                        height: 38,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.history, size: 17),
                              const SizedBox(width: 6),
                              Text(
                                'Lịch sử (${_scanHistory.length})',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isStudent)
                        Tab(
                          height: 38,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.verified_outlined, size: 17),
                                const SizedBox(width: 6),
                                Text(
                                  'Đã ký (${_mySignedCerts.length})',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        // Nội dung các ngăn: Bắt buộc bọc OrientationBuilder (1 cột dọc <-> 2 cột ngang)
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildCertificatesVaultView(),
                  _buildScanHistoryView(),
                  if (isStudent) _buildMySignedCertificatesView(),
                ],
              ),
      ),
    );
  }

  // ========================================================
  // NGĂN 3 (SINH VIÊN): VĂN BẰNG CỦA TÔI ĐÃ ĐƯỢC KÝ XÁC NHẬN
  // ========================================================
  Widget _buildMySignedCertificatesView() {
    if (_mySignedCerts.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.workspace_premium_outlined,
                size: 68,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              const Text(
                'Chưa có văn bằng nào được ký xác nhận cho tài khoản của bạn',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Hãy đảm bảo Mã số sinh viên (MSSV) trong Hồ sơ cá nhân khớp với MSSV trên văn bằng được nhà trường cấp.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final pagedSigned = PaginationControls.slicePage(
      _mySignedCerts,
      currentPage: _signedPage,
    );

    return Column(
      children: [
        Expanded(
          child: OrientationBuilder(
            builder: (context, orientation) {
              final int columnCount =
                  MediaQuery.orientationOf(context) == Orientation.portrait
                      ? 1
                      : 2;

              if (columnCount == 1) {
                return ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  itemCount: pagedSigned.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = pagedSigned[index];
                    return CertificateCard(
                      record: item,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VerifyDetailScreen(
                              record: item,
                              searchedHash: item.dataHash,
                            ),
                          ),
                        ).then((_) => reloadData());
                      },
                    );
                  },
                );
              }

              return GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: 205,
                ),
                itemCount: pagedSigned.length,
                itemBuilder: (context, index) {
                  final item = pagedSigned[index];
                  return CertificateCard(
                    record: item,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VerifyDetailScreen(
                            record: item,
                            searchedHash: item.dataHash,
                          ),
                        ),
                      ).then((_) => reloadData());
                    },
                  );
                },
              );
            },
          ),
        ),
        PaginationControls(
          currentPage: _signedPage,
          totalItems: _mySignedCerts.length,
          onPageChanged: (p) => setState(() => _signedPage = p),
        ),
      ],
    );
  }

  // ========================================================
  // NGĂN 1: DANH SÁCH SỔ TAY VĂN BẰNG ĐÃ LƯU (ORIENTATIONBUILDER 1-2 CỘT)
  // ========================================================
  Widget _buildCertificatesVaultView() {
    if (_certificates.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_open, size: 68, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                _searchController.text.trim().isEmpty
                    ? 'Chưa có văn bằng nào trong Sổ tay Offline'
                    : 'Không tìm thấy văn bằng khớp với từ khóa "${_searchController.text}"',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              const Text(
                'Hãy xác thực văn bằng và bấm Lưu Offline để xem lại bất cứ lúc nào mà không cần Internet!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    // Sử dụng OrientationBuilder theo chuẩn Chương 9 flutter_demo:
    // Màn hình dọc (Portrait) -> 1 cột; Màn hình ngang (Landscape) -> 2 cột
    final pagedCerts = PaginationControls.slicePage(
      _certificates,
      currentPage: _certPage,
    );

    return Column(
      children: [
        Expanded(
          child: OrientationBuilder(
            builder: (context, orientation) {
              final int columnCount =
                  MediaQuery.orientationOf(context) == Orientation.portrait
                      ? 1
                      : 2;

              if (columnCount == 1) {
                return ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  itemCount: pagedCerts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = pagedCerts[index];
                    return CertificateCard(
                      record: item,
                      onDelete: () => _confirmDeleteCertificate(item),
                      onTap: () => _openSavedCertificateDetail(item),
                    );
                  },
                );
              }

              // Chế độ xoay ngang (Landscape): GridView 2 cột với mainAxisExtent chống tràn pixel
              return GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: 205,
                ),
                itemCount: pagedCerts.length,
                itemBuilder: (context, index) {
                  final item = pagedCerts[index];
                  return CertificateCard(
                    record: item,
                    onDelete: () => _confirmDeleteCertificate(item),
                    onTap: () => _openSavedCertificateDetail(item),
                  );
                },
              );
            },
          ),
        ),
        PaginationControls(
          currentPage: _certPage,
          totalItems: _certificates.length,
          onPageChanged: (p) => setState(() => _certPage = p),
        ),
      ],
    );
  }

  void _openSavedCertificateDetail(CertificateRecord item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VerifyDetailScreen(
          record: item,
          searchedHash: item.dataHash,
          isFromOfflineVault: true,
        ),
      ),
    ).then((_) => reloadData());
  }

  // ========================================================
  // NGĂN 2: LỊCH SỬ QUÉT MÃ & TRA CỨU OFFLINE (ORIENTATIONBUILDER 1-2 CỘT)
  // ========================================================
  Widget _buildScanHistoryView() {
    final list = _filteredHistory;
    final pagedHistory = PaginationControls.slicePage(
      list,
      currentPage: _historyPage,
    );

    return Column(
      children: [
        // Thanh bộ lọc nhanh ChoiceChip
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _buildFilterChip('ALL', 'Tất cả'),
              const SizedBox(width: 8),
              _buildFilterChip('VALID', 'Hợp lệ'),
              const SizedBox(width: 8),
              _buildFilterChip('INVALID', 'Cảnh báo giả'),
              const SizedBox(width: 8),
              _buildFilterChip('QR', 'Quét QR'),
              const SizedBox(width: 8),
              _buildFilterChip('FILE', 'Tệp PDF/Ảnh'),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off, size: 60, color: Colors.grey.shade400),
                      const SizedBox(height: 10),
                      const Text(
                        'Chưa có lịch sử quét mã hoặc tra cứu nào',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: OrientationBuilder(
                        builder: (context, orientation) {
                          final int columnCount =
                              MediaQuery.orientationOf(context) ==
                                      Orientation.portrait
                                  ? 1
                                  : 2;

                          if (columnCount == 1) {
                            return ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                              itemCount: pagedHistory.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) =>
                                  _buildHistoryCard(pagedHistory[index]),
                            );
                          }

                          // Khi xoay ngang: hiển thị 2 cột bằng GridView.builder
                          return GridView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 10,
                              mainAxisExtent: 150,
                            ),
                            itemCount: pagedHistory.length,
                            itemBuilder: (context, index) =>
                                _buildHistoryCard(pagedHistory[index]),
                          );
                        },
                      ),
                    ),
                    PaginationControls(
                      currentPage: _historyPage,
                      totalItems: list.length,
                      onPageChanged: (p) => setState(() => _historyPage = p),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String code, String label) {
    final bool selected = _historyFilter == code;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _historyFilter = code;
          _historyPage = 1;
        });
      },
    );
  }

  Widget _buildHistoryCard(ScanHistoryModel item) {
    final shortHash = item.dataHash.length > 18
        ? '${item.dataHash.substring(0, 10)}...${item.dataHash.substring(item.dataHash.length - 6)}'
        : item.dataHash;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          // Nếu văn bằng đã được lưu trong Sổ tay Offline thì mở đầy đủ thông tin
          final savedCert = await DatabaseService.instance.getCertificateByHash(item.dataHash);
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VerifyDetailScreen(
                record: savedCert,
                searchedHash: item.dataHash,
                isFromOfflineVault: savedCert != null,
              ),
            ),
          ).then((_) => reloadData());
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: item.isValid
                    ? Colors.green.withValues(alpha: 0.15)
                    : Colors.red.withValues(alpha: 0.15),
                child: Icon(
                  item.isValid ? Icons.verified : Icons.gpp_bad,
                  color: item.isValid ? Colors.green : Colors.red,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.scanMethod,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.degreeName ?? item.fileName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.isValid
                          ? 'Hợp lệ • ${item.issuerName ?? "Phòng Đào Tạo"}'
                          : 'Cảnh báo: Không tồn tại trên Blockchain',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: item.isValid
                            ? (Theme.of(context).brightness == Brightness.dark
                                ? Colors.greenAccent
                                : Colors.green.shade700)
                            : Colors.redAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            shortHash,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          item.scannedAt,
                          style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (item.id != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                  tooltip: 'Xóa dòng lịch sử',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () async {
                    await DatabaseService.instance.deleteScanHistory(item.id!);
                    reloadData();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VaultTabBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  const _VaultTabBarHeaderDelegate({
    required this.height,
    required this.child,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant _VaultTabBarHeaderDelegate oldDelegate) {
    return height != oldDelegate.height || child != oldDelegate.child;
  }
}

