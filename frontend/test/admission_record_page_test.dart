import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_management/core/api_client.dart';
import 'package:hospital_management/features/auth/auth_controller.dart';
import 'package:hospital_management/features/clinical/admission_record_page.dart';

void main() {
  testWidgets('神经内科默认展开神经查体，提示文字不会成为字段值',
      (tester) async {
    final api = _AdmissionRecordApi();
    await _pump(tester, api);

    expect(find.text('神经系统查体（可选）'), findsOneWidget);
    expect(find.byKey(const ValueKey('admission-field-cranialNerves')), findsOneWidget);

    final generalField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('admission-field-generalExam')),
    );
    expect(generalField.controller!.text, isEmpty);
    expect(generalField.decoration!.hintText, contains('发育、营养'));
  });

  testWidgets('保存时写入结构化字段和患者抬头快照，并能打开正式预览',
      (tester) async {
    final api = _AdmissionRecordApi();
    await _pump(tester, api);

    await tester.enterText(
      find.byKey(const ValueKey('admission-field-chiefComplaint')),
      '突发右侧肢体无力 5 小时。',
    );
    await tester.tap(find.byTooltip('保存草稿'));
    await tester.pumpAndSettle();

    final contentJson = jsonDecode(api.lastPayload!['contentJson'] as String)
        as Map<String, dynamic>;
    final fields = Map<String, dynamic>.from(contentJson['fields'] as Map);
    final header = Map<String, dynamic>.from(contentJson['header'] as Map);
    expect(fields['chiefComplaint'], '突发右侧肢体无力 5 小时。');
    expect(fields.containsKey('generalExam'), isFalse);
    expect(header['medicalRecordNo'], 'MR20260001');
    expect(header['departmentName'], '神经内科');

    await tester.tap(find.byTooltip('预览入院记录'));
    await tester.pumpAndSettle();
    expect(find.text('入院记录预览'), findsOneWidget);
    expect(find.text('突发右侧肢体无力 5 小时。'), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, _AdmissionRecordApi api) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: const MaterialApp(
        home: Scaffold(
          body: AdmissionRecordPage(admissionId: 1, role: 'DOCTOR'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _AdmissionRecordApi extends ApiClient {
  Map<String, dynamic>? lastPayload;

  @override
  Future<Map<String, dynamic>> getObject(String path) async {
    if (path.endsWith('/context')) {
      return {
        'admission': {
          'patient_name': '张患者',
          'gender': 'MALE',
          'birth_date': '1966-01-01',
          'patient_no': 'P20260001',
          'inpatient_no': 'IN20260001',
          'medical_record_no': 'MR20260001',
          'bed_no': '530',
          'department_code': 'NEU',
          'department_name': '神经内科',
          'admission_time': '2026-08-20T08:30:00',
          'doctor_name': '李医师',
        },
        'allergies': [],
        'depositBalance': 0,
        'availableBalance': 0,
      };
    }
    throw StateError('未处理的对象请求：$path');
  }

  @override
  Future<List<Map<String, dynamic>>> getList(String path) async {
    if (path.contains('/documents?code=ADMISSION_RECORD')) {
      if (lastPayload == null) {
        return [];
      }
      return [
        {
          'record_id': 8,
          'document_code': 'ADMISSION_RECORD',
          'title': '入院记录',
          'template_name': '入院记录',
          'content': lastPayload!['content'],
          'content_json': lastPayload!['contentJson'],
          'status': 'DRAFT',
          'version_no': 1,
          'recorded_at': '2026-08-20T08:35:00',
          'author_name': '李医师',
        },
      ];
    }
    if (path.contains('/document-templates')) {
      return [
        {
          'template_id': 4,
          'document_code': 'ADMISSION_RECORD',
          'template_name': '入院记录',
        },
      ];
    }
    throw StateError('未处理的列表请求：$path');
  }

  @override
  Future<Map<String, dynamic>> postObject(
      String path, Map<String, dynamic> data) async {
    expect(path, '/api/v1/workstation/admissions/1/documents');
    lastPayload = Map<String, dynamic>.from(data);
    return {'recordId': 8};
  }
}
