# CẤU TRÚC DỰ ÁN & DANH SÁCH THƯ VIỆN

Dự án được chia thành 2 thư mục độc lập (Frontend và Backend), tuân thủ tiêu chuẩn Microservices.

## 1. Cây Thư Mục Tổng Quan

```text
d:\BlockChain_chu_ky_so\
├── frontend/                          # Giao diện người dùng (React.js)
│   ├── package.json                   # Cấu hình và thư viện Frontend
│   ├── index.html                     # Trang khung HTML
│   ├── src/
│   │   ├── main.tsx                   # Điểm khởi chạy React
│   │   ├── App.tsx                    # Code logic chính (Tải file, Băm Hash, Giao diện)
│   │   └── App.css                    # Code làm đẹp giao diện
│
├── backend/                           # Máy chủ Node.js & Smart Contract
│   ├── package.json                   # Cấu hình và thư viện Backend (Chuẩn ESM)
│   ├── server.js                      # Trái tim của Backend, chứa logic kết nối API và Blockchain
│   ├── .env                           # Nơi giấu bí mật (Private Key, API Key) - Không bao giờ đưa lên Github!
│   ├── hardhat.config.js              # Cấu hình bộ biên dịch Smart Contract (Hỗ trợ mạng Sepolia & Cancun EVM)
│   ├── contracts/                     # Chứa mã nguồn Blockchain
│   │   └── SignedRecordRegistry.sol   # Mã nguồn Smart Contract chính thức của dự án
│   └── scripts/                       # Mã thực thi phụ trợ
│       └── deploy.js                  # Lệnh tự động Deploy và lưu địa chỉ vào .env
│
├── MVP_Architecture_and_Workflow.md         # (Tài liệu) Kiến trúc và Luồng chạy
├── Production_Upgrade_Plan.md               # (Tài liệu) Kế hoạch nâng cấp
└── Project_Structure_and_Files_Description.md # (Tài liệu) Cấu trúc dự án (Là file này)
```

## 2. Chi Tiết Các File Cốt Lõi

### Tầng Giao Diện (`frontend/src/App.tsx`)
Nơi xử lý giao diện hiển thị cho khách hàng. Chứa 2 tính năng quan trọng nhất:
1. **Hàm `hashFileContent`:** Đọc dữ liệu nhị phân (Binary) của file PDF và chạy thuật toán Keccak256 để xuất ra mã Hash. Việc này chạy ngay trên RAM của người dùng (Client-side), đảm bảo tuyệt đối không có sự rò rỉ dữ liệu lên mạng.
2. **Hàm `handleSubmit` và `handleVerifyFileChange`:** Nơi gọi API `POST /notarize` và `GET /verify` gửi đến Backend, có đính kèm khóa bí mật `x-api-key`.

### Tầng Xử Lý (`backend/server.js`)
Nơi nhận lệnh từ Frontend và đại diện người dùng giao tiếp với Blockchain.
- **Bảo mật:** Sử dụng `express-rate-limit` để chống Spam (10 req/min) và chặn những ai không có `x-api-key`.
- **Kết nối:** Khởi tạo mạng lưới Ethers và nạp `MASTER_PRIVATE_KEY`.
- **Chống kẹt xe:** Sử dụng `ethers.NonceManager` bọc ngoài ví, giúp Backend tự động xếp hàng hàng trăm giao dịch gửi đến cùng một lúc mà không bị văng lỗi.

### Tầng Lưu Trữ Blockchain (`backend/contracts/SignedRecordRegistry.sol`)
Linh hồn của hệ thống chứng nhận.
- Viết bằng ngôn ngữ **Solidity** v0.8.24.
- Lưu trữ một bảng ánh xạ `mapping(bytes32 => SignedRecord) public records;`. Nghĩa là ứng với mỗi mã Hash, hệ thống sẽ lưu lại `[Người Ký]` và `[Mốc Thời Gian]`.
- **Chống ghi đè (Bảo mật V2):** Thêm cơ chế kiểm tra `records[dataHash].timestamp == 0` để đảm bảo không ai được quyền cập nhật lại mốc thời gian của một file đã lưu.
- **Chống rác (Bảo mật V2):** Thiết lập quyền `admin`. Trực tiếp kiểm tra và từ chối các giao dịch đến từ người lạ.

## 3. Danh Sách Thư Viện (Libraries & Dependencies)

Để xây dựng hệ thống, chúng ta sử dụng các thư viện chuẩn công nghiệp:

### Thư Viện Frontend
- **`react` & `react-dom`:** Bộ khung giao diện UI số 1 thế giới hiện nay. Giúp xây dựng giao diện tương tác tức thời.
- **`vite`:** Trình khởi chạy và đóng gói siêu tốc, thay thế cho Create-React-App cũ kỹ.
- **`ethers` (v6.17):** Cầu nối giao tiếp với Blockchain. Dùng để chạy thuật toán `Keccak256` ngay trên trình duyệt máy khách.
- **`lucide-react`:** Thư viện chứa các Icon sắc nét (như dấu tích xanh, cái khiên bảo mật) làm đẹp UI.

### Thư Viện Backend
Hệ thống Backend được cấu hình chạy dưới chuẩn **ESM (ECMAScript Modules)** qua thẻ `"type": "module"` trong `package.json`.
- **`express`:** Framework dùng để tạo máy chủ HTTP, nhận các yêu cầu REST API từ Frontend.
- **`cors`:** Middleware cấp phép bảo mật cho Frontend (Port 5174) được quyền gọi vào Backend (Port 3000) mà không bị trình duyệt chặn (Lỗi CORS).
- **`dotenv`:** Tiện ích siêu nhỏ gọn dùng để đọc các biến môi trường nhạy cảm từ file `.env` nạp vào RAM.
- **`express-rate-limit`:** Lá chắn khiên thép, đếm và chặn các địa chỉ IP spam quá số lần quy định.
- **`ethers` (v6.17):** Bộ não kết nối Blockchain cho Node.js, quản lý ví, đóng gói chữ ký ECDSA và xử lý hàng đợi giao dịch bằng NonceManager.
- **`hardhat` & `@nomicfoundation/hardhat-toolbox`:** Bộ công cụ xưởng đúc (Framework) số 1 dành cho lập trình viên Smart Contract. Dùng để biên dịch code Solidity sang Bytecode, cung cấp công cụ Test và Deploy.
- **`@openzeppelin/contracts`:** Thư viện Smart Contract chuẩn mực của thế giới, cung cấp các hàm mã hóa an toàn đã được cộng đồng Audit gắt gao.
