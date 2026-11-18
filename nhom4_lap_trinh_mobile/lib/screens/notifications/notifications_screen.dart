import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/notification_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/signing_request_service.dart';
import '../../utils/verify_navigation_helper.dart';

/// Màn hình Thông báo In-App (hiển thị kết quả ký số kèm mã Hash/TxHash hoặc thông báo gia hạn >24h).
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final uid = user?.uid ?? '';
    final service = SigningRequestService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông Báo'),
        actions: [
          if (uid.isNotEmpty)
            TextButton.icon(
              onPressed: () => service.markAllNotificationsRead(uid),
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Đọc tất cả'),
            ),
        ],
      ),
      body: uid.isEmpty
          ? const Center(child: Text('Vui lòng đăng nhập để xem thông báo.'))
          : StreamBuilder<List<AppNotificationModel>>(
              stream: service.streamNotifications(uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data ?? const <AppNotificationModel>[];
                if (items.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notifications_none,
                            size: 52,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 10),
                          Text('Chưa có thông báo nào.'),
                        ],
                      ),
                    ),
                  );
                }

                final fmt = DateFormat('dd/MM/yyyy HH:mm');
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final n = items[index];
                    final IconData icon;
                    final Color color;
                    switch (n.type) {
                      case AppNotificationType.signingCompleted:
                        icon = Icons.verified;
                        color = Colors.teal;
                        break;
                      case AppNotificationType.signingDelayed:
                        icon = Icons.schedule;
                        color = Colors.orange;
                        break;
                      case AppNotificationType.signingRejected:
                        icon = Icons.cancel_outlined;
                        color = Colors.redAccent;
                        break;
                      case AppNotificationType.general:
                        icon = Icons.notifications;
                        color = Colors.blueGrey;
                        break;
                    }

                    return Card(
                      elevation: n.isRead ? 0.5 : 2,
                      color: n.isRead
                          ? null
                          : color.withValues(alpha: 0.06),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          if (!n.isRead) {
                            service.markNotificationRead(uid, n.id);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(icon, color: color, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      n.title,
                                      style: TextStyle(
                                        fontWeight: n.isRead
                                            ? FontWeight.w600
                                            : FontWeight.bold,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                  ),
                                  if (!n.isRead)
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                n.body,
                                style: const TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                fmt.format(n.createdDateTime),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey,
                                ),
                              ),
                              if (n.documentHash != null &&
                                  n.documentHash!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Hash: ${n.documentHash}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                      if (n.txHash != null &&
                                          n.txHash!.isNotEmpty)
                                        Text(
                                          'TxHash: ${n.txHash}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontFamily: 'monospace',
                                            color: Colors.teal,
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          TextButton.icon(
                                            onPressed: () {
                                              Clipboard.setData(
                                                ClipboardData(
                                                  text: n.documentHash!,
                                                ),
                                              );
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Đã sao chép mã Hash.',
                                                  ),
                                                ),
                                              );
                                            },
                                            icon: const Icon(
                                              Icons.copy,
                                              size: 15,
                                            ),
                                            label: const Text('Sao chép mã'),
                                          ),
                                          if (n.type ==
                                              AppNotificationType
                                                  .signingCompleted)
                                            TextButton.icon(
                                              onPressed: () {
                                                if (!n.isRead) {
                                                  service.markNotificationRead(
                                                    uid,
                                                    n.id,
                                                  );
                                                }
                                                openVerifyByHash(
                                                  context,
                                                  n.documentHash!,
                                                );
                                              },
                                              icon: const Icon(
                                                Icons.verified,
                                                size: 15,
                                              ),
                                              label: const Text(
                                                'Kiểm tra ngay',
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
