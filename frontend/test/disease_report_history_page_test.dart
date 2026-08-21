import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_management/core/api_client.dart';
import 'package:hospital_management/features/auth/auth_controller.dart';
import 'package:hospital_management/features/clinical/disease_report_history_page.dart';

void main() {
  testWidgets('默认只显示已上报记录，并可切换到未上报草稿', (tester) async {
    final api = _DiseaseReportApi();
    await _pumpPage(tester, api: api, role: 'DOCTOR');

    expect(find.text('流行性感冒'), findsOneWidget);
    expect(find.text('水痘'), findsNothing);
    expect(find.byTooltip('提交审核'), findsNothing);

    await tester.tap(find.text('未上报'));
    await tester.pumpAndSettle();

    expect(find.text('流行性感冒'), findsNothing);
    expect(find.text('水痘'), findsOneWidget);
    expect(find.byTooltip('提交审核'), findsOneWidget);
  });

  testWidgets('医师提交草稿后调用当前患者的上报接口', (tester) async {
    final api = _DiseaseReportApi();
    await _pumpPage(tester, api: api, role: 'DOCTOR');

    await tester.tap(find.text('未上报'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('提交审核'));
    await tester.pumpAndSettle();

    expect(
      api.postedPaths,
      contains('/api/v1/workstation/disease-reports/3/submit'),
    );
  });

  testWidgets('护士保留查阅与输出入口，但不能新增或提交上报', (tester) async {
    final api = _DiseaseReportApi();
    await _pumpPage(tester, api: api, role: 'NURSE');

    expect(find.byTooltip('新增疾病上报'), findsNothing);
    expect(find.byTooltip('导出 PDF'), findsOneWidget);
    expect(find.byTooltip('打印'), findsOneWidget);

    await tester.tap(find.text('未上报'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('提交审核'), findsNothing);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _DiseaseReportApi api,
  required String role,
}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: Scaffold(
          body: DiseaseReportHistoryPage(
            admissionId: 1,
            role: role,
            patientContext: const {
              'admission': {
                'patient_name': '赵患者',
                'gender': 'MALE',
                'birth_date': '1980-01-01',
                'inpatient_no': 'ZY001',
                'medical_record_no': 'MR001',
                'department_name': '神经内科',
                'bed_no': '2床',
              },
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _DiseaseReportApi extends ApiClient {
  final List<String> postedPaths = [];

  @override
  Future<List<Map<String, dynamic>>> getList(String path) async {
    if (path.endsWith('/disease-report-types')) {
      return const [
        {'type_code': 'INFECTIOUS', 'type_name': '传染病报告卡'},
        {'type_code': 'DEATH_CARD', 'type_name': '死亡医学证明上报卡'},
      ];
    }
    if (path.endsWith('/disease-reports')) {
      return const [
        {
          'disease_report_id': 1,
          'report_type': 'INFECTIOUS',
          'report_type_name': '传染病报告卡',
          'disease_name': '流行性感冒',
          'report_content': '患者出现发热、咳嗽症状。',
          'status': 'SUBMITTED',
          'reporter_name': '张医师',
          'created_at': '2026-08-18T09:10:00',
          'reported_at': '2026-08-18T10:00:00',
          'print_count': 0,
        },
        {
          'disease_report_id': 2,
          'report_type': 'DEATH_CARD',
          'report_type_name': '死亡医学证明上报卡',
          'disease_name': '死亡医学证明',
          'report_content': '已完成审核。',
          'status': 'APPROVED',
          'reporter_name': '张医师',
          'reviewer_name': '系统管理员',
          'created_at': '2026-08-16T09:10:00',
          'reported_at': '2026-08-16T10:00:00',
          'reviewed_at': '2026-08-17T10:00:00',
          'print_count': 1,
        },
        {
          'disease_report_id': 3,
          'report_type': 'INFECTIOUS',
          'report_type_name': '传染病报告卡',
          'disease_name': '水痘',
          'report_content': '草稿待补充。',
          'status': 'DRAFT',
          'reporter_name': '张医师',
          'created_at': '2026-08-20T09:10:00',
          'print_count': 0,
        },
      ];
    }
    throw StateError('未处理的列表请求：$path');
  }

  @override
  Future<void> postVoid(String path, Map<String, dynamic> data) async {
    postedPaths.add(path);
  }
}
