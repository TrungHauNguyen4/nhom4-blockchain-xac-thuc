import 'package:flutter/material.dart';
import '../services/hash_service.dart';

/// Thẻ hiển thị tiến trình thời gian thực dùng chung cho cả 2 luồng:
/// - Luồng Xác thực văn bằng (`ProgressStreamCard.verification`) -> dành cho TV3
/// - Luồng Cấp phát / Ký số văn bằng (`ProgressStreamCard.notarization`) -> dành cho TV2
/// Tuân thủ chuẩn Chương 10 (`flutter_demo`): kiểm tra tường minh ConnectionState.
class ProgressStreamCard extends StatelessWidget {
  final Stream<VerificationProgress>? verificationStream;
  final Stream<NotarizationProgress>? notarizationStream;
  final void Function(VerificationProgress result)? onViewVerificationDetail;
  final void Function(NotarizationProgress result)? onNotarizationCompleted;

  const ProgressStreamCard.verification({
    super.key,
    required Stream<VerificationProgress> stream,
    this.onViewVerificationDetail,
  })  : verificationStream = stream,
        notarizationStream = null,
        onNotarizationCompleted = null;

  const ProgressStreamCard.notarization({
    super.key,
    required Stream<NotarizationProgress> stream,
    this.onNotarizationCompleted,
  })  : notarizationStream = stream,
        verificationStream = null,
        onViewVerificationDetail = null;

  @override
  Widget build(BuildContext context) {
    if (verificationStream != null) {
      return _buildVerificationBuilder(context, verificationStream!);
    }
    if (notarizationStream != null) {
      return _buildNotarizationBuilder(context, notarizationStream!);
    }
    return const SizedBox.shrink();
  }

  // [READ STREAM] Luồng thẩm định / đối soát văn bằng
  Widget _buildVerificationBuilder(
    BuildContext context,
    Stream<VerificationProgress> stream,
  ) {
    return StreamBuilder<VerificationProgress>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return _buildLoadingCard('Đang khởi tạo luồng thẩm định...');
        }

        if (snapshot.hasError) {
          return _buildErrorCard('Lỗi luồng xử lý: ${snapshot.error}');
        }

        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data!;
        final bool isDone = snapshot.connectionState == ConnectionState.done || data.progress >= 1.0;
        final bool isSuccess = data.step == VerificationStep.verifiedValid;

        return _buildProgressBody(
          context: context,
          title: 'Tiến trình thẩm định:',
          progress: data.progress,
          statusMessage: data.statusMessage,
          errorMessage: data.errorMessage,
          hash: data.hash,
          isDone: isDone,
          isSuccess: isSuccess,
          actionButton: isDone && onViewVerificationDetail != null
              ? SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Xem Chi Tiết Chứng Nhận'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSuccess ? Colors.green : Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => onViewVerificationDetail!(data),
                  ),
                )
              : null,
        );
      },
    );
  }

  // [READ STREAM] Luồng ký số / niêm phong văn bằng lên Sepolia
  Widget _buildNotarizationBuilder(
    BuildContext context,
    Stream<NotarizationProgress> stream,
  ) {
    return StreamBuilder<NotarizationProgress>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return _buildLoadingCard('Đang chuẩn bị ký số văn bằng...');
        }

        if (snapshot.hasError) {
          return _buildErrorCard('Lỗi luồng ký số: ${snapshot.error}');
        }

        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data!;
        final bool isDone = snapshot.connectionState == ConnectionState.done || data.progress >= 1.0;
        final bool isSuccess = data.step == NotarizationStep.completed;

        return _buildProgressBody(
          context: context,
          title: 'Tiến trình ký số Blockchain:',
          progress: data.progress,
          statusMessage: data.statusMessage,
          errorMessage: data.errorMessage,
          hash: data.hash,
          txHash: data.txHash,
          blockNumber: data.blockNumber,
          isDone: isDone,
          isSuccess: isSuccess,
          actionButton: isDone && isSuccess && onNotarizationCompleted != null
              ? SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('Xuất Mã QR & Biên Lai Blockchain'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => onNotarizationCompleted!(data),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildLoadingCard(String message) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(message)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String message) {
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
                message,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBody({
    required BuildContext context,
    required String title,
    required double progress,
    required String statusMessage,
    required bool isDone,
    required bool isSuccess,
    String? errorMessage,
    String? hash,
    String? txHash,
    int? blockNumber,
    Widget? actionButton,
  }) {
    return Card(
      color: isDone
          ? (isSuccess
              ? Colors.green.withValues(alpha: 0.08)
              : Colors.red.withValues(alpha: 0.08))
          : null,
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
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.shade300,
              color: isDone
                  ? (isSuccess ? Colors.green : Colors.red)
                  : Theme.of(context).colorScheme.primary,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (!isDone)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    isSuccess ? Icons.check_circle : Icons.error,
                    color: isSuccess ? Colors.green : Colors.red,
                    size: 20,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusMessage,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
                          color: isDone
                              ? (isSuccess ? Colors.green.shade800 : Colors.red.shade800)
                              : null,
                        ),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Chi tiết: $errorMessage',
                          style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (hash != null) ...[
              const SizedBox(height: 10),
              Text(
                'Mã Hash: $hash',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.grey,
                ),
              ),
            ],
            if (txHash != null) ...[
              const SizedBox(height: 4),
              Text(
                'TxHash: $txHash${blockNumber != null ? ' (Block #$blockNumber)' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.grey,
                ),
              ),
            ],
            if (actionButton != null) ...[
              const SizedBox(height: 16),
              actionButton,
            ],
          ],
        ),
      ),
    );
  }
}
