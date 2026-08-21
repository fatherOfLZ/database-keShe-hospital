import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui_helpers.dart';
import '../../core/workstation_ui.dart';
import '../auth/auth_controller.dart';
import 'report_citation.dart';

/// 参考工作站右侧“检查”抽屉。住院与门诊仅切换数据源，筛选和报告阅读体验保持一致。
class ExamReportPanel extends ConsumerStatefulWidget {
  const ExamReportPanel({
    super.key,
    required this.admissionId,
    required this.role,
    this.onClose,
  });

  final int admissionId;
  final String role;
  final VoidCallback? onClose;

  @override
  ConsumerState<ExamReportPanel> createState() => _ExamReportPanelState();
}

class _ExamReportPanelState extends ConsumerState<ExamReportPanel> {
  late Future<List<Map<String, dynamic>>> _reportsFuture;
  List<Map<String, dynamic>> _outpatientVisits = const [];
  bool _visitsLoading = false;
  bool _inpatient = true;
  int? _outpatientVisitId;
  DateTime? _selectedDate;
  bool _calendarOpen = false;
  final _reportNameController = TextEditingController();
  String _reportNameKeyword = '';
  final Set<int> _selectedReportIds = <int>{};
  final Map<int, Map<String, dynamic>> _selectedReports =
      <int, Map<String, dynamic>>{};
  Map<String, dynamic>? _activeReport;
  Future<List<Map<String, dynamic>>>? _resultsFuture;
  final Map<String, bool> _citationFields = <String, bool>{
    '日期': true,
    '报告名称': true,
    '时分': true,
    '报告单号': false,
  };

  bool get _canCite => widget.role == 'DOCTOR';

  @override
  void initState() {
    super.initState();
    _reportsFuture = _loadInpatientReports();
  }

  @override
  void didUpdateWidget(covariant ExamReportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.admissionId != widget.admissionId) {
      _resetForAdmission();
    }
  }

  @override
  void dispose() {
    _reportNameController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadInpatientReports() {
    return ref.read(apiClientProvider).getList(
          '/api/v1/workstation/admissions/${widget.admissionId}/exam-reports',
        );
  }

  Future<List<Map<String, dynamic>>> _loadOutpatientReports(int visitId) {
    return ref.read(apiClientProvider).getList(
          '/api/v1/workstation/admissions/${widget.admissionId}/outpatient-visits/$visitId/exam-reports',
        );
  }

  Future<List<Map<String, dynamic>>> _loadResults(int reportId) {
    final path = _inpatient
        ? '/api/v1/workstation/admissions/${widget.admissionId}/exam-reports/$reportId/results'
        : '/api/v1/workstation/admissions/${widget.admissionId}/outpatient-exam-reports/$reportId/results';
    return ref.read(apiClientProvider).getList(path);
  }

  void _resetSelections() {
    _selectedReportIds.clear();
    _selectedReports.clear();
    _activeReport = null;
    _resultsFuture = null;
  }

  void _resetForAdmission() {
    setState(() {
      _inpatient = true;
      _outpatientVisits = const [];
      _outpatientVisitId = null;
      _selectedDate = null;
      _calendarOpen = false;
      _reportNameController.clear();
      _reportNameKeyword = '';
      _resetSelections();
      _reportsFuture = _loadInpatientReports();
    });
  }

  Future<void> _loadOutpatientVisits({bool keepSelection = false}) async {
    setState(() {
      _visitsLoading = true;
      if (!keepSelection) {
        _outpatientVisits = const [];
        _outpatientVisitId = null;
      }
    });
    try {
      final visits = await ref.read(apiClientProvider).getList(
            '/api/v1/workstation/admissions/${widget.admissionId}/outpatient-visits',
          );
      if (!mounted || _inpatient) {
        return;
      }
      final hasCurrent = visits.any(
        (visit) => _id(visit['outpatient_visit_id']) == _outpatientVisitId,
      );
      final selectedId = hasCurrent
          ? _outpatientVisitId
          : visits.isEmpty
              ? null
              : _id(visits.first['outpatient_visit_id']);
      setState(() {
        _outpatientVisits = visits;
        _outpatientVisitId = selectedId;
        _reportsFuture = selectedId == null
            ? Future<List<Map<String, dynamic>>>.value(const [])
            : _loadOutpatientReports(selectedId);
      });
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
        setState(() {
          _outpatientVisits = const [];
          _outpatientVisitId = null;
          _reportsFuture = Future<List<Map<String, dynamic>>>.value(const []);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _visitsLoading = false);
      }
    }
  }

  void _switchSource(bool inpatient) {
    if (_inpatient == inpatient) {
      return;
    }
    setState(() {
      _inpatient = inpatient;
      _selectedDate = null;
      _calendarOpen = false;
      _reportNameController.clear();
      _reportNameKeyword = '';
      _resetSelections();
      if (inpatient) {
        _reportsFuture = _loadInpatientReports();
      } else {
        _reportsFuture = Future<List<Map<String, dynamic>>>.value(const []);
      }
    });
    if (!inpatient) {
      _loadOutpatientVisits();
    }
  }

  void _refresh() {
    _resetSelections();
    setState(() {
      if (_inpatient) {
        _reportsFuture = _loadInpatientReports();
      }
    });
    if (!_inpatient) {
      _loadOutpatientVisits(keepSelection: true);
    }
  }

  void _selectOutpatientVisit(int? visitId) {
    if (visitId == null) {
      return;
    }
    setState(() {
      _outpatientVisitId = visitId;
      _resetSelections();
      _reportsFuture = _loadOutpatientReports(visitId);
    });
  }

  int _id(dynamic value) => (value as num).toInt();

  List<Map<String, dynamic>> _filterReports(List<Map<String, dynamic>> rows) {
    return rows.where((row) {
      final name =
          '${row['report_name'] ?? row['item_name'] ?? ''}'.toLowerCase();
      final date = '${row['reported_at'] ?? ''}';
      return (_reportNameKeyword.isEmpty ||
              name.contains(_reportNameKeyword.toLowerCase())) &&
          (_selectedDate == null || date.startsWith(_dateText(_selectedDate!)));
    }).toList();
  }

  String _dateText(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _formatDateTime(dynamic value, {bool includeTime = true}) {
    final text = _text(value);
    if (text.isEmpty) {
      return '-';
    }
    final formatted = text.replaceFirst('T', ' ');
    if (!includeTime && formatted.length >= 10) {
      return formatted.substring(0, 10);
    }
    return formatted.length > 16 ? formatted.substring(0, 16) : formatted;
  }

  String _text(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text == '-' ? '' : text;
  }

  void _toggleReport(Map<String, dynamic> report, bool? checked) {
    final reportId = _id(report['report_id']);
    setState(() {
      if (checked ?? false) {
        _selectedReportIds.add(reportId);
        _selectedReports[reportId] = report;
        _activeReport = report;
        _resultsFuture = _loadResults(reportId);
      } else {
        _selectedReportIds.remove(reportId);
        _selectedReports.remove(reportId);
        if (_activeReport?['report_id'] == reportId) {
          _activeReport = null;
          _resultsFuture = null;
        }
      }
    });
  }

  void _openReportDetail() async {
    final report = _activeReport;
    if (report == null) {
      return;
    }
    try {
      final results = await _loadResults(_id(report['report_id']));
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_text(report['report_name']).isEmpty
              ? '检查报告'
              : _text(report['report_name'])),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailLine('报告日期', _formatDateTime(report['reported_at'])),
                  _detailLine('报告单号', displayValue(report['order_no'])),
                  _detailLine('检查项目', displayValue(report['item_name'])),
                  _detailLine('执行科室', displayValue(report['department_name'])),
                  _detailLine('报告人', displayValue(report['reporter_name'])),
                  const Divider(height: 26),
                  const Text('检查所见',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  SelectableText(_detailText(report['finding_text'])),
                  const SizedBox(height: 16),
                  const Text('诊断结果',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  SelectableText(_detailText(report['conclusion'])),
                  const SizedBox(height: 18),
                  const Text('结果明细',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _resultTable(results, compact: true),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  String _detailText(dynamic value) {
    final text = _text(value);
    return text.isEmpty ? '暂无内容' : text;
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: WorkstationColors.ink),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(color: WorkstationColors.muted),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  void _citeSelectedReports() {
    if (!_canCite || _selectedReports.isEmpty) {
      return;
    }
    final reports = _selectedReports.values.toList()
      ..sort((left, right) =>
          _text(left['reported_at']).compareTo(_text(right['reported_at'])));
    final summary = reports.map(_citationFor).join('\n\n');
    ref.read(pendingReportCitationProvider(widget.admissionId).notifier).state =
        summary;
    showOperationMessage(context, '检查报告已加入下一条病程记录。');
  }

  String _citationFor(Map<String, dynamic> report) {
    final lines = <String>[];
    final reportDate = _formatDateTime(
      report['reported_at'],
      includeTime: _citationFields['时分'] ?? false,
    );
    if (_citationFields['日期'] ?? false) {
      lines.add('报告日期：$reportDate');
    }
    if (_citationFields['报告名称'] ?? false) {
      lines.add('报告名称：${displayValue(report['report_name'])}');
    }
    if (_citationFields['报告单号'] ?? false) {
      lines.add('报告单号：${displayValue(report['order_no'])}');
    }
    final finding = _text(report['finding_text']);
    final conclusion = _text(report['conclusion']);
    if (finding.isNotEmpty) {
      lines.add('检查所见：$finding');
    }
    if (conclusion.isNotEmpty) {
      lines.add('诊断结果：$conclusion');
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Column(
        children: [
          _buildHeader(),
          _buildFilters(),
          Expanded(flex: 4, child: _buildReportList()),
          _buildCitationActions(),
          Expanded(flex: 5, child: _buildReportContent()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: WorkstationColors.border)),
      ),
      child: Row(
        children: [
          _sourceTab('住院检查', _inpatient, () => _switchSource(true),
              key: const ValueKey('exam-source-inpatient')),
          _sourceTab('门诊检查', !_inpatient, () => _switchSource(false),
              key: const ValueKey('exam-source-outpatient')),
          const Spacer(),
          IconButton(
            onPressed: _refresh,
            tooltip: '刷新检查报告',
            icon: const Icon(Icons.refresh, size: 20),
          ),
          if (widget.onClose != null)
            IconButton(
              onPressed: widget.onClose,
              tooltip: '关闭检查面板',
              icon: const Icon(Icons.close, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _sourceTab(
    String label,
    bool selected,
    VoidCallback onTap, {
    Key? key,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? WorkstationColors.cyan : Colors.transparent,
              width: 3,
            ),
          ),
        ),
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

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FBFC),
        border: Border(bottom: BorderSide(color: WorkstationColors.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildVisitSelector()),
              const SizedBox(width: 8),
              SizedBox(
                width: 166,
                height: 36,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _calendarOpen = !_calendarOpen),
                  icon: const Icon(Icons.calendar_month_outlined, size: 17),
                  label: Text(_selectedDate == null
                      ? '选择日期'
                      : _dateText(_selectedDate!)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    key: const ValueKey('exam-report-name-filter'),
                    controller: _reportNameController,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '报告名称',
                      prefixIcon: Icon(Icons.search, size: 18),
                    ),
                    onChanged: (value) =>
                        setState(() => _reportNameKeyword = value.trim()),
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedDate = null;
                    _reportNameController.clear();
                    _reportNameKeyword = '';
                  });
                },
                tooltip: '清空报告筛选条件',
                icon: const Icon(Icons.filter_alt_off_outlined, size: 20),
              ),
            ],
          ),
          if (_calendarOpen) ...[
            const SizedBox(height: 8),
            Container(
              height: 296,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border.fromBorderSide(
                  BorderSide(color: WorkstationColors.border),
                ),
              ),
              child: CalendarDatePicker(
                initialDate: _selectedDate ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
                onDateChanged: (value) => setState(() {
                  _selectedDate = value;
                  _calendarOpen = false;
                }),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVisitSelector() {
    if (_inpatient) {
      return Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border.fromBorderSide(
              BorderSide(color: WorkstationColors.border)),
        ),
        child: const Row(
          children: [
            Icon(Icons.local_hospital_outlined,
                size: 17, color: WorkstationColors.blue),
            SizedBox(width: 6),
            Text('当前住院检查'),
          ],
        ),
      );
    }
    if (_visitsLoading && _outpatientVisits.isEmpty) {
      return const SizedBox(
        height: 36,
        child: Center(child: LinearProgressIndicator(minHeight: 2)),
      );
    }
    return DropdownButtonFormField<int>(
      key: ValueKey('outpatient-visit-$_outpatientVisitId'),
      initialValue: _outpatientVisits.any((visit) =>
              _id(visit['outpatient_visit_id']) == _outpatientVisitId)
          ? _outpatientVisitId
          : null,
      isDense: true,
      decoration: const InputDecoration(
        isDense: true,
        labelText: '门诊就诊记录',
      ),
      items: _outpatientVisits
          .map(
            (visit) => DropdownMenuItem<int>(
              value: _id(visit['outpatient_visit_id']),
              child: Text(
                '${_formatDateTime(visit['visited_at'])} · ${displayValue(visit['department_name'])}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: _outpatientVisits.isEmpty ? null : _selectOutpatientVisit,
    );
  }

  Widget _buildReportList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _reportsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _centerMessage(apiErrorMessage(snapshot.error!), error: true);
        }
        if (!_inpatient && _outpatientVisits.isEmpty) {
          return _centerMessage('暂无门诊检查记录');
        }
        final reports = _filterReports(snapshot.data ?? const []);
        return Column(
          children: [
            Container(
              height: 42,
              color: WorkstationColors.heading,
              child: const Row(
                children: [
                  SizedBox(width: 48),
                  Expanded(flex: 2, child: Center(child: Text('报告日期'))),
                  Expanded(flex: 3, child: Center(child: Text('报告名称'))),
                ],
              ),
            ),
            Expanded(
              child: reports.isEmpty
                  ? _centerMessage('暂无符合条件的检查报告')
                  : ListView.builder(
                      itemCount: reports.length,
                      itemBuilder: (context, index) {
                        final report = reports[index];
                        final reportId = _id(report['report_id']);
                        final checked = _selectedReportIds.contains(reportId);
                        final active = _activeReport?['report_id'] == reportId;
                        return InkWell(
                          key: ValueKey('exam-report-$reportId'),
                          onTap: () => _toggleReport(report, !checked),
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: active
                                  ? const Color(0xFFDDF2F7)
                                  : Colors.white,
                              border: const Border(
                                bottom: BorderSide(
                                  color: WorkstationColors.border,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 48,
                                  child: Checkbox(
                                    value: checked,
                                    onChanged: (value) =>
                                        _toggleReport(report, value),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    _formatDateTime(report['reported_at']),
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    displayValue(report['report_name']),
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

  Widget _centerMessage(String message, {bool error = false}) {
    return Center(
      child: Text(
        message,
        style: TextStyle(
          color: error ? Colors.red.shade700 : WorkstationColors.muted,
          fontWeight: error ? FontWeight.w700 : FontWeight.normal,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildCitationActions() {
    final hasSelection = _selectedReportIds.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: WorkstationColors.border)),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ..._citationFields.keys.map(
            (label) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _citationFields[label],
                  visualDensity: VisualDensity.compact,
                  onChanged: (value) => setState(
                    () => _citationFields[label] = value ?? false,
                  ),
                ),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: _activeReport == null ? null : _openReportDetail,
            icon: const Icon(Icons.description_outlined, size: 17),
            label: const Text('报告单'),
          ),
          Tooltip(
            message: _canCite ? '引用所选报告到下一条病程记录' : '仅医师可以引用报告',
            child: OutlinedButton.icon(
              onPressed: _canCite && hasSelection ? _citeSelectedReports : null,
              icon: const Icon(Icons.reply_outlined, size: 17),
              label: const Text('引用'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportContent() {
    final report = _activeReport;
    if (report == null) {
      return _centerMessage('选择一份检查报告后查看报告内容');
    }
    return DefaultTabController(
      key: ValueKey('exam-detail-${report['report_id']}'),
      length: 3,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 0),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: WorkstationColors.border)),
            ),
            child: Row(
              children: [
                const Text('报告内容',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    displayValue(report['report_name']),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: WorkstationColors.muted),
                  ),
                ),
              ],
            ),
          ),
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: '检查所见'),
              Tab(text: '诊断结果'),
              Tab(text: '结果明细'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _contentText(_detailText(report['finding_text'])),
                _contentText(_detailText(report['conclusion'])),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _resultsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _centerMessage(apiErrorMessage(snapshot.error!),
                          error: true);
                    }
                    final rows = snapshot.data ?? const [];
                    return rows.isEmpty
                        ? _centerMessage('暂无结果明细')
                        : _resultTable(rows);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contentText(String content) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: SelectableText(
        content,
        style: const TextStyle(height: 1.6),
      ),
    );
  }

  Widget _resultTable(List<Map<String, dynamic>> rows, {bool compact = false}) {
    final table = DataTable(
      headingRowColor: const WidgetStatePropertyAll(WorkstationColors.heading),
      horizontalMargin: compact ? 10 : 14,
      columnSpacing: compact ? 16 : 22,
      columns: const [
        DataColumn(label: Text('项目')),
        DataColumn(label: Text('定性')),
        DataColumn(label: Text('定量')),
        DataColumn(label: Text('单位')),
        DataColumn(label: Text('提示')),
        DataColumn(label: Text('参考范围')),
      ],
      rows: rows
          .map(
            (row) => DataRow(
              cells: [
                DataCell(Text(displayValue(row['item_name']))),
                DataCell(Text(displayValue(row['qualitative_value']))),
                DataCell(Text(displayValue(row['quantitative_value']))),
                DataCell(Text(displayValue(row['unit']))),
                DataCell(Text(
                  displayValue(row['abnormal_flag']),
                  style: TextStyle(
                    color: _text(row['abnormal_flag']).isEmpty
                        ? null
                        : Colors.red.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                )),
                DataCell(Text(displayValue(row['reference_range']))),
              ],
            ),
          )
          .toList(),
    );
    return SingleChildScrollView(
      padding: compact ? EdgeInsets.zero : const EdgeInsets.all(8),
      scrollDirection: Axis.horizontal,
      child: table,
    );
  }
}
