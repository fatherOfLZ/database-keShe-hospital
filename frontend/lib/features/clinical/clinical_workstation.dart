import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui_helpers.dart';
import '../../core/workstation_ui.dart';
import '../auth/auth_controller.dart';
import 'case_home_page.dart';

/// 参考图片中的临床工作站：左侧菜单始终围绕当前选中的在院患者展开。
class ClinicalWorkstation extends ConsumerStatefulWidget {
  const ClinicalWorkstation({super.key, required this.role});

  final String role;

  @override
  ConsumerState<ClinicalWorkstation> createState() =>
      _ClinicalWorkstationState();
}

class _ClinicalWorkstationState extends ConsumerState<ClinicalWorkstation> {
  List<Map<String, dynamic>> _admissions = [];
  Map<String, dynamic>? _context;
  int? _admissionId;
  // 默认进入病案首页，确保移动端下拉菜单的初始值也属于左侧菜单项。
  String _selectedMenu = 'record_home';
  bool _loading = true;
  String _keyword = '';

  bool get _isNurse => widget.role == 'NURSE';
  bool get _isDoctor => widget.role == 'DOCTOR';

  @override
  void initState() {
    super.initState();
    _loadAdmissions();
  }

  Future<void> _loadAdmissions() async {
    setState(() => _loading = true);
    try {
      final path = _keyword.isEmpty
          ? '/api/v1/workstation/admissions'
          : '/api/v1/workstation/admissions?keyword=${Uri.encodeQueryComponent(_keyword)}';
      final admissions = await ref.read(apiClientProvider).getList(path);
      if (!mounted) {
        return;
      }
      setState(() {
        _admissions = admissions;
        if (_admissionId == null ||
            !_admissions
                .any((item) => _id(item['admission_id']) == _admissionId)) {
          _admissionId = _admissions.isEmpty
              ? null
              : _id(_admissions.first['admission_id']);
        }
      });
      await _loadContext();
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

  Future<void> _loadContext() async {
    final admissionId = _admissionId;
    if (admissionId == null) {
      if (mounted) {
        setState(() => _context = null);
      }
      return;
    }
    try {
      final value = await ref
          .read(apiClientProvider)
          .getObject('/api/v1/workstation/admissions/$admissionId/context');
      if (mounted) {
        setState(() => _context = value);
      }
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  void _refreshPage() {
    _loadContext();
    setState(() {});
  }

  int _id(dynamic value) => (value as num).toInt();

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        _patientSelector(),
        if (_context != null) _contextBanner(),
        Expanded(
          child: _admissionId == null
              ? const Center(child: Text('暂无可操作的在院患者'))
              : desktop
                  ? Row(
                      children: [
                        _clinicalSidebar(),
                        Expanded(child: _workspace()),
                        _rightSidebar(),
                      ],
                    )
                  : Column(
                      children: [
                        _mobileMenu(),
                        Expanded(child: _workspace()),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _patientSelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          const Icon(Icons.people_alt_outlined, color: WorkstationColors.blue),
          const SizedBox(width: 8),
          Text(_isNurse ? '本科室在院患者' : '我的在院患者',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 16),
          SizedBox(
            width: 180,
            child: TextField(
              decoration: const InputDecoration(
                hintText: '姓名、住院号、床位',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (value) {
                _keyword = value.trim();
                _loadAdmissions();
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _admissionId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '当前患者'),
              items: _admissions
                  .map(
                    (item) => DropdownMenuItem(
                      value: _id(item['admission_id']),
                      child: Text(
                        '${item['patient_name']}  |  ${item['inpatient_no']}  |  ${item['bed_no'] ?? '未分配床位'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _admissionId = value);
                  _loadContext();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _contextBanner() {
    final admission = Map<String, dynamic>.from(_context!['admission'] as Map);
    final allergies = List<Map<String, dynamic>>.from(
      (_context!['allergies'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    final facts = <String, String>{
      '住院号': displayValue(admission['inpatient_no']),
      '病案号': displayValue(admission['medical_record_no']),
      '床号': displayValue(admission['bed_no']),
      '住院天数': '${displayValue(admission['stay_days'])} 天',
      '护理等级': displayValue(admission['nursing_level']),
      '科室': displayValue(admission['department_name']),
      '责任医师': displayValue(admission['doctor_name']),
      '预交金': displayValue(_context!['depositBalance']),
      '可用余额': displayValue(_context!['availableBalance']),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      color: WorkstationColors.amber,
      child: Wrap(
        spacing: 20,
        runSpacing: 7,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white70,
                child: Icon(Icons.person, color: WorkstationColors.blue),
              ),
              const SizedBox(width: 8),
              Text(
                '${admission['patient_name']}  ${_gender(admission['gender'])}  ${_age(admission['birth_date'])}岁',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          ...facts.entries.map(
            (entry) => RichText(
              text: TextSpan(
                style:
                    const TextStyle(color: WorkstationColors.ink, fontSize: 13),
                children: [
                  TextSpan(
                      text: '${entry.key}: ',
                      style: const TextStyle(color: WorkstationColors.muted)),
                  TextSpan(
                      text: entry.value,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          if (allergies.isNotEmpty)
            Text(
              '过敏史: ${allergies.map((item) => item['allergen_name']).join('、')}',
              style: const TextStyle(
                  color: Color(0xFFC22E2E), fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }

  String _gender(dynamic value) => value == 'MALE'
      ? '男'
      : value == 'FEMALE'
          ? '女'
          : '-';

  String _age(dynamic birthday) {
    if (birthday == null) {
      return '-';
    }
    final year = int.tryParse(birthday.toString().substring(0, 4));
    return year == null ? '-' : '${DateTime.now().year - year}';
  }

  Widget _clinicalSidebar() {
    return Container(
      width: 212,
      color: WorkstationColors.blue,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: _menuGroups()
            .map(
              (group) => _MenuGroup(
                group: group,
                selected: _selectedMenu,
                onSelected: (value) => setState(() => _selectedMenu = value),
              ),
            )
            .toList(),
      ),
    );
  }

  /// 右侧快捷栏与参考工作站保持固定顺序；尚无后端数据的模块先进入占位工作区。
  Widget _rightSidebar() {
    const items = [
      ('检验', Icons.science_outlined, 'lab_records'),
      ('检查', Icons.image_search_outlined, 'exam_records'),
      ('护理', Icons.health_and_safety_outlined, 'nursing_records'),
      ('医嘱', Icons.medication_outlined, 'orders'),
      ('诊断引用', Icons.link_outlined, 'diagnosis_reference'),
      ('临床仪表', Icons.dashboard_outlined, 'dashboard'),
      ('书写助手', Icons.edit_note_outlined, 'writing_assistant'),
      ('时限控制', Icons.timer_outlined, 'quality'),
    ];
    return Container(
      width: 118,
      color: Colors.white,
      child: Column(
        children: [
          Container(
            height: 42,
            alignment: Alignment.center,
            color: WorkstationColors.heading,
            child: const Text(
              '快捷工具',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ...items.map(
            (item) => InkWell(
              onTap: () => setState(() => _selectedMenu = item.$3),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: _selectedMenu == item.$3
                      ? const Color(0xFFE3F3F8)
                      : Colors.white,
                  border: const Border(
                    bottom: BorderSide(color: WorkstationColors.border),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(item.$2, color: WorkstationColors.blue, size: 21),
                    const SizedBox(height: 5),
                    Text(item.$1, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileMenu() {
    final items = _menuGroups().expand((group) => group.items).toList();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(8),
      child: DropdownButtonFormField<String>(
        value: _selectedMenu,
        decoration: const InputDecoration(labelText: '工作模块'),
        items: items
            .map((item) =>
                DropdownMenuItem(value: item.key, child: Text(item.label)))
            .toList(),
        onChanged: (value) => setState(() => _selectedMenu = value!),
      ),
    );
  }

  List<_MenuGroupData> _menuGroups() {
    final documentItems = <_MenuItemData>[
      const _MenuItemData('record_home', '病案首页', Icons.folder_open_outlined),
      const _MenuItemData(
          'inpatient_record', '住院病历', Icons.assignment_outlined),
      const _MenuItemData('documents', '病程记录', Icons.description_outlined),
      const _MenuItemData(
          'consultation_records', '会诊记录', Icons.groups_outlined),
      const _MenuItemData(
          'discharge_record', '出院记录', Icons.exit_to_app_outlined),
      const _MenuItemData(
          'surgery_anesthesia', '手术麻醉', Icons.medical_services_outlined),
      const _MenuItemData(
          'informed_consent', '知情告知', Icons.fact_check_outlined),
      const _MenuItemData(
          'diagnostic_assessment', '诊疗评估', Icons.assessment_outlined),
      const _MenuItemData('operation_record', '操作记录', Icons.build_outlined),
      const _MenuItemData('batch_print', '批量打印', Icons.print_outlined),
      const _MenuItemData(
          'legal_certificate', '法定医学证明', Icons.verified_outlined),
      const _MenuItemData(
          'other_doctor_document', '其他医生文书', Icons.more_horiz_outlined),
    ];
    final orderItems = <_MenuItemData>[
      const _MenuItemData('orders', '住院医嘱', Icons.receipt_long_outlined),
      const _MenuItemData('pathway', '临床路径', Icons.account_tree_outlined),
      const _MenuItemData('print', '医嘱打印', Icons.print_outlined),
      const _MenuItemData('instructions', '说明录入', Icons.notes_outlined),
      const _MenuItemData(
          'disease_reports', '疾病上报史', Icons.assignment_outlined),
      const _MenuItemData('surgery', '手术查询', Icons.medical_services_outlined),
      const _MenuItemData('reports', '影像查阅', Icons.image_search_outlined),
    ];
    final nursingItems = <_MenuItemData>[
      const _MenuItemData('nursing_records', '护理记录', Icons.edit_note_outlined),
      const _MenuItemData('vitals', '体温单', Icons.monitor_heart_outlined),
      const _MenuItemData(
          'nursing_assessment', '护理评估单', Icons.fact_check_outlined),
      const _MenuItemData(
          'other_nursing', '其他护理文件', Icons.folder_copy_outlined),
      const _MenuItemData(
          'critical_care', '重症特护单', Icons.monitor_heart_outlined),
    ];
    final reportItems = <_MenuItemData>[
      const _MenuItemData('exam_records', '检查记录', Icons.image_search_outlined),
      const _MenuItemData('lab_records', '检验记录', Icons.science_outlined),
      const _MenuItemData(
          'surgery_reports', '手麻报告', Icons.local_hospital_outlined),
      const _MenuItemData('ecg_reports', '心电报告', Icons.monitor_heart_outlined),
    ];
    return [
      _MenuGroupData('医生文书', Icons.article_outlined, documentItems),
      _MenuGroupData('医嘱管理', Icons.medication_outlined, orderItems),
      _MenuGroupData('护理文书', Icons.health_and_safety_outlined, nursingItems),
      _MenuGroupData('报告查询', Icons.folder_shared_outlined, reportItems),
      const _MenuGroupData('诊断录入', Icons.medical_information_outlined, [
        _MenuItemData('diagnoses', '诊断录入', Icons.medical_information_outlined),
      ]),
      const _MenuGroupData('过敏史录入', Icons.warning_amber_outlined, [
        _MenuItemData('allergy_history', '过敏史管理', Icons.history_outlined),
      ]),
    ];
  }

  Widget _workspace() {
    return ColoredBox(
      color: WorkstationColors.canvas,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: switch (_selectedMenu) {
          'dashboard' => _dashboard(),
          'quality' => _quality(),
          'documents' || 'record_home' => _selectedMenu == 'record_home'
              ? CaseHomePage(
                  admissionId: _admissionId!,
                  role: widget.role,
                  onSaved: _refreshPage,
                )
              : _documents(recordHome: false),
          'inpatient_record' ||
          'consultation_records' ||
          'discharge_record' ||
          'surgery_anesthesia' ||
          'informed_consent' ||
          'diagnostic_assessment' ||
          'operation_record' ||
          'batch_print' ||
          'legal_certificate' ||
          'other_doctor_document' =>
            _placeholderModule(_menuLabel(_selectedMenu)),
          'orders' ||
          'instructions' =>
            _orders(instructionOnly: _selectedMenu == 'instructions'),
          'pathway' => _pathway(),
          'print' => _exports(),
          'disease_reports' => _diseaseReports(),
          'surgery' => _surgery(),
          'consultations' => _consultations(),
          'reports' => _reports(),
          'lab_records' ||
          'exam_records' ||
          'nursing_records' =>
            _selectedMenu == 'nursing_records'
                ? _nursingRecords()
                : _placeholderModule(_menuLabel(_selectedMenu)),
          'surgery_reports' ||
          'ecg_reports' ||
          'other_nursing' ||
          'critical_care' =>
            _placeholderModule(_menuLabel(_selectedMenu)),
          'nursing_assessment' => _nursingAssessments(),
          'vitals' => _vitals(),
          'executions' => _executions(),
          'diagnoses' => _diagnoses(),
          'allergy_entry' ||
          'allergy_history' =>
            _allergies(entry: _selectedMenu == 'allergy_entry'),
          'diagnosis_reference' ||
          'writing_assistant' =>
            _placeholderModule(_menuLabel(_selectedMenu)),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  Widget _placeholderModule(String title) {
    return WorkSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkspaceToolbar(
            title: title,
            subtitle: '该模块已预留工作区入口，待接入对应业务接口。',
            actions: [
              IconButton(
                onPressed: _refreshPage,
                tooltip: '刷新',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const Expanded(
            child: Center(
              child: Text('当前参考资料未提供该模块的字段和流程，界面入口已保留。'),
            ),
          ),
        ],
      ),
    );
  }

  String _menuLabel(String key) {
    const labels = {
      'inpatient_record': '住院病历',
      'consultation_records': '会诊记录',
      'discharge_record': '出院记录',
      'surgery_anesthesia': '手术麻醉',
      'informed_consent': '知情告知',
      'diagnostic_assessment': '诊疗评估',
      'operation_record': '操作记录',
      'batch_print': '批量打印',
      'legal_certificate': '法定医学证明',
      'other_doctor_document': '其他医生文书',
      'lab_records': '检验记录',
      'exam_records': '检查记录',
      'surgery_reports': '手麻报告',
      'ecg_reports': '心电报告',
      'other_nursing': '其他护理文件',
      'critical_care': '重症特护单',
      'diagnosis_reference': '诊断引用',
      'writing_assistant': '书写助手',
    };
    return labels[key] ?? key;
  }

  Widget _dashboard() {
    final admissionId = _admissionId!;
    return FutureBuilder<Map<String, dynamic>>(
      future: ref
          .read(apiClientProvider)
          .getObject('/api/v1/workstation/admissions/$admissionId/summary'),
      builder: (context, snapshot) {
        final data = snapshot.data;
        return WorkSurface(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WorkspaceToolbar(
                title: _isNurse ? '护理工作台' : '临床仪表盘',
                subtitle: '住院文书、医嘱、报告和路径待办概览',
                actions: [
                  IconButton(
                      onPressed: _refreshPage,
                      tooltip: '刷新',
                      icon: const Icon(Icons.refresh))
                ],
              ),
              if (snapshot.connectionState != ConnectionState.done)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      _metric('文书数量', data?['documents']),
                      _metric('待签文书', data?['unsignedDocuments'], error: true),
                      _metric('执行中医嘱', data?['openCareOrders']),
                      _metric('已出报告', data?['reports']),
                      _metric('路径待办', data?['pendingPathwayTasks'],
                          error: true),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _metric(String label, dynamic value, {bool error = false}) {
    return SizedBox(
      width: 160,
      child: WorkSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: WorkstationColors.muted)),
            const SizedBox(height: 8),
            Text(
              displayValue(value),
              style: TextStyle(
                color: error ? Colors.red.shade700 : WorkstationColors.blue,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quality() {
    return _futureTable(
      title: '时限质控',
      subtitle: '按入院时间和文书模板时限实时计算，未签名文书会显示待办或逾期。',
      future: ref
          .read(apiClientProvider)
          .getList('/api/v1/workstation/admissions/${_admissionId!}/quality'),
      columns: const [
        'document_code',
        'template_name',
        'due_hours',
        'latest_status',
        'quality_status'
      ],
    );
  }

  Widget _documents({required bool recordHome}) {
    final admissionId = _admissionId!;
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        ref
            .read(apiClientProvider)
            .getList('/api/v1/workstation/admissions/$admissionId/documents'),
        ref
            .read(apiClientProvider)
            .getList('/api/v1/workstation/document-templates?category=DOCTOR'),
      ]),
      builder: (context, snapshot) {
        final documents = snapshot.hasData
            ? List<Map<String, dynamic>>.from(snapshot.data![0] as List)
            : <Map<String, dynamic>>[];
        final templates = snapshot.hasData
            ? List<Map<String, dynamic>>.from(snapshot.data![1] as List)
            : <Map<String, dynamic>>[];
        return WorkSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              WorkspaceToolbar(
                title: recordHome ? '病案首页与文书树' : '病程记录',
                subtitle: '保存草稿、提交、签名、修订和审计均保留可追溯记录。',
                actions: [
                  if (_isDoctor)
                    IconButton(
                      onPressed: templates.isEmpty
                          ? null
                          : () => _createDocument(templates),
                      tooltip: '新增文书',
                      icon: const Icon(Icons.note_add_outlined),
                    ),
                  IconButton(
                      onPressed: _refreshPage,
                      tooltip: '刷新',
                      icon: const Icon(Icons.refresh)),
                ],
              ),
              Expanded(
                child: snapshot.connectionState != ConnectionState.done
                    ? const Center(child: CircularProgressIndicator())
                    : _documentTable(documents),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _documentTable(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const Center(child: Text('当前患者暂无文书，可从右上角新增。'));
    }
    return SingleChildScrollView(
      child: DataTable(
        headingRowColor:
            const WidgetStatePropertyAll(WorkstationColors.heading),
        columns: const [
          DataColumn(label: Text('文书类型')),
          DataColumn(label: Text('标题')),
          DataColumn(label: Text('状态')),
          DataColumn(label: Text('版本')),
          DataColumn(label: Text('记录人')),
          DataColumn(label: Text('记录时间')),
          DataColumn(label: Text('操作')),
        ],
        rows: rows
            .map(
              (row) => DataRow(
                cells: [
                  DataCell(Text(displayValue(
                      row['document_code'] ?? row['record_type']))),
                  DataCell(SizedBox(
                      width: 150,
                      child: Text(displayValue(row['title']),
                          overflow: TextOverflow.ellipsis))),
                  DataCell(_statusText(row['status'])),
                  DataCell(Text(displayValue(row['version_no']))),
                  DataCell(Text(displayValue(row['author_name']))),
                  DataCell(Text(displayValue(row['recorded_at']))),
                  DataCell(_documentActions(row)),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _documentActions(Map<String, dynamic> row) {
    final recordId = _id(row['record_id']);
    return Wrap(
      spacing: 2,
      children: [
        IconButton(
          tooltip: '审计轨迹',
          icon: const Icon(Icons.history, size: 20),
          onPressed: () => _showRows(
              '文书审计轨迹', '/api/v1/workstation/documents/$recordId/audit'),
        ),
        if (_isDoctor && row['status'] == 'DRAFT')
          IconButton(
            tooltip: '提交',
            icon: const Icon(Icons.send_outlined, size: 20),
            onPressed: () =>
                _post('/api/v1/workstation/documents/$recordId/submit', {}),
          ),
        if (_isDoctor && row['status'] == 'SUBMITTED')
          IconButton(
            tooltip: '签名',
            icon: const Icon(Icons.draw_outlined, size: 20),
            onPressed: () => _signDocument(recordId),
          ),
        if (_isDoctor && row['status'] == 'SIGNED')
          IconButton(
            tooltip: '修订',
            icon: const Icon(Icons.edit_note_outlined, size: 20),
            onPressed: () => _reasonPost(
                '/api/v1/workstation/documents/$recordId/revise', '修订文书'),
          ),
        if (_isDoctor &&
            (row['status'] == 'DRAFT' || row['status'] == 'SUBMITTED'))
          IconButton(
            tooltip: '作废',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => _reasonPost(
                '/api/v1/workstation/documents/$recordId/void', '作废文书'),
          ),
      ],
    );
  }

  Widget _orders({required bool instructionOnly}) {
    final admissionId = _admissionId!;
    return WorkSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          WorkspaceToolbar(
            title: instructionOnly ? '医嘱说明录入' : '住院医嘱',
            subtitle: instructionOnly
                ? '查看和维护治疗、护理医嘱的说明信息。'
                : '长期、临时、治疗和护理医嘱的开立、停止与执行。',
            actions: [
              if (_isDoctor)
                IconButton(
                  onPressed: _createCareOrder,
                  tooltip: '新增医嘱',
                  icon: const Icon(Icons.add_circle_outline),
                ),
              IconButton(
                  onPressed: _refreshPage,
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh)),
            ],
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: ref.read(apiClientProvider).getList(
                  '/api/v1/workstation/admissions/$admissionId/care-orders'),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data ?? [];
                if (rows.isEmpty) {
                  return const Center(child: Text('暂无治疗或护理医嘱。'));
                }
                return SingleChildScrollView(
                  child: DataTable(
                    headingRowColor:
                        const WidgetStatePropertyAll(WorkstationColors.heading),
                    columns: const [
                      DataColumn(label: Text('医嘱号')),
                      DataColumn(label: Text('类型')),
                      DataColumn(label: Text('长期/临时')),
                      DataColumn(label: Text('医嘱内容')),
                      DataColumn(label: Text('剂量/途径/频次')),
                      DataColumn(label: Text('状态')),
                      DataColumn(label: Text('操作')),
                    ],
                    rows: rows
                        .map(
                          (row) => DataRow(cells: [
                            DataCell(Text(displayValue(row['order_no']))),
                            DataCell(Text(displayValue(row['order_type']))),
                            DataCell(Text(displayValue(row['order_class']))),
                            DataCell(SizedBox(
                                width: 180,
                                child: Text(displayValue(row['order_name']),
                                    overflow: TextOverflow.ellipsis))),
                            DataCell(Text(
                                '${displayValue(row['dose'])} ${displayValue(row['route'])} ${displayValue(row['frequency'])}')),
                            DataCell(_statusText(row['status'])),
                            DataCell(_careOrderActions(row)),
                          ]),
                        )
                        .toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _careOrderActions(Map<String, dynamic> row) {
    final id = _id(row['care_order_id']);
    if (row['status'] != 'OPEN') {
      return const Text('-');
    }
    return Wrap(
      spacing: 2,
      children: [
        if (_isNurse)
          IconButton(
            tooltip: '执行医嘱',
            icon: const Icon(Icons.task_alt_outlined, size: 20),
            onPressed: () => _post(
                '/api/v1/workstation/care-orders/$id/execute',
                {'resultNote': '已按医嘱执行'}),
          ),
        if (_isDoctor) ...[
          IconButton(
            tooltip: '停止医嘱',
            icon: const Icon(Icons.stop_circle_outlined, size: 20),
            onPressed: () =>
                _reasonPost('/api/v1/workstation/care-orders/$id/stop', '停止医嘱'),
          ),
          IconButton(
            tooltip: '取消医嘱',
            icon: const Icon(Icons.cancel_outlined, size: 20),
            onPressed: () => _reasonPost(
                '/api/v1/workstation/care-orders/$id/cancel', '取消医嘱'),
          ),
        ],
      ],
    );
  }

  Widget _pathway() {
    final admissionId = _admissionId!;
    return _futureTable(
      title: '临床路径',
      subtitle: '入径后从模板复制任务，完成情况与变异原因独立留痕。',
      future: ref
          .read(apiClientProvider)
          .getList('/api/v1/workstation/admissions/$admissionId/pathways'),
      columns: const ['enrollment_id', 'pathway_name', 'status', 'enrolled_at'],
      actions: [
        if (_isDoctor)
          IconButton(
              onPressed: _enrollPathway,
              tooltip: '患者入径',
              icon: const Icon(Icons.playlist_add_outlined)),
      ],
      rowAction: (row) => IconButton(
        tooltip: '查看节点',
        icon: const Icon(Icons.format_list_bulleted, size: 20),
        onPressed: () => _showPathwayTasks(_id(row['enrollment_id'])),
      ),
    );
  }

  Widget _exports() {
    final admissionId = _admissionId!;
    return _futureTable(
      title: '医嘱打印 / PDF 导出',
      subtitle: '已保留正式 PDF 导出任务，当前尚未配置课程项目的打印模板。',
      future: ref
          .read(apiClientProvider)
          .getList('/api/v1/workstation/admissions/$admissionId/exports'),
      columns: const [
        'export_type',
        'status',
        'message',
        'requester_name',
        'requested_at'
      ],
      actions: [
        IconButton(
            onPressed: _requestExport,
            tooltip: '创建导出任务',
            icon: const Icon(Icons.picture_as_pdf_outlined)),
      ],
    );
  }

  Widget _diseaseReports() {
    final admissionId = _admissionId!;
    return _futureTable(
      title: '疾病上报史',
      subtitle: '本地演示草稿、提交、管理员审核和退回流程，不连接真实公共卫生平台。',
      future: ref.read(apiClientProvider).getList(
          '/api/v1/workstation/admissions/$admissionId/disease-reports'),
      columns: const [
        'report_type',
        'disease_name',
        'status',
        'reporter_name',
        'review_note'
      ],
      actions: [
        if (_isDoctor)
          IconButton(
              onPressed: _createDiseaseReport,
              tooltip: '新增疾病上报',
              icon: const Icon(Icons.add_circle_outline)),
      ],
      rowAction: (row) => _diseaseReportActions(row),
    );
  }

  Widget _diseaseReportActions(Map<String, dynamic> row) {
    final id = _id(row['disease_report_id']);
    return Wrap(
      spacing: 2,
      children: [
        if (_isDoctor &&
            (row['status'] == 'DRAFT' || row['status'] == 'RETURNED'))
          IconButton(
            tooltip: '提交审核',
            icon: const Icon(Icons.send_outlined, size: 20),
            onPressed: () =>
                _post('/api/v1/workstation/disease-reports/$id/submit', {}),
          ),
        if (widget.role == 'SUPER_ADMIN' && row['status'] == 'SUBMITTED')
          IconButton(
            tooltip: '审核',
            icon: const Icon(Icons.fact_check_outlined, size: 20),
            onPressed: () => _reviewDiseaseReport(id),
          ),
      ],
    );
  }

  Widget _surgery() {
    final admissionId = _admissionId!;
    return _futureTable(
      title: '手术查询与申请',
      subtitle: '显示当前患者的手术申请、拟手术时间与风险说明。',
      future: ref.read(apiClientProvider).getList(
          '/api/v1/workstation/admissions/$admissionId/surgery-applications'),
      columns: const [
        'surgery_name',
        'surgery_level',
        'planned_at',
        'status',
        'doctor_name'
      ],
      actions: [
        if (_isDoctor)
          IconButton(
              onPressed: _createSurgery,
              tooltip: '新增手术申请',
              icon: const Icon(Icons.add_circle_outline)),
      ],
    );
  }

  Widget _consultations() {
    return _futureTable(
      title: '会诊申请',
      subtitle: '为当前住院患者发起科内、科间或全院会诊，并保留申请原因和处理状态。',
      future: ref.read(apiClientProvider).getList(
          '/api/v1/workstation/admissions/${_admissionId!}/consultations'),
      columns: const [
        'department_name',
        'consultation_type',
        'request_reason',
        'requester_name',
        'requested_at',
        'status',
      ],
      actions: [
        if (_isDoctor)
          IconButton(
            onPressed: _createConsultation,
            tooltip: '发起会诊',
            icon: const Icon(Icons.add_circle_outline),
          ),
      ],
    );
  }

  Widget _reports() {
    return _futureTable(
      title: '报告查阅 / 影像查阅',
      subtitle: '查看检查检验状态、报告结论、结果异常标识和本地附件元数据。',
      future: ref
          .read(apiClientProvider)
          .getList('/api/v1/workstation/admissions/${_admissionId!}/reports'),
      columns: const [
        'order_no',
        'item_name',
        'item_status',
        'report_name',
        'conclusion',
        'attachment_count'
      ],
      rowAction: (row) {
        if (row['report_id'] == null) {
          return const Text('-');
        }
        return IconButton(
          tooltip: '附件',
          icon: const Icon(Icons.attach_file, size: 20),
          onPressed: () => _showRows('报告附件',
              '/api/v1/workstation/reports/${_id(row['report_id'])}/attachments'),
        );
      },
    );
  }

  Widget _nursingAssessments() {
    return _futureTable(
      title: '护理评估',
      subtitle:
          _isNurse ? '记录意识、跌倒、压疮和营养等风险评估，并形成护理措施依据。' : '医师可查阅护理人员完成的风险评估和护理措施。',
      future: ref.read(apiClientProvider).getList(
          '/api/v1/workstation/admissions/${_admissionId!}/nursing-assessments'),
      columns: const [
        'assessment_type',
        'score',
        'risk_level',
        'measures',
        'assessor_name',
        'assessed_at',
        'remark',
      ],
      actions: [
        if (_isNurse)
          IconButton(
            onPressed: _createNursingAssessment,
            tooltip: '新增护理评估',
            icon: const Icon(Icons.add_circle_outline),
          ),
      ],
    );
  }

  Widget _nursingRecords() {
    return _futureTable(
      title: '成人护理记录',
      subtitle: _isNurse ? '护士可记录护理观察、护理措施和出入量。' : '医师可查阅护士已签名的成人护理记录。',
      future: ref.read(apiClientProvider).getList(
          '/api/v1/workstation/admissions/${_admissionId!}/nursing-records'),
      columns: const [
        'record_type',
        'content',
        'pain_score',
        'intake_ml',
        'output_ml',
        'nurse_name',
        'recorded_at'
      ],
      actions: [
        if (_isNurse)
          IconButton(
              onPressed: _createNursingRecord,
              tooltip: '新增护理记录',
              icon: const Icon(Icons.add_circle_outline)),
      ],
    );
  }

  Widget _vitals() {
    return _futureTable(
      title: '生命体征 / 体温单',
      subtitle: '按测量时间排列的体温、脉搏、血压、血氧、疼痛和出入量时间序列。',
      future: ref.read(apiClientProvider).getList(
          '/api/v1/workstation/admissions/${_admissionId!}/temperature-chart'),
      columns: const [
        'measured_at',
        'temperature',
        'pulse',
        'systolic_bp',
        'diastolic_bp',
        'spo2',
        'pain_score',
        'intake_ml',
        'output_ml'
      ],
      actions: [
        if (_isNurse)
          IconButton(
              onPressed: _createVitalSign,
              tooltip: '录入生命体征',
              icon: const Icon(Icons.add_circle_outline)),
        IconButton(
            onPressed: _requestExport,
            tooltip: '导出体温单',
            icon: const Icon(Icons.print_outlined)),
      ],
    );
  }

  Widget _executions() {
    return _futureTable(
      title: '护理执行记录',
      subtitle: '展示已执行医嘱的执行人、时间和结果；执行入口位于住院医嘱页面。',
      future: ref.read(apiClientProvider).getList(
          '/api/v1/workstation/admissions/${_admissionId!}/care-order-executions'),
      columns: const [
        'order_no',
        'order_name',
        'order_type',
        'execution_status',
        'executor_name',
        'executed_at',
        'result_note',
      ],
    );
  }

  Widget _diagnoses() {
    return _futureTable(
      title: '诊断录入',
      subtitle: '按入院、出院等诊断阶段维护；同一阶段只允许一个主要诊断。',
      future: ref
          .read(apiClientProvider)
          .getList('/api/v1/workstation/admissions/${_admissionId!}/diagnoses'),
      columns: const [
        'diagnosis_code',
        'diagnosis_name',
        'diagnosis_type',
        'is_primary',
        'doctor_name',
        'diagnosed_at'
      ],
      actions: [
        if (_isDoctor)
          IconButton(
              onPressed: _createDiagnosis,
              tooltip: '新增诊断',
              icon: const Icon(Icons.add_circle_outline)),
      ],
    );
  }

  Widget _allergies({required bool entry}) {
    final allergies = List<Map<String, dynamic>>.from(
      ((_context?['allergies'] ?? []) as List)
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    return WorkSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          WorkspaceToolbar(
            title: entry ? '过敏录入' : '过敏史管理',
            subtitle: '过敏信息会同步显示在当前患者的顶部风险提示区域。',
            actions: [
              if (_isDoctor)
                IconButton(
                    onPressed: _createAllergy,
                    tooltip: '新增过敏史',
                    icon: const Icon(Icons.add_circle_outline)),
              IconButton(
                  onPressed: _refreshPage,
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh)),
            ],
          ),
          Expanded(
            child: allergies.isEmpty
                ? const Center(child: Text('未记录过敏史。'))
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: JsonTable(
                      rows: allergies,
                      columns: const [
                        'allergen_name',
                        'allergy_type',
                        'result',
                        'severity',
                        'reaction_text'
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _futureTable({
    required String title,
    required String subtitle,
    required Future<List<Map<String, dynamic>>> future,
    required List<String> columns,
    List<Widget> actions = const [],
    Widget Function(Map<String, dynamic> row)? rowAction,
  }) {
    return WorkSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          WorkspaceToolbar(
            title: title,
            subtitle: subtitle,
            actions: [
              ...actions,
              IconButton(
                  onPressed: _refreshPage,
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh)),
            ],
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(apiErrorMessage(snapshot.error!)));
                }
                final rows = snapshot.data ?? [];
                if (rows.isEmpty) {
                  return const Center(child: Text('暂无数据。'));
                }
                return SingleChildScrollView(
                  child: DataTable(
                    headingRowColor:
                        const WidgetStatePropertyAll(WorkstationColors.heading),
                    columns: [
                      ...columns.map((column) =>
                          DataColumn(label: Text(_columnTitle(column)))),
                      if (rowAction != null)
                        const DataColumn(label: Text('操作')),
                    ],
                    rows: rows
                        .map(
                          (row) => DataRow(
                            cells: [
                              ...columns.map(
                                (column) => DataCell(
                                  SizedBox(
                                    width: column.contains('content') ||
                                            column.contains('conclusion')
                                        ? 180
                                        : null,
                                    child: Text(displayValue(row[column]),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                              ),
                              if (rowAction != null) DataCell(rowAction(row)),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusText(dynamic value) {
    final status = displayValue(value);
    final color = switch (status) {
      'SIGNED' ||
      'COMPLETED' ||
      'APPROVED' ||
      'EXECUTED' =>
        Colors.green.shade700,
      'OVERDUE' || 'VOID' || 'CANCELLED' => Colors.red.shade700,
      'SUBMITTED' || 'OPEN' || 'PENDING' => Colors.orange.shade800,
      _ => WorkstationColors.ink,
    };
    return Text(status,
        style: TextStyle(color: color, fontWeight: FontWeight.w700));
  }

  String _columnTitle(String key) {
    const titles = {
      'document_code': '文书类型',
      'template_name': '模板名称',
      'due_hours': '时限(小时)',
      'latest_status': '最新状态',
      'quality_status': '质控状态',
      'enrollment_id': '入径编号',
      'pathway_name': '路径名称',
      'enrolled_at': '入径时间',
      'export_type': '导出类型',
      'requester_name': '申请人',
      'requested_at': '申请时间',
      'report_type': '上报类型',
      'disease_name': '疾病名称',
      'reporter_name': '上报人',
      'review_note': '审核意见',
      'surgery_name': '手术名称',
      'surgery_level': '手术等级',
      'planned_at': '拟手术时间',
      'consultation_type': '会诊类型',
      'request_reason': '申请原因',
      'department_name': '受邀科室',
      'doctor_name': '医师',
      'order_no': '检查单号',
      'item_name': '项目名称',
      'item_status': '项目状态',
      'report_name': '报告名称',
      'conclusion': '结论',
      'attachment_count': '附件数',
      'record_type': '记录类型',
      'assessment_type': '评估项目',
      'score': '评分',
      'risk_level': '风险等级',
      'measures': '护理措施',
      'assessor_name': '评估护士',
      'assessed_at': '评估时间',
      'remark': '备注',
      'content': '记录内容',
      'pain_score': '疼痛',
      'intake_ml': '入量(ml)',
      'output_ml': '出量(ml)',
      'nurse_name': '护士',
      'recorded_at': '记录时间',
      'measured_at': '测量时间',
      'temperature': '体温',
      'pulse': '脉搏',
      'systolic_bp': '收缩压',
      'diastolic_bp': '舒张压',
      'spo2': '血氧',
      'order_name': '医嘱内容',
      'order_type': '医嘱类型',
      'execution_status': '执行状态',
      'executor_name': '执行人',
      'executed_at': '执行时间',
      'result_note': '执行结果',
      'frequency': '频次',
      'diagnosis_code': '诊断编码',
      'diagnosis_name': '诊断名称',
      'diagnosis_type': '诊断阶段',
      'is_primary': '主要诊断',
      'diagnosed_at': '诊断时间',
      'message': '说明',
      'status': '状态',
    };
    return titles[key] ?? key.replaceAll('_', ' ');
  }

  Future<void> _createDocument(List<Map<String, dynamic>> templates) async {
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        var template = templates.first;
        final contentController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('新增医生文书'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: _id(template['template_id']),
                    decoration: const InputDecoration(labelText: '文书模板'),
                    items: templates
                        .map((item) => DropdownMenuItem(
                            value: _id(item['template_id']),
                            child: Text(item['template_name'].toString())))
                        .toList(),
                    onChanged: (value) => setDialogState(() => template =
                        templates.firstWhere(
                            (item) => _id(item['template_id']) == value)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contentController,
                    minLines: 6,
                    maxLines: 10,
                    decoration: const InputDecoration(
                        labelText: '文书内容', hintText: '按模板要求填写临床记录内容'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消')),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, {
                  'templateId': _id(template['template_id']),
                  'content': contentController.text.trim(),
                  'contentJson':
                      jsonEncode({'content': contentController.text.trim()}),
                }),
                child: const Text('保存草稿'),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || (selected['content'] as String).isEmpty) {
      return;
    }
    await _post(
        '/api/v1/workstation/admissions/${_admissionId!}/documents', selected);
  }

  Future<void> _signDocument(int recordId) async {
    final values = await showTextFormDialog(
      context,
      title: '患者意见与医师签名',
      fields: const [FieldSpec('patientOpinion', '患者意见', multiline: true)],
      submitLabel: '确认签名',
    );
    if (values != null) {
      await _post('/api/v1/workstation/documents/$recordId/sign', values);
    }
  }

  Future<void> _createCareOrder() async {
    final values = await showTextFormDialog(
      context,
      title: '新增治疗/护理医嘱',
      fields: const [
        FieldSpec('orderType', '医嘱类型（TREATMENT/NURSING）',
            required: true, initialValue: 'TREATMENT'),
        FieldSpec('orderClass', '长期/临时（LONG_TERM/TEMPORARY）',
            required: true, initialValue: 'LONG_TERM'),
        FieldSpec('name', '医嘱内容', required: true),
        FieldSpec('dose', '剂量'),
        FieldSpec('route', '途径'),
        FieldSpec('frequency', '频次'),
        FieldSpec('instruction', '说明', multiline: true),
      ],
    );
    if (values != null) {
      await _post('/api/v1/workstation/admissions/${_admissionId!}/care-orders',
          values);
    }
  }

  Future<void> _enrollPathway() async {
    try {
      final templates = await ref
          .read(apiClientProvider)
          .getList('/api/v1/workstation/pathway-templates');
      if (!mounted || templates.isEmpty) {
        return;
      }
      final selected = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择临床路径'),
          children: templates
              .map((item) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(
                        context, _id(item['pathway_template_id'])),
                    child: Text(
                        '${item['pathway_name']}  ${item['diagnosis_hint'] ?? ''}'),
                  ))
              .toList(),
        ),
      );
      if (selected != null) {
        await _post('/api/v1/workstation/admissions/${_admissionId!}/pathways',
            {'templateId': selected});
      }
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  Future<void> _showPathwayTasks(int enrollmentId) async {
    final path = '/api/v1/workstation/pathways/$enrollmentId/tasks';
    await _showRows('临床路径节点', path, action: (row) {
      if (!_isDoctor || row['status'] != 'PENDING') {
        return null;
      }
      return IconButton(
        tooltip: '完成节点',
        icon: const Icon(Icons.task_alt_outlined),
        onPressed: () async {
          Navigator.pop(context);
          await _post(
              '/api/v1/workstation/pathway-tasks/${_id(row['pathway_task_id'])}/complete',
              {});
        },
      );
    });
  }

  Future<void> _requestExport() async {
    final values = await showTextFormDialog(
      context,
      title: '创建 PDF 导出任务',
      fields: const [
        FieldSpec('exportType', '导出类型（DOCUMENT/ORDER/TEMPERATURE/DISEASE）',
            required: true, initialValue: 'DOCUMENT')
      ],
      submitLabel: '创建任务',
    );
    if (values != null) {
      await _post(
          '/api/v1/workstation/admissions/${_admissionId!}/exports', values);
    }
  }

  Future<void> _createDiseaseReport() async {
    final values = await showTextFormDialog(
      context,
      title: '新增疾病上报',
      fields: const [
        FieldSpec('reportType', '上报类型编码',
            required: true, initialValue: 'INFECTIOUS'),
        FieldSpec('diseaseName', '疾病名称', required: true),
        FieldSpec('content', '上报内容', required: true, multiline: true),
      ],
    );
    if (values != null) {
      await _post(
          '/api/v1/workstation/admissions/${_admissionId!}/disease-reports',
          values);
    }
  }

  Future<void> _reviewDiseaseReport(int reportId) async {
    final values = await showTextFormDialog(
      context,
      title: '审核疾病上报',
      fields: const [FieldSpec('note', '审核意见', multiline: true)],
      submitLabel: '通过',
    );
    if (values != null) {
      values['approved'] = true;
      await _post(
          '/api/v1/workstation/disease-reports/$reportId/review', values);
    }
  }

  Future<void> _createSurgery() async {
    final values = await showTextFormDialog(
      context,
      title: '新增手术申请',
      fields: const [
        FieldSpec('surgeryName', '手术名称', required: true),
        FieldSpec('surgeryLevel', '手术等级'),
        FieldSpec('diagnosisSummary', '诊断摘要', multiline: true),
        FieldSpec('riskNote', '风险说明', multiline: true),
      ],
    );
    if (values != null) {
      await _post(
          '/api/v1/workstation/admissions/${_admissionId!}/surgery-applications',
          values);
    }
  }

  Future<void> _createConsultation() async {
    final values = await showTextFormDialog(
      context,
      title: '发起会诊申请',
      fields: const [
        FieldSpec('targetDepartmentId', '受邀科室 ID',
            required: true, numeric: true),
        FieldSpec('consultationType', '会诊类型',
            required: true, initialValue: 'INTER_DEPARTMENT'),
        FieldSpec('reason', '会诊原因', required: true, multiline: true),
      ],
    );
    if (values != null) {
      await _post(
        '/api/v1/workstation/admissions/${_admissionId!}/consultations',
        values,
      );
    }
  }

  Future<void> _createNursingRecord() async {
    final values = await showTextFormDialog(
      context,
      title: '新增成人护理记录',
      fields: const [
        FieldSpec('recordType', '记录类型',
            required: true, initialValue: 'ADULT_NURSING'),
        FieldSpec('content', '护理记录', required: true, multiline: true),
        FieldSpec('painScore', '疼痛评分', numeric: true),
        FieldSpec('intakeMl', '入量（ml）', numeric: true, decimal: true),
        FieldSpec('outputMl', '出量（ml）', numeric: true, decimal: true),
      ],
    );
    if (values != null) {
      await _post(
          '/api/v1/workstation/admissions/${_admissionId!}/nursing-records',
          values);
    }
  }

  Future<void> _createNursingAssessment() async {
    final values = await showTextFormDialog(
      context,
      title: '新增护理评估',
      fields: const [
        FieldSpec('assessmentType', '评估项目',
            required: true, initialValue: 'FALL_RISK'),
        FieldSpec('score', '评分', numeric: true, decimal: true),
        FieldSpec('riskLevel', '风险等级', initialValue: 'LOW'),
        FieldSpec('measures', '护理措施', multiline: true),
        FieldSpec('remark', '备注', multiline: true),
      ],
    );
    if (values != null) {
      await _post(
        '/api/v1/workstation/admissions/${_admissionId!}/nursing-assessments',
        values,
      );
    }
  }

  Future<void> _createVitalSign() async {
    final values = await showTextFormDialog(
      context,
      title: '录入生命体征',
      fields: const [
        FieldSpec('temperature', '体温', numeric: true, decimal: true),
        FieldSpec('pulse', '脉搏', numeric: true),
        FieldSpec('respiratoryRate', '呼吸频率', numeric: true),
        FieldSpec('systolicBp', '收缩压', numeric: true),
        FieldSpec('diastolicBp', '舒张压', numeric: true),
        FieldSpec('spo2', '血氧饱和度', numeric: true, decimal: true),
        FieldSpec('painScore', '疼痛评分', numeric: true),
        FieldSpec('consciousness', '意识状态', initialValue: '清醒'),
        FieldSpec('intakeMl', '入量（ml）', numeric: true, decimal: true),
        FieldSpec('outputMl', '出量（ml）', numeric: true, decimal: true),
        FieldSpec('remark', '备注'),
      ],
    );
    if (values != null) {
      await _post('/api/v1/workstation/admissions/${_admissionId!}/vital-signs',
          values);
    }
  }

  Future<void> _createDiagnosis() async {
    final values = await showTextFormDialog(
      context,
      title: '新增诊断',
      fields: const [
        FieldSpec('diagnosisCode', '诊断编码'),
        FieldSpec('diagnosisName', '诊断名称', required: true),
        FieldSpec('diagnosisType', '诊断阶段（ADMISSION/DISCHARGE）',
            required: true, initialValue: 'ADMISSION'),
      ],
    );
    if (values != null) {
      values['primary'] = true;
      await _post(
          '/api/v1/workstation/admissions/${_admissionId!}/diagnoses', values);
    }
  }

  Future<void> _createAllergy() async {
    final admission = Map<String, dynamic>.from(_context!['admission'] as Map);
    final values = await showTextFormDialog(
      context,
      title: '新增过敏史',
      fields: const [
        FieldSpec('allergenName', '过敏原', required: true),
        FieldSpec('allergyType', '过敏类型', required: true, initialValue: 'DRUG'),
        FieldSpec('result', '结果', required: true, initialValue: 'POSITIVE'),
        FieldSpec('severity', '严重程度', initialValue: 'MODERATE'),
        FieldSpec('reaction', '反应描述', multiline: true),
        FieldSpec('remark', '备注'),
      ],
    );
    if (values != null) {
      await _post(
          '/api/v1/patients/${_id(admission['patient_id'])}/allergies', values);
    }
  }

  Future<void> _reasonPost(String path, String title) async {
    final values = await showTextFormDialog(
      context,
      title: title,
      fields: const [
        FieldSpec('reason', '原因', required: true, multiline: true)
      ],
      submitLabel: '确认',
    );
    if (values != null) {
      await _post(path, values);
    }
  }

  Future<void> _post(String path, Map<String, dynamic> data) async {
    try {
      await ref.read(apiClientProvider).postVoid(path, data);
      if (mounted) {
        showOperationMessage(context, '操作已完成。');
        _refreshPage();
      }
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  Future<void> _showRows(
    String title,
    String path, {
    Widget? Function(Map<String, dynamic> row)? action,
  }) async {
    try {
      final rows = await ref.read(apiClientProvider).getList(path);
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 760,
            child: rows.isEmpty
                ? const Center(child: Text('暂无数据。'))
                : SingleChildScrollView(
                    child: Column(
                      children: rows
                          .map(
                            (row) => ListTile(
                              title: Text(row.values
                                  .take(3)
                                  .map(displayValue)
                                  .join('  |  ')),
                              subtitle: Text(row.entries
                                  .skip(3)
                                  .take(4)
                                  .map((entry) =>
                                      '${entry.key}: ${displayValue(entry.value)}')
                                  .join('\n')),
                              trailing: action?.call(row),
                            ),
                          )
                          .toList(),
                    ),
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'))
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }
}

class _MenuGroupData {
  const _MenuGroupData(this.label, this.icon, this.items);

  final String label;
  final IconData icon;
  final List<_MenuItemData> items;
}

class _MenuItemData {
  const _MenuItemData(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}

class _MenuGroup extends StatefulWidget {
  const _MenuGroup(
      {required this.group, required this.selected, required this.onSelected});

  final _MenuGroupData group;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  State<_MenuGroup> createState() => _MenuGroupState();
}

class _MenuGroupState extends State<_MenuGroup> {
  var _expanded = true;

  @override
  Widget build(BuildContext context) {
    final groupSelected =
        widget.group.items.any((item) => item.key == widget.selected);
    return Column(
      children: [
        Material(
          color: groupSelected ? const Color(0xFF007DAB) : Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(widget.group.icon, color: Colors.white, size: 20),
                  const SizedBox(width: 9),
                  Expanded(
                      child: Text(widget.group.label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700))),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.white),
                ],
              ),
            ),
          ),
        ),
        if (_expanded)
          ...widget.group.items.map(
            (item) => Material(
              color: item.key == widget.selected
                  ? const Color(0xFF00A1CE)
                  : Colors.transparent,
              child: InkWell(
                onTap: () => widget.onSelected(item.key),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 10, 12, 10),
                  child: Row(
                    children: [
                      Icon(item.icon, color: const Color(0xFFD3EDF6), size: 17),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(item.label,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13))),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
