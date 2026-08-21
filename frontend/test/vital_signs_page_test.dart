import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_management/core/api_client.dart';
import 'package:hospital_management/features/auth/auth_controller.dart';
import 'package:hospital_management/features/clinical/clinical_workstation.dart';
import 'package:hospital_management/features/clinical/vital_signs_page.dart';

void main() {
  testWidgets('体征页按日期请求，支持单位、显示列和血压趋势切换',
      (tester) async {
    final api = _VitalSignsApi();
    await _pumpVitalSigns(tester, api);

    expect(api.temperatureRequests, hasLength(1));
    expect(api.temperatureRequests.single, contains('from='));
    expect(find.text('36.6 ℃'), findsOneWidget);
    expect(find.text('体温趋势（℃）'), findsOneWidget);

    await tester.tap(find.byTooltip('前一天'));
    await tester.pumpAndSettle();
    expect(api.temperatureRequests, hasLength(2));
    expect(api.temperatureRequests.last, contains('from='));

    await tester.tap(find.byTooltip('后一天'));
    await tester.pumpAndSettle();
    expect(api.temperatureRequests, hasLength(3));

    await tester.tap(find.text('单位'));
    await tester.pumpAndSettle();
    expect(find.text('36.6'), findsOneWidget);

    await tester.tap(find.text('列显示'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('身高'));
    await tester.tap(find.text('体重'));
    await tester.tap(find.widgetWithText(FilledButton, '应用'));
    await tester.pumpAndSettle();
    expect(find.text('170'), findsOneWidget);
    expect(find.text('65'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '血压').last);
    await tester.pumpAndSettle();
    expect(find.text('血压趋势（mmHg）'), findsOneWidget);
    expect(find.text('收缩压'), findsOneWidget);
    expect(find.text('舒张压'), findsOneWidget);
  });

  testWidgets('无体征记录时显示空态，右侧护理打开抽屉并保留未开放入口',
      (tester) async {
    final api = _VitalSignsApi(emptyRecords: true);
    await _pumpVitalSigns(tester, api);
    expect(find.text('该日期暂无体征记录。'), findsOneWidget);
    expect(find.text('当日暂无该指标的趋势数据。'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: Scaffold(body: ClinicalWorkstation(role: 'DOCTOR')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('护理'));
    await tester.pumpAndSettle();
    expect(find.text('体征').hitTestable(), findsOneWidget);
    expect(find.byTooltip('关闭护理抽屉').hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('nursing-drawer-nursing_records')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('nursing-drawer-nursing_assessment')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('nursing-drawer-other_nursing')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('nursing-drawer-critical_care')),
        findsOneWidget);

    await tester.tap(
        find.byKey(const ValueKey('nursing-drawer-nursing_assessment')));
    await tester.pumpAndSettle();
    expect(find.text('该功能入口已预留，暂未开放业务页面。'), findsOneWidget);
    expect(api.temperatureRequests, hasLength(2));

    await tester.tap(find.byTooltip('关闭护理抽屉'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('关闭护理抽屉').hitTestable(), findsNothing);
  });
}

Future<void> _pumpVitalSigns(WidgetTester tester, _VitalSignsApi api) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: const MaterialApp(
        home: Scaffold(
          body: VitalSignsPage(
            admissionId: 1,
            role: 'DOCTOR',
            patientHeightCm: 170,
            patientWeightKg: 65,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _VitalSignsApi extends ApiClient {
  _VitalSignsApi({this.emptyRecords = false});

  final bool emptyRecords;
  final List<String> temperatureRequests = [];

  @override
  Future<List<Map<String, dynamic>>> getList(String path) async {
    if (path.contains('/temperature-chart')) {
      temperatureRequests.add(path);
      if (emptyRecords) {
        return [];
      }
      return [
        {
          'measured_at': '2026-08-20T08:00:00',
          'temperature': 36.6,
          'pulse': 78,
          'heart_rate': 80,
          'respiratory_rate': 18,
          'systolic_bp': 128,
          'diastolic_bp': 82,
          'spo2': 98,
          'pain_score': 2,
          'analgesic_pain_score': 1,
          'breakthrough_pain_score': 0,
          'intake_ml': 500,
          'output_ml': 360,
        },
      ];
    }
    if (path == '/api/v1/workstation/admissions') {
      return const [
        {
          'admission_id': 1,
          'patient_name': '赵患者',
          'inpatient_no': 'ZY001',
          'bed_no': '2床',
        },
      ];
    }
    return [];
  }

  @override
  Future<Map<String, dynamic>> getObject(String path) async {
    if (path.endsWith('/context')) {
      return {
        'admission': {
          'patient_name': '赵患者',
          'gender': 'MALE',
          'birth_date': '1990-01-01',
          'inpatient_no': 'ZY001',
          'medical_record_no': 'MR001',
          'bed_no': '2床',
          'stay_days': 1,
          'nursing_level': 'LEVEL_2',
          'department_name': '内科',
          'doctor_name': '李医师',
          'height_cm': 170,
          'weight_kg': 65,
        },
        'allergies': [],
        'depositBalance': 0,
        'availableBalance': 0,
      };
    }
    if (path.endsWith('/case-home')) {
      return {
        'home': <String, dynamic>{},
        'diagnoses': <Map<String, dynamic>>[],
        'facilityName': '示例医院',
        'facilityCode': 'H001',
      };
    }
    throw StateError('未处理的对象请求：$path');
  }
}
