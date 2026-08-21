import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_management/core/api_client.dart';
import 'package:hospital_management/features/auth/auth_controller.dart';
import 'package:hospital_management/features/clinical/clinical_workstation.dart';

void main() {
  testWidgets('左侧住院医嘱使用动态患者信息并切换长期和临时医嘱',
      (tester) async {
    final api = _OrderPanelApi();
    await _pumpWorkstation(tester, api: api, role: 'DOCTOR');

    await tester.tap(find.text('住院医嘱'));
    await tester.pumpAndSettle();

    expect(_richTextContaining('患者编号: PT001'), findsOneWidget);
    expect(_richTextContaining('身高/体重: 170cm / 65kg'), findsOneWidget);
    expect(_richTextContaining('过敏史: 青霉素'), findsOneWidget);
    expect(api.orderRequests.last, contains('orderClass=LONG_TERM'));
    expect(find.text('阿莫西林胶囊'), findsOneWidget);
    expect(find.text('静脉输液'), findsNothing);

    await tester.tap(find.text('临时医嘱单'));
    await tester.pumpAndSettle();

    expect(api.orderRequests.last, contains('orderClass=TEMPORARY'));
    expect(find.text('阿莫西林胶囊'), findsNothing);
    expect(find.text('静脉输液'), findsOneWidget);

    final keywordField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == '医嘱内容',
    );
    await tester.enterText(keywordField, '输液');
    await tester.pump();
    expect(find.text('静脉输液'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('住院医嘱-仅在执行')));
    await tester.pumpAndSettle();
    expect(api.orderRequests.last, contains('status=OPEN'));

    final disabledEntry = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '中药处方'),
    );
    expect(disabledEntry.onPressed, isNull);
  });

  testWidgets('右侧医嘱打开全宽面板，且与检验面板互斥', (tester) async {
    final api = _OrderPanelApi();
    await _pumpWorkstation(tester, api: api, role: 'DOCTOR');

    expect(find.byTooltip('关闭医嘱面板').hitTestable(), findsNothing);

    await tester.tap(find.text('医嘱'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('关闭医嘱面板').hitTestable(), findsOneWidget);
    expect(find.text('阿莫西林胶囊'), findsOneWidget);
    expect(find.byTooltip('新增医嘱'), findsOneWidget);
    expect(find.byTooltip('停止医嘱'), findsOneWidget);
    expect(find.byTooltip('取消医嘱'), findsOneWidget);
    expect(find.byTooltip('执行医嘱'), findsNothing);

    await tester.tap(find.text('检验'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('关闭检验面板').hitTestable(), findsOneWidget);
    expect(find.byTooltip('关闭医嘱面板').hitTestable(), findsNothing);

    await tester.tap(find.text('医嘱'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭医嘱面板'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('关闭医嘱面板').hitTestable(), findsNothing);
    expect(find.text('病案首页').hitTestable(), findsOneWidget);
  });

  testWidgets('医嘱面板筛选会请求类别和状态，并随患者切换刷新',
      (tester) async {
    final api = _OrderPanelApi();
    await _pumpWorkstation(tester, api: api, role: 'DOCTOR');
    await tester.tap(find.text('医嘱'));
    await tester.pumpAndSettle();

    final keywordField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == '医嘱内容',
    );
    await tester.enterText(keywordField, '输液');
    await tester.pump();
    expect(find.text('阿莫西林胶囊'), findsNothing);
    expect(find.text('静脉输液'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('医嘱类别-')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('长期医嘱').last);
    await tester.pumpAndSettle();
    expect(api.orderRequests.last, contains('orderClass=LONG_TERM'));

    await tester.tap(find.byKey(const ValueKey('医嘱状态-')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已停止').last);
    await tester.pumpAndSettle();
    expect(api.orderRequests.last, contains('status=STOPPED'));

    await tester.tap(find.byTooltip('清空筛选条件'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(keywordField).controller!.text, isEmpty);
    expect(api.orderRequests.last, isNot(contains('?')));

    await tester.tap(find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<int> &&
          widget.decoration.labelText == '当前患者',
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('王患者  |  ZY002  |  3床'));
    await tester.pumpAndSettle();

    expect(find.text('替代患者医嘱'), findsOneWidget);
    expect(api.orderRequests.last, contains('/admissions/2/care-orders'));
  });

  testWidgets('护士只能执行医嘱，执行后会刷新面板数据', (tester) async {
    final api = _OrderPanelApi();
    await _pumpWorkstation(tester, api: api, role: 'NURSE');
    await tester.tap(find.text('医嘱'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('新增医嘱'), findsNothing);
    expect(find.byTooltip('停止医嘱'), findsNothing);
    expect(find.byTooltip('取消医嘱'), findsNothing);
    final executeAction = find.byTooltip('执行医嘱');
    expect(executeAction, findsOneWidget);
    await tester.ensureVisible(executeAction);
    await tester.pumpAndSettle();

    await tester.tap(executeAction);
    await tester.pumpAndSettle();

    expect(api.postedPaths,
        contains('/api/v1/workstation/care-orders/11/execute'));
    expect(api.orderRequests.length, greaterThanOrEqualTo(2));
  });
}

Future<void> _pumpWorkstation(
  WidgetTester tester, {
  required _OrderPanelApi api,
  required String role,
}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 960));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: MaterialApp(home: Scaffold(body: ClinicalWorkstation(role: role))),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _richTextContaining(String value) {
  return find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText().contains(value),
  );
}

class _OrderPanelApi extends ApiClient {
  final List<String> orderRequests = [];
  final List<String> postedPaths = [];

  @override
  Future<Map<String, dynamic>> getObject(String path) async {
    if (path.endsWith('/context')) {
      return {
        'admission': {
          'patient_name': path.contains('/2/') ? '王患者' : '赵患者',
          'gender': 'MALE',
          'birth_date': '1990-01-01',
          'height_cm': 170,
          'weight_kg': 65,
          'phone': '13800000000',
          'patient_no': 'PT001',
          'inpatient_no': path.contains('/2/') ? 'ZY002' : 'ZY001',
          'medical_record_no': 'MR001',
          'bed_no': path.contains('/2/') ? '3床' : '2床',
          'stay_days': 1,
          'nursing_level': 'LEVEL_2',
          'department_name': '内科',
          'doctor_name': '李医师',
          'admission_time': '2026-08-20T08:00:00',
          'fee_type': 'SELF_PAY',
          'insurance_type': '居民医保',
        },
        'allergies': [
          {'allergen_name': '青霉素'},
        ],
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

  @override
  Future<List<Map<String, dynamic>>> getList(String path) async {
    if (path.startsWith('/api/v1/workstation/admissions') &&
        !path.contains('/care-orders') &&
        !path.contains('/reports') &&
        !path.contains('/case-home')) {
      return const [
        {
          'admission_id': 1,
          'patient_name': '赵患者',
          'inpatient_no': 'ZY001',
          'bed_no': '2床',
        },
        {
          'admission_id': 2,
          'patient_name': '王患者',
          'inpatient_no': 'ZY002',
          'bed_no': '3床',
        },
      ];
    }
    if (path.contains('/care-orders')) {
      orderRequests.add(path);
      if (path.contains('/admissions/2/')) {
        return [_order(21, '替代患者医嘱', 'TEMPORARY')];
      }
      return [
        _order(11, '阿莫西林胶囊', 'LONG_TERM'),
        _order(12, '静脉输液', 'TEMPORARY'),
      ];
    }
    return [];
  }

  @override
  Future<void> postVoid(String path, Map<String, dynamic> data) async {
    postedPaths.add(path);
  }

  Map<String, dynamic> _order(int id, String name, String orderClass) => {
        'care_order_id': id,
        'order_no': 'YZ$id',
        'order_type': 'TREATMENT',
        'order_class': orderClass,
        'order_name': name,
        'dose': '0.5g',
        'route': '口服',
        'frequency': '每日三次',
        'start_time': '2026-08-20T08:00:00',
        'end_time': null,
        'status': 'OPEN',
        'ordered_by': 1,
        'created_at': '2026-08-20T08:00:00',
        'stopped_at': null,
        'doctor_name': '李医师',
      };
}
