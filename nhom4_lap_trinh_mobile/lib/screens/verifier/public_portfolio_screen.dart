import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/certificate_record.dart';
import '../../models/user_model.dart';
import '../../services/certificate_firebase_service.dart';
import '../../services/user_service.dart';
import 'verify_detail_screen.dart';

/// Trang Portfolio công khai (chỉ đọc) của chủ sở hữu văn bằng
/// được mở trực tiếp từ màn hình kết quả xác thực tài liệu.
class PublicPortfolioScreen extends StatefulWidget {
  final CertificateRecord record;
  final UserService? userService;
  final CertificateFirebaseService? firebaseService;

  const PublicPortfolioScreen({
    super.key,
    required this.record,
    this.userService,
    this.firebaseService,
  });

  @override
  State<PublicPortfolioScreen> createState() => _PublicPortfolioScreenState();
}

class _PublicPortfolioScreenState extends State<PublicPortfolioScreen> {
  late final UserService _userService;
  late final CertificateFirebaseService _firebaseService;

  bool _isLoading = true;
  UserModel? _portfolioUser;
  List<CertificateRecord> _verifiedCertificates = const [];

  @override
  void initState() {
    super.initState();
    _userService = widget.userService ?? UserService();
    _firebaseService = widget.firebaseService ?? CertificateFirebaseService();
    _verifiedCertificates = [widget.record];
    _loadOwnerPortfolio();
  }

  Future<void> _loadOwnerPortfolio() async {
    setState(() => _isLoading = true);

    final String code = (widget.record.studentCode ?? '').trim();
    final String name = (widget.record.studentName ?? '').trim();

    UserModel? loadedUser;
    List<CertificateRecord> certs = [widget.record];

    try {
      if (code.isNotEmpty) {
        loadedUser = await _userService.getPublicPortfolioByStudentCode(code);
        final allMatching = await _firebaseService.fetchAllCertificates(
          keyword: code,
        );
        final normalizedCode = code.toLowerCase();
        final filtered = allMatching.where((c) {
          return (c.studentCode ?? '').trim().toLowerCase() == normalizedCode;
        }).toList();
        certs = _mergeUniqueCertificates(widget.record, filtered);
      } else if (name.isNotEmpty) {
        final allMatching = await _firebaseService.fetchAllCertificates(
          keyword: name,
        );
        final normalizedName = name.toLowerCase();
        final filtered = allMatching.where((c) {
          return (c.studentName ?? '').trim().toLowerCase() == normalizedName;
        }).toList();
        certs = _mergeUniqueCertificates(widget.record, filtered);
      }
    } catch (_) {
      // Giữ nguyên fallback từ widget.record nếu offline hoặc chưa cấu hình Firebase
    }

    if (!mounted) return;
    setState(() {
      _portfolioUser = loadedUser;
      _verifiedCertificates = certs;
      _isLoading = false;
    });
  }

  List<CertificateRecord> _mergeUniqueCertificates(
    CertificateRecord primary,
    List<CertificateRecord> fetched,
  ) {
    final map = <String, CertificateRecord>{
      CertificateFirebaseService.normalizeHashKey(primary.dataHash): primary,
    };
    for (final item in fetched) {
      final key = CertificateFirebaseService.normalizeHashKey(item.dataHash);
      map.putIfAbsent(key, () => item);
    }
    return map.values.toList();
  }

  ImageProvider? _getAvatarImage(String? avatar) {
    if (avatar == null || avatar.isEmpty) return null;
    if (avatar.startsWith('http://') || avatar.startsWith('https://')) {
      return NetworkImage(avatar);
    }
    try {
      return MemoryImage(base64Decode(avatar));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _portfolioUser;
    final bool isOwnerHidden = user != null && !user.isPortfolioPublic;
    final UserModel? visibleUser = isOwnerHidden ? null : user;

    final String displayName = (visibleUser?.name.trim().isNotEmpty == true)
        ? visibleUser!.name
        : ((widget.record.studentName?.trim().isNotEmpty == true)
            ? widget.record.studentName!
            : 'Chủ sở hữu văn bằng');
    final String displayCode =
        (visibleUser?.studentCode.trim().isNotEmpty == true)
            ? visibleUser!.studentCode
            : (widget.record.studentCode ?? '').trim();
    final String displayOrg =
        (visibleUser?.organization.trim().isNotEmpty == true)
            ? visibleUser!.organization
            : widget.record.issuerName;
    final String displayHeadline = (visibleUser?.headline ?? '').trim();
    final String displayBio = (visibleUser?.bio ?? '').trim();
    final String displayEmail = (visibleUser?.email ?? '').trim();
    final String displayPortfolioUrl = (visibleUser?.portfolioUrl ?? '').trim();
    final avatarImage = _getAvatarImage(visibleUser?.avatarBase64OrUrl);

    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Portfolio Chủ Văn Bằng'),
        ),
        actions: [
          IconButton(
            tooltip: 'Tải lại Portfolio',
            icon: const Icon(Icons.refresh),
            onPressed: _loadOwnerPortfolio,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadOwnerPortfolio,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1. HERO BANNER PORTFOLIO CÔNG KHAI
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF031226),
                    Color(0xFF0D2B4E),
                    Color(0xFF18181A),
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.75),
                        width: 2.2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 44,
                      backgroundColor: const Color(0xFF0D2B4E),
                      backgroundImage: avatarImage,
                      onBackgroundImageError:
                          avatarImage != null ? (_, _) {} : null,
                      child: avatarImage == null
                          ? const Icon(
                              Icons.person,
                              size: 48,
                              color: Color(0xFFECEBE6),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    displayName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFECEBE6),
                    ),
                  ),
                  if (displayHeadline.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      displayHeadline,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF38BDF8),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (displayEmail.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      displayEmail,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFFECEBE6).withValues(alpha: 0.8),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.verified,
                              size: 15,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                visibleUser != null
                                    ? UserRole.getRoleLabel(visibleUser.role)
                                    : 'Chủ sở hữu văn bằng',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (displayCode.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'MSSV: $displayCode',
                            style: const TextStyle(
                              color: Color(0xFFECEBE6),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),

            if (!_isLoading && visibleUser == null) ...[
              Card(
                color: Colors.blueGrey.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        isOwnerHidden ? Icons.lock_outline : Icons.info_outline,
                        size: 18,
                        color: Colors.blueGrey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isOwnerHidden
                              ? 'Chủ sở hữu đã ẩn hồ sơ Portfolio cá nhân. Thông tin dưới đây chỉ hiển thị tóm tắt từ văn bằng đã xác thực.'
                              : 'Chủ sở hữu chưa cập nhật thêm hồ sơ giới thiệu cá nhân trên ứng dụng. Thông tin dưới đây được tổng hợp từ văn bằng đã xác thực.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // 2. GIỚI THIỆU BẢN THÂN
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.person_pin_outlined,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Giới Thiệu Cá Nhân',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Text(
                      displayBio.isNotEmpty
                          ? displayBio
                          : (isOwnerHidden
                              ? 'Chủ sở hữu đã chọn ẩn phần giới thiệu cá nhân.'
                              : 'Chủ sở hữu chưa cập nhật phần giới thiệu bản thân.'),
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: displayBio.isNotEmpty
                            ? null
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 3. THÔNG TIN ĐỊNH DANH & LIÊN KẾT (ẨN SỐ ĐIỆN THOẠI)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Thông Tin Định Danh & Liên Kết',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const Divider(height: 20),
                    _buildInfoRow(
                      context,
                      Icons.account_balance,
                      'Đơn vị / Trường đào tạo',
                      displayOrg,
                    ),
                    if (displayCode.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        context,
                        Icons.badge_outlined,
                        'Mã số sinh viên (MSSV)',
                        displayCode,
                      ),
                    ],
                    if (displayEmail.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        context,
                        Icons.email_outlined,
                        'Email liên hệ',
                        displayEmail,
                      ),
                    ],
                    if (displayPortfolioUrl.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.link_rounded,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Liên kết Portfolio / GitHub',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  displayPortfolioUrl,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blueAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Sao chép liên kết',
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: displayPortfolioUrl),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Đã sao chép liên kết Portfolio'),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 4. DANH MỤC VĂN BẰNG & CHỨNG CHỈ ĐÃ XÁC THỰC
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.workspace_premium_outlined,
                          color: Colors.teal,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Văn Bằng & Chứng Chỉ Đã Xác Thực',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_verifiedCertificates.length} bằng',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    ..._verifiedCertificates.map((cert) {
                      final isCurrent = CertificateFirebaseService
                              .normalizeHashKey(cert.dataHash) ==
                          CertificateFirebaseService.normalizeHashKey(
                            widget.record.dataHash,
                          );
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isCurrent
                                ? Colors.teal.withValues(alpha: 0.18)
                                : Colors.blue.withValues(alpha: 0.12),
                            child: Icon(
                              Icons.verified_rounded,
                              color: isCurrent ? Colors.teal : Colors.blue,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            cert.degreeName?.trim().isNotEmpty == true
                                ? cert.degreeName!
                                : cert.fileName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                          subtitle: Text(
                            'Đơn vị: ${cert.issuerName}\nNgày ký: ${cert.formattedBlockchainDate}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: isCurrent
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => VerifyDetailScreen(
                                        record: cert,
                                        searchedHash: cert.dataHash,
                                      ),
                                    ),
                                  );
                                },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: muted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: muted)),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
