import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/ui_helpers.dart';
import '../../core/workstation_ui.dart';
import '../auth/auth_controller.dart';

/// 当前住院患者的疾病上报历史。页面只保存界面筛选与勾选状态，业务记录始终来自接口。
class DiseaseReportHistoryPage extends ConsumerStatefulWidget {
  const DiseaseReportHistoryPage({
    super.key,
    required this.admissionId,
    required this.role,
    required this.patientContext,
    this.onChanged,
  });

  final int admissionId;
  final String role;
  final Map<String, dynamic> patientContext;
  final VoidCallback? onChanged;

  @override
  ConsumerState<DiseaseReportHistoryPage> createState() =>
      _DiseaseReportHistoryPageState();
}

class _DiseaseReportHistoryPageState
    extends ConsumerState<DiseaseReportHistoryPage> {
  static const _pageSize = 10;

  final _diseaseController = TextEditingController();
  final _reporterController = TextEditingController();
  final Map<int, Map<String, dynamic>> _selectedRows = {};

  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _reportTypes = [];
  String _bucket = 'REPORTED';
  String _reportType = '';
  String _status = '';
  String _printStatus = '';
  DateTimeRange? _registeredRange;
  DateTimeRange? _reviewedRange;
  int _page = 1;
  bool _loading = true;

  bool get _isDoctor => widget.role == 'DOCTOR';
  bool get _isAdministrator => widget.role == 'SUPER_ADMIN';

  Map<String, dynamic> get _admission => Map<String, dynamic>.from(
        widget.patientContext['admission'] as Map? ?? const {},
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DiseaseReportHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.admissionId != widget.admissionId) {
      _clearFilters(reload: false);
      _load();
    }
  }

  @override
  void dispose() {
    _diseaseController.dispose();
    _reporterController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    try {
      final values = await Future.wait(<Future<List<Map<String, dynamic>>>>[
        ref.read(apiClientProvider).getList(
              '/api/v1/workstation/admissions/${widget.admissionId}/disease-reports',
            ),
        ref
            .read(apiClientProvider)
            .getList('/api/v1/workstation/disease-report-types'),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _rows = values.first;
        _reportTypes = values.last;
        _selectedRows.clear();
        _page = 1;
      });
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

  List<Map<String, dynamic>> get _filteredRows {
    final diseaseKeyword = _diseaseController.text.trim().toLowerCase();
    final reporterKeyword = _reporterController.text.trim().toLowerCase();
    return _rows.where((row) {
      final reported = _hasReported(row);
      if (_bucket == 'REPORTED' ? !reported : reported) {
        return false;
      }
      if (_reportType.isNotEmpty && row['report_type'] != _reportType) {
        return false;
      }
      if (_status.isNotEmpty && row['status'] != _status) {
        return false;
      }
      final printed = _printCount(row) > 0;
      if (_printStatus == 'PRINTED' && !printed) {
        return false;
      }
      if (_printStatus == 'UNPRINTED' && printed) {
        return false;
      }
      if (diseaseKeyword.isNotEmpty &&
          !('${row['disease_name'] ?? ''} ${row['report_content'] ?? ''}')
              .toLowerCase()
              .contains(diseaseKeyword)) {
        return false;
      }
      if (reporterKeyword.isNotEmpty &&
          !('${row['reporter_name'] ?? ''}').toLowerCase().contains(reporterKeyword)) {
        return false;
      }
      if (!_withinRange(row['created_at'], _registeredRange) ||
          !_withinRange(row['reviewed_at'], _reviewedRange)) {
        return false;
      }
      return true;
    }).toList();
  }

  bool _hasReported(Map<String, dynamic> row) {
    final value = row['reported_at']?.toString().trim();
    return value != null && value.isNotEmpty && value != 'null';
  }

  int _printCount(Map<String, dynamic> row) {
    final value = row['print_count'];
    return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  }

  bool _withinRange(dynamic raw, DateTimeRange? range) {
    if (range == null) {
      return true;
    }
    final date = _dateValue(raw);
    if (date == null) {
      return false;
    }
    final day = DateUtils.dateOnly(date);
    return !day.isBefore(DateUtils.dateOnly(range.start)) &&
        !day.isAfter(DateUtils.dateOnly(range.end));
  }

  DateTime? _dateValue(dynamic raw) {
    if (raw == null) {
      return null;
    }
    return DateTime.tryParse(raw.toString().replaceFirst(' ', 'T'));
  }

  void _applyFilters() {
    setState(() {
      _page = 1;
      _selectedRows.clear();
    });
  }

  void _clearFilters({bool reload = true}) {
    _diseaseController.clear();
    _reporterController.clear();
    setState(() {
      _bucket = 'REPORTED';
      _reportType = '';
      _status = '';
      _printStatus = '';
      _registeredRange = null;
      _reviewedRange = null;
      _page = 1;
      _selectedRows.clear();
    });
    if (reload) {
      _load();
    }
  }

  Future<void> _pickRange({required bool registered}) async {
    final initial = registered ? _registeredRange : _reviewedRange;
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: initial,
      helpText: registered ? '选择登记时间' : '选择审核时间',
    );
    if (result != null && mounted) {
      setState(() {
        if (registered) {
          _registeredRange = result;
        } else {
          _reviewedRange = result;
        }
        _page = 1;
        _selectedRows.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WorkSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          WorkspaceToolbar(
            title: '疾病上报史',
            actions: [
              if (_isDoctor)
                IconButton(
                  onPressed: _reportTypes.isEmpty ? null : _createReport,
                  tooltip: '新增疾病上报',
                  icon: const Icon(Icons.add_circle_outline),
                ),
              IconButton(
                onPressed: _loading || _outputRows.isEmpty ? null : _exportPdf,
                tooltip: '导出 PDF',
                icon: const Icon(Icons.file_download_outlined),
              ),
              IconButton(
                onPressed: _loading || _outputRows.isEmpty ? null : _printPdf,
                tooltip: '打印',
                icon: const Icon(Icons.print_outlined),
              ),
              IconButton(
                onPressed: _loading ? null : _load,
                tooltip: '刷新',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          _filterBar(),
          const Divider(height: 1),
          Expanded(child: _table()),
          _pager(),
        ],
      ),
    );
  }

  Widget _filterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'REPORTED', label: Text('已上报')),
              ButtonSegment(value: 'UNREPORTED', label: Text('未上报')),
            ],
            selected: {_bucket},
            onSelectionChanged: (value) {
              setState(() {
                _bucket = value.first;
                _page = 1;
                _selectedRows.clear();
              });
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                _filterField(
                  width: _filterWidth(constraints.maxWidth),
                  child: _dateRangeButton(
                    label: '登记时间',
                    value: _registeredRange,
                    onPressed: () => _pickRange(registered: true),
                  ),
                ),
                _filterField(
                  width: _filterWidth(constraints.maxWidth),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('disease-report-type-$_reportType'),
                    value: _reportType,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '上报类型'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('全部')),
                      ..._reportTypes.map(
                        (type) => DropdownMenuItem(
                          value: type['type_code']?.toString() ?? '',
                          child: Text(_display(type['type_name'])),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      _reportType = value ?? '';
                      _page = 1;
                      _selectedRows.clear();
                    }),
                  ),
                ),
                _filterField(
                  width: _filterWidth(constraints.maxWidth),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('disease-report-status-$_status'),
                    value: _status,
                    decoration: const InputDecoration(labelText: '上报状态'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('全部')),
                      ..._statusLabels.entries.map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      _status = value ?? '';
                      _page = 1;
                      _selectedRows.clear();
                    }),
                  ),
                ),
                _filterField(
                  width: _filterWidth(constraints.maxWidth),
                  child: TextField(
                    controller: _diseaseController,
                    decoration: const InputDecoration(
                      labelText: '疾病名称',
                      hintText: '输入疾病名称',
                      prefixIcon: Icon(Icons.search, size: 18),
                    ),
                    onSubmitted: (_) => _applyFilters(),
                  ),
                ),
                _filterField(
                  width: _filterWidth(constraints.maxWidth),
                  child: TextField(
                    controller: _reporterController,
                    decoration: const InputDecoration(
                      labelText: '登记医生',
                      hintText: '输入登记医生',
                      prefixIcon: Icon(Icons.person_search_outlined, size: 18),
                    ),
                    onSubmitted: (_) => _applyFilters(),
                  ),
                ),
                _filterField(
                  width: _filterWidth(constraints.maxWidth),
                  child: _dateRangeButton(
                    label: '审核时间',
                    value: _reviewedRange,
                    onPressed: () => _pickRange(registered: false),
                  ),
                ),
                _filterField(
                  width: _filterWidth(constraints.maxWidth),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('disease-report-print-$_printStatus'),
                    value: _printStatus,
                    decoration: const InputDecoration(labelText: '打印标识'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('全部')),
                      DropdownMenuItem(value: 'PRINTED', child: Text('已打印')),
                      DropdownMenuItem(value: 'UNPRINTED', child: Text('未打印')),
                    ],
                    onChanged: (value) => setState(() {
                      _printStatus = value ?? '';
                      _page = 1;
                      _selectedRows.clear();
                    }),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _applyFilters,
                  icon: const Icon(Icons.search),
                  label: const Text('查询'),
                ),
                IconButton(
                  onPressed: _clearFilters,
                  tooltip: '清空筛选条件',
                  icon: const Icon(Icons.restart_alt),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _filterWidth(double available) => available < 720 ? available : 214;

  Widget _filterField({required double width, required Widget child}) =>
      SizedBox(width: width, child: child);

  Widget _dateRangeButton({
    required String label,
    required DateTimeRange? value,
    required VoidCallback onPressed,
  }) {
    final formatter = DateFormat('yyyy-MM-dd');
    final text = value == null
        ? '选择日期'
        : '${formatter.format(value.start)} ~ ${formatter.format(value.end)}';
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.date_range_outlined, size: 18),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text('$label：$text', overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _table() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final rows = _filteredRows;
    if (rows.isEmpty) {
      return Center(
        child: Text(_bucket == 'REPORTED' ? '暂无已上报记录' : '暂无未上报记录'),
      );
    }
    final pageCount = math.max(1, (rows.length / _pageSize).ceil());
    final currentPage = _page.clamp(1, pageCount);
    final start = (currentPage - 1) * _pageSize;
    final visibleRows = rows.skip(start).take(_pageSize).toList();
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 1510,
          child: SingleChildScrollView(
            child: DataTable(
              showCheckboxColumn: true,
              headingRowColor:
                  const WidgetStatePropertyAll(WorkstationColors.heading),
              horizontalMargin: 12,
              columnSpacing: 18,
              columns: const [
                DataColumn(label: Text('序号')),
                DataColumn(label: Text('上报类型')),
                DataColumn(label: Text('疾病名称')),
                DataColumn(label: Text('状态')),
                DataColumn(label: Text('登记医生')),
                DataColumn(label: Text('登记时间')),
                DataColumn(label: Text('审核医生')),
                DataColumn(label: Text('审核时间')),
                DataColumn(label: Text('审核意见')),
                DataColumn(label: Text('打印标识')),
                DataColumn(label: Text('操作')),
              ],
              rows: [
                for (var index = 0; index < visibleRows.length; index++)
                  _reportRow(visibleRows[index], start + index + 1),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DataRow _reportRow(Map<String, dynamic> row, int sequence) {
    final id = _id(row['disease_report_id']);
    return DataRow(
      selected: _selectedRows.containsKey(id),
      onSelectChanged: (selected) {
        setState(() {
          if (selected == true) {
            _selectedRows[id] = row;
          } else {
            _selectedRows.remove(id);
          }
        });
      },
      cells: [
        DataCell(Text('$sequence')),
        DataCell(_tableText(_reportTypeName(row), width: 118)),
        DataCell(_tableText(_display(row['disease_name']), width: 138)),
        DataCell(_statusBadge(row['status'])),
        DataCell(_tableText(_display(row['reporter_name']), width: 96)),
        DataCell(_tableText(_formatDateTime(row['created_at']), width: 128)),
        DataCell(_tableText(_display(row['reviewer_name']), width: 96)),
        DataCell(_tableText(_formatDateTime(row['reviewed_at']), width: 128)),
        DataCell(_tableText(_display(row['review_note']), width: 160)),
        DataCell(_printBadge(row)),
        DataCell(_rowActions(row)),
      ],
    );
  }

  Widget _tableText(String value, {required double width}) => SizedBox(
        width: width,
        child: Text(value, overflow: TextOverflow.ellipsis),
      );

  Widget _statusBadge(dynamic raw) {
    final status = raw?.toString() ?? '';
    final color = switch (status) {
      'APPROVED' => Colors.green.shade700,
      'SUBMITTED' => Colors.orange.shade800,
      'RETURNED' => Colors.red.shade700,
      _ => WorkstationColors.muted,
    };
    return Text(
      _statusLabels[status] ?? _display(raw),
      style: TextStyle(color: color, fontWeight: FontWeight.w700),
    );
  }

  Widget _printBadge(Map<String, dynamic> row) {
    final printed = _printCount(row) > 0;
    return Text(
      printed ? '已打印' : '未打印',
      style: TextStyle(
        color: printed ? Colors.green.shade700 : WorkstationColors.muted,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _rowActions(Map<String, dynamic> row) {
    final status = row['status']?.toString();
    final id = _id(row['disease_report_id']);
    return SizedBox(
      width: 130,
      child: Row(
        children: [
          IconButton(
            onPressed: () => _showDetail(row),
            tooltip: '查看上报内容',
            icon: const Icon(Icons.visibility_outlined, size: 20),
          ),
          if (_isDoctor && (status == 'DRAFT' || status == 'RETURNED'))
            IconButton(
              onPressed: () => _submitReport(id),
              tooltip: '提交审核',
              icon: const Icon(Icons.send_outlined, size: 20),
            ),
          if (_isAdministrator && status == 'SUBMITTED')
            IconButton(
              onPressed: () => _reviewReport(row),
              tooltip: '审核上报',
              icon: const Icon(Icons.fact_check_outlined, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _pager() {
    final total = _filteredRows.length;
    final pageCount = math.max(1, (total / _pageSize).ceil());
    final currentPage = _page.clamp(1, pageCount);
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: WorkstationColors.border)),
      ),
      child: Row(
        children: [
          Text('共 $total 条，每页 $_pageSize 条'),
          const Spacer(),
          IconButton(
            onPressed: currentPage > 1
                ? () => setState(() => _page = 1)
                : null,
            tooltip: '首页',
            icon: const Icon(Icons.first_page),
          ),
          IconButton(
            onPressed: currentPage > 1
                ? () => setState(() => _page = currentPage - 1)
                : null,
            tooltip: '上一页',
            icon: const Icon(Icons.chevron_left),
          ),
          Text('$currentPage / $pageCount'),
          IconButton(
            onPressed: currentPage < pageCount
                ? () => setState(() => _page = currentPage + 1)
                : null,
            tooltip: '下一页',
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            onPressed: currentPage < pageCount
                ? () => setState(() => _page = pageCount)
                : null,
            tooltip: '末页',
            icon: const Icon(Icons.last_page),
          ),
        ],
      ),
    );
  }

  Future<void> _createReport() async {
    if (_reportTypes.isEmpty) {
      showOperationMessage(context, '暂无可用的疾病上报类型。', error: true);
      return;
    }
    final formKey = GlobalKey<FormState>();
    final disease = TextEditingController();
    final content = TextEditingController();
    var reportType = _reportTypes.first['type_code']?.toString() ?? '';
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新增疾病上报'),
          content: SizedBox(
            width: 460,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: reportType,
                      decoration: const InputDecoration(labelText: '上报类型'),
                      items: _reportTypes
                          .map(
                            (type) => DropdownMenuItem(
                              value: type['type_code']?.toString() ?? '',
                              child: Text(_display(type['type_name'])),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setDialogState(
                        () => reportType = value ?? reportType,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: disease,
                      decoration: const InputDecoration(labelText: '疾病名称'),
                      validator: (value) => value == null || value.trim().isEmpty
                          ? '请填写疾病名称'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: content,
                      maxLines: 5,
                      decoration: const InputDecoration(labelText: '上报内容'),
                      validator: (value) => value == null || value.trim().isEmpty
                          ? '请填写上报内容'
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, {
                    'reportType': reportType,
                    'diseaseName': disease.text.trim(),
                    'content': content.text.trim(),
                  });
                }
              },
              child: const Text('保存草稿'),
            ),
          ],
        ),
      ),
    );
    disease.dispose();
    content.dispose();
    if (values == null) {
      return;
    }
    try {
      await ref.read(apiClientProvider).postVoid(
            '/api/v1/workstation/admissions/${widget.admissionId}/disease-reports',
            values,
          );
      if (mounted) {
        showOperationMessage(context, '疾病上报草稿已保存。');
      }
      widget.onChanged?.call();
      await _load();
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  Future<void> _submitReport(int reportId) async {
    try {
      await ref.read(apiClientProvider).postVoid(
            '/api/v1/workstation/disease-reports/$reportId/submit',
            const {},
          );
      if (mounted) {
        showOperationMessage(context, '疾病上报已提交审核。');
      }
      widget.onChanged?.call();
      await _load();
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  Future<void> _reviewReport(Map<String, dynamic> row) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('审核：${_display(row['disease_name'])}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('退回修改'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('审核通过'),
          ),
        ],
      ),
    );
    if (approved == null || !mounted) {
      return;
    }
    final values = await showTextFormDialog(
      context,
      title: approved ? '填写审核意见' : '填写退回原因',
      fields: [
        FieldSpec(
          'note',
          '审核意见',
          required: !approved,
          multiline: true,
          initialValue: approved ? '审核通过' : '',
        ),
      ],
      submitLabel: approved ? '确认通过' : '确认退回',
    );
    if (values == null) {
      return;
    }
    values['approved'] = approved;
    try {
      await ref.read(apiClientProvider).postVoid(
            '/api/v1/workstation/disease-reports/${_id(row['disease_report_id'])}/review',
            values,
          );
      if (mounted) {
        showOperationMessage(context, approved ? '疾病上报已审核通过。' : '疾病上报已退回。');
      }
      widget.onChanged?.call();
      await _load();
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  Future<void> _showDetail(Map<String, dynamic> row) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_display(row['disease_name'])),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailLine('上报类型', _reportTypeName(row)),
                  _detailLine('状态', _statusLabels[row['status']] ?? _display(row['status'])),
                  _detailLine('登记医生', _display(row['reporter_name'])),
                  _detailLine('登记时间', _formatDateTime(row['created_at'])),
                  _detailLine('审核医生', _display(row['reviewer_name'])),
                  _detailLine('审核时间', _formatDateTime(row['reviewed_at'])),
                  _detailLine('审核意见', _display(row['review_note'])),
                  const SizedBox(height: 14),
                  const Text('上报内容', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(_display(row['report_content'])),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('$label：$value'),
      );

  List<Map<String, dynamic>> get _outputRows => _selectedRows.isNotEmpty
      ? _selectedRows.values.toList()
      : _filteredRows;

  Future<void> _exportPdf() async {
    await _output('EXPORT');
  }

  Future<void> _printPdf() async {
    await _output('PRINT');
  }

  Future<void> _output(String outputType) async {
    final rows = _outputRows;
    if (rows.isEmpty) {
      showOperationMessage(context, '当前没有可输出的疾病上报记录。', error: true);
      return;
    }
    try {
      final bytes = await _buildPdf(PdfPageFormat.a4, rows);
      final fileName = _pdfFileName();
      if (outputType == 'PRINT') {
        await Printing.layoutPdf(name: fileName, onLayout: (_) async => bytes);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: '$fileName.pdf');
      }
      await ref.read(apiClientProvider).postVoid(
            '/api/v1/workstation/admissions/${widget.admissionId}/disease-reports/output-events',
            {
              'reportIds': rows.map((row) => _id(row['disease_report_id'])).toList(),
              'outputType': outputType,
            },
          );
      if (mounted) {
        showOperationMessage(
          context,
          outputType == 'PRINT' ? '打印任务已提交。' : '疾病上报 PDF 已导出。',
        );
      }
      await _load();
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, '无法生成输出文件：${apiErrorMessage(error)}', error: true);
      }
    }
  }

  Future<Uint8List> _buildPdf(
    PdfPageFormat format,
    List<Map<String, dynamic>> rows,
  ) async {
    final regular = await PdfGoogleFonts.notoSansSCRegular();
    final bold = await PdfGoogleFonts.notoSansSCBold();
    final document = pw.Document();
    final admission = _admission;
    document.addPage(
      pw.MultiPage(
        pageFormat: format.landscape,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              '疾病上报史',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Wrap(
            spacing: 14,
            runSpacing: 5,
            children: [
              _pdfFact('姓名', admission['patient_name']),
              _pdfFact('性别', _gender(admission['gender'])),
              _pdfFact('年龄', '${_age(admission['birth_date'])}岁'),
              _pdfFact('住院号', admission['inpatient_no']),
              _pdfFact('病案号', admission['medical_record_no']),
              _pdfFact('科室', admission['department_name']),
              _pdfFact('床号', admission['bed_no']),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text('生成时间：${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: const ['上报类型', '疾病名称', '状态', '登记医生', '登记时间', '审核医生', '审核时间', '打印标识'],
            data: rows
                .map(
                  (row) => [
                    _reportTypeName(row),
                    _display(row['disease_name']),
                    _statusLabels[row['status']] ?? _display(row['status']),
                    _display(row['reporter_name']),
                    _formatDateTime(row['created_at']),
                    _display(row['reviewer_name']),
                    _formatDateTime(row['reviewed_at']),
                    _printCount(row) > 0 ? '已打印' : '未打印',
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 16),
          ...rows.map(
            (row) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(
                      text: '${_display(row['disease_name'])}：',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.TextSpan(text: _display(row['report_content'])),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return document.save();
  }

  pw.Widget _pdfFact(String label, dynamic value) => pw.Text(
        '$label：${_display(value)}',
        style: const pw.TextStyle(fontSize: 9),
      );

  String _pdfFileName() =>
      '疾病上报史_${_display(_admission['inpatient_no'])}_${DateFormat('yyyyMMddHHmm').format(DateTime.now())}';

  String _reportTypeName(Map<String, dynamic> row) =>
      _display(row['report_type_name'] ?? row['report_type']);

  int _id(dynamic value) => value is num ? value.toInt() : int.parse('$value');

  String _display(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text == 'null' ? '-' : text;
  }

  String _formatDateTime(dynamic value) {
    final date = _dateValue(value);
    return date == null ? '-' : DateFormat('yyyy-MM-dd HH:mm').format(date);
  }

  String _gender(dynamic value) => value == 'MALE'
      ? '男'
      : value == 'FEMALE'
          ? '女'
          : '-';

  String _age(dynamic birthday) {
    final date = _dateValue(birthday);
    if (date == null) {
      return '-';
    }
    final today = DateTime.now();
    var years = today.year - date.year;
    if (DateTime(today.year, date.month, date.day).isAfter(today)) {
      years--;
    }
    return '$years';
  }
}

const _statusLabels = <String, String>{
  'DRAFT': '草稿',
  'SUBMITTED': '待审核',
  'APPROVED': '已审核',
  'RETURNED': '已退回',
};
