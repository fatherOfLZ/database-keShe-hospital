import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui_helpers.dart';
import '../../core/workstation_ui.dart';
import '../auth/auth_controller.dart';
import 'report_citation.dart';

/// 病程记录采用参考工作站的卡片式时间线，而不是通用文书表格。
/// 记录的保存、签名和作废仍由后端文书状态机约束。
class CourseRecordPage extends ConsumerStatefulWidget {
  const CourseRecordPage({
    super.key,
    required this.admissionId,
    required this.role,
  });

  final int admissionId;
  final String role;

  @override
  ConsumerState<CourseRecordPage> createState() => _CourseRecordPageState();
}

class _CourseRecordPageState extends ConsumerState<CourseRecordPage> {
  static const _courseCodes = <String>{
    'FIRST_COURSE',
    'DAILY_COURSE',
    'POSTOPERATIVE_FIRST_COURSE',
  };

  late Future<_CourseRecordData> _pageFuture;
  DateTime? _selectedDate;
  bool _calendarOpen = false;
  bool _departmentOnly = false;
  bool _newestFirst = true;
  int? _voidingRecordId;
  final _voidReasonController = TextEditingController();
  String? _voidReasonError;
  bool _voidSubmitting = false;

  bool get _canWrite => widget.role == 'DOCTOR';

  @override
  void initState() {
    super.initState();
    _pageFuture = _loadPage();
  }

  @override
  void dispose() {
    _voidReasonController.dispose();
    super.dispose();
  }

  Future<_CourseRecordData> _loadPage() async {
    final api = ref.read(apiClientProvider);
    final responses = await Future.wait([
      api.getList('/api/v1/workstation/admissions/${widget.admissionId}/documents'),
      api.getList('/api/v1/workstation/document-templates?category=DOCTOR'),
    ]);
    final records = responses[0]
        .where(_isCourseRecord)
        .map(Map<String, dynamic>.from)
        .toList();
    final templates = responses[1]
        .where((item) => _courseCodes.contains(item['document_code']))
        .map(Map<String, dynamic>.from)
        .toList();
    return _CourseRecordData(records: records, templates: templates);
  }

  bool _isCourseRecord(Map<String, dynamic> record) {
    final code = record['document_code']?.toString();
    final title = record['title']?.toString() ?? '';
    return _courseCodes.contains(code) || title.contains('病程记录');
  }

  void _reload() {
    setState(() => _pageFuture = _loadPage());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CourseRecordData>(
      future: _pageFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return WorkSurface(
          padding: EdgeInsets.zero,
          child: Stack(
            children: [
              Column(
                children: [
                  WorkspaceToolbar(
                    title: '病程记录',
                    subtitle: '按病程时间查看、书写和追溯当前患者的临床记录。',
                    actions: [
                      IconButton(
                        tooltip: '刷新',
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  _buildToolBar(context, data),
                  if (_calendarOpen) _buildCalendar(),
                  Expanded(
                    child: snapshot.connectionState != ConnectionState.done
                        ? const Center(child: CircularProgressIndicator())
                        : snapshot.hasError
                            ? _ErrorState(
                                message: apiErrorMessage(snapshot.error!),
                                onRetry: _reload,
                              )
                            : _buildRecordList(data!.records),
                  ),
                ],
              ),
              if (_canWrite && data != null)
                Positioned(
                  right: 22,
                  bottom: 22,
                  child: FloatingActionButton(
                    heroTag: 'course-record-create',
                    tooltip: '新增病程记录',
                    backgroundColor: WorkstationColors.cyan,
                    foregroundColor: Colors.white,
                    onPressed: data.templates.isEmpty
                        ? null
                        : () => _createRecord(data.templates),
                    child: const Icon(Icons.add, size: 31),
                  ),
                ),
              if (_voidingRecordId != null) _buildVoidConfirmation(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolBar(BuildContext context, _CourseRecordData? data) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FBFC),
        border: Border(bottom: BorderSide(color: WorkstationColors.border)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _toolButton(
            label: '新增',
            icon: Icons.add,
            enabled: _canWrite && (data?.templates.isNotEmpty ?? false),
            onPressed: () => _createRecord(data!.templates),
          ),
          _toolButton(
            label: '全部打印',
            icon: Icons.print_outlined,
            onPressed: () => _showUnavailable('全部打印'),
          ),
          _toolButton(
            label: '续打',
            icon: Icons.print_outlined,
            onPressed: () => _showUnavailable('续打'),
          ),
          _toolButton(
            label: '拉线打印',
            icon: Icons.format_align_left_outlined,
            onPressed: () => _showUnavailable('拉线打印'),
          ),
          const SizedBox(width: 8),
          const Text('病程时间:', style: TextStyle(fontWeight: FontWeight.w700)),
          OutlinedButton.icon(
            onPressed: () => setState(() => _calendarOpen = !_calendarOpen),
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(_selectedDate == null ? '选择日期' : _formatDate(_selectedDate!)),
            style: _compactButtonStyle,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _departmentOnly,
                visualDensity: VisualDensity.compact,
                onChanged: (value) =>
                    setState(() => _departmentOnly = value ?? false),
              ),
              const Text('本科室'),
            ],
          ),
          OutlinedButton(
            onPressed: _reload,
            style: _compactButtonStyle,
            child: const Text('查询'),
          ),
          OutlinedButton(
            onPressed: () => _showTimeline(data?.records ?? const []),
            style: _compactButtonStyle,
            child: const Text('病程浏览'),
          ),
          OutlinedButton(
            onPressed: () => setState(() => _newestFirst = !_newestFirst),
            style: _compactButtonStyle,
            child: Text(_newestFirst ? '重新排序' : '按时间倒序'),
          ),
          OutlinedButton(
            onPressed: () => _showUnavailable('补打'),
            style: _compactButtonStyle,
            child: const Text('补打'),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 310,
        margin: const EdgeInsets.fromLTRB(190, 0, 0, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border.fromBorderSide(BorderSide(color: WorkstationColors.border)),
          boxShadow: [
            BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: CalendarDatePicker(
          initialDate: _selectedDate ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
          onDateChanged: (date) => setState(() {
            _selectedDate = date;
            _calendarOpen = false;
          }),
        ),
      ),
    );
  }

  Widget _buildRecordList(List<Map<String, dynamic>> source) {
    final records = source.where((record) {
      if (_selectedDate == null) {
        return true;
      }
      return record['recorded_at']?.toString().startsWith(_formatDate(_selectedDate!)) ?? false;
    }).toList()
      ..sort((left, right) {
        final order = displayValue(right['recorded_at'])
            .compareTo(displayValue(left['recorded_at']));
        return _newestFirst ? order : -order;
      });
    if (records.isEmpty) {
      return Center(
        child: Text(
          _selectedDate == null ? '当前患者暂无病程记录。' : '该日期暂无病程记录。',
          style: const TextStyle(color: WorkstationColors.muted),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 88),
      itemCount: records.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _recordCard(records[index]),
    );
  }

  Widget _recordCard(Map<String, dynamic> record) {
    final status = displayValue(record['status']);
    final signed = status == 'SIGNED';
    final recordId = (record['record_id'] as num).toInt();
    final title = displayValue(record['title']);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: WorkstationColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 760;
          final information = Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: signed ? WorkstationColors.ink : const Color(0xFF755D1C),
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (signed) const Icon(Icons.check, color: Color(0xFF4F8B35), size: 21),
              Icon(
                status == 'VOID' ? Icons.block_outlined : Icons.inventory_2_outlined,
                color: status == 'VOID' ? Colors.red.shade600 : const Color(0xFF5E9636),
                size: 18,
              ),
              Text(
                '病程时间: ${_formatDateTime(record['recorded_at'])}',
                style: const TextStyle(color: WorkstationColors.muted),
              ),
              Text(
                '创建人: ${displayValue(record['author_name'])}',
                style: const TextStyle(color: WorkstationColors.muted),
              ),
              _signatureState(status),
            ],
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _recordLeading(signed),
                const SizedBox(height: 8),
                information,
                const SizedBox(height: 10),
                _recordActions(record, recordId),
              ],
            );
          }
          return Row(
            children: [
              _recordLeading(signed),
              const SizedBox(width: 14),
              Expanded(child: information),
              const SizedBox(width: 12),
              _recordActions(record, recordId),
            ],
          );
        },
      ),
    );
  }

  Widget _recordLeading(bool signed) {
    return Container(
      width: 44,
      height: 52,
      decoration: BoxDecoration(
        color: signed ? const Color(0xFFEAF3FB) : const Color(0xFFF3F5F6),
        border: Border.all(color: signed ? WorkstationColors.cyan : WorkstationColors.border),
      ),
      child: Icon(
        Icons.check,
        color: signed ? const Color(0xFF2779BF) : WorkstationColors.muted,
        size: 32,
      ),
    );
  }

  Widget _signatureState(String status) {
    final label = switch (status) {
      'SIGNED' => '患者签名[已完成]',
      'SUBMITTED' => '患者签名[待签名]',
      'DRAFT' => '患者签名[未发送]',
      'VOID' => '文书已作废',
      _ => '患者签名[$status]',
    };
    final color = status == 'SIGNED'
        ? const Color(0xFF4F8B35)
        : status == 'VOID'
            ? Colors.red.shade700
            : WorkstationColors.muted;
    return Text(label, style: TextStyle(color: color));
  }

  Widget _recordActions(Map<String, dynamic> record, int recordId) {
    final status = displayValue(record['status']);
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      children: [
        TextButton.icon(
          onPressed: () => _showRecord(record, detailsOnly: true),
          icon: const Icon(Icons.info_outline, size: 18),
          label: const Text('病历信息'),
        ),
        if (_canWrite && (status == 'DRAFT' || status == 'SUBMITTED'))
          TextButton.icon(
            onPressed: () => _openVoidConfirmation(recordId),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('删除'),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
          ),
        if (_canWrite && status == 'SIGNED')
          TextButton.icon(
            onPressed: () => _reviseRecord(recordId),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('修订'),
          )
        else
          TextButton.icon(
            onPressed: () => _showRecord(record),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('编辑'),
          ),
        TextButton.icon(
          onPressed: () => _showRecord(record),
          icon: const Icon(Icons.find_in_page_outlined, size: 18),
          label: const Text('查看'),
        ),
        PopupMenuButton<_RecordCommand>(
          tooltip: '更多',
          icon: const Icon(Icons.more_horiz),
          onSelected: (command) => _handleCommand(command, record, recordId),
          itemBuilder: (context) => [
            if (_canWrite && status == 'DRAFT')
              const PopupMenuItem(
                value: _RecordCommand.submit,
                child: Text('提交文书'),
              ),
            if (_canWrite && status == 'SUBMITTED')
              const PopupMenuItem(
                value: _RecordCommand.sign,
                child: Text('患者意见并签名'),
              ),
            const PopupMenuItem(
              value: _RecordCommand.audit,
              child: Text('查看审计轨迹'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _handleCommand(
    _RecordCommand command,
    Map<String, dynamic> record,
    int recordId,
  ) async {
    switch (command) {
      case _RecordCommand.submit:
        await _post('/api/v1/workstation/documents/$recordId/submit', {});
        return;
      case _RecordCommand.sign:
        final values = await showTextFormDialog(
          context,
          title: '患者意见与医师签名',
          fields: const [FieldSpec('patientOpinion', '患者意见', multiline: true)],
          submitLabel: '确认签名',
        );
        if (values != null) {
          await _post('/api/v1/workstation/documents/$recordId/sign', values);
        }
        return;
      case _RecordCommand.audit:
        await _showAudit(recordId);
        return;
    }
  }

  Future<void> _createRecord(List<Map<String, dynamic>> templates) async {
    final citation = ref.read(pendingReportCitationProvider(widget.admissionId));
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        var template = templates.first;
        final titleController = TextEditingController(
          text: template['template_name']?.toString() ?? '日常病程记录',
        );
        final contentController = TextEditingController(text: citation ?? '');
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('新增病程记录'),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: (template['template_id'] as num).toInt(),
                      decoration: const InputDecoration(labelText: '病程记录类型'),
                      items: templates
                          .map(
                            (item) => DropdownMenuItem(
                              value: (item['template_id'] as num).toInt(),
                              child: Text(displayValue(item['template_name'])),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setDialogState(() {
                        template = templates.firstWhere(
                          (item) => (item['template_id'] as num).toInt() == value,
                        );
                        titleController.text = displayValue(itemName(template));
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: '标题'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: contentController,
                      minLines: 8,
                      maxLines: 13,
                      decoration: const InputDecoration(
                        labelText: '病程内容',
                        hintText: '请按所选文书模板填写病情变化、检查结果和诊疗计划。',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
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
                  final content = contentController.text.trim();
                  if (content.isEmpty) {
                    showOperationMessage(context, '请填写病程内容。', error: true);
                    return;
                  }
                  Navigator.pop(dialogContext, {
                    'templateId': (template['template_id'] as num).toInt(),
                    'documentCode': template['document_code'],
                    'title': titleController.text.trim(),
                    'content': content,
                    'contentJson': jsonEncode({'content': content}),
                  });
                },
                child: const Text('保存草稿'),
              ),
            ],
          ),
        );
      },
    );
    if (citation != null) {
      ref.read(pendingReportCitationProvider(widget.admissionId).notifier).state =
          null;
    }
    if (values != null) {
      await _post('/api/v1/workstation/admissions/${widget.admissionId}/documents', values);
    }
  }

  String itemName(Map<String, dynamic> item) =>
      item['template_name']?.toString() ?? '日常病程记录';

  void _openVoidConfirmation(int recordId) {
    setState(() {
      _voidingRecordId = recordId;
      _voidReasonController.clear();
      _voidReasonError = null;
    });
  }

  void _closeVoidConfirmation() {
    if (_voidSubmitting) {
      return;
    }
    setState(() {
      _voidingRecordId = null;
      _voidReasonController.clear();
      _voidReasonError = null;
    });
  }

  Future<void> _submitVoidRecord() async {
    final recordId = _voidingRecordId;
    final reason = _voidReasonController.text.trim();
    if (recordId == null || _voidSubmitting) {
      return;
    }
    if (reason.isEmpty) {
      setState(() => _voidReasonError = '请填写作废原因。');
      return;
    }

    setState(() {
      _voidSubmitting = true;
      _voidReasonError = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .postVoid('/api/v1/workstation/documents/$recordId/void', {
        'reason': reason,
      });
      if (!mounted) {
        return;
      }
      setState(() {
        _voidingRecordId = null;
        _voidReasonController.clear();
        _voidSubmitting = false;
      });
      _reload();
      showOperationMessage(context, '病程记录已作废。');
    } catch (error) {
      if (mounted) {
        setState(() {
          _voidSubmitting = false;
          _voidReasonError = apiErrorMessage(error);
        });
      }
    }
  }

  Widget _buildVoidConfirmation() {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x8A000000),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Material(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '作废病程记录',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '作废后记录仍会保留在审计历史中，不能恢复为原状态。',
                      style: TextStyle(color: WorkstationColors.muted),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _voidReasonController,
                      autofocus: true,
                      minLines: 3,
                      maxLines: 5,
                      enabled: !_voidSubmitting,
                      decoration: InputDecoration(
                        labelText: '作废原因',
                        alignLabelWithHint: true,
                        errorText: _voidReasonError,
                      ),
                      onChanged: (_) {
                        if (_voidReasonError != null) {
                          setState(() => _voidReasonError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed:
                              _voidSubmitting ? null : _closeVoidConfirmation,
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed:
                              _voidSubmitting ? null : _submitVoidRecord,
                          child: Text(_voidSubmitting ? '正在作废...' : '确认作废'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _reviseRecord(int recordId) async {
    final values = await showTextFormDialog(
      context,
      title: '修订病程记录',
      fields: const [FieldSpec('reason', '修订原因', required: true, multiline: true)],
      submitLabel: '生成修订草稿',
    );
    if (values != null) {
      await _post('/api/v1/workstation/documents/$recordId/revise', values);
    }
  }

  Future<void> _post(String path, Map<String, dynamic> data) async {
    try {
      await ref.read(apiClientProvider).postVoid(path, data);
      if (!mounted) {
        return;
      }
      showOperationMessage(context, '操作已完成。');
      // The dialog route can still be finishing its reverse transition when
      // the API responds. Refresh after this frame so its inherited
      // dependents have completed deactivation first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _reload();
        }
      });
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  Future<void> _showAudit(int recordId) async {
    try {
      final rows = await ref
          .read(apiClientProvider)
          .getList('/api/v1/workstation/documents/$recordId/audit');
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('病程记录审计轨迹'),
          content: SizedBox(
            width: 620,
            child: rows.isEmpty
                ? const Text('暂无审计记录。')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return ListTile(
                        dense: true,
                        title: Text(displayValue(row['action_type'])),
                        subtitle: Text(
                          '${displayValue(row['actor_name'])}  ${_formatDateTime(row['action_at'])}\n${displayValue(row['remark'])}',
                        ),
                      );
                    },
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

  Future<void> _showRecord(
    Map<String, dynamic> record, {
    bool detailsOnly = false,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(detailsOnly ? '病历信息' : displayValue(record['title'])),
        content: SizedBox(
          width: 660,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailLine('文书类型', record['template_name'] ?? record['document_code']),
                _detailLine('病程时间', _formatDateTime(record['recorded_at'])),
                _detailLine('创建人', record['author_name']),
                _detailLine('状态', record['status']),
                _detailLine('版本', record['version_no']),
                const Divider(height: 26),
                const Text('病程内容', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SelectableText(displayValue(record['content'])),
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
  }

  Widget _detailLine(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: WorkstationColors.ink),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(color: WorkstationColors.muted),
            ),
            TextSpan(text: displayValue(value)),
          ],
        ),
      ),
    );
  }

  Future<void> _showTimeline(List<Map<String, dynamic>> records) {
    final sorted = [...records]
      ..sort((left, right) => displayValue(left['recorded_at'])
          .compareTo(displayValue(right['recorded_at'])));
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('病程浏览'),
        content: SizedBox(
          width: 620,
          child: sorted.isEmpty
              ? const Text('暂无病程记录。')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final record = sorted[index];
                    return ListTile(
                      leading: const Icon(Icons.circle, size: 14, color: WorkstationColors.cyan),
                      title: Text(displayValue(record['title'])),
                      subtitle: Text(
                        '${_formatDateTime(record['recorded_at'])}  ${displayValue(record['author_name'])}',
                      ),
                      onTap: () => _showRecord(record),
                    );
                  },
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
  }

  void _showUnavailable(String command) {
    showOperationMessage(context, '$command 已保留入口，待正式打印模板配置后启用。');
  }

  Widget _toolButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool enabled = true,
  }) {
    return TextButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: WorkstationColors.ink,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(dynamic value) {
    final text = displayValue(value);
    if (text == '-') {
      return text;
    }
    final formatted = text.replaceFirst('T', ' ');
    return formatted.length > 16 ? formatted.substring(0, 16) : formatted;
  }
}

const _compactButtonStyle = ButtonStyle(
  visualDensity: VisualDensity.compact,
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 11, vertical: 8)),
);

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(color: WorkstationColors.muted)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重新加载'),
          ),
        ],
      ),
    );
  }
}

class _CourseRecordData {
  const _CourseRecordData({required this.records, required this.templates});

  final List<Map<String, dynamic>> records;
  final List<Map<String, dynamic>> templates;
}

enum _RecordCommand { submit, sign, audit }
