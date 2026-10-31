# KẾ HOẠCH NÂNG CẤP LÊN MÔI TRƯỜNG PRODUCTION (ROADMAP)

Dự án hiện tại đã vượt qua giai đoạn MVP (Thử nghiệm) và vừa hoàn tất đợt nâng cấp bảo mật toàn diện **Security Patch V2**. 
Hệ thống hiện tại hoàn toàn có thể chạy thực tế cho một quy mô doanh nghiệp vừa và nhỏ (SME). Tuy nhiên, để đáp ứng quy mô Enterprise (Hàng triệu giao dịch), đây là lộ trình tiếp theo.

## 1. Những Nền Tảng Đã Hoàn Thiện (Thành Tựu)

Sau bản cập nhật V2, chúng ta đã giải quyết dứt điểm các bài toán hóc búa nhất của một hệ thống Blockchain BaaS:
- ✅ **Chống Spam (DDoS):** Tích hợp Rate Limit, bảo vệ số dư quỹ Gas của nền tảng.
- ✅ **Kiểm soát Truy cập (Access Control):** Khóa cổng API bằng API Key và định danh Admin cấp Smart Contract. Ngăn chặn triệt để hành vi chèn dữ liệu rác.
- ✅ **Bất biến Dữ liệu (Anti-Overwrite):** Smart Contract từ chối mọi yêu cầu ghi đè mốc thời gian của một Data Hash đã tồn tại.
- ✅ **Nghẽn cổ chai (Nonce Collision):** Ứng dụng Ethers NonceManager, xếp hàng đồng thời hàng chục yêu cầu trong cùng 1 giây mà không bị rơi rớt giao dịch.
- ✅ **Môi trường Hiện đại:** Nâng cấp cấu trúc lên ESM Module (`import`), tương thích Hardhat v3 và Solidity 0.8.24 (Cancun EVM).

## 2. Lộ Trình Nâng Cấp Enterprise (Giai đoạn tiếp theo)

Để đưa nền tảng này thành một Dịch vụ SaaS thương mại hóa (Bán API cho các phần mềm khác nghiệm thu), chúng ta cần thực hiện các nâng cấp sau:

### Tầng 1: Hạ tầng & Quản trị Bí mật (DevSecOps)
> [!IMPORTANT]
> **Vấn đề:** Hiện tại `MASTER_PRIVATE_KEY` đang nằm trong file `.env` trên ổ cứng. Nếu máy chủ bị Hack, tiền ETH trong ví sẽ bốc hơi.
- **Giải pháp:** Xóa file `.env`. Tích hợp **AWS KMS (Key Management Service)** hoặc **HashiCorp Vault**. Các dịch vụ này sẽ giữ Private Key trong một hộp đen mã hóa, khi cần ký giao dịch, Node.js sẽ gửi dữ liệu vào hộp đen, hộp đen tự ký và ném chữ ký ra ngoài, không bao giờ lộ Private Key cho Node.js biết.

### Tầng 2: Cấp phép & Quản trị Đối tác (API Gateway)
> [!NOTE]
> **Vấn đề:** Hiện tại chúng ta chỉ có 1 `API_KEY` cứng dùng chung. Không thể biết đối tác nào đang gọi và gọi bao nhiêu lần để thu tiền.
- **Giải pháp:** 
  - Thay thế Middleware kiểm tra tĩnh bằng một hệ thống Database (PostgreSQL / MongoDB).
  - Viết chức năng cấp phát API Key cho từng đối tác (Dashboard).
  - Triển khai **API Gateway** (như Kong hoặc AWS API Gateway) để giới hạn tốc độ và tính tiền (Billing) tự động theo từng lượng Request thực tế (Ví dụ: 1000 VNĐ / 1 API Call).

### Tầng 3: Tối ưu Trải nghiệm (Database Indexing)
> [!TIP]
> **Vấn đề:** Mọi truy vấn Tra cứu (Verify) hiện tại đều đâm thẳng vào Blockchain. Nó không tốn phí nhưng rất chậm và phụ thuộc vào tốc độ mạng lưới. Khách hàng cũng không thể xem lại "Lịch sử các file đã ký" vì Blockchain không có chức năng List.
- **Giải pháp:** 
  - Khởi tạo Database truyền thống (PostgreSQL).
  - Bổ sung **Blockchain Event Listener**: Lắng nghe sự kiện `RecordSigned` từ Smart Contract. Khi bắt được tín hiệu, lưu bộ ba: `[Mã Hash] + [Mã TxHash] + [Thời Gian]` vào PostgreSQL.
  - Khi cần Tra cứu, Frontend gọi API hỏi PostgreSQL. Tốc độ sẽ nhanh gấp 100 lần, giao diện có thể hiển thị bảng Lịch sử, và có luôn đường link màu xanh (TxHash) dẫn ra Etherscan.

### Tầng 4: Xử lý Tải trọng lớn (Load Balancing & Message Queue)
> [!WARNING]
> **Vấn đề:** NonceManager hiện tại chỉ chạy tốt trên 1 máy chủ Node.js đơn lẻ. Nếu chạy 3 máy chủ (Load Balancer) để gánh 10.000 khách hàng, 3 máy chủ sẽ tự giẫm chân lên Nonce của nhau.
- **Giải pháp:**
  - Hủy bỏ NonceManager nội bộ. 
  - Dựng hệ thống **Message Queue (Redis / RabbitMQ)** và **Worker**. 
  - 10.000 yêu cầu đâm vào sẽ được đẩy hết vào Kho (Queue). 
  - Sẽ chỉ có duy nhất 1 "Thợ xây" (Worker) lần lượt lôi từng yêu cầu ra, tự tăng Nonce, ký tên và vứt lên Blockchain. Mô hình này đảm bảo tốc độ cực cao, không kẹt xe, và Scale vô hạn.
