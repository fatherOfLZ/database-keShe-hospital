import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui_helpers.dart';
import '../../core/workstation_ui.dart';
import '../auth/auth_controller.dart';
import 'admission_record_page.dart';
import 'case_home_page.dart';
import 'course_record_page.dart';
import 'disease_report_history_page.dart';
import 'diagnosis_reference_page.dart';
import 'inpatient_order_page.dart';
import 'vital_signs_page.dart';
import 'exam_report_panel.dart';

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
  bool _labPanelOpen = false;
  double? _labPanelWidth;
  bool _examPanelOpen = false;
  double? _examPanelWidth;
  bool _labInpatient = true;
  bool _labCalendarOpen = false;
  DateTime? _labSelectedDate;
  String _labDateLabel = '选择日期';
  String _labReportKeyword = '';
  Future<List<Map<String, dynamic>>>? _labReportsFuture;
  final Set<int> _selectedLabReportIds = <int>{};
  int? _activeLabReportId;
  final Set<int> _selectedLabResultIds = <int>{};
  final Map<String, bool> _labDisplayOptions = {
    '异常指标': false,
    '日期': false,
    '报告名称': true,
    '换行': false,
    '时分': false,
    '全部显示': false,
  };
  bool _orderPanelOpen = false;
  Future<List<Map<String, dynamic>>>? _orderPanelFuture;
  String _orderPanelClass = '';
  String _orderPanelStatus = '';
  String _orderPanelKeyword = '';
  final _orderPanelKeywordController = TextEditingController();
  DateTime? _orderPanelStartDate;
  DateTime? _orderPanelEndDate;
  bool _nursingPanelOpen = false;
  bool _nursingPanelMounted = false;
  String _nursingPanelSection = 'vitals';
  bool _loading = true;
  String _keyword = '';

  bool get _isNurse => widget.role == 'NURSE';
  bool get _isDoctor => widget.role == 'DOCTOR';

  @override
  void initState() {
    super.initState();
    _loadAdmissions();
  }

  @override
  void dispose() {
    _orderPanelKeywordController.dispose();
    super.dispose();
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

  num? _numberValue(dynamic value) {
    if (value is num) {
      return value;
    }
    return value == null ? null : num.tryParse(value.toString());
  }

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
                        Expanded(child: _workspaceWithTools()),
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

  /// 中间工作区保持原尺寸，检验抽屉叠加在其右侧，避免改变左侧菜单和主页面布局。
  Widget _workspaceWithTools() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maximum = constraints.maxWidth;
        final initialWidth = maximum * 0.5;
        final labWidth = (_labPanelWidth ?? initialWidth)
            .clamp(360.0, maximum - 120.0)
            .toDouble();
        final examWidth = (_examPanelWidth ?? initialWidth)
            .clamp(360.0, maximum - 120.0)
            .toDouble();
        return Stack(
          fit: StackFit.expand,
          children: [
            _workspace(),
            if (_labPanelOpen)
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                width: labWidth,
                child: _labPanel(labWidth, maximum),
              ),
            if (_examPanelOpen)
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                width: examWidth,
                child: _examPanel(examWidth, maximum),
              ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_orderPanelOpen,
                child: AnimatedSlide(
                  offset: _orderPanelOpen ? Offset.zero : const Offset(1, 0),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: _orderPanel(),
                ),
              ),
            ),
            if (_nursingPanelMounted)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_nursingPanelOpen,
                  child: AnimatedSlide(
                    offset: _nursingPanelOpen
                        ? Offset.zero
                        : const Offset(1, 0),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: _nursingPanel(),
                  ),
                ),
              ),
          ],
        );
      },
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
                  setState(() {
                    _admissionId = value;
                    _selectedLabReportIds.clear();
                    _activeLabReportId = null;
                    if (_labPanelOpen) {
                      _labReportsFuture = ref.read(apiClientProvider).getList(
                          '/api/v1/workstation/admissions/$value/reports');
                    }
                    if (_orderPanelOpen) {
                      _orderPanelFuture = _loadOrderPanel();
                    }
                  });
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
    final allergyNames = allergies
        .map((item) => _contextValue(item['allergen_name']))
        .where((name) => name != '--')
        .join('、');
    final facts = <(String, String)>[
      ('联系方式', _contextValue(admission['phone'])),
      (
        '身高/体重',
        '${_measurement(admission['height_cm'], 'cm')} / '
            '${_measurement(admission['weight_kg'], 'kg')}'
      ),
      ('患者编号', _contextValue(admission['patient_no'])),
      ('住院号', _contextValue(admission['inpatient_no'])),
      ('病案号', _contextValue(admission['medical_record_no'])),
      ('床号', _contextValue(admission['bed_no'])),
      ('住院天数', '${_contextValue(admission['stay_days'])} 天'),
      ('护理等级', _nursingLevel(admission['nursing_level'])),
      ('科室', _contextValue(admission['department_name'])),
      ('责任医师', _contextValue(admission['doctor_name'])),
      ('过敏史', allergyNames.isEmpty ? '未登记' : allergyNames),
      ('入院时间', _contextDate(admission['admission_time'])),
      ('预交金', _contextValue(_context!['depositBalance'])),
      ('费别', _feeType(admission['fee_type'])),
      ('医保类型', _contextValue(admission['insurance_type'])),
      ('可用余额', _contextValue(_context!['availableBalance'])),
    ];
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
                '${_contextValue(admission['patient_name'])}  '
                '${_gender(admission['gender'])}  '
                '${_age(admission['birth_date'])}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          ...facts.map(
            (entry) => RichText(
              text: TextSpan(
                style:
                    const TextStyle(color: WorkstationColors.ink, fontSize: 13),
                children: [
                  TextSpan(
                      text: '${entry.$1}: ',
                      style: const TextStyle(color: WorkstationColors.muted)),
                  TextSpan(
                      text: entry.$2,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _gender(dynamic value) => value == 'MALE'
      ? '男'
      : value == 'FEMALE'
          ? '女'
          : '--';

  String _age(dynamic birthday) {
    final date = DateTime.tryParse(birthday?.toString() ?? '');
    if (date == null) {
      return '--';
    }
    final now = DateTime.now();
    var age = now.year - date.year;
    if (now.month < date.month ||
        (now.month == date.month && now.day < date.day)) {
      age--;
    }
    return '$age岁';
  }

  String _contextValue(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '--' : text;
  }

  String _measurement(dynamic value, String unit) {
    final text = _contextValue(value);
    return text == '--' ? text : '$text$unit';
  }

  String _contextDate(dynamic value) {
    final text = _contextValue(value);
    if (text == '--') {
      return text;
    }
    final normalized = text.replaceFirst('T', ' ');
    return normalized.length > 16 ? normalized.substring(0, 16) : normalized;
  }

  String _nursingLevel(dynamic value) => switch (value) {
        'LEVEL_1' => '一级护理',
        'LEVEL_2' => '二级护理',
        'LEVEL_3' => '三级护理',
        _ => _contextValue(value),
      };

  String _feeType(dynamic value) => switch (value) {
        'SELF_PAY' => '自费',
        'INSURED' => '医保',
        _ => _contextValue(value),
      };

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
                onSelected: (value) {
                  if (value == 'exam_records') {
                    _openExamPanel();
                  } else {
                    setState(() {
                      if (value == 'vitals') {
                        _labPanelOpen = false;
                        _orderPanelOpen = false;
                        _examPanelOpen = false;
                      }
                      _nursingPanelOpen = false;
                      _selectedMenu = value;
                    });
                  }
                },
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
      ('护理', Icons.health_and_safety_outlined, 'vitals'),
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
              onTap: () {
                if (item.$3 == 'lab_records') {
                  _openLabPanel();
                } else if (item.$3 == 'exam_records') {
                  _openExamPanel();
                } else if (item.$3 == 'orders') {
                  _openOrderPanel();
                } else if (item.$3 == 'vitals') {
                  _openNursingPanel();
                } else {
                  setState(() {
                    _labPanelOpen = false;
                    _orderPanelOpen = false;
                    _examPanelOpen = false;
                    _nursingPanelOpen = false;
                    _selectedMenu = item.$3;
                  });
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: (item.$3 == 'lab_records' && _labPanelOpen) ||
                          (item.$3 == 'exam_records' && _examPanelOpen) ||
                          (item.$3 == 'orders' && _orderPanelOpen) ||
                          (item.$3 == 'vitals' && _nursingPanelOpen) ||
                          _selectedMenu == item.$3
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

  void _openLabPanel() {
    setState(() {
      _orderPanelOpen = false;
      _examPanelOpen = false;
      _nursingPanelOpen = false;
      _labPanelOpen = true;
      _labReportsFuture = ref
          .read(apiClientProvider)
          .getList('/api/v1/workstation/admissions/${_admissionId!}/reports');
    });
  }

  void _closeLabPanel() {
    setState(() => _labPanelOpen = false);
  }

  void _openOrderPanel() {
    setState(() {
      _labPanelOpen = false;
      _examPanelOpen = false;
      _nursingPanelOpen = false;
      _orderPanelOpen = true;
      _orderPanelFuture = _loadOrderPanel();
    });
  }

  void _closeOrderPanel() {
    setState(() => _orderPanelOpen = false);
  }

  void _openExamPanel() {
    setState(() {
      _labPanelOpen = false;
      _orderPanelOpen = false;
      _nursingPanelOpen = false;
      _examPanelOpen = true;
    });
  }

  void _closeExamPanel() {
    setState(() => _examPanelOpen = false);
  }

  void _openNursingPanel() {
    setState(() {
      _labPanelOpen = false;
      _examPanelOpen = false;
      _orderPanelOpen = false;
      _nursingPanelSection = 'vitals';
      _nursingPanelMounted = true;
      _nursingPanelOpen = true;
    });
  }

  void _closeNursingPanel() {
    setState(() => _nursingPanelOpen = false);
  }

  void _resizeExamPanel(double delta, double maximum) {
    final current = _examPanelWidth ?? maximum * 0.5;
    final next = (current - delta).clamp(360.0, maximum - 120.0).toDouble();
    setState(() => _examPanelWidth = next);
  }

  Widget _examPanel(double width, double maximum) {
    return Material(
      elevation: 12,
      color: Colors.white,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: WorkstationColors.border, width: 2),
                ),
              ),
              child: ExamReportPanel(
                key: ValueKey('exam-panel-$_admissionId'),
                admissionId: _admissionId!,
                role: widget.role,
                onClose: _closeExamPanel,
              ),
            ),
          ),
          Positioned(
            left: -5,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) =>
                    _resizeExamPanel(details.delta.dx, maximum),
                child: const SizedBox(width: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nursingPanel() {
    const items = [
      ('nursing_records', '护理记录', Icons.edit_note_outlined),
      ('vitals', '体征', Icons.monitor_heart_outlined),
      ('nursing_assessment', '护理评估单', Icons.fact_check_outlined),
      ('other_nursing', '其他护理文件', Icons.folder_copy_outlined),
      ('critical_care', '重症特护单', Icons.health_and_safety_outlined),
    ];
    final selected = items.firstWhere(
      (item) => item.$1 == _nursingPanelSection,
      orElse: () => items[1],
    );
    return Material(
      elevation: 14,
      color: Colors.white,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: WorkstationColors.border, width: 2),
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: WorkstationColors.border),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.health_and_safety_outlined,
                    color: WorkstationColors.blue,
                  ),
                  const SizedBox(width: 8),
                  Text('护理', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭护理抽屉',
                    onPressed: _closeNursingPanel,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 176,
                    color: const Color(0xFFF8FAFB),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: items
                          .map(
                            (item) => _nursingPanelItem(
                              section: item.$1,
                              label: item.$2,
                              icon: item.$3,
                              selected: item.$1 == _nursingPanelSection,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: WorkstationColors.border,
                  ),
                  Expanded(
                    child: _nursingPanelSection == 'vitals'
                        ? _vitals()
                        : _nursingPanelPlaceholder(
                            label: selected.$2,
                            icon: selected.$3,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nursingPanelItem({
    required String section,
    required String label,
    required IconData icon,
    required bool selected,
  }) {
    return Material(
      color: selected ? const Color(0xFFE3F3F8) : Colors.transparent,
      child: InkWell(
        key: ValueKey('nursing-drawer-$section'),
        onTap: () => setState(() => _nursingPanelSection = section),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? WorkstationColors.cyan : Colors.transparent,
                width: 3,
              ),
              bottom: const BorderSide(color: WorkstationColors.border),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? WorkstationColors.blue : WorkstationColors.muted,
                size: 19,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? WorkstationColors.blue : WorkstationColors.ink,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
              if (section != 'vitals')
                const Icon(
                  Icons.lock_outline,
                  size: 15,
                  color: WorkstationColors.muted,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nursingPanelPlaceholder({
    required String label,
    required IconData icon,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: WorkstationColors.muted),
          const SizedBox(height: 12),
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            '该功能入口已预留，暂未开放业务页面。',
            style: TextStyle(color: WorkstationColors.muted),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadOrderPanel() {
    final parameters = <String>[];
    if (_orderPanelClass.isNotEmpty) {
      parameters.add('orderClass=${Uri.encodeQueryComponent(_orderPanelClass)}');
    }
    if (_orderPanelStatus.isNotEmpty) {
      parameters.add('status=${Uri.encodeQueryComponent(_orderPanelStatus)}');
    }
    final query = parameters.isEmpty ? '' : '?${parameters.join('&')}';
    return ref.read(apiClientProvider).getList(
        '/api/v1/workstation/admissions/${_admissionId!}/care-orders$query');
  }

  void _reloadOrderPanel() {
    if (!_orderPanelOpen) {
      return;
    }
    setState(() => _orderPanelFuture = _loadOrderPanel());
  }

  void _resizeLabPanel(double delta, double maximum) {
    final current = (_labPanelWidth ?? maximum * 0.5);
    final next = (current - delta).clamp(360.0, maximum - 120.0).toDouble();
    setState(() => _labPanelWidth = next);
  }

  Widget _labPanel(double width, double maximum) {
    return Material(
      elevation: 12,
      color: Colors.white,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  left: BorderSide(color: WorkstationColors.border, width: 2),
                ),
              ),
              child: Column(
                children: [
                  Expanded(child: _labPanelContent()),
                ],
              ),
            ),
          ),
          Positioned(
            left: -5,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) =>
                    _resizeLabPanel(details.delta.dx, maximum),
                child: const SizedBox(width: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _labPanelContent() {
    return Column(
      children: [
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: WorkstationColors.border)),
          ),
          child: Row(
            children: [
              _labTab('住院检验', _labInpatient, () {
                setState(() => _labInpatient = true);
              }),
              _labTab('门诊检验', !_labInpatient, () {
                setState(() => _labInpatient = false);
              }),
              const Spacer(),
              IconButton(
                onPressed: _closeLabPanel,
                tooltip: '关闭检验面板',
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
        ),
        _labFilters(),
        Expanded(flex: 4, child: _labReportTable()),
        _labBottomActions(),
        Expanded(flex: 5, child: _labResultTable()),
      ],
    );
  }

  Widget _labTab(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? WorkstationColors.cyan : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? WorkstationColors.blue : WorkstationColors.muted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _labFilters() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 5),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: WorkstationColors.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  setState(() => _labCalendarOpen = !_labCalendarOpen);
                },
                icon: const Icon(Icons.calendar_month_outlined, size: 17),
                label: Text(_labDateLabel),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '报告名称',
                      prefixIcon: Icon(Icons.search, size: 17),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    ),
                    onChanged: (value) {
                      setState(() => _labReportKeyword = value.trim());
                    },
                  ),
                ),
              ),
              IconButton(
                constraints:
                    const BoxConstraints.tightFor(width: 32, height: 32),
                padding: EdgeInsets.zero,
                onPressed: () => setState(() {
                  _labReportsFuture = ref.read(apiClientProvider).getList(
                      '/api/v1/workstation/admissions/${_admissionId!}/reports');
                }),
                tooltip: '刷新报告',
                icon: const Icon(Icons.refresh, size: 19),
              ),
            ],
          ),
          if (_labCalendarOpen) ...[
            const SizedBox(height: 6),
            Container(
              height: 300,
              decoration: const BoxDecoration(
                border: Border.fromBorderSide(
                  BorderSide(color: WorkstationColors.border),
                ),
              ),
              child: CalendarDatePicker(
                initialDate: _labSelectedDate ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
                onDateChanged: (value) {
                  setState(() {
                    _labSelectedDate = value;
                    _labDateLabel = _dateText(value);
                    _labCalendarOpen = false;
                  });
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _dateText(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  Widget _labReportTable() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _labReportsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(apiErrorMessage(snapshot.error!)));
        }
        final reports =
            (snapshot.data ?? const <Map<String, dynamic>>[]).where((row) {
          final reportName =
              '${row['report_name'] ?? row['item_name'] ?? ''}'.toLowerCase();
          final reportedAt = '${row['reported_at'] ?? ''}';
          final nameMatches = _labReportKeyword.isEmpty ||
              reportName.contains(_labReportKeyword.toLowerCase());
          final dateMatches = _labSelectedDate == null ||
              reportedAt.startsWith(_dateText(_labSelectedDate!));
          return nameMatches && dateMatches;
        }).toList();
        return Column(
          children: [
            Container(
              height: 44,
              color: WorkstationColors.heading,
              child: const Row(
                children: [
                  SizedBox(width: 48, child: Center(child: Text(''))),
                  Expanded(
                    flex: 2,
                    child: Center(child: Text('报告日期')),
                  ),
                  Expanded(
                    flex: 3,
                    child: Center(child: Text('报告名称')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: reports.isEmpty
                  ? const Center(
                      child: Text(
                        '暂无数据',
                        style: TextStyle(
                          color: Color(0xFFC62828),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: reports.length,
                      itemBuilder: (context, index) {
                        final row = reports[index];
                        final reportId = (row['report_id'] as num?)?.toInt();
                        final selected = reportId != null &&
                            _selectedLabReportIds.contains(reportId);
                        return InkWell(
                          onTap: () {
                            if (reportId == null) return;
                            setState(() {
                              if (selected) {
                                _selectedLabReportIds.remove(reportId);
                                if (_activeLabReportId == reportId) {
                                  _activeLabReportId = null;
                                }
                              } else {
                                _selectedLabReportIds.add(reportId);
                                _activeLabReportId = reportId;
                              }
                            });
                          },
                          child: Container(
                            height: 48,
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom:
                                    BorderSide(color: WorkstationColors.border),
                              ),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 48,
                                  child: Checkbox(
                                    value: selected,
                                    onChanged: reportId == null
                                        ? null
                                        : (value) => setState(() {
                                              if (value == true) {
                                                _selectedLabReportIds
                                                    .add(reportId);
                                                _activeLabReportId = reportId;
                                              } else {
                                                _selectedLabReportIds
                                                    .remove(reportId);
                                                if (_activeLabReportId ==
                                                    reportId) {
                                                  _activeLabReportId = null;
                                                }
                                              }
                                            }),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    displayValue(row['reported_at']),
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    displayValue(
                                        row['report_name'] ?? row['item_name']),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _labBottomActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: WorkstationColors.border)),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ..._labDisplayOptions.keys.map(_labOption),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _selectedLabReportIds.isEmpty ? null : () {},
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('报告单'),
          ),
          OutlinedButton.icon(
            onPressed: _selectedLabReportIds.isEmpty ? null : () {},
            icon: const Icon(Icons.show_chart, size: 18),
            label: const Text('趋势图'),
          ),
          OutlinedButton.icon(
            onPressed: _selectedLabReportIds.isEmpty ? null : () {},
            icon: const Icon(Icons.reply_outlined, size: 18),
            label: const Text('引用'),
          ),
        ],
      ),
    );
  }

  Widget _labResultTable() {
    final reportId = _activeLabReportId;
    if (reportId == null) {
      return _emptyLabResultTable('选择一份检验报告后查看指标明细');
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ref
          .read(apiClientProvider)
          .getList('/api/v1/workstation/reports/$reportId/results'),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(apiErrorMessage(snapshot.error!)));
        }
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        if (rows.isEmpty) {
          return _emptyLabResultTable('暂无指标明细');
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 920,
            child: SingleChildScrollView(
              child: DataTable(
                headingRowColor:
                    const WidgetStatePropertyAll(WorkstationColors.heading),
                columnSpacing: 16,
                columns: const [
                  DataColumn(label: SizedBox(width: 34)),
                  DataColumn(label: Text('序号')),
                  DataColumn(label: Text('细项名称')),
                  DataColumn(label: Text('定量')),
                  DataColumn(label: Text('定性')),
                  DataColumn(label: Text('提示')),
                  DataColumn(label: Text('单位')),
                  DataColumn(label: Text('参考范围')),
                  DataColumn(label: Text('编码')),
                ],
                rows: List.generate(
                  rows.length,
                  (index) {
                    final row = rows[index];
                    final resultId = (row['result_id'] as num?)?.toInt();
                    final resultSelected = resultId != null &&
                        _selectedLabResultIds.contains(resultId);
                    final abnormal = displayValue(row['abnormal_flag']);
                    final abnormalText = abnormal == '-' ? '' : abnormal;
                    return DataRow(
                      cells: [
                        DataCell(
                          Checkbox(
                            value: resultSelected,
                            onChanged: resultId == null
                                ? null
                                : (value) => setState(() {
                                      if (value == true) {
                                        _selectedLabResultIds.add(resultId);
                                      } else {
                                        _selectedLabResultIds.remove(resultId);
                                      }
                                    }),
                          ),
                        ),
                        DataCell(Text('${index + 1}')),
                        DataCell(Text(displayValue(row['item_name']))),
                        DataCell(Text(displayValue(row['quantitative_value']))),
                        DataCell(Text(displayValue(row['qualitative_value']))),
                        DataCell(Text(
                          abnormalText,
                          style: TextStyle(
                            color: abnormalText.isEmpty
                                ? null
                                : Colors.red.shade700,
                            fontWeight: FontWeight.w700,
                          ),
                        )),
                        DataCell(Text(displayValue(row['unit']))),
                        DataCell(Text(displayValue(row['reference_range']))),
                        DataCell(Text(displayValue(row['result_code']))),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _emptyLabResultTable(String message) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 920,
        child: DataTable(
          headingRowColor:
              const WidgetStatePropertyAll(WorkstationColors.heading),
          columnSpacing: 16,
          columns: const [
            DataColumn(label: SizedBox(width: 34)),
            DataColumn(label: Text('序号')),
            DataColumn(label: Text('细项名称')),
            DataColumn(label: Text('定量')),
            DataColumn(label: Text('定性')),
            DataColumn(label: Text('提示')),
            DataColumn(label: Text('单位')),
            DataColumn(label: Text('参考范围')),
            DataColumn(label: Text('编码')),
          ],
          rows: [
            DataRow(
              cells: [
                const DataCell(Checkbox(value: false, onChanged: null)),
                DataCell(Text(message)),
                const DataCell(Text('-')),
                const DataCell(Text('-')),
                const DataCell(Text('-')),
                const DataCell(Text('-')),
                const DataCell(Text('-')),
                const DataCell(Text('-')),
                const DataCell(Text('-')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _labOption(String label) {
    final selected = _labDisplayOptions[label] ?? false;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: selected,
          onChanged: (value) {
            setState(() => _labDisplayOptions[label] = value ?? false);
          },
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _orderPanel() {
    return Material(
      elevation: 14,
      color: Colors.white,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: WorkstationColors.border, width: 2),
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: WorkstationColors.border),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.medication_outlined,
                    color: WorkstationColors.blue,
                  ),
                  const SizedBox(width: 8),
                  Text('住院医嘱', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  if (_isDoctor)
                    IconButton(
                      onPressed: () =>
                          _createCareOrder(onSuccess: _reloadOrderPanel),
                      tooltip: '新增医嘱',
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  IconButton(
                    onPressed: _reloadOrderPanel,
                    tooltip: '刷新医嘱',
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    onPressed: _closeOrderPanel,
                    tooltip: '关闭医嘱面板',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            _orderPanelFilters(),
            Expanded(child: _orderPanelTable()),
          ],
        ),
      ),
    );
  }

  Widget _orderPanelFilters() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FBFC),
        border: Border(bottom: BorderSide(color: WorkstationColors.border)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _orderDateFilterButton('开立日期起', _orderPanelStartDate, true),
          _orderDateFilterButton('开立日期止', _orderPanelEndDate, false),
          SizedBox(
            width: 200,
            height: 38,
            child: TextField(
              controller: _orderPanelKeywordController,
              decoration: const InputDecoration(
                isDense: true,
                labelText: '医嘱内容',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              onChanged: (value) {
                setState(() => _orderPanelKeyword = value.trim());
              },
            ),
          ),
          _orderFilterDropdown(
            label: '医嘱类别',
            value: _orderPanelClass,
            options: const {
              '': '全部类别',
              'LONG_TERM': '长期医嘱',
              'TEMPORARY': '临时医嘱',
            },
            onChanged: (value) {
              setState(() => _orderPanelClass = value ?? '');
              _reloadOrderPanel();
            },
          ),
          _orderFilterDropdown(
            label: '医嘱状态',
            value: _orderPanelStatus,
            options: const {
              '': '全部状态',
              'OPEN': '执行中',
              'STOPPED': '已停止',
              'CANCELLED': '已取消',
            },
            onChanged: (value) {
              setState(() => _orderPanelStatus = value ?? '');
              _reloadOrderPanel();
            },
          ),
          IconButton(
            onPressed: _resetOrderPanelFilters,
            tooltip: '清空筛选条件',
            icon: const Icon(Icons.filter_alt_off_outlined),
          ),
        ],
      ),
    );
  }

  Widget _orderDateFilterButton(String label, DateTime? value, bool isStart) {
    return OutlinedButton.icon(
      onPressed: () => _pickOrderDate(isStart),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 38),
        visualDensity: VisualDensity.compact,
      ),
      icon: const Icon(Icons.calendar_month_outlined, size: 17),
      label: Text(value == null ? label : _dateText(value)),
    );
  }

  Widget _orderFilterDropdown({
    required String label,
    required String value,
    required Map<String, String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return SizedBox(
      width: 152,
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$value'),
        initialValue: value,
        isDense: true,
        decoration: InputDecoration(labelText: label),
        items: options.entries
            .map(
              (option) => DropdownMenuItem(
                value: option.key,
                child: Text(option.value),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _pickOrderDate(bool isStart) async {
    final current = isStart ? _orderPanelStartDate : _orderPanelEndDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ??
          (isStart ? _orderPanelEndDate : _orderPanelStartDate) ??
          DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      if (isStart) {
        _orderPanelStartDate = picked;
        if (_orderPanelEndDate != null && picked.isAfter(_orderPanelEndDate!)) {
          _orderPanelEndDate = picked;
        }
      } else {
        _orderPanelEndDate = picked;
        if (_orderPanelStartDate != null &&
            picked.isBefore(_orderPanelStartDate!)) {
          _orderPanelStartDate = picked;
        }
      }
    });
  }

  void _resetOrderPanelFilters() {
    setState(() {
      _orderPanelClass = '';
      _orderPanelStatus = '';
      _orderPanelKeyword = '';
      _orderPanelStartDate = null;
      _orderPanelEndDate = null;
      _orderPanelFuture = _loadOrderPanel();
    });
    _orderPanelKeywordController.clear();
  }

  Widget _orderPanelTable() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _orderPanelFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(apiErrorMessage(snapshot.error!)));
        }
        final rows = (snapshot.data ?? const <Map<String, dynamic>>[])
            .where(_matchesOrderPanelFilters)
            .toList();
        if (rows.isEmpty) {
          return const Center(
            child: Text(
              '暂无符合条件的医嘱。',
              style: TextStyle(color: WorkstationColors.muted),
            ),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 1570),
            child: SingleChildScrollView(
              child: DataTable(
                headingRowColor:
                    const WidgetStatePropertyAll(WorkstationColors.heading),
                columnSpacing: 18,
                horizontalMargin: 16,
                columns: const [
                  DataColumn(label: Text('开立时间')),
                  DataColumn(label: Text('医嘱号')),
                  DataColumn(label: Text('类型')),
                  DataColumn(label: Text('长期/临时')),
                  DataColumn(label: Text('医嘱内容')),
                  DataColumn(label: Text('剂量')),
                  DataColumn(label: Text('途径')),
                  DataColumn(label: Text('频次')),
                  DataColumn(label: Text('开始时间')),
                  DataColumn(label: Text('结束时间')),
                  DataColumn(label: Text('开立医师')),
                  DataColumn(label: Text('状态')),
                  DataColumn(label: Text('操作')),
                ],
                rows: rows
                    .map(
                      (row) => DataRow(
                        cells: [
                          DataCell(Text(_formatOrderDate(row['created_at']))),
                          DataCell(Text(displayValue(row['order_no']))),
                          DataCell(Text(_orderTypeLabel(row['order_type']))),
                          DataCell(Text(_orderClassLabel(row['order_class']))),
                          DataCell(
                            SizedBox(
                              width: 220,
                              child: Text(
                                displayValue(row['order_name']),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(Text(displayValue(row['dose']))),
                          DataCell(Text(displayValue(row['route']))),
                          DataCell(Text(displayValue(row['frequency']))),
                          DataCell(Text(_formatOrderDate(row['start_time']))),
                          DataCell(Text(_formatOrderDate(
                              row['end_time'] ?? row['stopped_at']))),
                          DataCell(Text(displayValue(row['doctor_name']))),
                          DataCell(_orderPanelStatusText(row['status'])),
                          DataCell(
                            _careOrderActions(
                              row,
                              onSuccess: _reloadOrderPanel,
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _matchesOrderPanelFilters(Map<String, dynamic> row) {
    final keyword = _orderPanelKeyword.toLowerCase();
    final searchable =
        '${row['order_name'] ?? ''} ${row['order_no'] ?? ''}'.toLowerCase();
    if (keyword.isNotEmpty && !searchable.contains(keyword)) {
      return false;
    }
    if (_orderPanelStartDate == null && _orderPanelEndDate == null) {
      return true;
    }
    final createdAt = _orderDate(row['created_at']);
    if (createdAt == null) {
      return false;
    }
    final day = DateUtils.dateOnly(createdAt);
    if (_orderPanelStartDate != null &&
        day.isBefore(DateUtils.dateOnly(_orderPanelStartDate!))) {
      return false;
    }
    if (_orderPanelEndDate != null &&
        day.isAfter(DateUtils.dateOnly(_orderPanelEndDate!))) {
      return false;
    }
    return true;
  }

  DateTime? _orderDate(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString().replaceFirst(' ', 'T'));
  }

  String _formatOrderDate(dynamic value) {
    final text = displayValue(value);
    if (text == '-') {
      return text;
    }
    final formatted = text.replaceFirst('T', ' ');
    return formatted.length > 16 ? formatted.substring(0, 16) : formatted;
  }

  String _orderTypeLabel(dynamic value) => switch (value) {
        'TREATMENT' => '治疗医嘱',
        'NURSING' => '护理医嘱',
        _ => displayValue(value),
      };

  String _orderClassLabel(dynamic value) => switch (value) {
        'LONG_TERM' => '长期医嘱',
        'TEMPORARY' => '临时医嘱',
        _ => displayValue(value),
      };

  Widget _orderPanelStatusText(dynamic value) {
    final status = displayValue(value);
    final label = switch (status) {
      'OPEN' => '执行中',
      'STOPPED' => '已停止',
      'CANCELLED' => '已取消',
      _ => status,
    };
    final color = switch (status) {
      'OPEN' => Colors.orange.shade800,
      'CANCELLED' => Colors.red.shade700,
      'STOPPED' => WorkstationColors.muted,
      _ => WorkstationColors.ink,
    };
    return Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w700),
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
          'documents' => CourseRecordPage(
              admissionId: _admissionId!,
              role: widget.role,
            ),
          'record_home' => CaseHomePage(
              admissionId: _admissionId!,
              role: widget.role,
              onSaved: _refreshPage,
            ),
          'inpatient_record' => AdmissionRecordPage(
              admissionId: _admissionId!,
              role: widget.role,
              onChanged: _refreshPage,
            ),
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
          'disease_reports' => DiseaseReportHistoryPage(
              key: ValueKey('disease-report-history-$_admissionId'),
              admissionId: _admissionId!,
              role: widget.role,
              patientContext: _context ?? const {},
              onChanged: _refreshPage,
            ),
          'surgery' => _surgery(),
          'consultations' => _consultations(),
          'reports' => _reports(),
          'exam_records' => ExamReportPanel(
              key: ValueKey('mobile-exam-panel-$_admissionId'),
              admissionId: _admissionId!,
              role: widget.role,
              onClose: () => setState(() => _selectedMenu = 'record_home'),
            ),
          'lab_records' || 'nursing_records' =>
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
          'diagnosis_reference' => DiagnosisReferencePage(
              admissionId: _admissionId!,
            ),
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
    return InpatientOrderPage(
      key: ValueKey('inpatient-orders-${_admissionId!}-$instructionOnly'),
      admissionId: _admissionId!,
      role: widget.role,
      instructionOnly: instructionOnly,
    );
  }

  Widget _careOrderActions(
    Map<String, dynamic> row, {
    VoidCallback? onSuccess,
  }) {
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
                {'resultNote': '已按医嘱执行'},
                onSuccess: onSuccess),
          ),
        if (_isDoctor) ...[
          IconButton(
            tooltip: '停止医嘱',
            icon: const Icon(Icons.stop_circle_outlined, size: 20),
            onPressed: () => _reasonPost(
              '/api/v1/workstation/care-orders/$id/stop',
              '停止医嘱',
              onSuccess: onSuccess,
            ),
          ),
          IconButton(
            tooltip: '取消医嘱',
            icon: const Icon(Icons.cancel_outlined, size: 20),
            onPressed: () => _reasonPost(
              '/api/v1/workstation/care-orders/$id/cancel',
              '取消医嘱',
              onSuccess: onSuccess,
            ),
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
    final admission = _context?['admission'];
    final values = admission is Map ? Map<String, dynamic>.from(admission) : const <String, dynamic>{};
    return VitalSignsPage(
      admissionId: _admissionId!,
      role: widget.role,
      patientHeightCm: _numberValue(values['height_cm']),
      patientWeightKg: _numberValue(values['weight_kg']),
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

  Future<void> _createCareOrder({VoidCallback? onSuccess}) async {
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
          values, onSuccess: onSuccess);
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

  Future<void> _reasonPost(
    String path,
    String title, {
    VoidCallback? onSuccess,
  }) async {
    final values = await showTextFormDialog(
      context,
      title: title,
      fields: const [
        FieldSpec('reason', '原因', required: true, multiline: true)
      ],
      submitLabel: '确认',
    );
    if (values != null) {
      await _post(path, values, onSuccess: onSuccess);
    }
  }

  Future<void> _post(
    String path,
    Map<String, dynamic> data, {
    VoidCallback? onSuccess,
  }) async {
    try {
      await ref.read(apiClientProvider).postVoid(path, data);
      if (mounted) {
        showOperationMessage(context, '操作已完成。');
        onSuccess?.call();
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
