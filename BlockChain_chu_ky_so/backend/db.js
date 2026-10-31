import sql from 'mssql/msnodesqlv8.js';
import dotenv from 'dotenv';
dotenv.config();

const dbConfig = {
    server: 'MSI\\MSSQLSERVER01', // Tên Server SQL Server của bạn
    database: 'EnterpriseNotaryDB',
    driver: 'msnodesqlv8',
    options: {
        trustedConnection: true, // Dùng Windows Authentication
        encrypt: false,
        trustServerCertificate: true
    }
};

let poolPromise;

// Tự động kiểm tra và thêm các cột còn thiếu trong bảng NotaryHistory (Zero-config migration)
const ensureTableSchema = async (pool) => {
    try {
        const query = `
            IF OBJECT_ID('dbo.NotaryHistory', 'U') IS NOT NULL
            BEGIN
                IF COL_LENGTH('dbo.NotaryHistory', 'FileType') IS NULL ALTER TABLE dbo.NotaryHistory ADD FileType VARCHAR(20) DEFAULT 'PDF';
                IF COL_LENGTH('dbo.NotaryHistory', 'BlockNumber') IS NULL ALTER TABLE dbo.NotaryHistory ADD BlockNumber INT NULL;
                IF COL_LENGTH('dbo.NotaryHistory', 'StudentName') IS NULL ALTER TABLE dbo.NotaryHistory ADD StudentName NVARCHAR(150) NULL;
                IF COL_LENGTH('dbo.NotaryHistory', 'StudentCode') IS NULL ALTER TABLE dbo.NotaryHistory ADD StudentCode VARCHAR(50) NULL;
                IF COL_LENGTH('dbo.NotaryHistory', 'DegreeName') IS NULL ALTER TABLE dbo.NotaryHistory ADD DegreeName NVARCHAR(255) NULL;
                IF COL_LENGTH('dbo.NotaryHistory', 'IssuerName') IS NULL ALTER TABLE dbo.NotaryHistory ADD IssuerName NVARCHAR(255) DEFAULT N'Phòng Đào Tạo';
                IF COL_LENGTH('dbo.NotaryHistory', 'CreatedByEmail') IS NULL ALTER TABLE dbo.NotaryHistory ADD CreatedByEmail VARCHAR(150) NULL;
            END
        `;
        await pool.request().query(query);
        console.log("✅ Cấu trúc bảng NotaryHistory trên SQL Server đã được đồng bộ!");
    } catch (err) {
        console.warn("⚠️ Cảnh báo kiểm tra cấu trúc bảng SQL Server:", err.message);
    }
};

export const connectDB = async () => {
    if (!poolPromise) {
        console.log("- Đang kết nối tới SQL Server (MSI\\MSSQLSERVER01)...");
        poolPromise = new sql.ConnectionPool(dbConfig)
            .connect()
            .then(async (pool) => {
                console.log("✅ Kết nối SQL Server Database thành công!");
                await ensureTableSchema(pool);
                return pool;
            })
            .catch(err => {
                console.error("❌ Lỗi kết nối SQL Server Database:", err);
                poolPromise = null;
                throw err;
            });
    }
    return poolPromise;
};

// Hàm tiện ích để chèn lịch sử (hỗ trợ cả truyền object hoặc các tham số rời)
export const insertNotaryHistory = async (params, maybeDataHash, maybeTxHash, maybeSigner) => {
    try {
        let p = {};
        if (typeof params === 'object' && params !== null) {
            p = params;
        } else {
            p = {
                fileName: params,
                dataHash: maybeDataHash,
                txHash: maybeTxHash,
                signer: maybeSigner
            };
        }

        const pool = await connectDB();
        const request = pool.request();

        request.input('FileName', sql.NVarChar(255), p.fileName || 'Tài liệu văn bằng');
        request.input('FileType', sql.VarChar(20), p.fileType || 'PDF');
        request.input('DataHash', sql.VarChar(66), p.dataHash);
        request.input('TxHash', sql.VarChar(66), p.txHash);
        request.input('BlockNumber', sql.Int, p.blockNumber || null);
        request.input('Signer', sql.VarChar(42), p.signer);
        request.input('StudentName', sql.NVarChar(150), p.studentName || null);
        request.input('StudentCode', sql.VarChar(50), p.studentCode || null);
        request.input('DegreeName', sql.NVarChar(255), p.degreeName || null);
        request.input('IssuerName', sql.NVarChar(255), p.issuerName || 'Phòng Đào Tạo');
        request.input('CreatedByEmail', sql.VarChar(150), p.createdByEmail || null);

        const result = await request.query(`
            INSERT INTO NotaryHistory (
                FileName, FileType, DataHash, TxHash, BlockNumber, Signer,
                StudentName, StudentCode, DegreeName, IssuerName, CreatedByEmail
            )
            VALUES (
                @FileName, @FileType, @DataHash, @TxHash, @BlockNumber, @Signer,
                @StudentName, @StudentCode, @DegreeName, @IssuerName, @CreatedByEmail
            )
        `);

        console.log(`[DB] Đã lưu lịch sử vào Database thành công: ${p.fileName || 'Tài liệu văn bằng'}`);
        return result;
    } catch (error) {
        console.error("[DB] Lỗi lưu trữ lịch sử:", error);
    }
};

// Truy vấn thông tin bổ sung từ SQL Server khi Verify
export const getNotaryByHash = async (dataHash) => {
    try {
        const pool = await connectDB();
        const request = pool.request();
        request.input('DataHash', sql.VarChar(66), dataHash);
        const result = await request.query(`
            SELECT TOP 1 * FROM NotaryHistory WHERE DataHash = @DataHash ORDER BY Id DESC
        `);
        return result.recordset[0] || null;
    } catch (error) {
        console.error("[DB] Lỗi khi truy vấn NotaryHistory theo hash:", error);
        return null;
    }
};

// Lấy danh sách văn bằng đã cấp phát (hỗ trợ lọc theo từ khóa)
export const getAllNotaryRecords = async (keyword = '') => {
    try {
        const pool = await connectDB();
        const request = pool.request();
        if (keyword && keyword.trim()) {
            request.input('Keyword', sql.NVarChar(255), `%${keyword.trim()}%`);
            const result = await request.query(`
                SELECT * FROM NotaryHistory 
                WHERE FileName LIKE @Keyword 
                   OR DataHash LIKE @Keyword 
                   OR TxHash LIKE @Keyword
                   OR StudentName LIKE @Keyword 
                   OR StudentCode LIKE @Keyword 
                   OR DegreeName LIKE @Keyword
                   OR IssuerName LIKE @Keyword
                ORDER BY Id DESC
            `);
            return result.recordset;
        } else {
            const result = await request.query(`
                SELECT TOP 100 * FROM NotaryHistory ORDER BY Id DESC
            `);
            return result.recordset;
        }
    } catch (error) {
        console.error("[DB] Lỗi khi lấy danh sách NotaryHistory:", error);
        return [];
    }
};
