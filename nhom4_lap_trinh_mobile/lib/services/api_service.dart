import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/certificate_record.dart';
import 'certificate_firebase_service.dart';
import 'db_service.dart';

class ApiService {
  static const String _prefBaseUrlKey = 'server_base_url';

  // Địa chỉ Smart Contract công khai trên mạng lưới Ethereum Sepolia (SignedRecordRegistry.sol)
  // Chỉ dùng cho lệnh đọc công khai eth_call (view), hoàn toàn không chứa bất kỳ khóa bí mật nào!
  static const String sepoliaContractAddress =
      '0xC54ad469C7eBE3a7C84b728335247C6fBDaE1bB8';

  // Selector 4-byte của hàm getRecord(bytes32): keccak256("getRecord(bytes32)")[0..4] = 0x213681cd
  static const String _getRecordSelector = '0x213681cd';

  // Danh sách các cổng RPC Ethereum Sepolia công khai miễn phí dự phòng lẫn nhau khi Laptop tắt nguồn
  static const List<String> publicSepoliaRpcUrls = [
    'https://ethereum-sepolia-rpc.publicnode.com',
    'https://1rpc.io/sepolia',
    'https://rpc.sepolia.org',
  ];

  // Tự động nhận diện: Nếu chạy trên Web/Desktop thì dùng localhost:3000, nếu trên Android Emulator thì dùng 10.0.2.2:3000
  static String get defaultBaseUrl =>
      kIsWeb ? 'http://localhost:3000' : 'http://10.0.2.2:3000';

  static String baseUrl = defaultBaseUrl;
  static String apiKey = 'YOUR_SECRET_B2B_KEY_123';

  // [READ] Tải cấu hình địa chỉ IP Server từ SharedPreferences khi mở App
  static Future<void> loadSavedConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString(_prefBaseUrlKey);
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        baseUrl = _normalizeUrl(savedUrl);
      }
    } catch (e) {
      debugPrint('[ApiService] Không thể đọc cấu hình SharedPreferences: $e');
    }
  }

  // [UPDATE] Cập nhật địa chỉ Backend trên RAM và lưu bền vững vào SharedPreferences
  static void updateBaseUrl(String newUrl) {
    final normalized = _normalizeUrl(newUrl);
    if (normalized.isEmpty) return;
    baseUrl = normalized;
    saveBaseUrl(normalized);
  }

  static Future<void> saveBaseUrl(String newUrl) async {
    final normalized = _normalizeUrl(newUrl);
    if (normalized.isEmpty) return;
    baseUrl = normalized;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefBaseUrlKey, baseUrl);
    } catch (e) {
      debugPrint('[ApiService] Không thể lưu baseUrl: $e');
    }
  }

  static String _normalizeUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return defaultBaseUrl;
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  // ========================================================
  // API 1: Xác minh tính hợp lệ của văn bằng (GET /api/v1/verify/:hash)
  // Đọc dữ liệu từ Smart Contract trên Ethereum Sepolia & SQL Server
  // ========================================================
  Future<CertificateRecord?> verifyHash(
    String hash, {
    String fileName = 'Văn bằng kiểm tra',
  }) async {
    final cleanHash = hash.trim();

    // Chuẩn hóa định dạng 0x + 64 ký tự hex (bytes32)
    final normalizedHash =
        (!cleanHash.startsWith('0x') && cleanHash.length == 64)
            ? '0x$cleanHash'
            : cleanHash;
    final hexRegex = RegExp(r'^0x[0-9a-fA-F]{64}$');
    if (!hexRegex.hasMatch(normalizedHash)) {
      return null;
    }

    // TẦNG 1: Ưu tiên gọi Backend Node.js + SQL Server (lấy đầy đủ Metadata sinh viên)
    try {
      final url = Uri.parse('$baseUrl/api/v1/verify/$normalizedHash');
      final response = await http.get(url).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        if (body['success'] == true && body['data'] != null) {
          return CertificateRecord.fromJson(
            body['data'] as Map<String, dynamic>,
            fileName: fileName,
          );
        }
      } else if (response.statusCode == 404) {
        // Máy chủ đang bật và xác nhận mã hash chưa từng được lưu trữ trên Blockchain
        return null;
      }
    } catch (e) {
      debugPrint(
        '[ApiService] Laptop Backend không phản hồi ($e) -> Tự động chuyển sang TẦNG 2: Đọc trực tiếp Smart Contract Ethereum Sepolia!',
      );
    }

    // TẦNG 2: Laptop tắt hoàn toàn -> Điện thoại tự động gọi thẳng lên Smart Contract Ethereum Sepolia công khai!
    return await verifyOnChainSepoliaDirect(
      normalizedHash,
      fileName: fileName,
    );
  }

  // ========================================================
  // ĐỌC TRỰC TIẾP SMART CONTRACT ETHEREUM SEPOLIA (KHÔNG CẦN BACKEND LAPTOP)
  // Sử dụng chuẩn JSON-RPC eth_call tới hàm view getRecord(bytes32)
  // ========================================================
  static CertificateRecord? decodeOnChainGetRecordResult(
    String rawHex, {
    required String fallbackHash,
    String fileName = 'Văn bằng xác thực On-Chain',
    CertificateRecord? cachedLocal,
  }) {
    final clean = rawHex.trim();
    // Tuple tĩnh (bytes32 dataHash, address signer, uint256 timestamp) = 3 * 64 + 2 ('0x') = 194 ký tự
    if (!clean.startsWith('0x') || clean.length < 194) {
      return null;
    }

    final returnedHash = '0x${clean.substring(2, 66)}';
    final signerHex = '0x${clean.substring(90, 130)}';
    final timestampBig = BigInt.tryParse(clean.substring(130, 194), radix: 16);
    final timestamp = timestampBig?.toInt() ?? 0;

    final isZeroSigner =
        signerHex.toLowerCase() == '0x0000000000000000000000000000000000000000';
    if (timestamp <= 0 || isZeroSigner) {
      return null;
    }

    final resolvedHash =
        returnedHash == '0x0000000000000000000000000000000000000000000000000000000000000000'
            ? fallbackHash
            : returnedHash;

    return CertificateRecord(
      id: cachedLocal?.id,
      dataHash: resolvedHash,
      signer: signerHex,
      timestamp: timestamp,
      fileName: cachedLocal?.fileName ?? fileName,
      fileType: cachedLocal?.fileType ??
          (fileName.toLowerCase().endsWith('.pdf') ? 'PDF' : 'DOCUMENT'),
      txHash: cachedLocal?.txHash,
      blockNumber: cachedLocal?.blockNumber,
      studentName: cachedLocal?.studentName,
      studentCode: cachedLocal?.studentCode,
      degreeName: cachedLocal?.degreeName,
      issuerName: cachedLocal?.issuerName ??
          'Xác thực trực tiếp On-Chain (Ethereum Sepolia)',
    );
  }

  Future<CertificateRecord?> verifyOnChainSepoliaDirect(
    String normalizedHash, {
    String fileName = 'Văn bằng kiểm tra',
  }) async {
    final calldata =
        '$_getRecordSelector${normalizedHash.substring(2).toLowerCase()}';
    final payload = jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'eth_call',
      'params': [
        {
          'to': sepoliaContractAddress,
          'data': calldata,
        },
        'latest',
      ],
    });

    CertificateRecord? cachedLocal;
    try {
      cachedLocal =
          await DatabaseService.instance.getCertificateByHash(normalizedHash);
    } catch (_) {}

    // Nếu máy hiện tại chưa từng lưu văn bằng này vào SQLite, thử đọc Metadata từ Firebase Realtime Database (/certificates)
    cachedLocal ??=
        await CertificateFirebaseService().getMetadataByHash(normalizedHash);

    Object? lastError;
    for (final rpcUrl in publicSepoliaRpcUrls) {
      try {
        final response = await http
            .post(
              Uri.parse(rpcUrl),
              headers: const {'Content-Type': 'application/json'},
              body: payload,
            )
            .timeout(const Duration(seconds: 7));

        if (response.statusCode == 200) {
          final Map<String, dynamic> body = jsonDecode(response.body);
          if (body.containsKey('result') && body['result'] is String) {
            return decodeOnChainGetRecordResult(
              body['result'] as String,
              fallbackHash: normalizedHash,
              fileName: fileName,
              cachedLocal: cachedLocal,
            );
          }
        }
      } catch (e) {
        lastError = e;
        debugPrint('[ApiService] RPC $rpcUrl lỗi: $e');
      }
    }

    throw Exception(
      'Không có kết nối Internet để truy vấn Ethereum Sepolia (${lastError ?? "Offline"})',
    );
  }

  // ========================================================
  // API 2: Niêm phong văn bằng lên Blockchain (POST /api/v1/notarize)
  // Gửi DataHash đã băm trên RAM kèm Metadata lên Backend
  // ========================================================
  Future<Map<String, dynamic>> notarizeCertificate({
    required String dataHash,
    required String fileName,
    String fileType = 'PDF',
    String? studentName,
    String? studentCode,
    String? degreeName,
    String? issuerName,
    String? createdByEmail,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/notarize');
      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': apiKey,
            },
            body: jsonEncode({
              'dataHash': dataHash,
              'fileName': fileName,
              'fileType': fileType,
              'studentName': studentName,
              'studentCode': studentCode,
              'degreeName': degreeName,
              'issuerName': issuerName,
              'createdByEmail': createdByEmail,
            }),
          )
          .timeout(const Duration(seconds: 60));

      final Map<String, dynamic> body = jsonDecode(response.body);
      if (response.statusCode == 409 || body['isDuplicate'] == true) {
        return {
          'success': false,
          'isDuplicate': true,
          'error': body['error'] ??
              'Tài liệu này đã được niêm phong từ trước trên hệ thống!',
          if (body['existingRecord'] != null)
            'existingRecord': body['existingRecord'],
        };
      }
      if (body['success'] == true && body['isDuplicate'] != true) {
        await _syncNotarizedMetadataToFirebase(
          body: body,
          dataHash: dataHash,
          fileName: fileName,
          fileType: fileType,
          studentName: studentName,
          studentCode: studentCode,
          degreeName: degreeName,
          issuerName: issuerName,
          createdByEmail: createdByEmail,
        );
      }
      return body;
    } catch (e) {
      return {
        'success': false,
        'error': 'Lỗi kết nối máy chủ: $e',
      };
    }
  }

  // ========================================================
  // API 2B: Ký trực tiếp File/Ảnh qua Multipart (POST /api/v1/notarize-file)
  // Hỗ trợ khi cần gửi nhị phân Ảnh/PDF trực tiếp lên Backend Multer
  // ========================================================
  Future<Map<String, dynamic>> notarizeFileMultipart({
    required Uint8List fileBytes,
    required String fileName,
    String? fileType,
    String? studentName,
    String? studentCode,
    String? degreeName,
    String? issuerName,
    String? createdByEmail,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/notarize-file');
      final request = http.MultipartRequest('POST', url);
      request.headers['x-api-key'] = apiKey;

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
        ),
      );

      request.fields['fileName'] = fileName;
      if (fileType != null) request.fields['fileType'] = fileType;
      if (studentName != null) request.fields['studentName'] = studentName;
      if (studentCode != null) request.fields['studentCode'] = studentCode;
      if (degreeName != null) request.fields['degreeName'] = degreeName;
      if (issuerName != null) request.fields['issuerName'] = issuerName;
      if (createdByEmail != null) {
        request.fields['createdByEmail'] = createdByEmail;
      }

      final streamedRes =
          await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamedRes);
      final Map<String, dynamic> body = jsonDecode(response.body);
      if (response.statusCode == 409 || body['isDuplicate'] == true) {
        return {
          'success': false,
          'isDuplicate': true,
          'error': body['error'] ??
              'Tài liệu này đã được niêm phong từ trước trên hệ thống!',
          if (body['existingRecord'] != null)
            'existingRecord': body['existingRecord'],
        };
      }
      if (body['success'] == true && body['isDuplicate'] != true) {
        final returnedHash =
            (body['data']?['dataHash'] ?? body['dataHash'] ?? '').toString();
        if (returnedHash.isNotEmpty) {
          await _syncNotarizedMetadataToFirebase(
            body: body,
            dataHash: returnedHash,
            fileName: fileName,
            fileType: fileType ?? 'PDF',
            studentName: studentName,
            studentCode: studentCode,
            degreeName: degreeName,
            issuerName: issuerName,
            createdByEmail: createdByEmail,
          );
        }
      }
      return body;
    } catch (e) {
      return {
        'success': false,
        'error': 'Lỗi tải file lên máy chủ: $e',
      };
    }
  }

  /// Đồng bộ Metadata văn bằng lên Firebase Realtime Database (/certificates)
  /// ngay sau khi Backend xác nhận ghi thành công lên Ethereum Sepolia & SQL Server.
  Future<void> _syncNotarizedMetadataToFirebase({
    required Map<String, dynamic> body,
    required String dataHash,
    required String fileName,
    required String fileType,
    String? studentName,
    String? studentCode,
    String? degreeName,
    String? issuerName,
    String? createdByEmail,
  }) async {
    try {
      final dataMap = body['data'] is Map
          ? Map<String, dynamic>.from(body['data'] as Map)
          : const <String, dynamic>{};

      final record = CertificateRecord(
        dataHash: dataHash,
        signer: (body['signerUsed'] ?? dataMap['signer'] ?? '').toString(),
        timestamp: dataMap['timestamp'] is int
            ? dataMap['timestamp'] as int
            : DateTime.now().millisecondsSinceEpoch ~/ 1000,
        fileName: fileName,
        fileType: fileType,
        txHash: (body['transactionHash'] ?? dataMap['transactionHash'])
            ?.toString(),
        blockNumber: body['blockNumber'] is int
            ? body['blockNumber'] as int
            : int.tryParse(body['blockNumber']?.toString() ?? ''),
        studentName: studentName,
        studentCode: studentCode,
        degreeName: degreeName,
        issuerName: issuerName,
      );

      await CertificateFirebaseService().saveCertificateMetadata(
        record,
        createdByEmail: createdByEmail,
      );
    } catch (e) {
      debugPrint('[ApiService] Lỗi đồng bộ metadata lên Firebase: $e');
    }
  }

  // ========================================================
  // API 3: Danh sách văn bằng đã cấp phát (GET /api/v1/certificates)
  // Lấy dữ liệu từ SQL Server (hỗ trợ tìm kiếm theo từ khóa)
  // ========================================================
  Future<List<CertificateRecord>> fetchIssuedCertificates({
    String keyword = '',
  }) async {
    try {
      final queryParam = keyword.trim().isNotEmpty
          ? '?q=${Uri.encodeComponent(keyword.trim())}'
          : '';
      final url = Uri.parse('$baseUrl/api/v1/certificates$queryParam');

      final response = await http.get(url).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        if (body['success'] == true && body['data'] is List) {
          final List list = body['data'];
          return list
              .map(
                (item) =>
                    CertificateRecord.fromJson(item as Map<String, dynamic>),
              )
              .toList();
        }
      }
    } catch (e) {
      debugPrint(
        '[ApiService] Không kết nối được SQL Server ($e) -> Thử đọc danh sách từ Firebase Realtime Database!',
      );
      final firebaseList = await CertificateFirebaseService()
          .fetchAllCertificates(keyword: keyword);
      if (firebaseList.isNotEmpty) {
        return firebaseList;
      }
      try {
        return await DatabaseService.instance.searchCertificates(keyword);
      } catch (_) {}
    }
    return [];
  }

  // ========================================================
  // API 4: Kiểm tra kết nối tới Server Backend (/health) & Sepolia On-Chain RPC
  // ========================================================
  Future<bool> checkServerHealth() async {
    try {
      final url = Uri.parse('$baseUrl/health');
      final res = await http.get(url).timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> checkSepoliaRpcHealth() async {
    final payload = jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'eth_chainId',
      'params': [],
    });
    for (final rpcUrl in publicSepoliaRpcUrls) {
      try {
        final res = await http
            .post(
              Uri.parse(rpcUrl),
              headers: const {'Content-Type': 'application/json'},
              body: payload,
            )
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) return true;
      } catch (_) {}
    }
    return false;
  }
}
