import 'package:flutter/material.dart';

import 'api_client.dart';
import 'workstation_ui.dart';

String apiErrorMessage(Object error) {
  if (error is ApiException) {
    return error.message;
  }
  return '操作未完成，请检查网络和输入内容后重试。';
}

void showOperationMessage(BuildContext context, String message,
    {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      content: Text(message),
    ),
  );
}

String displayValue(dynamic value) {
  if (value == null) {
    return '-';
  }
  if (value is bool) {
    return value ? '是' : '否';
  }
  return value.toString();
}

class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.required = false,
    this.numeric = false,
    this.decimal = false,
    this.multiline = false,
    this.initialValue,
  });

  final String key;
  final String label;
  final bool required;
  final bool numeric;
  final bool decimal;
  final bool multiline;
  final String? initialValue;
}

/// 复用在目录维护和临床录入中的文本表单弹窗。
Future<Map<String, dynamic>?> showTextFormDialog(
  BuildContext context, {
  required String title,
  required List<FieldSpec> fields,
  String submitLabel = '保存',
}) async {
  final formKey = GlobalKey<FormState>();
  final controllers = {
    for (final field in fields)
      field.key: TextEditingController(text: field.initialValue ?? ''),
  };

  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: fields.map((field) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: controllers[field.key],
                      keyboardType: field.numeric || field.decimal
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : TextInputType.text,
                      maxLines: field.multiline ? 4 : 1,
                      decoration: InputDecoration(labelText: field.label),
                      validator: (value) {
                        if (field.required &&
                            (value == null || value.trim().isEmpty)) {
                          return '请填写${field.label}';
                        }
                        if (value != null &&
                            value.isNotEmpty &&
                            field.numeric) {
                          final parsed = field.decimal
                              ? double.tryParse(value.trim())
                              : int.tryParse(value.trim());
                          if (parsed == null) {
                            return '请输入有效的${field.label}';
                          }
                        }
                        return null;
                      },
                    ),
                  );
                }).toList(),
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
              final values = <String, dynamic>{};
              for (final field in fields) {
                final text = controllers[field.key]!.text.trim();
                if (text.isEmpty) {
                  continue;
                }
                values[field.key] = field.numeric
                    ? field.decimal
                        ? double.parse(text)
                        : int.parse(text)
                    : text;
              }
              Navigator.pop(dialogContext, values);
            },
            child: Text(submitLabel),
          ),
        ],
      );
    },
  );

  for (final controller in controllers.values) {
    controller.dispose();
  }
  return result;
}

class JsonTable extends StatelessWidget {
  const JsonTable({
    super.key,
    required this.rows,
    this.columns,
    this.emptyText = '暂无数据',
  });

  final List<Map<String, dynamic>> rows;
  final List<String>? columns;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(child: Text(emptyText));
    }
    final visibleColumns = columns ?? rows.first.keys.take(6).toList();
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border.fromBorderSide(
          BorderSide(color: WorkstationColors.border),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: const WidgetStatePropertyAll(
            WorkstationColors.heading,
          ),
          dividerThickness: 0.7,
          horizontalMargin: 16,
          columnSpacing: 28,
          columns: visibleColumns
              .map(
                (column) => DataColumn(
                  label: Text(
                    _columnLabel(column),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              )
              .toList(),
          rows: rows
              .map(
                (row) => DataRow(
                  cells: visibleColumns
                      .map(
                          (column) => DataCell(Text(displayValue(row[column]))))
                      .toList(),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  String _columnLabel(String column) {
    const labels = {
      'patient_id': '患者 ID',
      'patient_no': '患者编号',
      'patient_name': '患者姓名',
      'department_id': '科室 ID',
      'department_code': '科室编码',
      'department_name': '科室名称',
      'ward_id': '病区 ID',
      'ward_name': '病区名称',
      'bed_id': '床位 ID',
      'bed_no': '床位号',
      'drug_id': '药品 ID',
      'drug_name': '药品名称',
      'exam_item_id': '项目 ID',
      'item_name': '项目名称',
      'user_id': '用户 ID',
      'real_name': '姓名',
      'role_code': '角色',
      'unit_price': '单价',
      'birth_date': '出生日期',
      'admission_id': '住院 ID',
      'inpatient_no': '住院号',
    };
    return labels[column] ?? column.replaceAll('_', ' ').toUpperCase();
  }
}

class LoadingPanel extends StatelessWidget {
  const LoadingPanel({super.key, required this.loading, required this.child});

  final bool loading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return child;
  }
}
