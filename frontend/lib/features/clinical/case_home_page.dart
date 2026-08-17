import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui_helpers.dart';
import '../../core/workstation_ui.dart';
import '../auth/auth_controller.dart';

/// 参照住院病历系统的病案首页：患者主档、住院归档与分阶段诊断集中在同一工作页。
class CaseHomePage extends ConsumerStatefulWidget {
  const CaseHomePage({
    super.key,
    required this.admissionId,
    required this.role,
    required this.onSaved,
  });

  final int admissionId;
  final String role;
  final VoidCallback onSaved;

  @override
  ConsumerState<CaseHomePage> createState() => _CaseHomePageState();
}

class _CaseHomePageState extends ConsumerState<CaseHomePage> {
  static const _integerKeys = {
    'admissionCount',
    'dischargeDepartmentId',
    'specialNursingDays',
    'levelOneNursingDays',
    'levelTwoNursingDays',
    'levelThreeNursingDays',
  };

  static const _staffKeys = {
    'departmentDirectorId',
    'chiefPhysicianId',
    'medicalGroupLeaderId',
    'residentDoctorId',
    'headNurseId',
    'responsibleNurseId',
    'qualityDoctorId',
    'qualityNurseId',
  };

  static const _booleanKeys = {
    'readmissionWithin31Days',
    'interhospitalOperation',
  };

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, int?> _staffIds = {};
  List<Map<String, dynamic>> _staff = [];
  Map<String, dynamic>? _home;
  List<Map<String, dynamic>> _diagnoses = [];
  final Set<int> _selectedDiagnosisIds = <int>{};
  String _facilityName = '';
  String _facilityCode = '';
  String _section = '全部';
  bool _loading = true;
  bool _saving = false;

  bool get _isDoctor => widget.role == 'DOCTOR';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(String key) {
    return _controllers.putIfAbsent(key, TextEditingController.new);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final requests = <Future<dynamic>>[
        ref.read(apiClientProvider).getObject(
            '/api/v1/workstation/admissions/${widget.admissionId}/case-home'),
        if (_isDoctor)
          ref
              .read(apiClientProvider)
              .getList('/api/v1/workstation/case-home/staff'),
      ];
      final values = await Future.wait(requests);
      final response = Map<String, dynamic>.from(values.first as Map);
      _home = Map<String, dynamic>.from(response['home'] as Map);
      _diagnoses = List<Map<String, dynamic>>.from(
        (response['diagnoses'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map)),
      );
      _facilityName = response['facilityName'].toString();
      _facilityCode = response['facilityCode'].toString();
      _staff = values.length == 2
          ? List<Map<String, dynamic>>.from(
              (values[1] as List)
                  .map((item) => Map<String, dynamic>.from(item as Map)),
            )
          : [];
      _populateForm();
      _selectedDiagnosisIds.clear();
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

  void _populateForm() {
    final home = _home!;
    for (final key in _fieldKeys) {
      _controller(key).text = home[key]?.toString() ?? '';
    }
    for (final key in _staffKeys) {
      final value = home[_snakeCase(key)];
      _staffIds[key] = value is num ? value.toInt() : int.tryParse('$value');
    }
  }

  Future<void> _save() async {
    final values = <String, dynamic>{};
    for (final key in _fieldKeys) {
      final value = _controller(key).text.trim();
      values[key] = _integerKeys.contains(key)
          ? int.tryParse(value)
          : _booleanKeys.contains(key)
              ? value.isEmpty
                  ? null
                  : value == 'true'
              : value.isEmpty
                  ? null
                  : value;
    }
    values.addAll(_staffIds);
    try {
      setState(() => _saving = true);
      await ref.read(apiClientProvider).putVoid(
            '/api/v1/workstation/admissions/${widget.admissionId}/case-home',
            values,
          );
      widget.onSaved();
      if (mounted) {
        showOperationMessage(context, '病案首页已保存。');
      }
      await _load();
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _addDiagnosis(String type) async {
    final values = await showTextFormDialog(
      context,
      title: '新增${_diagnosisTitle(type)}',
      fields: _diagnosisFormFields(type),
      submitLabel: '新增诊断',
    );
    if (values == null) {
      return;
    }
    values['diagnosisType'] = type;
    values['primary'] =
        _diagnoses.where((item) => item['diagnosis_type'] == type).isEmpty;
    try {
      await ref.read(apiClientProvider).postVoid(
            '/api/v1/workstation/admissions/${widget.admissionId}/diagnoses',
            values,
          );
      if (mounted) {
        showOperationMessage(context, '诊断已添加。');
      }
      await _load();
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  List<FieldSpec> _diagnosisFormFields(String type) {
    final fields = <FieldSpec>[
      if (type == 'OUTPATIENT' || type == 'ADMISSION')
        const FieldSpec('predecessor', '前体'),
      if (type == 'PATHOLOGY') const FieldSpec('pathologyNo', '病理号'),
      if (type == 'DISCHARGE' || type == 'PATHOLOGY')
        const FieldSpec('bodyPosition', '方位'),
      if (type == 'DISCHARGE' || type == 'PATHOLOGY')
        const FieldSpec('bodySite', '部位'),
      const FieldSpec('diagnosisName', '诊断名称', required: true),
      const FieldSpec('diagnosisNote', '诊断补充说明', multiline: true),
      const FieldSpec('diagnosisCode', '诊断编码'),
      if (type == 'OUTPATIENT' || type == 'ADMISSION' || type == 'PATHOLOGY')
        const FieldSpec('additionalCode', '附加码'),
      if (type != 'PATHOLOGY')
        const FieldSpec('infectiousDisease', '传染病（true/false）'),
      if (type == 'DISCHARGE') ...[
        const FieldSpec('tStage', 'T 分期'),
        const FieldSpec('nStage', 'N 分期'),
        const FieldSpec('mStage', 'M 分期'),
        const FieldSpec('admissionCondition', '入院病情'),
        const FieldSpec('treated', '是否治疗（true/false）'),
        const FieldSpec('efficacy', '疗效'),
      ],
      if (type == 'PATHOLOGY') ...[
        const FieldSpec('tumorDiagnosisBasis', '肿瘤诊断依据'),
        const FieldSpec('pathologist', '病理医师'),
        const FieldSpec('pathologyTechnician', '病理技师'),
      ],
    ];
    return fields;
  }

  Future<void> _deleteSelected(String type) async {
    final rows = _diagnoses.where((item) => item['diagnosis_type'] == type);
    final ids = rows
        .map((row) => row['diagnosis_id'])
        .whereType<num>()
        .map((value) => value.toInt())
        .where(_selectedDiagnosisIds.contains)
        .toList();
    if (ids.isEmpty) {
      showOperationMessage(context, '请先勾选要删除的诊断。', error: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认删除诊断'),
        content: Text('将作废选中的 ${ids.length} 条诊断，原记录仍保留在审计历史中。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref.read(apiClientProvider).deleteVoid(
        '/api/v1/workstation/admissions/${widget.admissionId}/diagnoses',
        {'diagnosisIds': ids},
      );
      if (mounted) {
        showOperationMessage(context, '选中诊断已删除。');
      }
      await _load();
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_home == null) {
      return const Center(child: Text('病案首页数据暂不可用。'));
    }
    final desktop = MediaQuery.sizeOf(context).width >= 1120;
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          WorkspaceToolbar(
            title: '病案首页',
            subtitle: '患者主档、住院归档和分阶段诊断信息。',
            actions: [
              IconButton(
                onPressed: _load,
                tooltip: '刷新',
                icon: const Icon(Icons.refresh),
              ),
              if (_isDoctor)
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? '保存中' : '保存首页'),
                ),
            ],
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (desktop) _navigation(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(desktop ? 18 : 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!desktop) _sectionSelector(),
                        if (_visible('基本信息')) _basicInformation(),
                        if (_visible('住院信息')) _admissionInformation(),
                        if (_visible('诊断信息')) _diagnosisInformation(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navigation() {
    const sections = ['全部', '基本信息', '住院信息', '诊断信息'];
    return Container(
      width: 182,
      decoration: const BoxDecoration(
        color: Color(0xFFF7F9FA),
        border: Border(right: BorderSide(color: WorkstationColors.border)),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 16, 14, 10),
            child: TextField(
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索字段',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
            ),
          ),
          const Divider(height: 1),
          ...sections.map(
            (item) => ListTile(
              dense: true,
              selected: _section == item,
              selectedTileColor: const Color(0xFFDDF1F7),
              leading: Icon(
                _section == item
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: _section == item
                    ? WorkstationColors.cyan
                    : WorkstationColors.muted,
                size: 18,
              ),
              title: Text(item),
              onTap: () => setState(() => _section = item),
            ),
          ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('导航', style: TextStyle(color: WorkstationColors.muted)),
          ),
        ],
      ),
    );
  }

  Widget _sectionSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: '全部', label: Text('全部')),
          ButtonSegment(value: '基本信息', label: Text('基本')),
          ButtonSegment(value: '住院信息', label: Text('住院')),
          ButtonSegment(value: '诊断信息', label: Text('诊断')),
        ],
        selected: {_section},
        onSelectionChanged: (value) => setState(() => _section = value.first),
      ),
    );
  }

  bool _visible(String section) => _section == '全部' || _section == section;

  Widget _basicInformation() {
    final home = _home!;
    return _sectionBox(
      '基本信息',
      [
        _readOnlyField('医疗机构名称', _facilityName),
        _readOnlyField('医疗机构组织', _facilityCode),
        _readOnlyField('住院号', displayValue(home['inpatient_no'])),
        _readOnlyField('病案号', displayValue(home['medical_record_no'])),
        _readOnlyField('姓名', displayValue(home['name'])),
        _readOnlyField('性别', _gender(home['gender'])),
        _readOnlyField('出生日期', displayValue(home['birth_date'])),
        _readOnlyField('年龄', '${_age(home['birth_date'])}岁'),
        _choiceField('证件类型', 'idType', const {
          'ID_CARD': '居民身份证',
          'PASSPORT': '护照',
          'OTHER': '其他',
        }),
        _textField('证件号码', 'idCardNo'),
        _textField('国籍', 'nationality'),
        _textField('民族', 'ethnicity'),
        _textField('职业类别', 'occupation'),
        _choiceField('婚姻状况', 'maritalStatus', const {
          'UNMARRIED': '未婚',
          'MARRIED': '已婚',
          'OTHER': '其他',
        }),
        _textField('籍贯(省)', 'nativePlaceProvince'),
        _textField('籍贯(市)', 'nativePlaceCity'),
        _textField('出生地(省)', 'birthPlaceProvince'),
        _textField('出生地(市)', 'birthPlaceCity'),
        _textField('出生地(县)', 'birthPlaceCounty'),
        _textField('出生地详细地址', 'birthPlaceDetail'),
        _textField('现住址(省)', 'currentAddressProvince'),
        _textField('现住址(市)', 'currentAddressCity'),
        _textField('现住址(县)', 'currentAddressCounty'),
        _textField('现住址详细地址', 'currentAddressDetail'),
        _textField('现住址邮编', 'postalCode'),
        _textField('现住址电话', 'phone'),
        _textField('户口地址(省)', 'registeredAddressProvince'),
        _textField('户口地址(市)', 'registeredAddressCity'),
        _textField('户口地址(县)', 'registeredAddressCounty'),
        _textField('户口地址详细地址', 'registeredAddressDetail'),
        _textField('户口地址邮编', 'registeredPostalCode'),
        _textField('工作单位名称', 'employerName'),
        _textField('工作单位地址', 'employerAddress'),
        _textField('单位电话', 'employerPhone'),
        _textField('工作单位邮编', 'employerPostalCode'),
        _textField('联系人姓名', 'emergencyContactName'),
        _textField('联系人与患者关系', 'emergencyContactRelation'),
        _textField('联系人地址', 'emergencyContactAddress'),
        _textField('联系人电话', 'emergencyContactPhone'),
        _choiceField('ABO 血型', 'aboBloodType', const {
          'A': 'A 型',
          'B': 'B 型',
          'AB': 'AB 型',
          'O': 'O 型',
        }),
        _choiceField('Rh 血型', 'rhBloodType', const {
          'POSITIVE': 'Rh 阳性',
          'NEGATIVE': 'Rh 阴性',
        }),
      ],
    );
  }

  Widget _admissionInformation() {
    final home = _home!;
    return _sectionBox(
      '住院信息',
      [
        _textField('住院次数', 'admissionCount', numeric: true),
        _textField('医疗付费方式', 'feeType'),
        _textField('险种类型', 'insuranceType'),
        _choiceField('入院途径', 'admissionSource', const {
          'OUTPATIENT': '门诊',
          'EMERGENCY': '急诊',
          'TRANSFER': '转诊',
        }),
        _readOnlyField('入院日期时间', displayValue(home['admission_time'])),
        _readOnlyField('入院科室', displayValue(home['admission_department_name'])),
        _readOnlyField('入院病床号', displayValue(home['admission_bed_no'])),
        _readOnlyField('实际住院天数', '${displayValue(home['actual_stay_days'])}天'),
        _readOnlyField('药物过敏标志',
            (home['allergy_count'] as num?)?.toInt() == 0 ? '否' : '是'),
        _readOnlyField('出院日期时间', displayValue(home['discharge_time'])),
        _textField('出院科室 ID', 'dischargeDepartmentId', numeric: true),
        _textField('出院病床号', 'dischargeBedNo'),
        _choiceField('离院方式', 'dischargeMethod', const {
          'HOME': '医嘱离院',
          'TRANSFER': '转院',
          'DEATH': '死亡',
          'OTHER': '其他',
        }),
        _booleanField('31 日内再住院', 'readmissionWithin31Days'),
        _booleanField('是否日间手术', 'interhospitalOperation'),
        _readOnlyField(
            '临床路径入径情况', displayValue(home['pathway_enrollment_status'])),
        _readOnlyField(
            '临床路径完成情况', displayValue(home['pathway_completion_status'])),
        _readOnlyField(
            '临床路径变异情况', displayValue(home['pathway_variation_status'])),
        _staffField('科主任', 'departmentDirectorId'),
        _staffField('主任(副主任)', 'chiefPhysicianId'),
        _staffField('医疗组长', 'medicalGroupLeaderId'),
        _readOnlyField('主治医师', displayValue(_home!['attending_doctor_name'])),
        _staffField('住院医师', 'residentDoctorId'),
        _staffField('护士长', 'headNurseId'),
        _staffField('责任护士', 'responsibleNurseId'),
        _staffField('质控医师', 'qualityDoctorId'),
        _staffField('质控护士', 'qualityNurseId'),
        _textField('质控日期', 'qualityControlDate', hint: 'YYYY-MM-DD'),
        _textField('特级护理', 'specialNursingDays', numeric: true, suffix: '天'),
        _textField('一级护理', 'levelOneNursingDays', numeric: true, suffix: '天'),
        _textField('二级护理', 'levelTwoNursingDays', numeric: true, suffix: '天'),
        _textField('三级护理', 'levelThreeNursingDays', numeric: true, suffix: '天'),
      ],
    );
  }

  Widget _diagnosisInformation() {
    return _sectionBox(
      '诊断信息',
      [
        _diagnosisTable('门诊诊断', 'OUTPATIENT'),
        _diagnosisTable('入院诊断', 'ADMISSION'),
        _diagnosisTable('出院诊断', 'DISCHARGE'),
        _diagnosisTable('病理诊断', 'PATHOLOGY'),
      ],
      fullWidth: true,
    );
  }

  Widget _diagnosisTable(String title, String type) {
    final rows =
        _diagnoses.where((item) => item['diagnosis_type'] == type).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: const BoxDecoration(
        border:
            Border.fromBorderSide(BorderSide(color: WorkstationColors.border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
            child: Row(
              children: [
                Text('$title（至少一条）',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (_isDoctor)
                  OutlinedButton.icon(
                    onPressed: () => _deleteSelected(type),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('删除'),
                  ),
                if (_isDoctor) const SizedBox(width: 8),
                if (_isDoctor)
                  OutlinedButton.icon(
                    onPressed: () => _addDiagnosis(type),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新增诊断'),
                  ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor:
                  const WidgetStatePropertyAll(WorkstationColors.heading),
              columns: _diagnosisColumns(type),
              rows: rows.isEmpty
                  ? [
                      DataRow(
                          cells: List<DataCell>.generate(
                        _diagnosisColumns(type).length,
                        (index) => DataCell(
                          Text(index == 1 ? '暂无数据' : '-'),
                        ),
                      )),
                    ]
                  : List.generate(
                      rows.length,
                      (index) {
                        final row = rows[index];
                        final diagnosisId =
                            (row['diagnosis_id'] as num?)?.toInt();
                        final selected = diagnosisId != null &&
                            _selectedDiagnosisIds.contains(diagnosisId);
                        return DataRow(
                            cells: _diagnosisCells(
                          row,
                          index,
                          type,
                          diagnosisId,
                          selected,
                        ));
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  List<DataColumn> _diagnosisColumns(String type) {
    final labels = switch (type) {
      'OUTPATIENT' || 'ADMISSION' => [
          '序号',
          '前体',
          '诊断名称',
          '诊断补充说明',
          '诊断编码',
          '附加码',
          '传染病',
          '下诊医生',
          '下诊时间',
          '操作',
        ],
      'DISCHARGE' => [
          '序号',
          '方位',
          '部位',
          '诊断名称',
          '诊断补充说明',
          '诊断编码',
          'T 分期',
          'N 分期',
          'M 分期',
          '入院病情',
          '是否治疗',
          '疗效',
          '传染病',
          '下诊医生',
          '下诊时间',
        ],
      _ => [
          '序号',
          '病理号',
          '方位',
          '部位',
          '诊断名称',
          '诊断补充说明',
          '诊断编码',
          '附加码',
          '肿瘤诊断依据',
          '病理医师',
          '病理技师',
          '操作',
        ],
    };
    return labels.map((label) => DataColumn(label: Text(label))).toList();
  }

  List<DataCell> _diagnosisCells(
    Map<String, dynamic> row,
    int index,
    String type,
    int? diagnosisId,
    bool selected,
  ) {
    final serial = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: selected,
          onChanged: diagnosisId == null || !_isDoctor
              ? null
              : (value) => setState(() {
                    if (value == true) {
                      _selectedDiagnosisIds.add(diagnosisId);
                    } else {
                      _selectedDiagnosisIds.remove(diagnosisId);
                    }
                  }),
        ),
        Text('${index + 1}'),
      ],
    );
    final value = (String key) => Text(displayValue(row[key]));
    if (type == 'OUTPATIENT' || type == 'ADMISSION') {
      return [
        DataCell(serial),
        DataCell(value('predecessor')),
        DataCell(value('diagnosis_name')),
        DataCell(value('diagnosis_note')),
        DataCell(value('diagnosis_code')),
        DataCell(value('additional_code')),
        DataCell(value('infectious_disease')),
        DataCell(value('doctor_name')),
        DataCell(value('diagnosed_at')),
        DataCell(Text(_isDoctor ? '勾选后删除' : '-')),
      ];
    }
    if (type == 'DISCHARGE') {
      return [
        DataCell(serial),
        DataCell(value('body_position')),
        DataCell(value('body_site')),
        DataCell(value('diagnosis_name')),
        DataCell(value('diagnosis_note')),
        DataCell(value('diagnosis_code')),
        DataCell(value('t_stage')),
        DataCell(value('n_stage')),
        DataCell(value('m_stage')),
        DataCell(value('admission_condition')),
        DataCell(value('treated')),
        DataCell(value('efficacy')),
        DataCell(value('infectious_disease')),
        DataCell(value('doctor_name')),
        DataCell(value('diagnosed_at')),
      ];
    }
    return [
      DataCell(serial),
      DataCell(value('pathology_no')),
      DataCell(value('body_position')),
      DataCell(value('body_site')),
      DataCell(value('diagnosis_name')),
      DataCell(value('diagnosis_note')),
      DataCell(value('diagnosis_code')),
      DataCell(value('additional_code')),
      DataCell(value('tumor_diagnosis_basis')),
      DataCell(value('pathologist')),
      DataCell(value('pathology_technician')),
      DataCell(Text(_isDoctor ? '勾选后删除' : '-')),
    ];
  }

  Widget _sectionBox(String title, List<Widget> fields,
      {bool fullWidth = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: const BoxDecoration(
        border:
            Border.fromBorderSide(BorderSide(color: WorkstationColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: WorkstationColors.heading,
            child: Text(title,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: fullWidth ? Column(children: fields) : _fieldGrid(fields),
          ),
        ],
      ),
    );
  }

  Widget _fieldGrid(List<Widget> fields) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1450
            ? 4
            : constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 580
                    ? 2
                    : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: fields
              .map((field) => SizedBox(width: width, child: field))
              .toList(),
        );
      },
    );
  }

  Widget _readOnlyField(String label, String value) {
    return _fieldLayout(
      label,
      TextFormField(
        initialValue: value == '-' ? '' : value,
        enabled: false,
        decoration: const InputDecoration(isDense: true, filled: true),
      ),
    );
  }

  Widget _textField(String label, String key,
      {bool numeric = false, String? suffix, String? hint}) {
    return _fieldLayout(
      label,
      TextFormField(
        controller: _controller(key),
        enabled: _isDoctor,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration:
            InputDecoration(isDense: true, hintText: hint, suffixText: suffix),
      ),
    );
  }

  Widget _choiceField(String label, String key, Map<String, String> options) {
    final value = _controller(key).text;
    return _fieldLayout(
      label,
      DropdownButtonFormField<String>(
        initialValue: options.containsKey(value) ? value : null,
        isDense: true,
        decoration: const InputDecoration(isDense: true),
        items: options.entries
            .map((entry) =>
                DropdownMenuItem(value: entry.key, child: Text(entry.value)))
            .toList(),
        onChanged:
            !_isDoctor ? null : (value) => _controller(key).text = value ?? '',
      ),
    );
  }

  Widget _booleanField(String label, String key) {
    final value = _controller(key).text.toLowerCase();
    return _fieldLayout(
      label,
      DropdownButtonFormField<String>(
        initialValue: value == 'true' || value == 'false' ? value : null,
        isDense: true,
        decoration: const InputDecoration(isDense: true),
        items: const [
          DropdownMenuItem(value: 'true', child: Text('是')),
          DropdownMenuItem(value: 'false', child: Text('否')),
        ],
        onChanged: !_isDoctor
            ? null
            : (selected) => _controller(key).text = selected ?? '',
      ),
    );
  }

  Widget _staffField(String label, String key) {
    if (!_isDoctor) {
      return _readOnlyField(
          label,
          displayValue(
              _home!['${_snakeCase(key).replaceFirst('_id', '')}_name']));
    }
    final selected = _staffIds[key];
    return _fieldLayout(
      label,
      DropdownButtonFormField<int>(
        initialValue: _staff.any((item) => _id(item['user_id']) == selected)
            ? selected
            : null,
        isDense: true,
        decoration: const InputDecoration(isDense: true),
        items: _staff
            .map(
              (item) => DropdownMenuItem(
                value: _id(item['user_id']),
                child: Text('${item['real_name']}（${item['role_code']}）'),
              ),
            )
            .toList(),
        onChanged: !_isDoctor
            ? null
            : (value) => setState(() => _staffIds[key] = value),
      ),
    );
  }

  Widget _fieldLayout(String label, Widget input) {
    return Row(
      children: [
        SizedBox(
          width: 104,
          child: Text(label,
              textAlign: TextAlign.right, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        Expanded(child: input),
      ],
    );
  }

  int _id(dynamic value) => (value as num).toInt();

  String _gender(dynamic value) => value == 'MALE'
      ? '男'
      : value == 'FEMALE'
          ? '女'
          : '-';

  String _age(dynamic value) {
    final text = value?.toString();
    final year = text == null || text.length < 4
        ? null
        : int.tryParse(text.substring(0, 4));
    return year == null ? '-' : '${DateTime.now().year - year}';
  }

  String _diagnosisTitle(String type) => switch (type) {
        'OUTPATIENT' => '门诊诊断',
        'ADMISSION' => '入院诊断',
        'DISCHARGE' => '出院诊断',
        _ => '病理诊断',
      };

  String _snakeCase(String value) => value.replaceAllMapped(
        RegExp(r'[A-Z]'),
        (match) => '_${match.group(0)!.toLowerCase()}',
      );

  static const _fieldKeys = [
    'idType',
    'idCardNo',
    'nationality',
    'ethnicity',
    'occupation',
    'maritalStatus',
    'nativePlaceProvince',
    'nativePlaceCity',
    'birthPlaceProvince',
    'birthPlaceCity',
    'birthPlaceCounty',
    'birthPlaceDetail',
    'currentAddressProvince',
    'currentAddressCity',
    'currentAddressCounty',
    'currentAddressDetail',
    'postalCode',
    'phone',
    'registeredAddressProvince',
    'registeredAddressCity',
    'registeredAddressCounty',
    'registeredAddressDetail',
    'registeredPostalCode',
    'employerName',
    'employerAddress',
    'employerPhone',
    'employerPostalCode',
    'emergencyContactName',
    'emergencyContactRelation',
    'emergencyContactAddress',
    'emergencyContactPhone',
    'aboBloodType',
    'rhBloodType',
    'feeType',
    'insuranceType',
    'admissionSource',
    'admissionCount',
    'dischargeDepartmentId',
    'dischargeBedNo',
    'dischargeMethod',
    'readmissionWithin31Days',
    'interhospitalOperation',
    'qualityControlDate',
    'specialNursingDays',
    'levelOneNursingDays',
    'levelTwoNursingDays',
    'levelThreeNursingDays',
  ];
}
