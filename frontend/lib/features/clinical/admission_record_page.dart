import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/ui_helpers.dart';
import '../../core/workstation_ui.dart';
import '../auth/auth_controller.dart';

/// 通用入院记录正文；神经内科可在同一文书中启用神经系统查体扩展。
class AdmissionRecordPage extends ConsumerStatefulWidget {
  const AdmissionRecordPage({
    super.key,
    required this.admissionId,
    required this.role,
    this.onChanged,
  });

  final int admissionId;
  final String role;
  final VoidCallback? onChanged;

  @override
  ConsumerState<AdmissionRecordPage> createState() =>
      _AdmissionRecordPageState();
}

class _AdmissionRecordPageState extends ConsumerState<AdmissionRecordPage> {
  static const _documentCode = 'ADMISSION_RECORD';

  final Map<String, TextEditingController> _controllers = {
    for (final key in _fieldLabels.keys) key: TextEditingController(),
  };

  late Future<_AdmissionRecordData> _pageFuture;
  Map<String, dynamic> _header = const {};
  bool _neurologyEnabled = false;
  bool _busy = false;
  String? _loadedToken;

  bool get _canWrite => widget.role == 'DOCTOR';

  @override
  void initState() {
    super.initState();
    _pageFuture = _load();
  }

  @override
  void didUpdateWidget(covariant AdmissionRecordPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.admissionId != widget.admissionId) {
      _loadedToken = null;
      _pageFuture = _load();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<_AdmissionRecordData> _load() async {
    final api = ref.read(apiClientProvider);
    final responses = await Future.wait([
      api.getObject('/api/v1/workstation/admissions/${widget.admissionId}/context'),
      api.getList(
          '/api/v1/workstation/admissions/${widget.admissionId}/documents?code=$_documentCode'),
      api.getList('/api/v1/workstation/document-templates?category=DOCTOR'),
    ]);
    final records = (responses[1] as List<Map<String, dynamic>>)
        .map(Map<String, dynamic>.from)
        .toList();
    final templates = (responses[2] as List<Map<String, dynamic>>)
        .map(Map<String, dynamic>.from)
        .toList();
    final data = _AdmissionRecordData(
      context: Map<String, dynamic>.from(responses[0] as Map<String, dynamic>),
      record: _currentRecord(records),
      template: templates
          .where((item) => item['document_code'] == _documentCode)
          .cast<Map<String, dynamic>>()
          .firstOrNull,
    );
    _hydrate(data);
    return data;
  }

  Map<String, dynamic>? _currentRecord(List<Map<String, dynamic>> records) {
    final active = records
        .where((record) => record['status']?.toString() != 'VOID')
        .toList()
      ..sort((left, right) {
        final version = _asInt(right['version_no']).compareTo(_asInt(left['version_no']));
        if (version != 0) {
          return version;
        }
        return _display(right['recorded_at'])
            .compareTo(_display(left['recorded_at']));
      });
    return active.isEmpty ? null : active.first;
  }

  void _hydrate(_AdmissionRecordData data) {
    final record = data.record;
    final token = '${widget.admissionId}:${record?['record_id'] ?? 'new'}:'
        '${record?['version_no'] ?? 0}:${record?['status'] ?? ''}';
    if (_loadedToken == token) {
      return;
    }
    final content = _jsonObject(record?['content_json']);
    final fields = _jsonObject(content['fields']);
    final savedHeader = _jsonObject(content['header']);
    final admission = Map<String, dynamic>.from(data.context['admission'] as Map);
    _header = savedHeader.isEmpty ? _headerFromAdmission(admission) : savedHeader;
    for (final entry in _controllers.entries) {
      entry.value.text = fields[entry.key]?.toString() ?? '';
    }
    _neurologyEnabled = content['neurologyEnabled'] == true ||
        (content['neurologyEnabled'] == null &&
            admission['department_code']?.toString() == 'NEU');
    _loadedToken = token;
  }

  Map<String, dynamic> _headerFromAdmission(Map<String, dynamic> admission) {
    return {
      'facilityName': '海州市第一人民医院',
      'patientName': _display(admission['patient_name']),
      'gender': _gender(admission['gender']),
      'age': _age(admission['birth_date']),
      'birthDate': _display(admission['birth_date']),
      'patientNo': _display(admission['patient_no']),
      'inpatientNo': _display(admission['inpatient_no']),
      'medicalRecordNo': _display(admission['medical_record_no']),
      'bedNo': _display(admission['bed_no']),
      'departmentName': _display(admission['department_name']),
      'admissionTime': _display(admission['admission_time']),
      'doctorName': _display(admission['doctor_name']),
    };
  }

  void _reload() {
    setState(() {
      _loadedToken = null;
      _pageFuture = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdmissionRecordData>(
      future: _pageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return WorkSurface(
            child: Center(
              child: Text(apiErrorMessage(snapshot.error!)),
            ),
          );
        }
        final data = snapshot.data!;
        final record = data.record;
        final status = record?['status']?.toString();
        final editable = _canWrite && (record == null || status == 'DRAFT');
        return WorkSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              WorkspaceToolbar(
                title: '入院记录',
                subtitle: '通用病史与查体记录，神经内科可启用神经系统查体扩展。',
                actions: [
                  IconButton(
                    tooltip: '预览入院记录',
                    onPressed: () => _showPreview(data),
                    icon: const Icon(Icons.preview_outlined),
                  ),
                  IconButton(
                    tooltip: '打印或另存为 PDF',
                    onPressed: _busy ? null : _printRecord,
                    icon: const Icon(Icons.print_outlined),
                  ),
                  if (editable)
                    IconButton(
                      tooltip: '保存草稿',
                      onPressed: _busy ? null : () => _saveDraft(data),
                      icon: const Icon(Icons.save_outlined),
                    ),
                  _actionMenu(data),
                ],
              ),
              _recordStatus(status, record),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _documentHeader(),
                      const SizedBox(height: 16),
                      _historySection(editable),
                      const SizedBox(height: 14),
                      _physicalSection(editable),
                      const SizedBox(height: 14),
                      _neurologySection(editable),
                      const SizedBox(height: 14),
                      _assessmentSection(editable),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _actionMenu(_AdmissionRecordData data) {
    final status = data.record?['status']?.toString();
    final actions = <PopupMenuEntry<_RecordAction>>[
      if (_canWrite && status == 'DRAFT')
        const PopupMenuItem(
          value: _RecordAction.submit,
          child: Text('提交文书'),
        ),
      if (_canWrite && status == 'SUBMITTED')
        const PopupMenuItem(
          value: _RecordAction.sign,
          child: Text('患者意见并签名'),
        ),
      if (_canWrite && status == 'SIGNED')
        const PopupMenuItem(
          value: _RecordAction.revise,
          child: Text('发起修订'),
        ),
      if (_canWrite && (status == 'DRAFT' || status == 'SUBMITTED'))
        const PopupMenuItem(
          value: _RecordAction.voidRecord,
          child: Text('作废记录'),
        ),
    ];
    return PopupMenuButton<_RecordAction>(
      tooltip: '文书操作',
      enabled: !_busy && actions.isNotEmpty,
      icon: const Icon(Icons.more_horiz),
      onSelected: (action) => _handleAction(action, data),
      itemBuilder: (context) => actions,
    );
  }

  Widget _recordStatus(String? status, Map<String, dynamic>? record) {
    final label = switch (status) {
      null => '未创建',
      'DRAFT' => '草稿',
      'SUBMITTED' => '待签名',
      'SIGNED' => '已签名',
      _ => status,
    };
    final color = switch (status) {
      'SIGNED' => const Color(0xFF347C38),
      'SUBMITTED' => const Color(0xFF965B00),
      'DRAFT' => WorkstationColors.blue,
      _ => WorkstationColors.muted,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: const Color(0xFFF9FBFC),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('文书状态：$label',
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          if (record != null) Text('版本：${_display(record['version_no'])}'),
          if (record != null)
            Text('记录时间：${_formatDateTime(record['recorded_at'])}'),
          if (record?['author_name'] != null)
            Text('创建医师：${_display(record!['author_name'])}'),
        ],
      ),
    );
  }

  Widget _documentHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border.fromBorderSide(BorderSide(color: WorkstationColors.border)),
      ),
      child: Column(
        children: [
          Text(
            _display(_header['facilityName']),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const Text('入 院 记 录',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          Wrap(
            spacing: 24,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              _headerFact('姓名', _header['patientName']),
              _headerFact('性别', _header['gender']),
              _headerFact('年龄', '${_display(_header['age'])}岁'),
              _headerFact('床号', _header['bedNo']),
              _headerFact('科室', _header['departmentName']),
              _headerFact('住院号', _header['inpatientNo']),
              _headerFact('病案号', _header['medicalRecordNo']),
              _headerFact('入院时间', _header['admissionTime']),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerFact(String label, dynamic value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: WorkstationColors.ink, fontSize: 14),
        children: [
          TextSpan(text: '$label：', style: const TextStyle(color: WorkstationColors.muted)),
          TextSpan(text: _display(value), style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _historySection(bool editable) {
    final female = _header['gender'] == '女';
    return _section(
      '病史',
      [
        _field('主诉', 'chiefComplaint', '例：右侧肢体麻木无力 5 小时。', editable),
        _field('现病史', 'presentIllness', '例：起病时间、诱因、症状演变、既往诊疗和伴随症状。', editable),
        _field('既往史', 'pastHistory', '例：慢性病、传染病、手术外伤、输血及药物/食物过敏史。', editable),
        _field('个人史', 'personalHistory', '例：出生地、居住史、吸烟饮酒及职业暴露史。', editable),
        _field(female ? '月经婚育史' : '婚育史', 'maritalHistory',
            female ? '例：月经史、妊娠分娩史及婚育情况。' : '例：婚姻状况、子女健康情况。', editable),
        _field('家族史', 'familyHistory', '例：遗传病、心脑血管病及其他重要家族病史。', editable),
      ],
    );
  }

  Widget _physicalSection(bool editable) {
    return _section(
      '体格检查',
      [
        _field('生命体征', 'vitalSigns', '例：T、P、R、BP、身高、体重。', editable,
            compact: true),
        _field('一般情况', 'generalExam', '例：发育、营养、神志、体位、表情及查体配合情况。', editable),
        _field('皮肤黏膜与浅表淋巴结', 'skinLymph', '例：皮肤色泽、皮疹出血点及浅表淋巴结情况。', editable),
        _field('头颈部', 'headNeck', '例：头颅、眼、耳鼻咽喉、口腔、甲状腺及气管。', editable),
        _field('心肺', 'cardiopulmonary', '例：胸廓、呼吸音、心率、心律、杂音及周围血管。', editable),
        _field('腹部', 'abdomen', '例：腹形、压痛反跳痛、肝脾、肠鸣音及移动性浊音。', editable),
        _field('泌尿生殖系统', 'genitourinary', '例：肾区叩痛、膀胱区、外生殖器检查情况。', editable),
        _field('脊柱四肢', 'spineLimbs', '例：脊柱畸形、关节、杵状指趾及双下肢水肿。', editable),
      ],
    );
  }

  Widget _neurologySection(bool editable) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border.fromBorderSide(BorderSide(color: WorkstationColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
            color: WorkstationColors.heading,
            child: Row(
              children: [
                const Expanded(
                  child: Text('神经系统查体（可选）',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                Switch(
                  value: _neurologyEnabled,
                  onChanged: editable
                      ? (value) => setState(() => _neurologyEnabled = value)
                      : null,
                ),
              ],
            ),
          ),
          if (_neurologyEnabled)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _field('意识与精神状态', 'consciousnessMental',
                      '例：意识、定向力、记忆、计算及语言理解情况。', editable),
                  _field('脑神经', 'cranialNerves',
                      '例：瞳孔、眼球运动、面舌、听力、吞咽及构音。', editable),
                  _field('运动与肌张力', 'motorTone',
                      '例：肌容积、肌张力、左右肢体肌力及不自主运动。', editable),
                  _field('感觉', 'sensation', '例：浅感觉、深感觉和复合感觉检查。', editable),
                  _field('共济', 'coordination', '例：指鼻、跟膝胫、快速轮替动作。', editable),
                  _field('深浅反射', 'reflexes',
                      '例：肱二头肌、膝腱、跟腱、腹壁及角膜反射。', editable),
                  _field('病理反射', 'pathologicalSigns', '例：Babinski、Hoffmann、Gordon 征。', editable),
                  _field('脑膜刺激征', 'meningealSigns', '例：颈强直、Kernig 征、Brudzinski 征。', editable),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _assessmentSection(bool editable) {
    return _section(
      '诊疗信息',
      [
        _field('辅助检查', 'auxiliaryExam', '例：已完成检查日期、重要结果及待查项目。', editable),
        _field('初步诊断', 'preliminaryDiagnosis', '例：按序号填写疾病名称及必要的分型/部位。', editable),
        _field('诊断依据', 'diagnosticBasis', '例：病史、体征、实验室及影像学依据。', editable),
        _field('诊疗计划', 'treatmentPlan', '例：进一步检查、治疗、护理、会诊及风险告知计划。', editable),
        _field('患者或家属意见', 'patientOpinion', '例：已知情并同意诊疗计划，或记录具体意见。', editable),
      ],
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border.fromBorderSide(BorderSide(color: WorkstationColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: WorkstationColors.heading,
            child: Text(title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    String key,
    String hint,
    bool editable, {
    bool compact = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        key: ValueKey('admission-field-$key'),
        controller: _controllers[key],
        enabled: editable,
        minLines: compact ? 2 : 3,
        maxLines: compact ? 4 : 8,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          alignLabelWithHint: true,
          filled: !editable,
        ),
      ),
    );
  }

  Future<void> _handleAction(
      _RecordAction action, _AdmissionRecordData data) async {
    switch (action) {
      case _RecordAction.submit:
        await _submit(data);
      case _RecordAction.sign:
        await _sign(data);
      case _RecordAction.revise:
        await _revise(data);
      case _RecordAction.voidRecord:
        await _voidRecord(data);
    }
  }

  Future<int?> _saveDraft(
    _AdmissionRecordData data, {
    bool notify = true,
    bool reload = true,
  }) async {
    final templateId = _asInt(data.template?['template_id']);
    if (data.record == null && templateId == 0) {
      showOperationMessage(context, '未找到入院记录模板，请联系管理员。', error: true);
      return null;
    }
    final payload = _documentPayload();
    setState(() => _busy = true);
    try {
      int recordId;
      if (data.record == null) {
        final created = await ref.read(apiClientProvider).postObject(
              '/api/v1/workstation/admissions/${widget.admissionId}/documents',
              {
                'templateId': templateId,
                'documentCode': _documentCode,
                'title': '入院记录',
                ...payload,
              },
            );
        recordId = _asInt(created['recordId']);
      } else {
        recordId = _asInt(data.record!['record_id']);
        await ref.read(apiClientProvider).putVoid(
              '/api/v1/workstation/documents/$recordId',
              {'title': '入院记录', ...payload},
            );
      }
      if (!mounted) {
        return recordId;
      }
      if (notify) {
        showOperationMessage(context, '入院记录草稿已保存。');
      }
      if (reload) {
        _reload();
        widget.onChanged?.call();
      }
      return recordId;
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _submit(_AdmissionRecordData data) async {
    final recordId = await _saveDraft(data, notify: false, reload: false);
    if (recordId == null || !mounted) {
      return;
    }
    await _runLifecycle(
      () => ref
          .read(apiClientProvider)
          .postVoid('/api/v1/workstation/documents/$recordId/submit', {}),
      '入院记录已提交，等待签名。',
    );
  }

  Future<void> _sign(_AdmissionRecordData data) async {
    final opinion = await showTextFormDialog(
      context,
      title: '患者意见与医师签名',
      fields: [
        FieldSpec(
          'patientOpinion',
          '患者或家属意见',
          multiline: true,
          initialValue: _controllers['patientOpinion']!.text,
        ),
      ],
      submitLabel: '确认签名',
    );
    final recordId = _asInt(data.record?['record_id']);
    if (opinion == null || recordId == 0) {
      return;
    }
    await _runLifecycle(
      () => ref.read(apiClientProvider).postVoid(
            '/api/v1/workstation/documents/$recordId/sign',
            opinion,
          ),
      '入院记录已签名。',
    );
  }

  Future<void> _revise(_AdmissionRecordData data) async {
    final values = await showTextFormDialog(
      context,
      title: '修订入院记录',
      fields: const [FieldSpec('reason', '修订原因', required: true, multiline: true)],
      submitLabel: '生成修订草稿',
    );
    final recordId = _asInt(data.record?['record_id']);
    if (values == null || recordId == 0) {
      return;
    }
    await _runLifecycle(
      () => ref.read(apiClientProvider).postVoid(
            '/api/v1/workstation/documents/$recordId/revise',
            values,
          ),
      '已创建入院记录修订草稿。',
    );
  }

  Future<void> _voidRecord(_AdmissionRecordData data) async {
    final values = await showTextFormDialog(
      context,
      title: '作废入院记录',
      fields: const [FieldSpec('reason', '作废原因', required: true, multiline: true)],
      submitLabel: '确认作废',
    );
    final recordId = _asInt(data.record?['record_id']);
    if (values == null || recordId == 0) {
      return;
    }
    await _runLifecycle(
      () => ref.read(apiClientProvider).postVoid(
            '/api/v1/workstation/documents/$recordId/void',
            values,
          ),
      '入院记录已作废。',
    );
  }

  Future<void> _runLifecycle(
    Future<void> Function() action,
    String successMessage,
  ) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) {
        return;
      }
      showOperationMessage(context, successMessage);
      _reload();
      widget.onChanged?.call();
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Map<String, dynamic> _documentPayload() {
    final fields = <String, String>{
      for (final entry in _controllers.entries)
        if (entry.value.text.trim().isNotEmpty) entry.key: entry.value.text.trim(),
    };
    final content = _plainContent(fields);
    return {
      'content': content,
      'contentJson': jsonEncode({
        'templateCode': _documentCode,
        'templateVersion': 1,
        'header': _header,
        'fields': fields,
        'neurologyEnabled': _neurologyEnabled,
      }),
    };
  }

  String _plainContent(Map<String, String> fields) {
    final buffer = StringBuffer('入院记录');
    for (final section in _documentSections(fields, _neurologyEnabled)) {
      if (section.values.isEmpty) {
        continue;
      }
      buffer.write('\n\n${section.title}');
      for (final entry in section.values.entries) {
        buffer.write('\n${entry.key}：${entry.value}');
      }
    }
    return buffer.toString();
  }

  Future<void> _showPreview(_AdmissionRecordData data) {
    final record = data.record;
    final fields = _currentFields();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 900,
          height: 760,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('入院记录预览',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      tooltip: '打印或另存为 PDF',
                      onPressed: _printRecord,
                      icon: const Icon(Icons.print_outlined),
                    ),
                    IconButton(
                      tooltip: '关闭预览',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: _FormalAdmissionRecord(
                    header: _header,
                    fields: fields,
                    neurologyEnabled: _neurologyEnabled,
                    status: record?['status']?.toString(),
                    patientOpinion: record?['patient_opinion']?.toString(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _printRecord() async {
    try {
      await Printing.layoutPdf(
        name: '入院记录_${_display(_header['medicalRecordNo'])}',
        onLayout: _buildPdf,
      );
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, '无法生成打印文档：${apiErrorMessage(error)}', error: true);
      }
    }
  }

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    final regular = await PdfGoogleFonts.notoSansSCRegular();
    final bold = await PdfGoogleFonts.notoSansSCBold();
    final fields = _currentFields();
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: format,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        margin: const pw.EdgeInsets.fromLTRB(44, 40, 44, 40),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              _display(_header['facilityName']),
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text('入 院 记 录',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 14),
          pw.Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _pdfHeaderFact('姓名', _header['patientName']),
              _pdfHeaderFact('性别', _header['gender']),
              _pdfHeaderFact('年龄', '${_display(_header['age'])}岁'),
              _pdfHeaderFact('床号', _header['bedNo']),
              _pdfHeaderFact('科室', _header['departmentName']),
              _pdfHeaderFact('住院号', _header['inpatientNo']),
              _pdfHeaderFact('病案号', _header['medicalRecordNo']),
              _pdfHeaderFact('入院时间', _header['admissionTime']),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Divider(),
          ..._documentSections(fields, _neurologyEnabled).expand((section) {
            if (section.values.isEmpty) {
              return const <pw.Widget>[];
            }
            return <pw.Widget>[
              pw.SizedBox(height: 10),
              pw.Text(section.title,
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              ...section.values.entries.map(
                (entry) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 5),
                  child: pw.RichText(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                          text: '${entry.key}：',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        pw.TextSpan(text: entry.value),
                      ],
                    ),
                  ),
                ),
              ),
            ];
          }),
          pw.SizedBox(height: 24),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('医师签名：${_display(_header['doctorName'])}'),
              pw.Text('记录日期：${_formatDateTime(DateTime.now().toIso8601String())}'),
            ],
          ),
        ],
      ),
    );
    return document.save();
  }

  pw.Widget _pdfHeaderFact(String label, dynamic value) =>
      pw.Text('$label：${_display(value)}', style: const pw.TextStyle(fontSize: 9));

  Map<String, String> _currentFields() => {
        for (final entry in _controllers.entries)
          if (entry.value.text.trim().isNotEmpty) entry.key: entry.value.text.trim(),
      };

  Map<String, dynamic> _jsonObject(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
      } on FormatException {
        return const {};
      }
    }
    return const {};
  }

  int _asInt(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  String _display(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text == 'null' ? '-' : text;
  }

  String _gender(dynamic value) => value == 'MALE'
      ? '男'
      : value == 'FEMALE'
          ? '女'
          : '-';

  String _age(dynamic value) {
    final text = value?.toString();
    final year = text == null || text.length < 4 ? null : int.tryParse(text.substring(0, 4));
    return year == null ? '-' : '${DateTime.now().year - year}';
  }

  String _formatDateTime(dynamic value) {
    final text = _display(value).replaceFirst('T', ' ');
    return text.length > 16 ? text.substring(0, 16) : text;
  }
}

class _AdmissionRecordData {
  const _AdmissionRecordData({
    required this.context,
    required this.record,
    required this.template,
  });

  final Map<String, dynamic> context;
  final Map<String, dynamic>? record;
  final Map<String, dynamic>? template;
}

class _DocumentSection {
  const _DocumentSection(this.title, this.values);

  final String title;
  final Map<String, String> values;
}

enum _RecordAction { submit, sign, revise, voidRecord }

class _FormalAdmissionRecord extends StatelessWidget {
  const _FormalAdmissionRecord({
    required this.header,
    required this.fields,
    required this.neurologyEnabled,
    required this.status,
    required this.patientOpinion,
  });

  final Map<String, dynamic> header;
  final Map<String, String> fields;
  final bool neurologyEnabled;
  final String? status;
  final String? patientOpinion;

  @override
  Widget build(BuildContext context) {
    final effectiveFields = Map<String, String>.from(fields);
    if ((patientOpinion?.trim().isNotEmpty ?? false)) {
      effectiveFields['patientOpinion'] = patientOpinion!.trim();
    }
    final sections = _documentSections(effectiveFields, neurologyEnabled);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(30, 24, 30, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_text(header['facilityName']),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const Text('入 院 记 录',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _fact('姓名', header['patientName']),
              _fact('性别', header['gender']),
              _fact('年龄', '${_text(header['age'])}岁'),
              _fact('床号', header['bedNo']),
              _fact('科室', header['departmentName']),
              _fact('住院号', header['inpatientNo']),
              _fact('病案号', header['medicalRecordNo']),
              _fact('入院时间', header['admissionTime']),
            ],
          ),
          const Divider(height: 28),
          ...sections.expand((section) {
            if (section.values.isEmpty) {
              return const <Widget>[];
            }
            return [
              Text(section.title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ...section.values.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(color: WorkstationColors.ink, height: 1.55),
                      children: [
                        TextSpan(
                          text: '${entry.key}：',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: entry.value),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ];
          }),
          const Divider(height: 30),
          Wrap(
            spacing: 28,
            runSpacing: 8,
            children: [
              Text('文书状态：${_statusText(status)}'),
              Text('医师签名：${_text(header['doctorName'])}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fact(String label, dynamic value) => Text('$label：${_text(value)}');

  String _text(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text == 'null' ? '-' : text;
  }

  String _statusText(String? value) => switch (value) {
        'DRAFT' => '草稿',
        'SUBMITTED' => '待签名',
        'SIGNED' => '已签名',
        _ => value ?? '未创建',
      };
}

List<_DocumentSection> _documentSections(
  Map<String, String> fields,
  bool neurologyEnabled,
) {
  Map<String, String> valuesFor(List<String> keys) => {
        for (final key in keys)
          if ((fields[key] ?? '').trim().isNotEmpty) _fieldLabels[key]!: fields[key]!.trim(),
      };
  return [
    _DocumentSection('病史', valuesFor(_historyKeys)),
    _DocumentSection('体格检查', valuesFor(_physicalKeys)),
    if (neurologyEnabled) _DocumentSection('神经系统查体', valuesFor(_neurologyKeys)),
    _DocumentSection('诊疗信息', valuesFor(_assessmentKeys)),
  ];
}

const _historyKeys = [
  'chiefComplaint',
  'presentIllness',
  'pastHistory',
  'personalHistory',
  'maritalHistory',
  'familyHistory',
];

const _physicalKeys = [
  'vitalSigns',
  'generalExam',
  'skinLymph',
  'headNeck',
  'cardiopulmonary',
  'abdomen',
  'genitourinary',
  'spineLimbs',
];

const _neurologyKeys = [
  'consciousnessMental',
  'cranialNerves',
  'motorTone',
  'sensation',
  'coordination',
  'reflexes',
  'pathologicalSigns',
  'meningealSigns',
];

const _assessmentKeys = [
  'auxiliaryExam',
  'preliminaryDiagnosis',
  'diagnosticBasis',
  'treatmentPlan',
  'patientOpinion',
];

const _fieldLabels = <String, String>{
  'chiefComplaint': '主诉',
  'presentIllness': '现病史',
  'pastHistory': '既往史',
  'personalHistory': '个人史',
  'maritalHistory': '婚育/月经史',
  'familyHistory': '家族史',
  'vitalSigns': '生命体征',
  'generalExam': '一般情况',
  'skinLymph': '皮肤黏膜与浅表淋巴结',
  'headNeck': '头颈部',
  'cardiopulmonary': '心肺',
  'abdomen': '腹部',
  'genitourinary': '泌尿生殖系统',
  'spineLimbs': '脊柱四肢',
  'consciousnessMental': '意识与精神状态',
  'cranialNerves': '脑神经',
  'motorTone': '运动与肌张力',
  'sensation': '感觉',
  'coordination': '共济',
  'reflexes': '深浅反射',
  'pathologicalSigns': '病理反射',
  'meningealSigns': '脑膜刺激征',
  'auxiliaryExam': '辅助检查',
  'preliminaryDiagnosis': '初步诊断',
  'diagnosticBasis': '诊断依据',
  'treatmentPlan': '诊疗计划',
  'patientOpinion': '患者或家属意见',
};

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
