import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui_helpers.dart';
import '../../core/workstation_ui.dart';
import '../auth/auth_controller.dart';

/// 从当前住院记录中选择诊断字段，并复制为可粘贴到临床文书的表格文本。
class DiagnosisReferencePage extends ConsumerStatefulWidget {
  const DiagnosisReferencePage({
    super.key,
    required this.admissionId,
  });

  final int admissionId;

  @override
  ConsumerState<DiagnosisReferencePage> createState() =>
      _DiagnosisReferencePageState();
}

class _DiagnosisReferencePageState
    extends ConsumerState<DiagnosisReferencePage> {
  List<Map<String, dynamic>> _diagnoses = const [];
  final Set<int> _selectedDiagnosisIds = <int>{};
  Set<String> _selectedFieldKeys =
      _fieldsForType('ADMISSION').map((field) => field.key).toSet();
  String _selectedType = 'ADMISSION';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDiagnoses();
  }

  @override
  void didUpdateWidget(covariant DiagnosisReferencePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.admissionId != widget.admissionId) {
      _loadDiagnoses();
    }
  }

  Future<void> _loadDiagnoses() async {
    setState(() {
      _loading = true;
      _selectedDiagnosisIds.clear();
    });
    try {
      final diagnoses = await ref.read(apiClientProvider).getList(
            '/api/v1/workstation/admissions/${widget.admissionId}/diagnoses',
          );
      if (!mounted) {
        return;
      }
      setState(() => _diagnoses = diagnoses);
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<Map<String, dynamic>> get _visibleRows => _diagnoses
      .where((diagnosis) => diagnosis['status'] == 'ACTIVE')
      .where((diagnosis) => diagnosis['diagnosis_type'] == _selectedType)
      .toList();

  List<_DiagnosisField> get _fields => _fieldsForType(_selectedType);

  bool get _allRowsSelected =>
      _visibleRows.isNotEmpty &&
      _visibleRows.every((row) => _selectedDiagnosisIds.contains(_id(row)));

  bool get _allFieldsSelected =>
      _fields.isNotEmpty &&
      _fields.every((field) => _selectedFieldKeys.contains(field.key));

  bool get _canCopy =>
      _selectedDiagnosisIds.isNotEmpty && _selectedFieldKeys.isNotEmpty;

  int? _id(Map<String, dynamic> row) {
    final value = row['diagnosis_id'];
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  void _changeType(String? value) {
    if (value == null || value == _selectedType) {
      return;
    }
    final fields = _fieldsForType(value);
    setState(() {
      _selectedType = value;
      _selectedDiagnosisIds.clear();
      _selectedFieldKeys = fields.map((field) => field.key).toSet();
    });
  }

  void _toggleAllRows(bool? selected) {
    setState(() {
      if (selected == true) {
        for (final row in _visibleRows) {
          final id = _id(row);
          if (id != null) {
            _selectedDiagnosisIds.add(id);
          }
        }
      } else {
        for (final row in _visibleRows) {
          final id = _id(row);
          if (id != null) {
            _selectedDiagnosisIds.remove(id);
          }
        }
      }
    });
  }

  void _toggleRow(int id, bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedDiagnosisIds.add(id);
      } else {
        _selectedDiagnosisIds.remove(id);
      }
    });
  }

  void _toggleField(String key, bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedFieldKeys.add(key);
      } else {
        _selectedFieldKeys.remove(key);
      }
    });
  }

  void _toggleAllFields(bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedFieldKeys = _fields.map((field) => field.key).toSet();
      } else {
        _selectedFieldKeys.clear();
      }
    });
  }

  Future<void> _copySelection() async {
    if (!_canCopy) {
      return;
    }
    final fields = _fields
        .where((field) => _selectedFieldKeys.contains(field.key))
        .toList();
    final rows = _visibleRows
        .where((row) => _selectedDiagnosisIds.contains(_id(row)))
        .toList();
    if (fields.isEmpty || rows.isEmpty) {
      return;
    }
    final text = [
      fields.map((field) => field.label).join('\t'),
      ...rows.map(
        (row) => fields.map((field) => displayValue(row[field.key])).join('\t'),
      ),
    ].join('\n');
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        showOperationMessage(context, '已复制 ${rows.length} 条诊断。');
      }
    } catch (_) {
      if (mounted) {
        showOperationMessage(context, '诊断内容复制失败，请重试。', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WorkSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          WorkspaceToolbar(
            title: '诊断引用',
            subtitle: '选择当前患者的诊断内容后复制到临床文书。',
            actions: [
              IconButton(
                key: const ValueKey('diagnosis-reference-refresh'),
                onPressed: _loading ? null : _loadDiagnoses,
                tooltip: '刷新诊断',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          _filters(),
          _selectionBar(),
          Expanded(child: _table()),
        ],
      ),
    );
  }

  Widget _filters() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FBFC),
        border: Border(bottom: BorderSide(color: WorkstationColors.border)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const _ReadOnlyFilter(label: '住院记录', value: '本次住院'),
          const _ReadOnlyFilter(label: '诊断体系', value: '西医'),
          SizedBox(
            width: 176,
            child: DropdownButtonFormField<String>(
              key: const ValueKey('diagnosis-reference-type'),
              initialValue: _selectedType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '诊断类别'),
              items: _diagnosisTypes
                  .map(
                    (type) => DropdownMenuItem(
                      value: type.key,
                      child: Text(type.label),
                    ),
                  )
                  .toList(),
              onChanged: _changeType,
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectionBar() {
    final selectedRows = _visibleRows
        .where((row) => _selectedDiagnosisIds.contains(_id(row)))
        .length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: WorkstationColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final summary = Text(
            '已选 $selectedRows 条诊断，${_selectedFieldKeys.length} 个字段',
            style: const TextStyle(color: WorkstationColors.muted),
          );
          final copyButton = OutlinedButton.icon(
            key: const ValueKey('diagnosis-reference-copy'),
            onPressed: _canCopy ? _copySelection : null,
            icon: const Icon(Icons.content_copy_outlined, size: 18),
            label: const Text('引用'),
          );
          if (constraints.maxWidth < 580) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [summary, _allFieldsControl()],
                ),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: copyButton),
              ],
            );
          }
          return Row(
            children: [
              summary,
              const SizedBox(width: 16),
              _allFieldsControl(),
              const Spacer(),
              copyButton,
            ],
          );
        },
      ),
    );
  }

  Widget _allFieldsControl() {
    return InkWell(
      onTap: () => _toggleAllFields(!_allFieldsSelected),
      borderRadius: const BorderRadius.all(Radius.circular(4)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            key: const ValueKey('diagnosis-reference-fields-all'),
            value: _allFieldsSelected,
            onChanged: _toggleAllFields,
            semanticLabel: '全选引用字段',
          ),
          const Text('全部字段'),
        ],
      ),
    );
  }

  Widget _table() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_visibleRows.isEmpty) {
      return const Center(
        child: Text(
          '暂无可引用的诊断记录。',
          style: TextStyle(color: WorkstationColors.muted),
        ),
      );
    }
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: 130 + _fields.length * 180,
          ),
          child: DataTable(
            headingRowColor:
                const WidgetStatePropertyAll(WorkstationColors.heading),
            dataRowMaxHeight: 58,
            dataRowMinHeight: 50,
            horizontalMargin: 14,
            columnSpacing: 20,
            columns: [
              DataColumn(
                label: Checkbox(
                  key: const ValueKey('diagnosis-reference-select-all'),
                  value: _allRowsSelected,
                  onChanged: _toggleAllRows,
                  semanticLabel: '全选诊断',
                ),
              ),
              ..._fields.map(
                (field) => DataColumn(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        key: ValueKey('diagnosis-reference-field-${field.key}'),
                        value: _selectedFieldKeys.contains(field.key),
                        onChanged: (selected) =>
                            _toggleField(field.key, selected),
                        semanticLabel: '引用${field.label}',
                      ),
                      Text(field.label),
                    ],
                  ),
                ),
              ),
            ],
            rows: _visibleRows.map(_tableRow).toList(),
          ),
        ),
      ),
    );
  }

  DataRow _tableRow(Map<String, dynamic> row) {
    final id = _id(row);
    final selected = id != null && _selectedDiagnosisIds.contains(id);
    return DataRow(
      selected: selected,
      color: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Color(0xFFE3F3F8)
            : null,
      ),
      onSelectChanged: id == null ? null : (value) => _toggleRow(id, value),
      cells: [
        DataCell(
          Checkbox(
            key: ValueKey('diagnosis-reference-select-$id'),
            value: selected,
            onChanged: id == null ? null : (value) => _toggleRow(id, value),
            semanticLabel: '选择${displayValue(row['diagnosis_name'])}',
          ),
        ),
        ..._fields.map(
          (field) => DataCell(
            SizedBox(
              width: 160,
              child: Text(
                displayValue(row[field.key]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyFilter extends StatelessWidget {
  const _ReadOnlyFilter({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(value),
      ),
    );
  }
}

class _DiagnosisType {
  const _DiagnosisType(this.key, this.label);

  final String key;
  final String label;
}

class _DiagnosisField {
  const _DiagnosisField(this.key, this.label);

  final String key;
  final String label;
}

const _diagnosisTypes = [
  _DiagnosisType('ADMISSION', '初步诊断'),
  _DiagnosisType('OUTPATIENT', '门诊诊断'),
  _DiagnosisType('DISCHARGE', '出院诊断'),
  _DiagnosisType('PATHOLOGY', '病理诊断'),
];

List<_DiagnosisField> _fieldsForType(String type) {
  return switch (type) {
    'OUTPATIENT' || 'ADMISSION' => const [
        _DiagnosisField('predecessor', '前体'),
        _DiagnosisField('diagnosis_name', '诊断名称'),
        _DiagnosisField('diagnosis_code', '诊断编码'),
        _DiagnosisField('additional_code', '附加码'),
      ],
    'DISCHARGE' => const [
        _DiagnosisField('body_position', '方位'),
        _DiagnosisField('body_site', '部位'),
        _DiagnosisField('diagnosis_name', '诊断名称'),
        _DiagnosisField('diagnosis_note', '诊断补充说明'),
        _DiagnosisField('diagnosis_code', '诊断编码'),
        _DiagnosisField('t_stage', 'T 分期'),
        _DiagnosisField('n_stage', 'N 分期'),
        _DiagnosisField('m_stage', 'M 分期'),
        _DiagnosisField('admission_condition', '入院病情'),
        _DiagnosisField('treated', '是否治疗'),
        _DiagnosisField('efficacy', '疗效'),
      ],
    'PATHOLOGY' => const [
        _DiagnosisField('pathology_no', '病理号'),
        _DiagnosisField('body_position', '方位'),
        _DiagnosisField('body_site', '部位'),
        _DiagnosisField('diagnosis_name', '诊断名称'),
        _DiagnosisField('diagnosis_note', '诊断补充说明'),
        _DiagnosisField('diagnosis_code', '诊断编码'),
        _DiagnosisField('additional_code', '附加码'),
        _DiagnosisField('tumor_diagnosis_basis', '肿瘤诊断依据'),
        _DiagnosisField('pathologist', '病理医师'),
        _DiagnosisField('pathology_technician', '病理技师'),
      ],
    _ => const [],
  };
}
