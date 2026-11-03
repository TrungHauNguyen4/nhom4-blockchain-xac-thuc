import 'package:flutter/material.dart';
import '../services/hash_service.dart';

class ProgressStreamCard extends StatelessWidget {
  final Stream<VerificationProgress> stream;
  final ValueChanged<VerificationProgress>? onCompleted;
  final ValueChanged<VerificationProgress>? onViewDetail;

  const ProgressStreamCard({
    super.key,
    required this.stream,
    this.onCompleted,
    this.onViewDetail,
  });

  @override
  Widget build(BuildContext context) {
    // Sử dụng StreamBuilder bắt tường minh các trạng thái ConnectionState (Chuẩn Chương 10 flutter_demo)
    return StreamBuilder<VerificationProgress>(
      stream: stream,
      builder: (context, snapshot) {
        // 1. Trạng thái đang khởi tạo luồng (ConnectionState.waiting)
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  SizedBox(width: 12),
                  Text('Đang khởi tạo luồng băm & đối soát...'),
                ],
              ),
            ),
          );
        }

        // 2. Trạng thái có lỗi bất ngờ trong Stream
        if (snapshot.hasError) {
          return Card(
            color: Colors.red.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Lỗi luồng xử lý: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        // 3. Trạng thái đang chạy (ConnectionState.active) hoặc hoàn tất (ConnectionState.done)
        final data = snapshot.data!;
        final bool isDone =
            snapshot.connectionState == ConnectionState.done || data.progress >= 1.0;
        final bool isValid = data.step == VerificationStep.verifiedValid;

        // Kích hoạt callback khi luồng vừa hoàn tất
        if (isDone && onCompleted != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onCompleted!(data);
          });
        }

        return Card(
          color: isDone
              ? (isValid
                  ? Colors.green.withValues(alpha: 0.08)
                  : Colors.red.withValues(alpha: 0.08))
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDone
                  ? (isValid ? Colors.green.withValues(alpha: 0.5) : Colors.red.withValues(alpha: 0.5))
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          isDone ? 'Kết quả thẩm định Realtime:' : 'Tiến trình thẩm định Realtime:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${(data.progress * 100).toInt()}%',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: data.progress,
                  backgroundColor: Colors.grey.shade300,
                  color: isDone
                      ? (isValid ? Colors.green : Colors.red)
                      : Theme.of(context).colorScheme.primary,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isDone)
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      Icon(
                        isValid ? Icons.check_circle : Icons.error,
                        color: isValid ? Colors.green : Colors.red,
                        size: 22,
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.statusMessage,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
                              color: isDone
                                  ? (isValid ? Colors.green.shade700 : Colors.red.shade700)
                                  : null,
                            ),
                          ),
                          if (data.errorMessage != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Chi tiết: ${data.errorMessage}',
                              style: const TextStyle(fontSize: 11.5, color: Colors.redAccent),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (data.hash != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Mã Hash (Keccak-256): ${data.hash}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
                if (isDone && onViewDetail != null) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Xem Chi Tiết Chứng Nhận & Mã QR'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isValid ? Colors.green : Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => onViewDetail!(data),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

