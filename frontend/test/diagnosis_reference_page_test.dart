import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_management/core/api_client.dart';
import 'package:hospital_management/features/auth/auth_controller.dart';
import 'package:hospital_management/features/clinical/diagnosis_reference_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String? clipboardText;

  setUp(() {
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('筛选活动诊断、选择字段和行后复制引用内容', (tester) async {
    final api = _DiagnosisReferenceApi();

    await tester.pumpWidget(_testApp(api, admissionId: 1));
    await tester.pumpAndSettle();

    expect(find.text('脑梗死'), findsOneWidget);
    expect(find.text('已作废诊断'), findsNothing);
    expect(_copyButton(tester).onPressed, isNull);

    await tester
        .tap(find.byKey(const ValueKey('diagnosis-reference-select-all')));
    await tester.pump();
    expect(_copyButton(tester).onPressed, isNotNull);

    await tester
        .tap(find.byKey(const ValueKey('diagnosis-reference-fields-all')));
    await tester.pump();
    expect(_copyButton(tester).onPressed, isNull);

    await tester
        .tap(find.byKey(const ValueKey('diagnosis-reference-fields-all')));
    await tester.pump();
    expect(_copyButton(tester).onPressed, isNotNull);

    await tester.tap(find
        .byKey(const ValueKey('diagnosis-reference-field-additional_code')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('diagnosis-reference-copy')));
    await tester.pumpAndSettle();

    expect(clipboardText, '前体\t诊断名称\t诊断编码\n-\t脑梗死\tI63.300');
    expect(find.text('已复制 1 条诊断。'), findsOneWidget);
  });

  testWidgets('切换类别与患者后重置选择并重新请求诊断', (tester) async {
    final api = _DiagnosisReferenceApi();
    final harness = GlobalKey<_ReferenceHarnessState>();

    await tester.pumpWidget(_ReferenceHarness(key: harness, api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('diagnosis-reference-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('门诊诊断').last);
    await tester.pumpAndSettle();
    expect(find.text('原发性高血压'), findsOneWidget);
    expect(find.text('前体'), findsOneWidget);
    expect(_copyButton(tester).onPressed, isNull);

    await tester
        .tap(find.byKey(const ValueKey('diagnosis-reference-select-3')));
    await tester.pump();
    expect(_copyButton(tester).onPressed, isNotNull);

    harness.currentState!.showAdmission(2);
    await tester.pumpAndSettle();

    expect(api.paths, contains('/api/v1/workstation/admissions/2/diagnoses'));
    expect(find.text('肺炎'), findsOneWidget);
    expect(_copyButton(tester).onPressed, isNull);
  });
}

MaterialApp _testApp(_DiagnosisReferenceApi api, {required int admissionId}) {
  return MaterialApp(
    home: ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: Scaffold(
        body: DiagnosisReferencePage(
          key: const ValueKey('diagnosis-reference-page'),
          admissionId: admissionId,
        ),
      ),
    ),
  );
}

OutlinedButton _copyButton(WidgetTester tester) {
  return tester.widget<OutlinedButton>(
    find.byKey(const ValueKey('diagnosis-reference-copy')),
  );
}

class _ReferenceHarness extends StatefulWidget {
  const _ReferenceHarness({super.key, required this.api});

  final _DiagnosisReferenceApi api;

  @override
  State<_ReferenceHarness> createState() => _ReferenceHarnessState();
}

class _ReferenceHarnessState extends State<_ReferenceHarness> {
  var _admissionId = 1;

  void showAdmission(int admissionId) {
    setState(() => _admissionId = admissionId);
  }

  @override
  Widget build(BuildContext context) {
    return _testApp(widget.api, admissionId: _admissionId);
  }
}

class _DiagnosisReferenceApi extends ApiClient {
  final List<String> paths = [];

  @override
  Future<List<Map<String, dynamic>>> getList(String path) async {
    paths.add(path);
    if (path.contains('/admissions/2/')) {
      return [
        {
          'diagnosis_id': 4,
          'diagnosis_type': 'OUTPATIENT',
          'diagnosis_name': '肺炎',
          'diagnosis_code': 'J18.900',
          'status': 'ACTIVE',
        },
      ];
    }
    return [
      {
        'diagnosis_id': 1,
        'diagnosis_type': 'ADMISSION',
        'diagnosis_name': '脑梗死',
        'diagnosis_code': 'I63.300',
        'additional_code': 'A01',
        'status': 'ACTIVE',
      },
      {
        'diagnosis_id': 2,
        'diagnosis_type': 'ADMISSION',
        'diagnosis_name': '已作废诊断',
        'diagnosis_code': 'Z00.000',
        'status': 'VOID',
      },
      {
        'diagnosis_id': 3,
        'diagnosis_type': 'OUTPATIENT',
        'diagnosis_name': '原发性高血压',
        'diagnosis_code': 'I10.x090',
        'status': 'ACTIVE',
      },
    ];
  }
}
