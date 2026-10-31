# KIẾN TRÚC & LUỒNG HOẠT ĐỘNG (CẬP NHẬT PATCH V2)

Tài liệu này mô tả chi tiết mô hình kiến trúc, các thành phần kỹ thuật, và luồng dữ liệu (Data Flow) của giải pháp **Enterprise e-Notary (BaaS - Blockchain as a Service)**.

> [!NOTE]
> Hệ thống vừa được nâng cấp bảo mật toàn diện (Security Patch V2), giải quyết triệt để các lỗ hổng về Access Control, Overwrite, Spam/DDoS và Xung đột giao dịch (Nonce Collision).

## 1. Mô Hình Kiến Trúc: B2B BaaS (Backend as a Service)

Thay vì bắt người dùng cuối (End-user) tự cài đặt ví MetaMask, tự mua tiền ảo ETH và tự trả phí, dự án áp dụng mô hình **BaaS dành cho Doanh nghiệp (B2B)**.
Hệ thống này cung cấp dịch vụ Công chứng Blockchain cho các phần mềm khác (như Phần mềm Kế toán, Quản lý Hợp đồng) thông qua một cổng kết nối duy nhất (API Server).

### Các thành phần chính:
1. **Frontend (React.js / Vite):** Đóng vai trò là công cụ tương tác trực tiếp hoặc bộ phận Client. Nhiệm vụ tối quan trọng là băm dữ liệu nội bộ trên máy khách (Client-side Hashing) để đảm bảo quyền riêng tư.
2. **Backend (Node.js / Express):** Trái tim của hệ thống BaaS. Nắm giữ **Master Wallet** (Ví quản trị có chứa ETH) và **B2B API Key**. Backend đóng vai trò Đại lý ủy quyền, thay mặt khách hàng trả phí Gas và đẩy dữ liệu lên mạng lưới.
3. **Smart Contract (Solidity):** Cuốn sổ cái bất biến trên mạng Sepolia (Ethereum). Nơi lưu trữ vĩnh viễn cặp dữ liệu `[Data Hash]` + `[Timestamp]`.

## 2. Các Cơ Chế Bảo Mật Tích Hợp (Security Features)

- **Anti-Spam (Rate Limiting):** Cổng API `/api/v1/notarize` được bảo vệ bởi bộ đếm giới hạn (Tối đa 10 yêu cầu / 1 phút / IP). Ngăn chặn Hacker dùng vòng lặp rút cạn tiền Gas của hệ thống.
- **API Key Authentication:** Yêu cầu header `x-api-key` để đảm bảo chỉ những đối tác doanh nghiệp hợp lệ mới được gọi dịch vụ.
- **Nonce Queueing:** Sử dụng `ethers.NonceManager` bọc ngoài Ví Quản trị. Giúp máy chủ có thể xử lý đồng thời hàng chục khách hàng cùng lúc mà không bị kẹt luồng (Lỗi `ALREADY KNOWN`).
- **Smart Contract Anti-Overwrite:** Contract kiểm tra chặt chẽ `records[dataHash].timestamp == 0` để đảm bảo mốc thời gian của tài liệu cũ không thể bị ghi đè.
- **Smart Contract Access Control:** Contract định danh `admin` khi khởi tạo và kiểm tra chữ ký `require(recoveredSigner == admin)` để từ chối mọi yêu cầu chèn dữ liệu rác từ các ví lạ.

## 3. Luồng Hoạt Động Chi Tiết (Data Flow)

### Luồng 1: Niêm phong Tài liệu (Notarize)
**Mục tiêu:** Chốt mốc thời gian (Timestamp) cho một tài liệu mà không làm lộ nội dung tài liệu ra Internet.

1. Khách hàng chọn file (PDF, Doc) hoặc nhập văn bản trên Frontend.
2. Frontend sử dụng thuật toán **Keccak256** để tạo ra Mã băm (`Data Hash`) của file đó **ngay trên RAM của máy tính khách hàng**. (Bảo vệ bí mật doanh nghiệp).
3. Frontend gửi `Data Hash` cùng `x-api-key` lên Backend qua API `POST /api/v1/notarize`.
4. Backend kiểm tra Rate Limit và API Key. Nếu hợp lệ, Backend sẽ:
   - Dùng `Master Wallet` để tính toán phí Gas.
   - Gắn chữ ký điện tử (ECDSA) của hệ thống vào `Data Hash`.
   - Đóng gói thành Transaction và đẩy lên Blockchain Sepolia.
5. Blockchain xác nhận (Mining). Trả về mã biên lai (TxHash).
6. Backend trả mã TxHash về cho Frontend báo cáo thành công.

### Luồng 2: Tra cứu & Xác minh (Verify)
**Mục tiêu:** Chứng minh tài liệu chưa từng bị sửa đổi nội dung và tra cứu thời điểm ký.

*(Hệ thống hỗ trợ 2 cách kiểm tra độc lập)*

**Cách A: Khách hàng tự tải File lên để tra cứu (Cập nhật mới)**
1. Khách hàng ném file PDF cần kiểm tra vào Cột "Tra cứu Chứng nhận".
2. Frontend tự động băm file thành `Data Hash`.
3. Frontend gọi API `GET /api/v1/verify/:hash` truyền lên Backend.
4. Backend đọc dữ liệu tĩnh (View function) từ Smart Contract mà không tốn phí Gas.
5. Trả kết quả: Nếu có dữ liệu, hiển thị Thời gian (Timestamp) và Ví người ký. Nếu không, báo lỗi "Chưa từng lưu trữ" (Bị làm giả).

**Cách B: Tra cứu thủ công bằng Hash**
1. Khách hàng copy mã Hash cũ (từ Cột 1 hoặc từ Database của họ).
2. Dán vào ô "Data Hash" ở Cột 2.
3. Bấm Kiểm tra. (Các bước tiếp theo tương tự như Cách A).
