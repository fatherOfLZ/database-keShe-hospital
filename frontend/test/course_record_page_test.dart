import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_management/core/api_client.dart';
import 'package:hospital_management/features/auth/auth_controller.dart';
import 'package:hospital_management/features/clinical/course_record_page.dart';

void main() {
  testWidgets('作废病程记录后关闭确认框并刷新列表', (tester) async {
    final api = _CourseRecordApi();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: Scaffold(
            body: CourseRecordPage(admissionId: 1, role: 'DOCTOR'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '重复记录');
    await tester.tap(find.widgetWithText(FilledButton, '确认作废'));
    await tester.pumpAndSettle();

    expect(api.voided, isTrue);
    expect(find.text('文书已作废'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _CourseRecordApi extends ApiClient {
  bool voided = false;

  @override
  Future<List<Map<String, dynamic>>> getList(String path) async {
    if (path.contains('/documents')) {
      return [
        {
          'record_id': 10,
          'document_code': 'DAILY_COURSE',
          'template_name': '日常病程记录',
          'title': '日常病程记录',
          'content': '病情平稳。',
          'recorded_at': '2026-08-20T10:00:00',
          'author_name': '张医师',
          'status': voided ? 'VOID' : 'DRAFT',
          'version_no': 1,
        },
      ];
    }
    return [
      {
        'template_id': 1,
        'document_code': 'DAILY_COURSE',
        'template_name': '日常病程记录',
      },
    ];
  }

  @override
  Future<void> postVoid(String path, Map<String, dynamic> data) async {
    expect(path, '/api/v1/workstation/documents/10/void');
    expect(data, {'reason': '重复记录'});
    voided = true;
  }
}
