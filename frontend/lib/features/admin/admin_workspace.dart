import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui_helpers.dart';
import '../../core/workstation_ui.dart';
import '../auth/auth_controller.dart';

class AdminWorkspace extends StatelessWidget {
  const AdminWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 11,
      child: Column(
        children: [
          const WorkspaceToolbar(
            title: '系统基础资料',
            subtitle: '维护住院业务的组织、资源、账号、文书模板、路径和上报字典',
          ),
          const WorkstationTabBar(
            tabs: [
              Tab(text: '科室'),
              Tab(text: '病区'),
              Tab(text: '床位'),
              Tab(text: '药品'),
              Tab(text: '检查项目'),
              Tab(text: '用户'),
              Tab(text: '文书模板'),
              Tab(text: '临床路径'),
              Tab(text: '上报类型'),
              Tab(text: '上报审核'),
              Tab(text: '统计'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                CatalogPanel.departments(),
                CatalogPanel.wards(),
                CatalogPanel.beds(),
                CatalogPanel.drugs(),
                CatalogPanel.examItems(),
                CatalogPanel.users(),
                CatalogPanel.documentTemplates(),
                CatalogPanel.pathwayTemplates(),
                CatalogPanel.diseaseReportTypes(),
                const DiseaseReviewPanel(),
                StatisticsPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CatalogConfig {
  const CatalogConfig({
    required this.title,
    required this.path,
    required this.fields,
    required this.columns,
    this.createPath,
    this.statusIdColumn,
  });

  final String title;
  final String path;
  final List<FieldSpec> fields;
  final List<String> columns;
  final String? createPath;
  final String? statusIdColumn;
}

class CatalogPanel extends ConsumerStatefulWidget {
  const CatalogPanel._({required this.config});

  factory CatalogPanel.departments() => const CatalogPanel._(
        config: const CatalogConfig(
          title: '科室目录',
          path: '/api/v1/master-data/departments',
          columns: [
            'department_id',
            'department_code',
            'department_name',
            'department_type',
            'status'
          ],
          statusIdColumn: 'department_id',
          fields: [
            FieldSpec('code', '科室编码', required: true),
            FieldSpec('name', '科室名称', required: true),
            FieldSpec('type', '科室类型', required: true, initialValue: 'CLINICAL'),
            FieldSpec('phone', '联系电话'),
          ],
        ),
      );

  factory CatalogPanel.wards() => const CatalogPanel._(
        config: const CatalogConfig(
          title: '病区目录',
          path: '/api/v1/master-data/wards',
          columns: [
            'ward_id',
            'ward_code',
            'ward_name',
            'department_name',
            'floor_no'
          ],
          fields: [
            FieldSpec('departmentId', '所属科室 ID', required: true, numeric: true),
            FieldSpec('code', '病区编码', required: true),
            FieldSpec('name', '病区名称', required: true),
            FieldSpec('floorNo', '楼层'),
          ],
        ),
      );

  factory CatalogPanel.beds() => const CatalogPanel._(
        config: const CatalogConfig(
          title: '床位目录',
          path: '/api/v1/master-data/beds',
          columns: [
            'bed_id',
            'bed_no',
            'ward_name',
            'department_name',
            'bed_type',
            'status'
          ],
          statusIdColumn: 'bed_id',
          fields: [
            FieldSpec('wardId', '所属病区 ID', required: true, numeric: true),
            FieldSpec('bedNo', '床位号', required: true),
            FieldSpec('bedType', '床位类型',
                required: true, initialValue: 'STANDARD'),
            FieldSpec('nursingLevel', '护理级别',
                required: true, initialValue: 'LEVEL_2'),
          ],
        ),
      );

  factory CatalogPanel.drugs() => const CatalogPanel._(
        config: const CatalogConfig(
          title: '药品目录',
          path: '/api/v1/master-data/drugs',
          columns: [
            'drug_id',
            'drug_code',
            'drug_name',
            'specification',
            'unit',
            'unit_price'
          ],
          fields: [
            FieldSpec('code', '药品编码', required: true),
            FieldSpec('name', '药品名称', required: true),
            FieldSpec('genericName', '通用名'),
            FieldSpec('specification', '规格'),
            FieldSpec('dosageForm', '剂型'),
            FieldSpec('unit', '单位', required: true),
            FieldSpec('unitPrice', '单价',
                required: true, numeric: true, decimal: true),
            FieldSpec('stockQty', '演示库存',
                required: true, numeric: true, initialValue: '0'),
          ],
        ),
      );

  factory CatalogPanel.examItems() => const CatalogPanel._(
        config: const CatalogConfig(
          title: '检查检验目录',
          path: '/api/v1/master-data/exam-items',
          columns: [
            'exam_item_id',
            'item_code',
            'item_name',
            'item_type',
            'unit',
            'unit_price'
          ],
          fields: [
            FieldSpec('code', '项目编码', required: true),
            FieldSpec('name', '项目名称', required: true),
            FieldSpec('type', '项目类型', required: true, initialValue: 'LAB'),
            FieldSpec('departmentId', '执行科室 ID', numeric: true),
            FieldSpec('unit', '单位'),
            FieldSpec('referenceRange', '参考范围'),
            FieldSpec('unitPrice', '单价',
                required: true, numeric: true, decimal: true),
          ],
        ),
      );

  factory CatalogPanel.users() => const CatalogPanel._(
        config: const CatalogConfig(
          title: '系统用户',
          path: '/api/v1/master-data/users',
          columns: [
            'user_id',
            'username',
            'real_name',
            'role_code',
            'department_name',
            'status'
          ],
          fields: [
            FieldSpec('roleId', '角色 ID（1 管理员、2 住院处、3 医师、4 护士）',
                required: true, numeric: true),
            FieldSpec('departmentId', '所属科室 ID', numeric: true),
            FieldSpec('username', '登录名', required: true),
            FieldSpec('password', '初始密码', required: true),
            FieldSpec('realName', '真实姓名', required: true),
            FieldSpec('employeeNo', '工号'),
            FieldSpec('licenseNo', '执业证号'),
            FieldSpec('phone', '联系电话'),
          ],
        ),
      );

  factory CatalogPanel.documentTemplates() => const CatalogPanel._(
        config: CatalogConfig(
          title: '医生文书模板',
          path: '/api/v1/workstation/document-templates',
          createPath: '/api/v1/workstation/admin/document-templates',
          columns: [
            'template_id',
            'document_code',
            'template_name',
            'document_category',
            'due_hours',
            'version_no'
          ],
          fields: [
            FieldSpec('documentCode', '文书编码', required: true),
            FieldSpec('templateName', '模板名称', required: true),
            FieldSpec('category', '类别（DOCTOR/NURSE）',
                required: true, initialValue: 'DOCTOR'),
            FieldSpec('fieldSchema', '字段 JSON 数组',
                required: true, multiline: true, initialValue: '["记录内容"]'),
            FieldSpec('dueHours', '时限（小时）', numeric: true),
          ],
        ),
      );

  factory CatalogPanel.pathwayTemplates() => const CatalogPanel._(
        config: CatalogConfig(
          title: '临床路径模板',
          path: '/api/v1/workstation/pathway-templates',
          createPath: '/api/v1/workstation/admin/pathway-templates',
          columns: [
            'pathway_template_id',
            'pathway_code',
            'pathway_name',
            'diagnosis_hint',
            'status'
          ],
          fields: [
            FieldSpec('code', '路径编码', required: true),
            FieldSpec('name', '路径名称', required: true),
            FieldSpec('diagnosisHint', '诊断提示'),
          ],
        ),
      );

  factory CatalogPanel.diseaseReportTypes() => const CatalogPanel._(
        config: CatalogConfig(
          title: '疾病上报类型',
          path: '/api/v1/workstation/disease-report-types',
          createPath: '/api/v1/workstation/admin/disease-report-types',
          columns: [
            'disease_report_type_id',
            'type_code',
            'type_name',
            'status'
          ],
          fields: [
            FieldSpec('code', '类型编码', required: true),
            FieldSpec('name', '类型名称', required: true),
          ],
        ),
      );

  final CatalogConfig config;

  @override
  ConsumerState<CatalogPanel> createState() => _CatalogPanelState();
}

class _CatalogPanelState extends ConsumerState<CatalogPanel> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = await ref.read(apiClientProvider).getList(widget.config.path);
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

  Future<void> _create() async {
    final values = await showTextFormDialog(
      context,
      title: '新增${widget.config.title}',
      fields: widget.config.fields,
    );
    if (values == null) {
      return;
    }
    try {
      await ref
          .read(apiClientProvider)
          .postVoid(widget.config.createPath ?? widget.config.path, values);
      if (mounted) {
        showOperationMessage(context, '已保存。');
      }
      await _load();
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  Future<void> _changeStatus() async {
    final idColumn = widget.config.statusIdColumn;
    if (idColumn == null) {
      return;
    }
    final values = await showTextFormDialog(
      context,
      title: '变更状态',
      fields: [
        FieldSpec('id', idColumn.replaceAll('_', ' '),
            required: true, numeric: true),
        FieldSpec('status', '新状态（ACTIVE 或 INACTIVE）',
            required: true, initialValue: 'ACTIVE'),
      ],
    );
    if (values == null) {
      return;
    }
    try {
      await ref.read(apiClientProvider).putVoid(
        '${widget.config.path}/${values['id']}/status?status=${values['status']}',
        const {},
      );
      if (mounted) {
        showOperationMessage(context, '状态已更新。');
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(widget.config.title,
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新'),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: const Text('新增'),
              ),
            ],
          ),
          if (widget.config.statusIdColumn != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _changeStatus,
              icon: const Icon(Icons.toggle_on_outlined),
              label: const Text('变更启用状态'),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: WorkSurface(
              padding: EdgeInsets.zero,
              child: LoadingPanel(
                loading: _loading,
                child: SingleChildScrollView(
                  child: JsonTable(rows: _rows, columns: widget.config.columns),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 最高管理员的疾病上报审核队列，按待审状态优先展示跨患者上报记录。
class DiseaseReviewPanel extends ConsumerStatefulWidget {
  const DiseaseReviewPanel({super.key});

  @override
  ConsumerState<DiseaseReviewPanel> createState() => _DiseaseReviewPanelState();
}

class _DiseaseReviewPanelState extends ConsumerState<DiseaseReviewPanel> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = await ref
          .read(apiClientProvider)
          .getList('/api/v1/workstation/disease-reports');
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

  Future<void> _review(Map<String, dynamic> row, bool approved) async {
    final action = approved ? '审核通过' : '退回修改';
    final values = await showTextFormDialog(
      context,
      title: '$action：${displayValue(row['disease_name'])}',
      fields: [
        FieldSpec(
          'note',
          '审核意见',
          required: !approved,
          multiline: true,
          initialValue: approved ? '审核通过' : '',
        ),
      ],
      submitLabel: action,
    );
    if (values == null) {
      return;
    }

    values['approved'] = approved;
    try {
      await ref.read(apiClientProvider).postVoid(
            '/api/v1/workstation/disease-reports/${row['disease_report_id']}/review',
            values,
          );
      if (mounted) {
        showOperationMessage(context, '疾病上报已$action。');
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '疾病上报审核',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text('待审记录优先显示；退回必须填写审核意见。'),
          const SizedBox(height: 12),
          Expanded(
            child: WorkSurface(
              padding: EdgeInsets.zero,
              child: LoadingPanel(
                loading: _loading,
                child: _rows.isEmpty
                    ? const Center(child: Text('暂无疾病上报记录。'))
                    : SingleChildScrollView(
                        child: DataTable(
                          headingRowColor: const WidgetStatePropertyAll(
                            WorkstationColors.heading,
                          ),
                          columns: const [
                            DataColumn(label: Text('患者')),
                            DataColumn(label: Text('住院号')),
                            DataColumn(label: Text('上报类型')),
                            DataColumn(label: Text('疾病名称')),
                            DataColumn(label: Text('上报人')),
                            DataColumn(label: Text('状态')),
                            DataColumn(label: Text('操作')),
                          ],
                          rows: _rows
                              .map(
                                (row) => DataRow(
                                  cells: [
                                    DataCell(Text(
                                        displayValue(row['patient_name']))),
                                    DataCell(Text(
                                        displayValue(row['inpatient_no']))),
                                    DataCell(
                                        Text(displayValue(row['report_type']))),
                                    DataCell(Text(
                                        displayValue(row['disease_name']))),
                                    DataCell(Text(
                                        displayValue(row['reporter_name']))),
                                    DataCell(Text(displayValue(row['status']))),
                                    DataCell(
                                      row['status'] == 'SUBMITTED'
                                          ? Wrap(
                                              spacing: 2,
                                              children: [
                                                IconButton(
                                                  onPressed: () =>
                                                      _review(row, true),
                                                  icon: const Icon(
                                                    Icons.check_circle_outline,
                                                    size: 20,
                                                  ),
                                                  tooltip: '审核通过',
                                                ),
                                                IconButton(
                                                  onPressed: () =>
                                                      _review(row, false),
                                                  icon: const Icon(
                                                    Icons.reply_outlined,
                                                    size: 20,
                                                  ),
                                                  tooltip: '退回修改',
                                                ),
                                              ],
                                            )
                                          : const Text('-'),
                                    ),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StatisticsPanel extends ConsumerStatefulWidget {
  const StatisticsPanel({super.key});

  @override
  ConsumerState<StatisticsPanel> createState() => _StatisticsPanelState();
}

class _StatisticsPanelState extends ConsumerState<StatisticsPanel> {
  var _selected = 0;
  var _loading = true;
  List<Map<String, dynamic>> _rows = [];

  final _paths = const [
    '/api/v1/statistics/bed-occupancy',
    '/api/v1/statistics/diagnoses',
    '/api/v1/statistics/charges',
  ];
  final _titles = const ['床位使用率', '疾病与住院天数', '费用构成'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = await ref.read(apiClientProvider).getList(_paths[_selected]);
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('运营统计', style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: List.generate(
              _titles.length,
              (index) =>
                  ButtonSegment(value: index, label: Text(_titles[index])),
            ),
            selected: {_selected},
            onSelectionChanged: (value) {
              setState(() => _selected = value.first);
              _load();
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LoadingPanel(
              loading: _loading,
              child: WorkSurface(
                padding: EdgeInsets.zero,
                child: SingleChildScrollView(child: JsonTable(rows: _rows)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
