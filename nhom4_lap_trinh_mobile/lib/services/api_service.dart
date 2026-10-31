import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/certificate_record.dart';

class ApiService {
  static const String _prefBaseUrlKey = 'server_base_url';
  static const String _prefMockModeKey = 'use_mock_when_offline';

  // Tự động nhận diện: Nếu chạy trên Web/Desktop thì dùng localhost:3000, nếu trên Android Emulator thì dùng 10.0.2.2:3000
  static String get defaultBaseUrl =>
      kIsWeb ? 'http://localhost:3000' : 'http://10.0.2.2:3000';

  static String baseUrl = defaultBaseUrl;
  static String apiKey = 'YOUR_SECRET_B2B_KEY_123';

  // Công tắc giả lập phản hồi khi TV2 & TV3 code giao diện độc lập tại nhà (Mục 7.4 kehoach.md)
  static bool useMockWhenOffline = false;

  // [READ] Tải cấu hình địa chỉ IP Server & chế độ Mock từ SharedPreferences khi mở App
  static Future<void> loadSavedConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString(_prefBaseUrlKey);
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        baseUrl = _normalizeUrl(savedUrl);
      }
      useMockWhenOffline = prefs.getBool(_prefMockModeKey) ?? false;
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

  // [UPDATE] Bật/tắt chế độ Mock Offline hỗ trợ phát triển độc lập
  static Future<void> setMockMode(bool enabled) async {
    useMockWhenOffline = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefMockModeKey, enabled);
    } catch (e) {
      debugPrint('[ApiService] Không thể lưu trạng thái mock: $e');
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

    if (useMockWhenOffline) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (!cleanHash.startsWith('0x') || cleanHash.length != 66) {
        return null;
      }
      return CertificateRecord(
        id: 1,
        dataHash: cleanHash,
        signer: '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        fileName: fileName,
        fileType: fileName.toLowerCase().endsWith('.pdf') ? 'PDF' : 'IMAGE',
        txHash: '0x9f8e7d6c5b4a392817263544556677889900aabbccddeeff1122334455667788',
        blockNumber: 6912045,
        studentName: 'Nguyễn Văn An (Mock)',
        studentCode: 'SV2026001',
        degreeName: 'Bằng Kỹ sư Công nghệ Thông tin',
        issuerName: 'Phòng Đào Tạo (Chế độ Mock)',
      );
    }

    try {
      final url = Uri.parse('$baseUrl/api/v1/verify/$cleanHash');
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        if (body['success'] == true && body['data'] != null) {
          return CertificateRecord.fromJson(
            body['data'] as Map<String, dynamic>,
            fileName: fileName,
          );
        }
      } else if (response.statusCode == 404) {
        // Mã hash chưa từng được lưu trữ trên Blockchain
        return null;
      } else {
        throw Exception('Máy chủ phản hồi lỗi: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
    return null;
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
    if (useMockWhenOffline) {
      await Future.delayed(const Duration(milliseconds: 900));
      const mockTxHash =
          '0xabc123def4567890abc123def4567890abc123def4567890abc123def4567890';
      return {
        'success': true,
        'message': 'Đã lưu giả lập (Chế độ Mock Offline)',
        'transactionHash': mockTxHash,
        'blockNumber': 6912099,
        'signerUsed': '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
        'data': {
          'dataHash': dataHash,
          'fileName': fileName,
          'fileType': fileType,
          'transactionHash': mockTxHash,
          'blockNumber': 6912099,
          'studentName': studentName,
          'studentCode': studentCode,
          'degreeName': degreeName,
          'issuerName': issuerName ?? 'Phòng Đào Tạo',
          'signer': '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
          'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
      };
    }

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
      return body;
    } catch (e) {
      return {
        'success': false,
        'error': 'Lỗi tải file lên máy chủ: $e',
      };
    }
  }

  // ========================================================
  // API 3: Danh sách văn bằng đã cấp phát (GET /api/v1/certificates)
  // Lấy dữ liệu từ SQL Server (hỗ trợ tìm kiếm theo từ khóa)
  // ========================================================
  Future<List<CertificateRecord>> fetchIssuedCertificates({
    String keyword = '',
  }) async {
    if (useMockWhenOffline) {
      await Future.delayed(const Duration(milliseconds: 400));
      return [
        CertificateRecord(
          id: 1,
          dataHash:
              '0x1111222233334444555566667777888899990000aaaabbbbccccddddeeeeffff',
          signer: '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          fileName: 'Bang_Tot_Nghiep_CNTT.pdf',
          fileType: 'PDF',
          txHash:
              '0x9f8e7d6c5b4a392817263544556677889900aabbccddeeff1122334455667788',
          blockNumber: 6912045,
          studentName: 'Nguyễn Văn An (Mock)',
          studentCode: 'SV2026001',
          degreeName: 'Bằng Kỹ sư Công nghệ Thông tin',
          issuerName: 'Phòng Đào Tạo',
        ),
      ];
    }

    try {
      final queryParam = keyword.trim().isNotEmpty
          ? '?q=${Uri.encodeComponent(keyword.trim())}'
          : '';
      final url = Uri.parse('$baseUrl/api/v1/certificates$queryParam');

      final response = await http.get(url).timeout(const Duration(seconds: 15));

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
      debugPrint('[ApiService] Lỗi lấy danh sách văn bằng: $e');
    }
    return [];
  }

  // ========================================================
  // API 4: Kiểm tra kết nối tới Server Backend (/health)
  // ========================================================
  Future<bool> checkServerHealth() async {
    if (useMockWhenOffline) return true;
    try {
      final url = Uri.parse('$baseUrl/health');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
