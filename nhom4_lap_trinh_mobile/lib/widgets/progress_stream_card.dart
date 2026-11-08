import 'package:flutter/material.dart';
import '../services/hash_service.dart';

/// Thẻ hiển thị tiến trình thời gian thực dùng chung cho toàn bộ ứng dụng:
/// - `ProgressStreamCard(...)` hoặc `ProgressStreamCard.verification(...)` -> Luồng Xác thực (TV1 & TV3)
/// - `ProgressStreamCard.notarization(...)` -> Luồng Cấp phát / Ký số (TV1 & TV2)
/// Tuân thủ chuẩn Chương 10 (`flutter_demo`): kiểm tra tường minh các trạng thái ConnectionState.
class ProgressStreamCard extends StatelessWidget {
  final Stream<VerificationProgress>? verificationStream;
  final Stream<NotarizationProgress>? notarizationStream;
  final ValueChanged<VerificationProgress>? onCompleted;
  final ValueChanged<VerificationProgress>? onViewVerificationDetail;
  final ValueChanged<NotarizationProgress>? onNotarizationCompleted;

  /// Constructor mặc định phục vụ trực tiếp `VerifyTab` (TV3)
  const ProgressStreamCard({
    super.key,
    required Stream<VerificationProgress> stream,
    this.onCompleted,
    ValueChanged<VerificationProgress>? onViewDetail,
  })  : verificationStream = stream,
        notarizationStream = null,
        onViewVerificationDetail = onViewDetail,
        onNotarizationCompleted = null;

  /// Constructor định danh cho luồng Thẩm định / Xác thực (TV1 & TV3)
  const ProgressStreamCard.verification({
    super.key,
    required Stream<VerificationProgress> stream,
    this.onCompleted,
    this.onViewVerificationDetail,
  })  : verificationStream = stream,
        notarizationStream = null,
        onNotarizationCompleted = null;

  /// Constructor định danh cho luồng Cấp phát / Ký số Blockchain (TV1 & TV2)
  const ProgressStreamCard.notarization({
    super.key,
    required Stream<NotarizationProgress> stream,
    this.onNotarizationCompleted,
  })  : notarizationStream = stream,
        verificationStream = null,
        onCompleted = null,
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
          return _buildLoadingCard('Đang bắt đầu kiểm tra văn bằng...');
        }

        if (snapshot.hasError) {
          return _buildErrorCard('Lỗi xử lý: ${snapshot.error}');
        }

        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data!;
        final bool isDone =
            snapshot.connectionState == ConnectionState.done || data.progress >= 1.0;
        final bool isSuccess = data.step == VerificationStep.verifiedValid;

        if (isDone && onCompleted != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onCompleted!(data);
          });
        }

        return _buildProgressBody(
          context: context,
          title: isDone ? 'Kết quả kiểm tra:' : 'Đang kiểm tra văn bằng:',
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
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Xem Chi Tiết Văn Bằng'),
                    ),
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
          return _buildLoadingCard('Đang chuẩn bị cấp phát văn bằng...');
        }

        if (snapshot.hasError) {
          return _buildErrorCard('Lỗi xử lý: ${snapshot.error}');
        }

        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data!;
        final bool isDone =
            snapshot.connectionState == ConnectionState.done || data.progress >= 1.0;
        final bool isSuccess = data.step == NotarizationStep.completed;

        if (isDone && isSuccess && onNotarizationCompleted != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onNotarizationCompleted!(data);
          });
        }

        return _buildProgressBody(
          context: context,
          title: 'Tiến trình cấp phát văn bằng:',
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
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Xem Mã QR & Giấy Chứng Nhận'),
                    ),
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
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Card(
        color: isDone
            ? (isSuccess
                ? Colors.green.withValues(alpha: 0.08)
                : Colors.red.withValues(alpha: 0.08))
            : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isDone
                ? (isSuccess
                    ? Colors.green.withValues(alpha: 0.5)
                    : Colors.red.withValues(alpha: 0.5))
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 340),
            curve: Curves.easeOutCubic,
            builder: (context, animatedProgress, _) {
              return Column(
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${(animatedProgress * 100).round()}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: animatedProgress,
                    backgroundColor:
                        Theme.of(context).brightness == Brightness.dark
                            ? Colors.white12
                            : Colors.grey.shade300,
                    color: isDone
                        ? (isSuccess ? Colors.green : Colors.red)
                        : Theme.of(context).colorScheme.primary,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: !isDone
                            ? const SizedBox(
                                key: ValueKey('spinner'),
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                isSuccess ? Icons.check_circle : Icons.error,
                                key: ValueKey('done_$isSuccess'),
                                color: isSuccess ? Colors.green : Colors.red,
                                size: 20,
                              ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              layoutBuilder:
                                  (currentChild, previousChildren) => Stack(
                                alignment: Alignment.centerLeft,
                                children: [
                                  ...previousChildren,
                                  ?currentChild,
                                ],
                              ),
                              child: Text(
                                statusMessage,
                                key: ValueKey<String>(statusMessage),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isDone
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isDone
                                      ? (Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? (isSuccess
                                              ? Colors.greenAccent
                                              : Colors.redAccent)
                                          : (isSuccess
                                              ? Colors.green.shade800
                                              : Colors.red.shade800))
                                      : null,
                                ),
                              ),
                            ),
                            if (errorMessage != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Chi tiết: $errorMessage',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.redAccent,
                                ),
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
                      'Mã văn bằng: $hash',
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
                      'Mã giao dịch: $txHash${blockNumber != null ? ' (Hồ sơ #$blockNumber)' : ''}',
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
              );
            },
          ),
        ),
      ),
    );
  }
}
