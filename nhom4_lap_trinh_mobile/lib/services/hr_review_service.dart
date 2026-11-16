import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dịch vụ đồng bộ Quyết định & Biên bản thẩm định HR (2 tầng):
/// - Tầng 1: Firebase Realtime Database (`hr_reviews/<uid>/<hashKey>`) để đồng bộ đa thiết bị
/// - Tầng 2: SharedPreferences cục bộ làm bộ đệm offline an toàn
class HrReviewService {
  static const String legacyPrefKey = 'hr_reviews_map';

  DatabaseReference? _rootReviewsRef;

  HrReviewService() {
    try {
      _rootReviewsRef = FirebaseDatabase.instance.ref().child('hr_reviews');
    } catch (e) {
      debugPrint('[HrReviewService] Firebase Realtime Database chưa kết nối: $e');
      _rootReviewsRef = null;
    }
  }

  String _prefKeyForUser(String? uid) {
    if (uid == null || uid.trim().isEmpty) return legacyPrefKey;
    return '${legacyPrefKey}_${uid.trim()}';
  }

  String normalizeHashKey(String rawHash) => rawHash.trim().toLowerCase();

  Future<Map<String, Map<String, dynamic>>> _loadLocalMap(String? uid) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _prefKeyForUser(uid);
    String? rawJson = prefs.getString(key);

    // Di chuyển dữ liệu cũ từ key chung sang key theo UID nếu cần
    if ((rawJson == null || rawJson.trim().isEmpty) && key != legacyPrefKey) {
      final legacyRaw = prefs.getString(legacyPrefKey);
      if (legacyRaw != null && legacyRaw.trim().isNotEmpty) {
        rawJson = legacyRaw;
        await prefs.setString(key, legacyRaw);
      }
    }

    final Map<String, Map<String, dynamic>> result = {};
    if (rawJson != null && rawJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            if (v is Map) {
              result[normalizeHashKey(k.toString())] =
                  Map<String, dynamic>.from(v);
            }
          });
        }
      } catch (e) {
        debugPrint('[HrReviewService] Lỗi giải mã cache local: $e');
      }
    }
    return result;
  }

  Future<void> _saveLocalMap(
    String? uid,
    Map<String, Map<String, dynamic>> data,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyForUser(uid), jsonEncode(data));
  }

  /// Tải toàn bộ danh sách thẩm định HR (Ưu tiên đồng bộ từ Firebase, fallback cache máy)
  Future<Map<String, Map<String, dynamic>>> fetchReviews({String? uid}) async {
    final localMap = await _loadLocalMap(uid);

    if (_rootReviewsRef != null && uid != null && uid.trim().isNotEmpty) {
      try {
        final snapshot = await _rootReviewsRef!
            .child(uid.trim())
            .get()
            .timeout(const Duration(seconds: 4));

        if (snapshot.exists && snapshot.value is Map) {
          final remoteMap = <String, Map<String, dynamic>>{};
          final rawMap = snapshot.value as Map;
          rawMap.forEach((k, v) {
            if (v is Map) {
              remoteMap[normalizeHashKey(k.toString())] =
                  Map<String, dynamic>.from(v);
            }
          });

          // Nếu có dữ liệu mới trên local chưa đẩy lên Firebase, gộp lại an toàn
          final merged = <String, Map<String, dynamic>>{...remoteMap};
          for (final entry in localMap.entries) {
            if (!merged.containsKey(entry.key)) {
              merged[entry.key] = entry.value;
              await _rootReviewsRef!
                  .child(uid.trim())
                  .child(entry.key)
                  .set(entry.value);
            }
          }

          await _saveLocalMap(uid, merged);
          return merged;
        } else if (localMap.isNotEmpty) {
          // Đồng bộ dữ liệu cục bộ có sẵn lên Firebase lần đầu
          await _rootReviewsRef!.child(uid.trim()).set(localMap);
        }
      } catch (e) {
        debugPrint(
          '[HrReviewService] Không thể đồng bộ từ Firebase, dùng cache máy: $e',
        );
      }
    }

    return localMap;
  }

  /// Lưu hoặc cập nhật một quyết định thẩm định HR
  Future<void> saveReview({
    required String? uid,
    required String hashKey,
    required Map<String, dynamic> reviewData,
  }) async {
    final normalizedKey = normalizeHashKey(hashKey);
    final localMap = await _loadLocalMap(uid);
    localMap[normalizedKey] = reviewData;
    await _saveLocalMap(uid, localMap);

    if (_rootReviewsRef != null && uid != null && uid.trim().isNotEmpty) {
      try {
        await _rootReviewsRef!
            .child(uid.trim())
            .child(normalizedKey)
            .set(reviewData);
      } catch (e) {
        debugPrint('[HrReviewService] Lỗi đẩy đánh giá HR lên Firebase: $e');
      }
    }
  }

  /// Xóa một quyết định thẩm định HR
  Future<void> deleteReview({
    required String? uid,
    required String hashKey,
  }) async {
    final normalizedKey = normalizeHashKey(hashKey);
    final localMap = await _loadLocalMap(uid);
    localMap.remove(normalizedKey);
    await _saveLocalMap(uid, localMap);

    if (_rootReviewsRef != null && uid != null && uid.trim().isNotEmpty) {
      try {
        await _rootReviewsRef!.child(uid.trim()).child(normalizedKey).remove();
      } catch (e) {
        debugPrint('[HrReviewService] Lỗi xóa đánh giá HR trên Firebase: $e');
      }
    }
  }
}
