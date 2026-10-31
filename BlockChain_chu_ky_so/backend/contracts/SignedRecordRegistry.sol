// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract SignedRecordRegistry {
    // Không cần 'using ECDSA for bytes32' ở phiên bản OZ v5 mới nhất để tránh lỗi
    
    struct SignedRecord {
        bytes32 dataHash;
        address signer;
        uint256 timestamp;
    }

    mapping(bytes32 => SignedRecord) public records;

    address public admin;

    event RecordSigned(address indexed signer, bytes32 indexed dataHash, uint256 timestamp);

    constructor() {
        admin = msg.sender;
    }

    // Hàm nhận Hash và Chữ ký để lưu lên Blockchain
    function submitSignedRecord(bytes32 dataHash, bytes memory signature) external {
        // 1. Thêm prefix chuẩn của Ethereum vào Hash (giống hệt cách ethers.js làm ở Frontend)
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(dataHash);
        
        // 2. Dùng ecrecover (thông qua thư viện ECDSA) để lấy địa chỉ ví đã ký
        address recoveredSigner = ECDSA.recover(ethSignedHash, signature);

        // 3. Đảm bảo chữ ký hợp lệ và ĐÚNG LÀ CỦA ADMIN (Hệ thống B2B)
        require(recoveredSigner != address(0), "Chu ky khong hop le hoac bi loi");
        require(recoveredSigner == admin, "Loi bao mat: Chi he thong B2B moi duoc phep ky");

        // 3.1 Kiểm tra chống ghi đè: Mã Hash này chưa từng tồn tại
        require(records[dataHash].timestamp == 0, "Loi bao mat: Tai lieu nay da duoc niem phong tu truoc");

        // 4. Lưu dữ liệu vào biến trạng thái (State variable) của Smart Contract
        records[dataHash] = SignedRecord({
            dataHash: dataHash,
            signer: recoveredSigner,
            timestamp: block.timestamp
        });

        // 5. Phát sự kiện để Frontend dễ dàng lắng nghe
        emit RecordSigned(recoveredSigner, dataHash, block.timestamp);
    }

    // Hàm kiểm tra xem một dataHash đã được ký và lưu chưa
    function getRecord(bytes32 dataHash) external view returns (SignedRecord memory) {
        return records[dataHash];
    }
}
