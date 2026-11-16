import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/certificate_record.dart';
import '../models/scan_history_model.dart';

class DatabaseService {
  // Cấu trúc Singleton chuẩn phong cách môn học (flutter_demo Chương 11)
  static final DatabaseService _databaseService = DatabaseService._init();
  static DatabaseService get instance => _databaseService;
  factory DatabaseService() => _databaseService;
  DatabaseService._init();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('certificates_vault.db');
    return _database!;
  }

  // Truy cập an toàn cho các môi trường chưa khởi tạo native Sqflite (Web / Unit Test)
  Future<Database?> _safeDatabase() async {
    if (kIsWeb) return null;
    try {
      return await instance.database;
    } catch (e) {
      debugPrint('[DatabaseService] Môi trường hiện tại không hỗ trợ native Sqflite: $e');
      return null;
    }
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2, // Nâng version lên 2 để hỗ trợ thêm cột và bảng scan_history
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Bảng lưu trữ văn bằng trong Sổ tay Offline
    await db.execute('''
      CREATE TABLE certificates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dataHash TEXT NOT NULL UNIQUE,
        signer TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        fileName TEXT NOT NULL,
        fileType TEXT DEFAULT 'PDF',
        txHash TEXT,
        blockNumber INTEGER,
        studentName TEXT,
        studentCode TEXT,
        degreeName TEXT,
        issuerName TEXT DEFAULT 'Phòng Đào Tạo',
        savedAt TEXT NOT NULL
      )
    ''');

    // 2. Bảng lưu lịch sử quét mã QR & đối soát offline
    await db.execute('''
      CREATE TABLE scan_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dataHash TEXT NOT NULL,
        fileName TEXT NOT NULL,
        scanMethod TEXT NOT NULL,
        isValid INTEGER NOT NULL,
        issuerName TEXT,
        studentName TEXT,
        degreeName TEXT,
        scannedAt TEXT NOT NULL
      )
    ''');
  }

  // Tự động nâng cấp bảng nếu người dùng đã có file database phiên bản cũ
  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute("ALTER TABLE certificates ADD COLUMN fileType TEXT DEFAULT 'PDF'");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE certificates ADD COLUMN blockNumber INTEGER");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE certificates ADD COLUMN studentCode TEXT");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE certificates ADD COLUMN issuerName TEXT DEFAULT 'Phòng Đào Tạo'");
      } catch (_) {}

      await db.execute('''
        CREATE TABLE IF NOT EXISTS scan_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          dataHash TEXT NOT NULL,
          fileName TEXT NOT NULL,
          scanMethod TEXT NOT NULL,
          isValid INTEGER NOT NULL,
          issuerName TEXT,
          studentName TEXT,
          degreeName TEXT,
          scannedAt TEXT NOT NULL
        )
      ''');
    }
  }

  // ========================================================
  // CÁC HÀM XỬ LÝ BẢNG SỔ TAY VĂN BẰNG (CERTIFICATES)
  // ========================================================

  // [CREATE] Lưu văn bằng vào Sổ tay Offline (Tránh trùng mã Hash)
  Future<int> saveCertificate(CertificateRecord cert) async {
    final db = await _safeDatabase();
    if (db == null) return 0;
    return await db.insert(
      'certificates',
      cert.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // [READ] Đọc danh sách toàn bộ văn bằng đã lưu offline
  Future<List<CertificateRecord>> getAllCertificates() async {
    final db = await _safeDatabase();
    if (db == null) return [];
    final result = await db.query('certificates', orderBy: 'id DESC');
    return result.map((json) => CertificateRecord.fromMap(json)).toList();
  }

  // [READ] Tìm kiếm văn bằng offline theo từ khóa (dùng LIKE chuẩn flutter_demo)
  Future<List<CertificateRecord>> searchCertificates(String keyword) async {
    final clean = keyword.trim();
    if (clean.isEmpty) return getAllCertificates();

    final db = await _safeDatabase();
    if (db == null) return [];

    final result = await db.query(
      'certificates',
      where:
          'fileName LIKE ? OR studentName LIKE ? OR studentCode LIKE ? OR degreeName LIKE ? OR issuerName LIKE ? OR dataHash LIKE ?',
      whereArgs: [
        '%$clean%',
        '%$clean%',
        '%$clean%',
        '%$clean%',
        '%$clean%',
        '%$clean%',
      ],
      orderBy: 'id DESC',
    );
    return result.map((json) => CertificateRecord.fromMap(json)).toList();
  }

  // [READ] Lấy 1 văn bằng đã lưu trong Sổ tay theo mã Hash (không phân biệt hoa thường)
  Future<CertificateRecord?> getCertificateByHash(String dataHash) async {
    final db = await _safeDatabase();
    if (db == null) return null;
    final result = await db.query(
      'certificates',
      where: 'LOWER(dataHash) = ?',
      whereArgs: [dataHash.trim().toLowerCase()],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return CertificateRecord.fromMap(result.first);
    }
    return null;
  }

  // [DELETE] Xóa văn bằng theo mã Hash
  Future<int> deleteCertificateByHash(String dataHash) async {
    final db = await _safeDatabase();
    if (db == null) return 0;
    return await db.delete(
      'certificates',
      where: 'LOWER(dataHash) = ?',
      whereArgs: [dataHash.trim().toLowerCase()],
    );
  }

  // [READ] Kiểm tra xem chứng chỉ đã được lưu trong máy chưa
  Future<bool> isCertificateSaved(String dataHash) async {
    final db = await _safeDatabase();
    if (db == null) return false;
    final result = await db.query(
      'certificates',
      where: 'LOWER(dataHash) = ?',
      whereArgs: [dataHash.trim().toLowerCase()],
    );
    return result.isNotEmpty;
  }

  // [DELETE] Xóa một văn bằng khỏi sổ tay offline
  Future<int> deleteCertificate(int id) async {
    final db = await _safeDatabase();
    if (db == null) return 0;
    return await db.delete(
      'certificates',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ========================================================
  // CÁC HÀM XỬ LÝ BẢNG LỊCH SỬ QUÉT (SCAN_HISTORY)
  // ========================================================

  // [CREATE] Thêm một bản ghi lịch sử tra cứu
  Future<int> saveScanHistory(ScanHistoryModel history) async {
    final db = await _safeDatabase();
    if (db == null) return 0;
    return await db.insert('scan_history', history.toMap());
  }

  // [READ] Lấy toàn bộ lịch sử tra cứu gần nhất
  Future<List<ScanHistoryModel>> getAllScanHistory() async {
    final db = await _safeDatabase();
    if (db == null) return [];
    final result = await db.query('scan_history', orderBy: 'id DESC', limit: 100);
    return result.map((json) => ScanHistoryModel.fromMap(json)).toList();
  }

  // [READ] Tìm kiếm lịch sử tra cứu offline theo từ khóa (dùng LIKE)
  Future<List<ScanHistoryModel>> searchScanHistory(String keyword) async {
    final clean = keyword.trim();
    if (clean.isEmpty) return getAllScanHistory();

    final db = await _safeDatabase();
    if (db == null) return [];

    final result = await db.query(
      'scan_history',
      where:
          'fileName LIKE ? OR studentName LIKE ? OR degreeName LIKE ? OR issuerName LIKE ? OR dataHash LIKE ? OR scanMethod LIKE ?',
      whereArgs: [
        '%$clean%',
        '%$clean%',
        '%$clean%',
        '%$clean%',
        '%$clean%',
        '%$clean%',
      ],
      orderBy: 'id DESC',
      limit: 100,
    );
    return result.map((json) => ScanHistoryModel.fromMap(json)).toList();
  }

  // [DELETE] Xóa toàn bộ lịch sử tra cứu
  Future<int> clearScanHistory() async {
    final db = await _safeDatabase();
    if (db == null) return 0;
    return await db.delete('scan_history');
  }

  // [DELETE] Xóa 1 bản ghi lịch sử
  Future<int> deleteScanHistory(int id) async {
    final db = await _safeDatabase();
    if (db == null) return 0;
    return await db.delete('scan_history', where: 'id = ?', whereArgs: [id]);
  }

  // Đóng cơ sở dữ liệu
  Future<void> close() async {
    final db = await _safeDatabase();
    await db?.close();
  }
}
