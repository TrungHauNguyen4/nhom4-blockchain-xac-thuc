import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final ImagePicker _imagePicker = ImagePicker();
  bool _hasScanned = false;
  bool _isAnalyzingImage = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  // Quét mã QR từ Ảnh trong Thư viện thiết bị (Hỗ trợ máy ảo & ảnh nhận qua Zalo/Email)
  Future<void> _scanFromGallery() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tính năng phân tích ảnh QR từ thư viện hỗ trợ trên Android/iOS.'),
        ),
      );
      return;
    }

    try {
      setState(() => _isAnalyzingImage = true);
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (!mounted) return;
      if (pickedFile == null) {
        setState(() => _isAnalyzingImage = false);
        return;
      }

      final BarcodeCapture? capture = await controller.analyzeImage(pickedFile.path);
      if (!mounted) return;

      if (capture != null && capture.barcodes.isNotEmpty) {
        for (final barcode in capture.barcodes) {
          final code = barcode.rawValue;
          if (code != null && code.trim().isNotEmpty) {
            _hasScanned = true;
            Navigator.pop(context, code.trim());
            return;
          }
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('Không tìm thấy mã QR hợp lệ trong bức ảnh đã chọn!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('Lỗi khi đọc ảnh QR: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isAnalyzingImage = false);
      }
    }
  }

  // Nhập nhanh mã Hash nếu Camera máy ảo không quét được
  Future<void> _showManualInputDialog() async {
    final textController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nhập mã QR / Data Hash'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Dán chuỗi 0x... hoặc nội dung QR',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, textController.text.trim()),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      _hasScanned = true;
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quét QR Văn Bằng'),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'Chọn ảnh QR từ Thư viện',
            onPressed: _isAnalyzingImage ? null : _scanFromGallery,
          ),
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'Bật/Tắt đèn Flash',
            onPressed: () => controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            tooltip: 'Đổi Camera',
            onPressed: () => controller.switchCamera(),
          ),
        ],
      ),
      // Sử dụng OrientationBuilder để tự động co giãn khung quét khi xoay ngang/dọc
      body: OrientationBuilder(
        builder: (context, orientation) {
          final bool isPortrait = orientation == Orientation.portrait;
          final double scanBoxSize = isPortrait ? 250.0 : 180.0;

          return Stack(
            alignment: Alignment.center,
            children: [
              MobileScanner(
                controller: controller,
                onDetect: (capture) {
                  if (_hasScanned) return;
                  final List<Barcode> barcodes = capture.barcodes;
                  for (final barcode in barcodes) {
                    final code = barcode.rawValue;
                    if (code != null && code.trim().isNotEmpty) {
                      _hasScanned = true;
                      Navigator.pop(context, code.trim());
                      break;
                    }
                  }
                },
              ),

              // Khung ngắm quét QR Code
              Container(
                width: scanBoxSize,
                height: scanBoxSize,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.greenAccent, width: 3),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.greenAccent.withValues(alpha: 0.2),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),

              if (_isAnalyzingImage)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 12),
                        Text(
                          'Đang phân tích mã QR từ ảnh...',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),

              // Cụm nút điều khiển phía dưới (Chọn ảnh QR từ Thư viện & Nhập mã)
              Positioned(
                bottom: isPortrait ? 28 : 14,
                left: 16,
                right: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Hướng Camera vào mã QR hoặc chọn ảnh QR từ thư viện máy',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.image_search),
                          label: const Text('Chọn ảnh QR từ Thư viện'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black87,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          onPressed: _isAnalyzingImage ? null : _scanFromGallery,
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.keyboard, color: Colors.white),
                          label: const Text(
                            'Nhập mã thủ công',
                            style: TextStyle(color: Colors.white),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white70),
                            backgroundColor: Colors.black45,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          onPressed: _showManualInputDialog,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

