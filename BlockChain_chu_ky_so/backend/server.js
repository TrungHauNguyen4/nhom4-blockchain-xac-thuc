import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import { ethers } from 'ethers';
import rateLimit from 'express-rate-limit';
import multer from 'multer';
import { insertNotaryHistory, getNotaryByHash, getAllNotaryRecords, connectDB } from './db.js';

// Khởi tạo kết nối DB ngay khi start server
connectDB();

const app = express();
app.use(cors());
app.use(express.json());

// Cấu hình Multer để đọc file nhị phân (RAM buffer)
const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 25 * 1024 * 1024 } // Tối đa 25MB
});

const apiLimiter = rateLimit({
    windowMs: 1 * 60 * 1000,
    max: 30, // Cho phép tối đa 30 yêu cầu / phút
    message: { error: 'Quá nhiều yêu cầu, vui lòng thử lại sau 1 phút' }
});

const checkApiKey = (req, res, next) => {
    const apiKey = req.headers['x-api-key'];
    if (!apiKey || apiKey !== process.env.API_KEY) {
        return res.status(403).json({ error: 'Truy cập bị từ chối: API Key không hợp lệ' });
    }
    next();
};

// 1. Cấu hình Blockchain
const RPC_URL = process.env.RPC_URL || 'https://ethereum-sepolia-rpc.publicnode.com';
const PRIVATE_KEY = process.env.MASTER_PRIVATE_KEY;
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS;

if (!PRIVATE_KEY || !CONTRACT_ADDRESS) {
    console.error("Vui lòng cấu hình MASTER_PRIVATE_KEY và CONTRACT_ADDRESS trong file .env");
    process.exit(1);
}

// Khởi tạo Ethers Provider và Wallet (Ví Master của Hệ thống)
const provider = new ethers.JsonRpcProvider(RPC_URL);
const baseWallet = new ethers.Wallet(PRIVATE_KEY, provider);
const masterWallet = new ethers.NonceManager(baseWallet);

const contractABI = [
    "function submitSignedRecord(bytes32 dataHash, bytes signature) external",
    "function getRecord(bytes32 dataHash) external view returns (tuple(bytes32 dataHash, address signer, uint256 timestamp))",
    "event RecordSigned(address indexed signer, bytes32 indexed dataHash, uint256 timestamp)"
];

const contract = new ethers.Contract(CONTRACT_ADDRESS, contractABI, masterWallet);

console.log(`[Khởi động] Đang kết nối mạng lưới Sepolia với ví Admin: ${baseWallet.address}`);

// Endpoint kiểm tra sức khỏe server (Health Check)
app.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        server: 'Blockchain Certificate Verifier Backend',
        signer: baseWallet.address,
        serverTime: new Date().toISOString()
    });
});

// ========================================================
// API 1: LƯU TRỮ LÊN BLOCKCHAIN TỪ CLIENT-SIDE HASH (NOTARIZE)
// Mobile/Web tự băm Keccak256 trên RAM -> gửi Hash lên
// ========================================================
app.post('/api/v1/notarize', apiLimiter, checkApiKey, async (req, res) => {
    try {
        const {
            dataHash,
            fileName,
            fileType,
            studentName,
            studentCode,
            degreeName,
            issuerName,
            createdByEmail
        } = req.body;

        if (!dataHash || !dataHash.startsWith('0x') || dataHash.length !== 66) {
            return res.status(400).json({ error: 'dataHash không hợp lệ (phải là chuỗi hex bytes32 bắt đầu bằng 0x)' });
        }

        console.log(`\n[Notarize] Nhận yêu cầu ký số cho Hash: ${dataHash}`);

        // 1. Hệ thống tự động tạo chữ ký ECDSA từ ví Master
        const signature = await masterWallet.signMessage(ethers.getBytes(dataHash));
        console.log(`- Đã tạo chữ ký hệ thống: ${signature.substring(0, 20)}...`);

        // 2. Gọi Smart Contract và trả phí Gas trên Sepolia
        console.log(`- Đang gửi giao dịch lên mạng lưới Sepolia...`);
        const tx = await contract.submitSignedRecord(dataHash, signature);

        console.log(`- Đã gửi. TxHash: ${tx.hash}`);
        console.log(`- Đang chờ Mạng lưới xác nhận (Mining)...`);
        const receipt = await tx.wait();

        console.log(`=> Thành công! Được lưu tại Block số ${receipt.blockNumber}`);

        // 3. Lưu toàn bộ Metadata vào Database SQL Server
        await insertNotaryHistory({
            fileName: fileName || 'Văn bằng chứng chỉ',
            fileType: fileType || 'PDF',
            dataHash,
            txHash: tx.hash,
            blockNumber: receipt.blockNumber,
            signer: baseWallet.address,
            studentName: studentName || null,
            studentCode: studentCode || null,
            degreeName: degreeName || null,
            issuerName: issuerName || 'Phòng Đào Tạo',
            createdByEmail: createdByEmail || null
        });

        return res.status(200).json({
            success: true,
            message: 'Đã lưu vĩnh viễn lên Blockchain và CSDL',
            transactionHash: tx.hash,
            blockNumber: receipt.blockNumber,
            signerUsed: baseWallet.address,
            data: {
                dataHash,
                fileName: fileName || 'Văn bằng chứng chỉ',
                fileType: fileType || 'PDF',
                transactionHash: tx.hash,
                blockNumber: receipt.blockNumber,
                studentName: studentName || null,
                studentCode: studentCode || null,
                degreeName: degreeName || null,
                issuerName: issuerName || 'Phòng Đào Tạo',
                signer: baseWallet.address,
                timestamp: Math.floor(Date.now() / 1000)
            }
        });
    } catch (error) {
        console.error('Lỗi khi notarize:', error.reason || error.message);

        let friendlyMessage = 'Lỗi hệ thống';
        if (error.reason) {
            friendlyMessage = error.reason;
        } else if (error.message && error.message.includes('revert')) {
            friendlyMessage = 'Giao dịch bị từ chối bởi Smart Contract (Văn bằng này đã từng được niêm phong từ trước)';
        } else {
            friendlyMessage = error.message;
        }

        return res.status(500).json({
            success: false,
            error: friendlyMessage
        });
    }
});

// ========================================================
// API 2: BĂM VÀ KÝ TRỰC TIẾP FILE/ẢNH QUA SERVER (MULTIPART)
// Hỗ trợ upload ảnh (jpg, png) hoặc PDF từ Postman hoặc Client
// ========================================================
app.post('/api/v1/notarize-file', apiLimiter, checkApiKey, upload.single('file'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({ error: 'Vui lòng đính kèm file trong trường "file"' });
        }

        const buffer = req.file.buffer;
        // Băm Keccak-256 trực tiếp trên RAM của Server
        const dataHash = ethers.keccak256(new Uint8Array(buffer));
        console.log(`\n[Notarize File] Đã băm "${req.file.originalname}" (${req.file.size} bytes) -> Hash: ${dataHash}`);

        // Tự động nhận diện loại file
        let detectedType = 'PDF';
        const mimetype = req.file.mimetype || '';
        const ext = req.file.originalname.split('.').pop()?.toLowerCase();
        if (mimetype.startsWith('image/') || ['png', 'jpg', 'jpeg'].includes(ext)) {
            detectedType = 'IMAGE';
        }

        const fileName = req.body.fileName || req.file.originalname;
        const fileType = req.body.fileType || detectedType;
        const { studentName, studentCode, degreeName, issuerName, createdByEmail } = req.body;

        // 1. Ký số trên Server
        const signature = await masterWallet.signMessage(ethers.getBytes(dataHash));
        console.log(`- Đã tạo chữ ký hệ thống: ${signature.substring(0, 20)}...`);

        // 2. Gửi Smart Contract
        console.log(`- Đang gửi giao dịch lên mạng lưới Sepolia...`);
        const tx = await contract.submitSignedRecord(dataHash, signature);
        console.log(`- Đã gửi. TxHash: ${tx.hash}`);
        const receipt = await tx.wait();
        console.log(`=> Thành công! Được lưu tại Block số ${receipt.blockNumber}`);

        // 3. Lưu vào Database SQL Server
        await insertNotaryHistory({
            fileName,
            fileType,
            dataHash,
            txHash: tx.hash,
            blockNumber: receipt.blockNumber,
            signer: baseWallet.address,
            studentName: studentName || null,
            studentCode: studentCode || null,
            degreeName: degreeName || null,
            issuerName: issuerName || 'Phòng Đào Tạo',
            createdByEmail: createdByEmail || null
        });

        return res.status(200).json({
            success: true,
            message: 'Đã băm và lưu file vĩnh viễn lên Blockchain và CSDL',
            dataHash,
            transactionHash: tx.hash,
            blockNumber: receipt.blockNumber,
            signerUsed: baseWallet.address,
            data: {
                dataHash,
                fileName,
                fileType,
                transactionHash: tx.hash,
                blockNumber: receipt.blockNumber,
                studentName: studentName || null,
                studentCode: studentCode || null,
                degreeName: degreeName || null,
                issuerName: issuerName || 'Phòng Đào Tạo',
                signer: baseWallet.address,
                timestamp: Math.floor(Date.now() / 1000)
            }
        });
    } catch (error) {
        console.error('Lỗi khi notarize file:', error.reason || error.message);
        let friendlyMessage = error.reason || (error.message && error.message.includes('revert')
            ? 'Giao dịch bị từ chối bởi Smart Contract (Tài liệu này đã từng được niêm phong từ trước)'
            : error.message);

        return res.status(500).json({
            success: false,
            error: friendlyMessage
        });
    }
});

// ========================================================
// API 3: XÁC MINH TRẠNG THÁI (VERIFY)
// Kết hợp đối soát Blockchain VÀ đọc thông tin từ SQL Server
// ========================================================
app.get('/api/v1/verify/:hash', async (req, res) => {
    try {
        const dataHash = req.params.hash.trim();
        if (!dataHash || !dataHash.startsWith('0x')) {
            return res.status(400).json({ success: false, error: 'Mã băm không đúng định dạng (phải bắt đầu bằng 0x)' });
        }

        // 1. Kiểm tra trên Blockchain Smart Contract
        const result = await contract.getRecord(dataHash);

        if (result.signer === "0x0000000000000000000000000000000000000000") {
            return res.status(404).json({ success: false, message: 'Dữ liệu này chưa từng được lưu trữ trên Blockchain' });
        }

        // 2. Tra cứu thêm thông tin chi tiết từ Database SQL Server
        const dbRecord = await getNotaryByHash(dataHash);

        return res.status(200).json({
            success: true,
            data: {
                dataHash: result.dataHash,
                signer: result.signer,
                timestamp: Number(result.timestamp),
                // Metadata bổ sung từ SQL Server
                transactionHash: dbRecord?.TxHash || null,
                fileName: dbRecord?.FileName || 'Văn bằng đã xác thực',
                fileType: dbRecord?.FileType || 'PDF',
                blockNumber: dbRecord?.BlockNumber || null,
                studentName: dbRecord?.StudentName || null,
                studentCode: dbRecord?.StudentCode || null,
                degreeName: dbRecord?.DegreeName || null,
                issuerName: dbRecord?.IssuerName || 'Phòng Đào Tạo',
                createdByEmail: dbRecord?.CreatedByEmail || null,
                previewUrl: dbRecord?.PreviewUrl || null
            }
        });
    } catch (error) {
        console.error('Lỗi khi verify:', error);
        return res.status(500).json({ success: false, error: 'Lỗi tra cứu Blockchain' });
    }
});

// ========================================================
// API 4: DANH SÁCH VĂN BẰNG ĐÃ CẤP PHÁT (SQL SERVER)
// Phục vụ màn hình danh sách của Cán bộ đào tạo
// ========================================================
app.get('/api/v1/certificates', async (req, res) => {
    try {
        const keyword = req.query.q || req.query.keyword || '';
        const list = await getAllNotaryRecords(keyword);

        return res.status(200).json({
            success: true,
            total: list.length,
            data: list.map(item => ({
                id: item.Id,
                fileName: item.FileName,
                fileType: item.FileType,
                dataHash: item.DataHash,
                transactionHash: item.TxHash,
                blockNumber: item.BlockNumber,
                signer: item.Signer,
                timestamp: item.CreatedAt
                    ? Math.floor(new Date(item.CreatedAt).getTime() / 1000)
                    : Math.floor(Date.now() / 1000),
                studentName: item.StudentName,
                studentCode: item.StudentCode,
                degreeName: item.DegreeName,
                issuerName: item.IssuerName,
                createdByEmail: item.CreatedByEmail,
                previewUrl: item.PreviewUrl || null,
                createdAt: item.CreatedAt
            }))
        });
    } catch (error) {
        console.error('Lỗi khi lấy danh sách certificates:', error);
        return res.status(500).json({ success: false, error: 'Lỗi truy vấn danh sách văn bằng' });
    }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`\n========================================`);
    console.log(` API Gateway Blockchain Certificate Verifier chạy tại Cổng ${PORT}`);
    console.log(`========================================\n`);
});
