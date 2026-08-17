import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui_helpers.dart';
import '../../core/workstation_ui.dart';
import '../auth/auth_controller.dart';

class AdmissionWorkspace extends StatelessWidget {
  const AdmissionWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: const [
          WorkspaceToolbar(
            title: '住院业务办理',
            subtitle: '患者建档、入院分床、押金、转科及出院结算',
          ),
          WorkstationTabBar(
            isScrollable: false,
            tabs: [
              Tab(text: '患者建档'),
              Tab(text: '在院患者'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [PatientPanel(), AdmissionPanel()],
            ),
          ),
        ],
      ),
    );
  }
}

class PatientPanel extends ConsumerStatefulWidget {
  const PatientPanel({super.key});

  @override
  ConsumerState<PatientPanel> createState() => _PatientPanelState();
}

class _PatientPanelState extends ConsumerState<PatientPanel> {
  final _keyword = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final page = await ref.read(apiClientProvider).getObject(
            '/api/v1/patients?keyword=${Uri.encodeQueryComponent(_keyword.text.trim())}&pageSize=100',
          );
      _rows = (page['items'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
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
      title: '新建患者档案',
      fields: const [
        FieldSpec('name', '姓名', required: true),
        FieldSpec('gender', '性别（MALE 或 FEMALE）',
            required: true, initialValue: 'MALE'),
        FieldSpec('birthDate', '出生日期（YYYY-MM-DD）', required: true),
        FieldSpec('idType', '证件类型', initialValue: 'ID_CARD'),
        FieldSpec('idCardNo', '身份证号'),
        FieldSpec('nationality', '国籍', initialValue: '中国'),
        FieldSpec('occupation', '职业'),
        FieldSpec('maritalStatus', '婚姻状况'),
        FieldSpec('birthPlace', '籍贯'),
        FieldSpec('registeredAddress', '户籍地址'),
        FieldSpec('currentAddress', '现住地址'),
        FieldSpec('postalCode', '邮编'),
        FieldSpec('phone', '联系电话'),
        FieldSpec('address', '住址'),
        FieldSpec('emergencyContactName', '紧急联系人'),
        FieldSpec('emergencyContactRelation', '与患者关系'),
        FieldSpec('emergencyContactPhone', '紧急联系人电话'),
      ],
    );
    if (values == null) {
      return;
    }
    try {
      await ref.read(apiClientProvider).postObject('/api/v1/patients', values);
      if (mounted) {
        showOperationMessage(context, '患者档案已建立。');
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
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keyword,
                  decoration: const InputDecoration(
                    labelText: '按姓名、编号或身份证号搜索',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.search),
                  tooltip: '搜索'),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('建档'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: WorkSurface(
              padding: EdgeInsets.zero,
              child: LoadingPanel(
                loading: _loading,
                child: SingleChildScrollView(
                  child: JsonTable(
                    rows: _rows,
                    columns: const [
                      'patient_id',
                      'patient_no',
                      'name',
                      'gender',
                      'birth_date',
                      'phone'
                    ],
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

class AdmissionPanel extends ConsumerStatefulWidget {
  const AdmissionPanel({super.key});

  @override
  ConsumerState<AdmissionPanel> createState() => _AdmissionPanelState();
}

class _AdmissionPanelState extends ConsumerState<AdmissionPanel> {
  List<Map<String, dynamic>> _rows = [];
  var _loading = true;

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
          .getList('/api/v1/admissions?status=IN_HOSPITAL');
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

  Future<void> _openAdmitDialog() async {
    try {
      final api = ref.read(apiClientProvider);
      final result = await Future.wait([
        api.getObject('/api/v1/patients?pageSize=100'),
        api.getList('/api/v1/admissions/departments'),
        api.getList('/api/v1/admissions/doctors'),
      ]);
      final patients = ((result[0] as Map<String, dynamic>)['items'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final departments = result[1] as List<Map<String, dynamic>>;
      final doctors = result[2] as List<Map<String, dynamic>>;
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          int? patientId;
          int? departmentId;
          int? doctorId;
          int? bedId;
          var beds = <Map<String, dynamic>>[];
          var saving = false;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> loadBeds(int id) async {
                setDialogState(() {
                  bedId = null;
                  beds = [];
                });
                try {
                  final loaded = await api.getList(
                      '/api/v1/admissions/available-beds?departmentId=$id');
                  setDialogState(() => beds = loaded);
                } catch (error) {
                  if (context.mounted) {
                    showOperationMessage(context, apiErrorMessage(error),
                        error: true);
                  }
                }
              }

              return AlertDialog(
                title: const Text('办理入院登记'),
                content: SizedBox(
                  width: 460,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<int>(
                          value: patientId,
                          decoration: const InputDecoration(labelText: '患者'),
                          items: patients
                              .map(
                                (patient) => DropdownMenuItem(
                                  value: (patient['patient_id'] as num).toInt(),
                                  child: Text(
                                      '${patient['name']}（${patient['patient_no']}）'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setDialogState(() => patientId = value),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: departmentId,
                          decoration: const InputDecoration(labelText: '入院科室'),
                          items: departments
                              .map(
                                (department) => DropdownMenuItem(
                                  value: (department['department_id'] as num)
                                      .toInt(),
                                  child: Text(
                                      department['department_name'].toString()),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => departmentId = value);
                              loadBeds(value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: bedId,
                          decoration: const InputDecoration(labelText: '可用床位'),
                          items: beds
                              .map(
                                (bed) => DropdownMenuItem(
                                  value: (bed['bed_id'] as num).toInt(),
                                  child: Text(
                                      '${bed['ward_name']} ${bed['bed_no']}'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setDialogState(() => bedId = value),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: doctorId,
                          decoration: const InputDecoration(labelText: '责任医师'),
                          items: doctors
                              .map(
                                (doctor) => DropdownMenuItem(
                                  value: (doctor['user_id'] as num).toInt(),
                                  child: Text(
                                      '${doctor['real_name']}（${doctor['department_name'] ?? '-'}）'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setDialogState(() => doctorId = value),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: saving ? null : () => Navigator.pop(context),
                      child: const Text('取消')),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            if (patientId == null ||
                                departmentId == null ||
                                bedId == null) {
                              showOperationMessage(context, '请选择患者、科室和床位。',
                                  error: true);
                              return;
                            }
                            setDialogState(() => saving = true);
                            try {
                              await api.postObject('/api/v1/admissions', {
                                'patientId': patientId,
                                'departmentId': departmentId,
                                'doctorId': doctorId,
                                'bedId': bedId,
                                'nursingLevel': 'LEVEL_2',
                                'feeType': 'INSURED',
                                'insuranceType': '居民医保',
                              });
                              if (context.mounted) {
                                Navigator.pop(context);
                                showOperationMessage(context, '入院登记成功，床位已占用。');
                              }
                              await _load();
                            } catch (error) {
                              if (context.mounted) {
                                showOperationMessage(
                                    context, apiErrorMessage(error),
                                    error: true);
                              }
                              setDialogState(() => saving = false);
                            }
                          },
                    child: const Text('确认登记'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  Future<void> _deposit(int admissionId) async {
    final values = await showTextFormDialog(
      context,
      title: '押金收退',
      fields: const [
        FieldSpec('type', '类型（DEPOSIT、REFUND 或 REVERSAL）',
            required: true, initialValue: 'DEPOSIT'),
        FieldSpec('amount', '金额', required: true, numeric: true, decimal: true),
        FieldSpec('paymentMethod', '支付方式',
            required: true, initialValue: 'CASH'),
        FieldSpec('remark', '备注'),
      ],
    );
    if (values == null) {
      return;
    }
    try {
      await ref
          .read(apiClientProvider)
          .postVoid('/api/v1/admissions/$admissionId/deposits', values);
      if (mounted) {
        showOperationMessage(context, '押金流水已记录。');
      }
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  Future<void> _settle(int admissionId) async {
    try {
      final settlement = await ref.read(apiClientProvider).postObject(
        '/api/v1/admissions/$admissionId/settlement',
        const {},
      );
      if (mounted) {
        showOperationMessage(
          context,
          '结算完成：总费用 ${settlement['totalCharge']}，退款 ${settlement['refundAmount']}。',
        );
      }
      await _load();
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  Future<void> _requestTransfer(int admissionId) async {
    try {
      final api = ref.read(apiClientProvider);
      final departments = await api.getList('/api/v1/admissions/departments');
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          int? departmentId;
          int? bedId;
          var beds = <Map<String, dynamic>>[];
          final reason = TextEditingController();
          var saving = false;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> loadBeds(int id) async {
                setDialogState(() {
                  bedId = null;
                  beds = [];
                });
                try {
                  final loaded = await api.getList(
                      '/api/v1/admissions/available-beds?departmentId=$id');
                  setDialogState(() => beds = loaded);
                } catch (error) {
                  if (context.mounted) {
                    showOperationMessage(context, apiErrorMessage(error),
                        error: true);
                  }
                }
              }

              return AlertDialog(
                title: const Text('申请转科'),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        value: departmentId,
                        decoration: const InputDecoration(labelText: '目标科室'),
                        items: departments
                            .map(
                              (item) => DropdownMenuItem(
                                value: (item['department_id'] as num).toInt(),
                                child: Text(item['department_name'].toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => departmentId = value);
                            loadBeds(value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: bedId,
                        decoration: const InputDecoration(labelText: '目标床位'),
                        items: beds
                            .map(
                              (item) => DropdownMenuItem(
                                value: (item['bed_id'] as num).toInt(),
                                child: Text(
                                    '${item['ward_name']} ${item['bed_no']}'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setDialogState(() => bedId = value),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: reason,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: '转科原因'),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消')),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            if (departmentId == null ||
                                bedId == null ||
                                reason.text.trim().isEmpty) {
                              showOperationMessage(context, '请选择目标科室、床位并填写原因。',
                                  error: true);
                              return;
                            }
                            setDialogState(() => saving = true);
                            try {
                              await api.postObject(
                                  '/api/v1/admissions/$admissionId/transfers', {
                                'toDepartmentId': departmentId,
                                'toBedId': bedId,
                                'reason': reason.text.trim(),
                              });
                              if (context.mounted) {
                                Navigator.pop(context);
                                showOperationMessage(context, '转科申请已提交，等待确认。');
                              }
                            } catch (error) {
                              if (context.mounted) {
                                showOperationMessage(
                                    context, apiErrorMessage(error),
                                    error: true);
                              }
                              setDialogState(() => saving = false);
                            }
                          },
                    child: const Text('提交申请'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }

  Future<void> _showTransferHistory(int admissionId) async {
    try {
      final detail = await ref
          .read(apiClientProvider)
          .getObject('/api/v1/admissions/$admissionId');
      final transfers = (detail['transfers'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('转科历史与确认'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: transfers.map((transfer) {
                  final pending = transfer['status'] == 'PENDING';
                  return ListTile(
                    title: Text(
                        '申请 #${transfer['transfer_id']} · ${transfer['status']}'),
                    subtitle: Text(
                        '目标科室 ID：${transfer['to_department_id']}\n${transfer['reason'] ?? ''}'),
                    trailing: pending
                        ? FilledButton(
                            onPressed: () async {
                              try {
                                await ref.read(apiClientProvider).postVoid(
                                  '/api/v1/admissions/transfers/${transfer['transfer_id']}/approve',
                                  const {},
                                );
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                  showOperationMessage(
                                      context, '转科已确认，床位和科室已同步更新。');
                                }
                                await _load();
                              } catch (error) {
                                if (context.mounted) {
                                  showOperationMessage(
                                      context, apiErrorMessage(error),
                                      error: true);
                                }
                              }
                            },
                            child: const Text('确认'),
                          )
                        : null,
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Text('在院患者', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新'),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _openAdmitDialog,
                icon: const Icon(Icons.local_hospital_outlined),
                label: const Text('入院登记'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: WorkSurface(
              padding: EdgeInsets.zero,
              child: LoadingPanel(
                loading: _loading,
                child: ListView.separated(
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = _rows[index];
                    final admissionId = (row['admission_id'] as num).toInt();
                    return ListTile(
                      title: Text(
                          '${row['patient_name']}  ${row['inpatient_no']}'),
                      subtitle: Text(
                          '${row['department_name']} · 床位 ${row['bed_no'] ?? '-'} · ${row['doctor_name'] ?? '未指定医师'}'),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            onPressed: () => _deposit(admissionId),
                            tooltip: '押金收退',
                            icon: const Icon(Icons.payments_outlined),
                          ),
                          IconButton(
                            onPressed: () => _requestTransfer(admissionId),
                            tooltip: '申请转科',
                            icon: const Icon(Icons.swap_horiz),
                          ),
                          IconButton(
                            onPressed: () => _showTransferHistory(admissionId),
                            tooltip: '确认转科',
                            icon: const Icon(Icons.fact_check_outlined),
                          ),
                          IconButton(
                            onPressed: () => _settle(admissionId),
                            tooltip: '出院结算',
                            icon: const Icon(Icons.receipt_long_outlined),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
