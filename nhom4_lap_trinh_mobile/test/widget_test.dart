import 'package:flutter_test/flutter_test.dart';
import 'package:nhom4_lap_trinh_mobile/main.dart';

void main() {
  testWidgets('App starts test', (WidgetTester tester) async {
    await tester.pumpWidget(const CertificateVerifierApp());
  });
}
