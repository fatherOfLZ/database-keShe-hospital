import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_management/core/api_client.dart';
import 'package:hospital_management/features/auth/auth_controller.dart';
import 'package:hospital_management/features/clinical/course_record_page.dart';
import 'package:hospital_management/features/clinical/exam_report_panel.dart';
import 'package:hospital_management/features/clinical/report_citation.dart';

void main() {
  testWidgets('检查面板切换门诊数据并引用所选报告', (tester) async {
    final api = _ExamReportApi();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 820,
              child: ExamReportPanel(admissionId: 1, role: 'DOCTOR'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('住院头颅CT平扫'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('exam-report-11')));
    await tester.pumpAndSettle();
    expect(find.textContaining('双侧额叶见低密度影'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '引用'));
    await tester.pump();
    expect(
      container.read(pendingReportCitationProvider(1)),
      contains('住院头颅CT平扫'),
    );

    await tester.tap(find.byKey(const ValueKey('exam-source-outpatient')));
    await tester.pumpAndSettle();
    expect(api.outpatientVisitRequested, isTrue);
    expect(find.text('门诊头颅CT平扫'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('exam-report-21')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('诊断结果'));
    await tester.pumpAndSettle();
    expect(find.textContaining('慢性缺血性改变'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('非医师可以查看报告但不能引用', (tester) async {
    final api = _ExamReportApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 820,
              child: ExamReportPanel(admissionId: 1, role: 'NURSE'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('exam-report-11')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('诊断结果'));
    await tester.pumpAndSettle();

    final quoteButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '引用'),
    );
    expect(quoteButton.onPressed, isNull);
    expect(find.textContaining('腔隙性脑梗死'), findsOneWidget);
  });

  testWidgets('待引用报告会预填下一条新增病程并在取消后清空', (tester) async {
    final api = _ExamReportApi();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    container.read(pendingReportCitationProvider(1).notifier).state =
        '报告名称：头颅CT平扫\n诊断结果：腔隙性脑梗死。';

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 820,
              child: CourseRecordPage(admissionId: 1, role: 'DOCTOR'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增').first);
    await tester.pumpAndSettle();

    final contentField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '病程内容',
    );
    expect(
      tester.widget<TextField>(contentField).controller!.text,
      contains('报告名称：头颅CT平扫'),
    );

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(container.read(pendingReportCitationProvider(1)), isNull);
  });
}

class _ExamReportApi extends ApiClient {
  bool outpatientVisitRequested = false;

  @override
  Future<List<Map<String, dynamic>>> getList(String path) async {
    if (path.endsWith('/outpatient-visits')) {
      outpatientVisitRequested = true;
      return [
        {
          'outpatient_visit_id': 9,
          'visited_at': '2026-08-10T09:00:00',
          'department_name': '神经内科',
        },
      ];
    }
    if (path.contains('/outpatient-visits/9/exam-reports')) {
      return [
        {
          'report_id': 21,
          'report_name': '门诊头颅CT平扫',
          'reported_at': '2026-08-10T10:00:00',
          'finding_text': '白质区散在低密度灶。',
          'conclusion': '慢性缺血性改变。',
          'order_no': 'OP001',
          'item_name': '头颅CT',
          'department_name': '影像科',
          'reporter_name': '张医师',
        },
      ];
    }
    if (path.endsWith('/exam-reports')) {
      return [
        {
          'report_id': 11,
          'report_name': '住院头颅CT平扫',
          'reported_at': '2026-08-20T10:30:00',
          'finding_text': '双侧额叶见低密度影。',
          'conclusion': '腔隙性脑梗死。',
          'order_no': 'EO001',
          'item_name': '头颅CT',
          'department_name': '影像科',
          'reporter_name': '张医师',
        },
      ];
    }
    if (path.contains('/documents')) {
      return const [];
    }
    if (path.contains('/document-templates')) {
      return [
        {
          'template_id': 1,
          'document_code': 'DAILY_COURSE',
          'template_name': '日常病程记录',
        },
      ];
    }
    if (path.endsWith('/exam-reports/11/results') ||
        path.endsWith('/outpatient-exam-reports/21/results')) {
      return [
        {
          'result_id': 1,
          'item_name': '头颅CT平扫',
          'qualitative_value': '已完成',
          'abnormal_flag': '',
        },
      ];
    }
    return const [];
  }
}
