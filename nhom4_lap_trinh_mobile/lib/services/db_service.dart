import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/certificate_record.dart';
import '../models/scan_history_model.dart';

class DatabaseService {
  // Cấu trúc Singleton chuẩn phong cách môn học (flutter_demo)
  static final DatabaseService instance = DatabaseService._init();
  factory DatabaseService() => instance;
  DatabaseService._init();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('certificates_vault.db');
    return _database!;
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
      // Bổ sung các cột mới vào certificates
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

      // Tạo bảng scan_history nếu chưa có
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

  // Lưu văn bằng vào Sổ tay Offline (Tránh trùng mã Hash)
  Future<int> saveCertificate(CertificateRecord cert) async {
    final db = await instance.database;
    return await db.insert(
      'certificates',
      cert.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Đọc danh sách toàn bộ văn bằng đã lưu offline
  Future<List<CertificateRecord>> getAllCertificates() async {
    final db = await instance.database;
    final result = await db.query('certificates', orderBy: 'id DESC');
    return result.map((json) => CertificateRecord.fromMap(json)).toList();
  }

  // Tìm kiếm văn bằng offline theo từ khóa (dùng LIKE chuẩn flutter_demo)
  Future<List<CertificateRecord>> searchCertificates(String keyword) async {
    final db = await instance.database;
    final clean = keyword.trim();
    if (clean.isEmpty) return getAllCertificates();

    final result = await db.query(
      'certificates',
      where: 'fileName LIKE ? OR studentName LIKE ? OR studentCode LIKE ? OR degreeName LIKE ? OR dataHash LIKE ?',
      whereArgs: ['%$clean%', '%$clean%', '%$clean%', '%$clean%', '%$clean%'],
      orderBy: 'id DESC',
    );
    return result.map((json) => CertificateRecord.fromMap(json)).toList();
  }

  // Kiểm tra xem chứng chỉ đã được lưu trong máy chưa
  Future<bool> isCertificateSaved(String dataHash) async {
    final db = await instance.database;
    final result = await db.query(
      'certificates',
      where: 'dataHash = ?',
      whereArgs: [dataHash],
    );
    return result.isNotEmpty;
  }

  // Xóa một văn bằng khỏi sổ tay offline
  Future<int> deleteCertificate(int id) async {
    final db = await instance.database;
    return await db.delete(
      'certificates',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ========================================================
  // CÁC HÀM XỬ LÝ BẢNG LỊCH SỬ QUÉT (SCAN_HISTORY)
  // ========================================================

  // Thêm một bản ghi lịch sử tra cứu
  Future<int> saveScanHistory(ScanHistoryModel history) async {
    final db = await instance.database;
    return await db.insert('scan_history', history.toMap());
  }

  // Lấy toàn bộ lịch sử tra cứu gần nhất
  Future<List<ScanHistoryModel>> getAllScanHistory() async {
    final db = await instance.database;
    final result = await db.query('scan_history', orderBy: 'id DESC', limit: 100);
    return result.map((json) => ScanHistoryModel.fromMap(json)).toList();
  }

  // Xóa toàn bộ lịch sử tra cứu
  Future<int> clearScanHistory() async {
    final db = await instance.database;
    return await db.delete('scan_history');
  }

  // Xóa 1 bản ghi lịch sử
  Future<int> deleteScanHistory(int id) async {
    final db = await instance.database;
    return await db.delete('scan_history', where: 'id = ?', whereArgs: [id]);
  }

  // Đóng cơ sở dữ liệu
  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
