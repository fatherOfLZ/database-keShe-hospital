import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/ui_helpers.dart';
import '../../core/workstation_ui.dart';
import '../auth/auth_controller.dart';

/// 左侧菜单“住院医嘱”的主工作区。
///
/// 页面只展示 care_order 中已持久化的字段；截图中没有数据来源的项目
/// 保持为禁用入口，不向页面填充演示数据。
class InpatientOrderPage extends ConsumerStatefulWidget {
  const InpatientOrderPage({
    super.key,
    required this.admissionId,
    required this.role,
    this.instructionOnly = false,
  });

  final int admissionId;
  final String role;
  final bool instructionOnly;

  @override
  ConsumerState<InpatientOrderPage> createState() =>
      _InpatientOrderPageState();
}

class _InpatientOrderPageState extends ConsumerState<InpatientOrderPage> {
  static const _longTerm = 'LONG_TERM';
  static const _temporary = 'TEMPORARY';

  final _keywordController = TextEditingController();
  Future<List<Map<String, dynamic>>>? _ordersFuture;
  String _orderClass = _longTerm;
  bool _onlyOpen = false;
  String _keyword = '';
  DateTime? _startDate;
  DateTime? _endDate;

  bool get _isDoctor => widget.role == 'DOCTOR';
  bool get _isNurse => widget.role == 'NURSE';

  @override
  void initState() {
    super.initState();
    _ordersFuture = _loadOrders();
  }

  @override
  void didUpdateWidget(covariant InpatientOrderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.admissionId != widget.admissionId) {
      _keywordController.clear();
      _keyword = '';
      _startDate = null;
      _endDate = null;
      _onlyOpen = false;
      _orderClass = _longTerm;
      _ordersFuture = _loadOrders();
    }
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadOrders() {
    final parameters = <String>['orderClass=$_orderClass'];
    if (_onlyOpen) {
      parameters.add('status=OPEN');
    }
    return ref.read(apiClientProvider).getList(
          '/api/v1/workstation/admissions/${widget.admissionId}/care-orders?'
          '${parameters.join('&')}',
        );
  }

  void _reloadOrders() {
    setState(() => _ordersFuture = _loadOrders());
  }

  void _selectOrderClass(String value) {
    if (value == _orderClass) {
      return;
    }
    setState(() {
      _orderClass = value;
      _ordersFuture = _loadOrders();
    });
  }

  @override
  Widget build(BuildContext context) {
    return WorkSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          WorkspaceToolbar(
            title: widget.instructionOnly ? '医嘱说明录入' : '住院医嘱',
            actions: [
              IconButton(
                tooltip: '刷新医嘱',
                onPressed: _reloadOrders,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          _orderTabs(),
          _filterBar(),
          _commandBar(),
          Expanded(child: _orderTable()),
        ],
      ),
    );
  }

  Widget _orderTabs() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: WorkstationColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _orderTab(_longTerm, '长期医嘱单'),
            _orderTab(_temporary, '临时医嘱单'),
            _disabledEntry('中药处方'),
            _disabledEntry('检验申请'),
            _disabledEntry('检查申请'),
            _disabledEntry('手术申请'),
            _disabledEntry('出院带药'),
            _disabledEntry('三级抗菌药申请'),
            _disabledEntry('医嘱查询'),
          ],
        ),
      ),
    );
  }

  Widget _orderTab(String value, String label) {
    final selected = value == _orderClass;
    return TextButton(
      onPressed: () => _selectOrderClass(value),
      style: TextButton.styleFrom(
        foregroundColor:
            selected ? Colors.white : WorkstationColors.ink,
        backgroundColor: selected ? WorkstationColors.blue : Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
      ),
      child: Text(label),
    );
  }

  Widget _disabledEntry(String label) {
    return Tooltip(
      message: '$label暂未实现',
      child: TextButton(
        onPressed: null,
        child: Text(label),
      ),
    );
  }

  Widget _filterBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FBFC),
        border: Border(bottom: BorderSide(color: WorkstationColors.border)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _dateFilter('开立日期起', _startDate, true),
          _dateFilter('开立日期止', _endDate, false),
          SizedBox(
            width: 210,
            height: 38,
            child: TextField(
              controller: _keywordController,
              decoration: const InputDecoration(
                isDense: true,
                labelText: '医嘱内容',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              onChanged: (value) => setState(() => _keyword = value.trim()),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                key: const ValueKey('住院医嘱-仅在执行'),
                value: _onlyOpen,
                onChanged: (value) {
                  setState(() {
                    _onlyOpen = value ?? false;
                    _ordersFuture = _loadOrders();
                  });
                },
              ),
              const Text('仅在执行'),
            ],
          ),
          _disabledFilter('药品'),
          _disabledFilter('诊疗'),
          _disabledFilter('当日新增医嘱'),
          IconButton(
            tooltip: '清空医嘱筛选条件',
            onPressed: _resetFilters,
            icon: const Icon(Icons.filter_alt_off_outlined),
          ),
        ],
      ),
    );
  }

  Widget _disabledFilter(String label) {
    return Tooltip(
      message: '$label筛选暂未实现',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Checkbox(value: false, onChanged: null),
          Text(label, style: const TextStyle(color: WorkstationColors.muted)),
        ],
      ),
    );
  }

  Widget _dateFilter(String label, DateTime? value, bool isStart) {
    return OutlinedButton.icon(
      onPressed: () => _pickDate(isStart),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 38),
        visualDensity: VisualDensity.compact,
      ),
      icon: const Icon(Icons.calendar_month_outlined, size: 17),
      label: Text(value == null ? label : _dateText(value)),
    );
  }

  Future<void> _pickDate(bool isStart) async {
    final current = isStart ? _startDate : _endDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: current ?? (isStart ? _endDate : _startDate) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      if (isStart) {
        _startDate = selected;
        if (_endDate != null && selected.isAfter(_endDate!)) {
          _endDate = selected;
        }
      } else {
        _endDate = selected;
        if (_startDate != null && selected.isBefore(_startDate!)) {
          _startDate = selected;
        }
      }
    });
  }

  void _resetFilters() {
    setState(() {
      _keyword = '';
      _startDate = null;
      _endDate = null;
      _onlyOpen = false;
      _ordersFuture = _loadOrders();
    });
    _keywordController.clear();
  }

  Widget _commandBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: WorkstationColors.border)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (_isDoctor)
            FilledButton.icon(
              onPressed: _createOrder,
              icon: const Icon(Icons.add),
              label: const Text('新开'),
            ),
          OutlinedButton.icon(
            onPressed: _reloadOrders,
            icon: const Icon(Icons.refresh),
            label: const Text('刷新'),
          ),
          _disabledCommand('批量操作'),
          _disabledCommand('调用模板'),
          _disabledCommand('历史医嘱引用'),
        ],
      ),
    );
  }

  Widget _disabledCommand(String label) {
    return Tooltip(
      message: '$label暂未实现',
      child: OutlinedButton(onPressed: null, child: Text(label)),
    );
  }

  Widget _orderTable() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _ordersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(apiErrorMessage(snapshot.error!)));
        }
        final rows = _filterRows(snapshot.data ?? const []);
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
            constraints: const BoxConstraints(minWidth: 1730),
            child: SingleChildScrollView(
              child: DataTable(
                headingRowColor:
                    const WidgetStatePropertyAll(WorkstationColors.heading),
                horizontalMargin: 16,
                columnSpacing: 18,
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
                  DataColumn(label: Text('说明')),
                  DataColumn(label: Text('状态')),
                  DataColumn(label: Text('操作')),
                ],
                rows: rows.map(_orderRow).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _filterRows(List<Map<String, dynamic>> rows) {
    final keyword = _keyword.toLowerCase();
    return rows.where((row) {
      if (row['order_class'] != _orderClass) {
        return false;
      }
      final searchable = '${row['order_name'] ?? ''} ${row['order_no'] ?? ''}'
          .toLowerCase();
      if (keyword.isNotEmpty && !searchable.contains(keyword)) {
        return false;
      }
      final createdAt = _asDate(row['created_at']);
      if ((_startDate != null || _endDate != null) && createdAt == null) {
        return false;
      }
      final day = createdAt == null ? null : DateUtils.dateOnly(createdAt);
      if (_startDate != null && day!.isBefore(DateUtils.dateOnly(_startDate!))) {
        return false;
      }
      if (_endDate != null && day!.isAfter(DateUtils.dateOnly(_endDate!))) {
        return false;
      }
      return true;
    }).toList();
  }

  DataRow _orderRow(Map<String, dynamic> row) {
    return DataRow(
      cells: [
        DataCell(Text(_formatDate(row['created_at']))),
        DataCell(Text(_value(row['order_no']))),
        DataCell(Text(_typeLabel(row['order_type']))),
        DataCell(Text(_classLabel(row['order_class']))),
        DataCell(
          SizedBox(
            width: 230,
            child: Text(
              _value(row['order_name']),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(Text(_value(row['dose']))),
        DataCell(Text(_value(row['route']))),
        DataCell(Text(_value(row['frequency']))),
        DataCell(Text(_formatDate(row['start_time']))),
        DataCell(Text(_formatDate(row['end_time'] ?? row['stopped_at']))),
        DataCell(Text(_value(row['doctor_name']))),
        DataCell(
          SizedBox(
            width: 180,
            child: Text(
              _value(row['instruction_text']),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(_statusText(row['status'])),
        DataCell(_rowActions(row)),
      ],
    );
  }

  Widget _rowActions(Map<String, dynamic> row) {
    if (row['status'] != 'OPEN') {
      return const Text('--');
    }
    final orderId = (row['care_order_id'] as num).toInt();
    return Wrap(
      spacing: 2,
      children: [
        if (_isNurse)
          IconButton(
            tooltip: '执行医嘱',
            icon: const Icon(Icons.task_alt_outlined, size: 20),
            onPressed: () => _executeOrder(orderId),
          ),
        if (_isDoctor) ...[
          IconButton(
            tooltip: '停止医嘱',
            icon: const Icon(Icons.stop_circle_outlined, size: 20),
            onPressed: () => _changeOrderStatus(orderId, 'stop', '停止医嘱'),
          ),
          IconButton(
            tooltip: '取消医嘱',
            icon: const Icon(Icons.cancel_outlined, size: 20),
            onPressed: () => _changeOrderStatus(orderId, 'cancel', '取消医嘱'),
          ),
        ],
      ],
    );
  }

  Future<void> _changeOrderStatus(
      int orderId, String action, String title) async {
    final values = await showTextFormDialog(
      context,
      title: title,
      fields: const [FieldSpec('reason', '原因', required: true, multiline: true)],
      submitLabel: '确认',
    );
    if (values == null) {
      return;
    }
    await _post(
      '/api/v1/workstation/care-orders/$orderId/$action',
      values,
      successMessage: '$title成功。',
    );
  }

  Future<void> _executeOrder(int orderId) async {
    final values = await showTextFormDialog(
      context,
      title: '执行医嘱',
      fields: const [FieldSpec('resultNote', '执行记录', multiline: true)],
      submitLabel: '确认执行',
    );
    if (values == null) {
      return;
    }
    await _post(
      '/api/v1/workstation/care-orders/$orderId/execute',
      values,
      successMessage: '医嘱已执行。',
    );
  }

  Future<void> _post(
    String path,
    Map<String, dynamic> values, {
    required String successMessage,
  }) async {
    try {
      await ref.read(apiClientProvider).postVoid(path, values);
      if (!mounted) {
        return;
      }
      _reloadOrders();
      showOperationMessage(context, successMessage);
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  Future<void> _createOrder() async {
    final values = await _showCreateOrderDialog();
    if (values == null) {
      return;
    }
    try {
      await ref.read(apiClientProvider).postObject(
            '/api/v1/workstation/admissions/${widget.admissionId}/care-orders',
            values,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _orderClass = values['orderClass'] as String;
        _ordersFuture = _loadOrders();
      });
      showOperationMessage(context, '医嘱已开立。');
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  Future<Map<String, dynamic>?> _showCreateOrderDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final doseController = TextEditingController();
    final routeController = TextEditingController();
    final frequencyController = TextEditingController();
    final instructionController = TextEditingController();
    var orderType = 'TREATMENT';
    var orderClass = _orderClass;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          title: const Text('新开医嘱'),
          content: SizedBox(
            width: 460,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: orderType,
                      decoration: const InputDecoration(labelText: '医嘱类型'),
                      items: const [
                        DropdownMenuItem(value: 'TREATMENT', child: Text('治疗医嘱')),
                        DropdownMenuItem(value: 'NURSING', child: Text('护理医嘱')),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => orderType = value!),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: orderClass,
                      decoration: const InputDecoration(labelText: '医嘱类别'),
                      items: const [
                        DropdownMenuItem(value: _longTerm, child: Text('长期医嘱')),
                        DropdownMenuItem(value: _temporary, child: Text('临时医嘱')),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => orderClass = value!),
                    ),
                    const SizedBox(height: 12),
                    _formField(nameController, '医嘱内容', required: true),
                    _formField(doseController, '剂量'),
                    _formField(routeController, '给药/执行途径'),
                    _formField(frequencyController, '频次'),
                    _formField(instructionController, '说明', multiline: true),
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
                if (!formKey.currentState!.validate()) {
                  return;
                }
                Navigator.pop(dialogContext, {
                  'orderType': orderType,
                  'orderClass': orderClass,
                  'name': nameController.text.trim(),
                  if (doseController.text.trim().isNotEmpty)
                    'dose': doseController.text.trim(),
                  if (routeController.text.trim().isNotEmpty)
                    'route': routeController.text.trim(),
                  if (frequencyController.text.trim().isNotEmpty)
                    'frequency': frequencyController.text.trim(),
                  if (instructionController.text.trim().isNotEmpty)
                    'instruction': instructionController.text.trim(),
                });
              },
              child: const Text('开立'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    doseController.dispose();
    routeController.dispose();
    frequencyController.dispose();
    instructionController.dispose();
    return result;
  }

  Widget _formField(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool multiline = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: multiline ? 3 : 1,
        decoration: InputDecoration(labelText: label),
        validator: (value) => required && (value == null || value.trim().isEmpty)
            ? '请填写$label'
            : null,
      ),
    );
  }

  Widget _statusText(dynamic value) {
    final status = value?.toString() ?? '';
    final label = switch (status) {
      'OPEN' => '执行中',
      'STOPPED' => '已停止',
      'CANCELLED' => '已取消',
      _ => _value(value),
    };
    final color = switch (status) {
      'OPEN' => Colors.orange.shade800,
      'STOPPED' => WorkstationColors.muted,
      'CANCELLED' => Colors.red.shade700,
      _ => WorkstationColors.ink,
    };
    return Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700));
  }

  String _typeLabel(dynamic value) => switch (value) {
        'TREATMENT' => '治疗医嘱',
        'NURSING' => '护理医嘱',
        _ => _value(value),
      };

  String _classLabel(dynamic value) => switch (value) {
        _longTerm => '长期医嘱',
        _temporary => '临时医嘱',
        _ => _value(value),
      };

  DateTime? _asDate(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString().replaceFirst(' ', 'T'));
  }

  String _formatDate(dynamic value) {
    final date = _asDate(value);
    if (date == null) {
      return '--';
    }
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _dateText(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _value(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '--' : text;
  }
}
