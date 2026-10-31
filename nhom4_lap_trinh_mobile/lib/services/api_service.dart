import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/certificate_record.dart';

class ApiService {
  // Tự động nhận diện: Nếu chạy trên Web/Desktop thì dùng localhost:3000, nếu trên Android Emulator thì dùng 10.0.2.2:3000
  static String baseUrl = kIsWeb ? 'http://localhost:3000' : 'http://10.0.2.2:3000';
  static String apiKey = 'YOUR_SECRET_B2B_KEY_123';

  // Cập nhật địa chỉ Backend khi người dùng đổi trong Cài đặt
  static void updateBaseUrl(String newUrl) {
    if (newUrl.endsWith('/')) {
      baseUrl = newUrl.substring(0, newUrl.length - 1);
    } else {
      baseUrl = newUrl;
    }
  }

  // ========================================================
  // API 1: Xác minh tính hợp lệ của văn bằng (GET /api/v1/verify/:hash)
  // Đọc dữ liệu từ Smart Contract trên Ethereum Sepolia & SQL Server
  // ========================================================
  Future<CertificateRecord?> verifyHash(String hash, {String fileName = 'Văn bằng kiểm tra'}) async {
    try {
      final cleanHash = hash.trim();
      final url = Uri.parse('$baseUrl/api/v1/verify/$cleanHash');

      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        if (body['success'] == true && body['data'] != null) {
          return CertificateRecord.fromJson(body['data'], fileName: fileName);
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
    try {
      final url = Uri.parse('$baseUrl/api/v1/notarize');
      final response = await http.post(
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
      ).timeout(const Duration(seconds: 60));

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
  // API 3: Danh sách văn bằng đã cấp phát (GET /api/v1/certificates)
  // Lấy dữ liệu từ SQL Server (hỗ trợ tìm kiếm theo từ khóa)
  // ========================================================
  Future<List<CertificateRecord>> fetchIssuedCertificates({String keyword = ''}) async {
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
              .map((item) => CertificateRecord.fromJson(item as Map<String, dynamic>))
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
    try {
      final url = Uri.parse('$baseUrl/health');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
