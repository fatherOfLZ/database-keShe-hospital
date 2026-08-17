import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_management/main.dart';

void main() {
  testWidgets('应用启动后显示登录页', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HospitalApp()));
    await tester.pumpAndSettle();

    expect(find.text('住院信息管理系统'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });
}
