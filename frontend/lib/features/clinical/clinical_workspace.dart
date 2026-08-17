import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui_helpers.dart';
import '../../core/workstation_ui.dart';
import '../auth/auth_controller.dart';

class ClinicalWorkspace extends ConsumerStatefulWidget {
  const ClinicalWorkspace({super.key});

  @override
  ConsumerState<ClinicalWorkspace> createState() => _ClinicalWorkspaceState();
}

class _ClinicalWorkspaceState extends ConsumerState<ClinicalWorkspace> {
  List<Map<String, dynamic>> _admissions = [];
  int? _admissionId;
  Future<Map<String, dynamic>>? _overview;
  var _loadingAdmissions = true;

  @override
  void initState() {
    super.initState();
    _loadAdmissions();
  }

  Future<void> _loadAdmissions() async {
    setState(() => _loadingAdmissions = true);
    try {
      _admissions = await ref
          .read(apiClientProvider)
          .getList('/api/v1/admissions?status=IN_HOSPITAL');
      if (_admissions.isNotEmpty && _admissionId == null) {
        _admissionId = (_admissions.first['admission_id'] as num).toInt();
      }
      _refreshOverview();
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingAdmissions = false);
      }
    }
  }

  void _refreshOverview() {
    if (_admissionId == null) {
      return;
    }
    setState(() {
      _overview = ref.read(apiClientProvider).getObject(
            '/api/v1/admissions/$_admissionId/clinical',
          );
    });
  }

  Future<void> _postSimple(
    String title,
    String suffix,
    List<FieldSpec> fields,
  ) async {
    if (_admissionId == null) {
      return;
    }
    final values =
        await showTextFormDialog(context, title: title, fields: fields);
    if (values == null) {
      return;
    }
    try {
      await ref.read(apiClientProvider).postVoid(
            '/api/v1/admissions/$_admissionId/clinical/$suffix',
            values,
          );
      if (mounted) {
        showOperationMessage(context, '已保存。');
      }
      _refreshOverview();
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  Future<Map<String, dynamic>?> _chooseOption({
    required String title,
    required List<Map<String, dynamic>> items,
    required String idKey,
    required String Function(Map<String, dynamic>) label,
  }) async {
    if (!mounted) {
      return null;
    }
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        Map<String, dynamic>? selected;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(title),
            content: DropdownButtonFormField<int>(
              value:
                  selected == null ? null : (selected![idKey] as num).toInt(),
              isExpanded: true,
              decoration: const InputDecoration(labelText: '请选择'),
              items: items
                  .map(
                    (item) => DropdownMenuItem(
                      value: (item[idKey] as num).toInt(),
                      child: Text(label(item), overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setDialogState(() {
                  selected = items.firstWhere(
                      (item) => (item[idKey] as num).toInt() == value);
                });
              },
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消')),
              FilledButton(
                onPressed: selected == null
                    ? null
                    : () => Navigator.pop(context, selected),
                child: const Text('确认'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _prescription() async {
    if (_admissionId == null) {
      return;
    }
    try {
      final drugs = await ref
          .read(apiClientProvider)
          .getList('/api/v1/clinical/catalog/drugs');
      final drug = await _chooseOption(
        title: '选择处方药品',
        items: drugs,
        idKey: 'drug_id',
        label: (item) => '${item['drug_name']} ${item['specification'] ?? ''}',
      );
      if (drug == null) {
        return;
      }
      final values = await showTextFormDialog(
        context,
        title: '开立处方：${drug['drug_name']}',
        fields: const [
          FieldSpec('dose', '单次剂量',
              required: true, numeric: true, decimal: true, initialValue: '1'),
          FieldSpec('doseUnit', '剂量单位', required: true, initialValue: '片'),
          FieldSpec('route', '给药途径', required: true, initialValue: '口服'),
          FieldSpec('frequency', '频次', required: true, initialValue: '每日一次'),
          FieldSpec('days', '用药天数',
              required: true, numeric: true, initialValue: '3'),
          FieldSpec('quantity', '数量',
              required: true, numeric: true, initialValue: '3'),
          FieldSpec('instruction', '医嘱说明'),
        ],
      );
      if (values == null) {
        return;
      }
      final item = <String, dynamic>{
        'drugId': (drug['drug_id'] as num).toInt(),
        ...values,
      };
      await ref.read(apiClientProvider).postObject(
        '/api/v1/admissions/$_admissionId/clinical/prescriptions',
        {
          'type': 'LONG_TERM',
          'startTime': DateTime.now().toIso8601String(),
          'items': [item],
        },
      );
      if (mounted) {
        showOperationMessage(context, '处方已开立并生成费用快照。');
      }
      _refreshOverview();
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  Future<void> _examOrder() async {
    if (_admissionId == null) {
      return;
    }
    try {
      final items = await ref
          .read(apiClientProvider)
          .getList('/api/v1/clinical/catalog/exam-items');
      if (!mounted) {
        return;
      }
      final selected = <int>{};
      final created = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('开立检查检验医嘱'),
            content: SizedBox(
              width: 460,
              child: ListView(
                shrinkWrap: true,
                children: items.map((item) {
                  final id = (item['exam_item_id'] as num).toInt();
                  return CheckboxListTile(
                    value: selected.contains(id),
                    title: Text(item['item_name'].toString()),
                    subtitle: Text(
                        '￥${item['unit_price']} · ${item['department_name'] ?? '-'}'),
                    onChanged: (checked) {
                      setDialogState(() {
                        if (checked ?? false) {
                          selected.add(id);
                        } else {
                          selected.remove(id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消')),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, true),
                child: const Text('开立'),
              ),
            ],
          ),
        ),
      );
      if (created != true) {
        return;
      }
      await ref.read(apiClientProvider).postObject(
        '/api/v1/admissions/$_admissionId/clinical/exam-orders',
        {
          'priority': 'NORMAL',
          'clinicalNote': '临床检查医嘱',
          'examItemIds': selected.toList(),
        },
      );
      if (mounted) {
        showOperationMessage(context, '检查检验医嘱已开立。');
      }
      _refreshOverview();
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  Future<void> _report(int orderId) async {
    if (_admissionId == null) {
      return;
    }
    try {
      final detail = await ref.read(apiClientProvider).getObject(
            '/api/v1/admissions/$_admissionId/clinical/exam-orders/$orderId',
          );
      final items = (detail['items'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .where((item) => item['status'] != 'REPORTED')
          .toList();
      final item = await _chooseOption(
        title: '选择待报告项目',
        items: items,
        idKey: 'exam_order_item_id',
        label: (value) => value['item_name'].toString(),
      );
      if (item == null) {
        return;
      }
      final values = await showTextFormDialog(
        context,
        title: '录入报告：${item['item_name']}',
        fields: const [
          FieldSpec('reportName', '报告名称', required: true),
          FieldSpec('conclusion', '结论', multiline: true),
          FieldSpec('itemName', '结果项目名称', required: true),
          FieldSpec('qualitativeValue', '定性结果'),
          FieldSpec('quantitativeValue', '定量结果', numeric: true, decimal: true),
          FieldSpec('unit', '单位'),
          FieldSpec('referenceRange', '参考范围'),
          FieldSpec('abnormalFlag', '异常标志'),
        ],
      );
      if (values == null) {
        return;
      }
      final payload = <String, dynamic>{
        'reportName': values.remove('reportName'),
        'conclusion': values.remove('conclusion'),
        'results': [
          {
            ...values,
            'sortNo': 1,
          },
        ],
      };
      await ref.read(apiClientProvider).postVoid(
            '/api/v1/admissions/$_admissionId/clinical/exam-order-items/${item['exam_order_item_id']}/report',
            payload,
          );
      if (mounted) {
        showOperationMessage(context, '报告已发布。');
      }
      _refreshOverview();
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  Widget _overviewBody(Map<String, dynamic> data) {
    final diagnoses = (data['diagnoses'] as List).cast<Map>();
    final records = (data['records'] as List).cast<Map>();
    final prescriptions = (data['prescriptions'] as List).cast<Map>();
    final examOrders = (data['examOrders'] as List).cast<Map>();
    final vitals = (data['vitalSigns'] as List).cast<Map>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section('诊断', diagnoses,
            const ['diagnosis_name', 'diagnosis_type', 'is_primary', 'status']),
        _section('病程记录', records,
            const ['title', 'record_type', 'status', 'recorded_at']),
        _section('处方', prescriptions, const [
          'prescription_no',
          'prescription_type',
          'status',
          'ordered_at'
        ]),
        _examSection(examOrders),
        _section('生命体征', vitals, const [
          'measured_at',
          'temperature',
          'pulse',
          'systolic_bp',
          'diastolic_bp'
        ]),
      ],
    );
  }

  Widget _section(String title, List<Map> rawRows, List<String> columns) {
    final rows = rawRows.map((row) => Map<String, dynamic>.from(row)).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          JsonTable(rows: rows, columns: columns),
        ],
      ),
    );
  }

  Widget _examSection(List<Map> rawRows) {
    if (rawRows.isEmpty) {
      return _section('检查检验医嘱', rawRows, const []);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('检查检验医嘱', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...rawRows.map((row) {
            final orderId = (row['exam_order_id'] as num).toInt();
            return Card(
              child: ListTile(
                title: Text(row['order_no'].toString()),
                subtitle: Text('状态：${row['status']} · 优先级：${row['priority']}'),
                trailing: OutlinedButton(
                  onPressed: () => _report(orderId),
                  child: const Text('录入报告'),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedAdmission = _admissionId == null
        ? null
        : _admissions.cast<Map<String, dynamic>>().firstWhere(
              (admission) =>
                  (admission['admission_id'] as num).toInt() == _admissionId,
            );
    return Column(
      children: [
        const WorkspaceToolbar(
          title: '医师临床工作站',
          subtitle: '诊断、病程、护理评估、生命体征、医嘱及检查报告',
        ),
        if (selectedAdmission != null)
          PatientContextBar(
            name: displayValue(selectedAdmission['patient_name']),
            inpatientNo: displayValue(selectedAdmission['inpatient_no']),
            department: displayValue(selectedAdmission['department_name']),
            bedNo: displayValue(selectedAdmission['bed_no']),
            doctor: selectedAdmission['doctor_name']?.toString(),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _admissionId,
                  decoration: const InputDecoration(labelText: '选择在院患者'),
                  items: _admissions
                      .map(
                        (admission) => DropdownMenuItem(
                          value: (admission['admission_id'] as num).toInt(),
                          child: Text(
                              '${admission['patient_name']} · ${admission['inpatient_no']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _admissionId = value);
                    _refreshOverview();
                  },
                ),
              ),
              IconButton(
                  onPressed: _loadAdmissions,
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新患者'),
            ],
          ),
        ),
        if (_loadingAdmissions)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_admissionId == null)
          const Expanded(child: Center(child: Text('当前没有可处理的在院患者。')))
        else
          Expanded(
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  const WorkstationTabBar(
                    isScrollable: false,
                    tabs: [
                      Tab(text: '临床概览'),
                      Tab(text: '临床记录'),
                      Tab(text: '医嘱与报告'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        FutureBuilder<Map<String, dynamic>>(
                          future: _overview,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            if (snapshot.hasError) {
                              return Center(
                                  child:
                                      Text(apiErrorMessage(snapshot.error!)));
                            }
                            return _overviewBody(snapshot.data!);
                          },
                        ),
                        _ClinicalRecordActions(onSubmit: _postSimple),
                        _OrderActions(
                            onPrescription: _prescription,
                            onExamOrder: _examOrder),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ClinicalRecordActions extends StatelessWidget {
  const _ClinicalRecordActions({required this.onSubmit});

  final Future<void> Function(String, String, List<FieldSpec>) onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.medical_information_outlined),
          title: const Text('新增诊断'),
          onTap: () => onSubmit('新增诊断', 'diagnoses', const [
            FieldSpec('code', '诊断编码'),
            FieldSpec('name', '诊断名称', required: true),
            FieldSpec('type', '诊断类型',
                required: true, initialValue: 'ADMISSION'),
            FieldSpec('primary', '是否主要诊断（true 或 false）',
                required: true, initialValue: 'true'),
          ]),
        ),
        ListTile(
          leading: const Icon(Icons.article_outlined),
          title: const Text('新增病程记录'),
          onTap: () => onSubmit('新增病程记录', 'records', const [
            FieldSpec('type', '文书类型', required: true, initialValue: 'COURSE'),
            FieldSpec('title', '标题', required: true),
            FieldSpec('content', '正文', required: true, multiline: true),
          ]),
        ),
        ListTile(
          leading: const Icon(Icons.assignment_outlined),
          title: const Text('新增护理评估'),
          onTap: () => onSubmit('新增护理评估', 'assessments', const [
            FieldSpec('type', '评估类型',
                required: true, initialValue: 'FALL_RISK'),
            FieldSpec('score', '评分', numeric: true, decimal: true),
            FieldSpec('riskLevel', '风险等级', initialValue: 'LOW'),
            FieldSpec('measures', '护理措施', multiline: true),
            FieldSpec('remark', '备注'),
          ]),
        ),
        ListTile(
          leading: const Icon(Icons.monitor_heart_outlined),
          title: const Text('录入生命体征'),
          onTap: () => onSubmit('录入生命体征', 'vital-signs', [
            FieldSpec('measuredAt', '测量时间',
                required: true, initialValue: DateTime.now().toIso8601String()),
            const FieldSpec('temperature', '体温', numeric: true, decimal: true),
            const FieldSpec('pulse', '脉搏', numeric: true),
            const FieldSpec('respiratoryRate', '呼吸频率', numeric: true),
            const FieldSpec('systolicBp', '收缩压', numeric: true),
            const FieldSpec('diastolicBp', '舒张压', numeric: true),
            const FieldSpec('spo2', '血氧饱和度', numeric: true, decimal: true),
            const FieldSpec('remark', '备注'),
          ]),
        ),
      ],
    );
  }
}

class _OrderActions extends StatelessWidget {
  const _OrderActions(
      {required this.onPrescription, required this.onExamOrder});

  final Future<void> Function() onPrescription;
  final Future<void> Function() onExamOrder;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.medication_outlined),
          title: const Text('开立处方'),
          subtitle: const Text('选择药品并生成本次住院费用快照'),
          onTap: onPrescription,
        ),
        ListTile(
          leading: const Icon(Icons.biotech_outlined),
          title: const Text('开立检查检验医嘱'),
          subtitle: const Text('可勾选多个检查项目'),
          onTap: onExamOrder,
        ),
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text('检查报告请在“临床概览”的检查检验医嘱区选择对应检查单录入。'),
        ),
      ],
    );
  }
}
