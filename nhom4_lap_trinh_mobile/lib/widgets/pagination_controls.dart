import 'package:flutter/material.dart';

/// Thanh phân trang dùng chung cho các danh sách dữ liệu (mặc định 7 dòng / trang).
class PaginationControls extends StatelessWidget {
  static const int defaultPageSize = 7;

  final int currentPage;
  final int totalItems;
  final int pageSize;
  final ValueChanged<int> onPageChanged;

  const PaginationControls({
    super.key,
    required this.currentPage,
    required this.totalItems,
    this.pageSize = defaultPageSize,
    required this.onPageChanged,
  });

  static int computeTotalPages(int totalItems, {int pageSize = defaultPageSize}) {
    if (totalItems <= 0 || pageSize <= 0) return 1;
    return (totalItems / pageSize).ceil();
  }

  static List<T> slicePage<T>(
    List<T> items, {
    required int currentPage,
    int pageSize = defaultPageSize,
  }) {
    if (items.isEmpty) return const [];
    final totalPages = computeTotalPages(items.length, pageSize: pageSize);
    final safePage = currentPage.clamp(1, totalPages);
    final start = (safePage - 1) * pageSize;
    final end = (start + pageSize).clamp(0, items.length);
    return items.sublist(start, end);
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = computeTotalPages(totalItems, pageSize: pageSize);
    if (totalItems <= pageSize) return const SizedBox.shrink();

    final safePage = currentPage.clamp(1, totalPages);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: safePage > 1 ? () => onPageChanged(safePage - 1) : null,
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('Trước'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Trang $safePage / $totalPages',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          OutlinedButton.icon(
            onPressed:
                safePage < totalPages ? () => onPageChanged(safePage + 1) : null,
            icon: const Icon(Icons.chevron_right, size: 18),
            label: const Text('Sau'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
          ),
        ],
      ),
    );
  }
}
