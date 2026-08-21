import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ui_helpers.dart';
import '../../core/workstation_ui.dart';
import '../auth/auth_controller.dart';

enum VitalColumn {
  measuredAt,
  temperature,
  pulse,
  respiratoryRate,
  heartRate,
  bloodPressure,
  spo2,
  painScore,
  analgesicPainScore,
  breakthroughPainScore,
  height,
  weight,
  intake,
  output,
}

extension on VitalColumn {
  String get label => switch (this) {
        VitalColumn.measuredAt => '时间',
        VitalColumn.temperature => '体温',
        VitalColumn.pulse => '脉搏',
        VitalColumn.respiratoryRate => '呼吸',
        VitalColumn.heartRate => '心率',
        VitalColumn.bloodPressure => '血压',
        VitalColumn.spo2 => 'SpO2',
        VitalColumn.painScore => '疼痛强度',
        VitalColumn.analgesicPainScore => '镇痛强度',
        VitalColumn.breakthroughPainScore => '突发疼痛',
        VitalColumn.height => '身高',
        VitalColumn.weight => '体重',
        VitalColumn.intake => '入量',
        VitalColumn.output => '出量',
      };

  double get width => switch (this) {
        VitalColumn.measuredAt => 126,
        VitalColumn.bloodPressure => 108,
        VitalColumn.analgesicPainScore ||
        VitalColumn.breakthroughPainScore =>
          100,
        _ => 82,
      };
}

enum VitalPreviewMetric {
  temperature,
  pulse,
  respiratoryRate,
  heartRate,
  bloodPressure,
  spo2,
  painScore,
  analgesicPainScore,
  breakthroughPainScore,
  intake,
  output,
}

extension on VitalPreviewMetric {
  String get label => switch (this) {
        VitalPreviewMetric.temperature => '体温',
        VitalPreviewMetric.pulse => '脉搏',
        VitalPreviewMetric.respiratoryRate => '呼吸',
        VitalPreviewMetric.heartRate => '心率',
        VitalPreviewMetric.bloodPressure => '血压',
        VitalPreviewMetric.spo2 => 'SpO2',
        VitalPreviewMetric.painScore => '疼痛强度',
        VitalPreviewMetric.analgesicPainScore => '镇痛强度',
        VitalPreviewMetric.breakthroughPainScore => '突发疼痛',
        VitalPreviewMetric.intake => '入量',
        VitalPreviewMetric.output => '出量',
      };

  String get unit => switch (this) {
        VitalPreviewMetric.temperature => '℃',
        VitalPreviewMetric.pulse || VitalPreviewMetric.heartRate => '次/分',
        VitalPreviewMetric.respiratoryRate => '次/分',
        VitalPreviewMetric.bloodPressure => 'mmHg',
        VitalPreviewMetric.spo2 => '%',
        VitalPreviewMetric.painScore ||
        VitalPreviewMetric.analgesicPainScore ||
        VitalPreviewMetric.breakthroughPainScore =>
          '分',
        VitalPreviewMetric.intake || VitalPreviewMetric.output => 'ml',
      };
}

/// 医师端按日查阅体征，护士在同一页面补录护理测量数据。
class VitalSignsPage extends ConsumerStatefulWidget {
  const VitalSignsPage({
    super.key,
    required this.admissionId,
    required this.role,
    this.patientHeightCm,
    this.patientWeightKg,
  });

  final int admissionId;
  final String role;
  final num? patientHeightCm;
  final num? patientWeightKg;

  @override
  ConsumerState<VitalSignsPage> createState() => _VitalSignsPageState();
}

class _VitalSignsPageState extends ConsumerState<VitalSignsPage> {
  static const _defaultColumns = <VitalColumn, bool>{
    VitalColumn.measuredAt: true,
    VitalColumn.temperature: true,
    VitalColumn.pulse: true,
    VitalColumn.respiratoryRate: true,
    VitalColumn.heartRate: true,
    VitalColumn.bloodPressure: true,
    VitalColumn.spo2: true,
    VitalColumn.painScore: false,
    VitalColumn.analgesicPainScore: false,
    VitalColumn.breakthroughPainScore: false,
    VitalColumn.height: false,
    VitalColumn.weight: false,
    VitalColumn.intake: false,
    VitalColumn.output: false,
  };

  late DateTime _selectedDate;
  late Future<List<Map<String, dynamic>>> _recordsFuture;
  late Map<VitalColumn, bool> _visibleColumns;
  bool _showUnits = true;
  VitalPreviewMetric _previewMetric = VitalPreviewMetric.temperature;

  bool get _isNurse => widget.role == 'NURSE';

  @override
  void initState() {
    super.initState();
    _selectedDate = DateUtils.dateOnly(DateTime.now());
    _visibleColumns = Map<VitalColumn, bool>.from(_defaultColumns);
    _recordsFuture = _loadRecords();
  }

  @override
  void didUpdateWidget(covariant VitalSignsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.admissionId != widget.admissionId) {
      _selectedDate = DateUtils.dateOnly(DateTime.now());
      _recordsFuture = _loadRecords();
    }
  }

  Future<List<Map<String, dynamic>>> _loadRecords() {
    final from = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final to = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      23,
      59,
      59,
    );
    final query = 'from=${Uri.encodeQueryComponent(from.toIso8601String())}'
        '&to=${Uri.encodeQueryComponent(to.toIso8601String())}';
    return ref.read(apiClientProvider).getList(
        '/api/v1/workstation/admissions/${widget.admissionId}/temperature-chart?$query');
  }

  void _reload() {
    setState(() => _recordsFuture = _loadRecords());
  }

  void _changeDay(int days) {
    setState(() {
      _selectedDate = DateUtils.dateOnly(
        _selectedDate.add(Duration(days: days)),
      );
      _recordsFuture = _loadRecords();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _selectedDate = DateUtils.dateOnly(picked);
      _recordsFuture = _loadRecords();
    });
  }

  @override
  Widget build(BuildContext context) {
    return WorkSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceToolbar(
            title: '体征',
            subtitle: '按测量时间查看生命体征与护理出入量。',
            actions: [
              if (_isNurse)
                IconButton(
                  tooltip: '录入生命体征',
                  onPressed: _createVitalSign,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              IconButton(
                tooltip: '刷新体征',
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          _filterBar(),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _recordsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(apiErrorMessage(snapshot.error!)));
                }
                final rows = snapshot.data ?? const <Map<String, dynamic>>[];
                return _recordsAndPreview(rows);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FBFC),
        border: Border(bottom: BorderSide(color: WorkstationColors.border)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: Text(DateFormat('yyyy-MM-dd').format(_selectedDate)),
          ),
          IconButton(
            tooltip: '前一天',
            onPressed: () => _changeDay(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: '后一天',
            onPressed: () => _changeDay(1),
            icon: const Icon(Icons.chevron_right),
          ),
          OutlinedButton.icon(
            onPressed: _configureColumns,
            icon: const Icon(Icons.view_column_outlined, size: 18),
            label: const Text('列显示'),
          ),
          InkWell(
            onTap: () => setState(() => _showUnits = !_showUnits),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _showUnits,
                  onChanged: (value) =>
                      setState(() => _showUnits = value ?? false),
                ),
                const Text('单位'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordsAndPreview(List<Map<String, dynamic>> rows) {
    return Column(
      children: [
        Expanded(child: _vitalTable(rows)),
        const Divider(height: 1, color: WorkstationColors.border),
        SizedBox(height: 238, child: _trendPreview(rows)),
      ],
    );
  }

  Widget _vitalTable(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const Center(
        child: Text(
          '该日期暂无体征记录。',
          style: TextStyle(color: WorkstationColors.muted),
        ),
      );
    }
    final columns = VitalColumn.values
        .where((column) => _visibleColumns[column] ?? false)
        .toList();
    final width = math.max(
      880.0,
      columns.fold<double>(24, (total, column) => total + column.width + 16),
    ).toDouble();
    return Scrollbar(
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: width),
            child: DataTable(
              headingRowColor:
                  const WidgetStatePropertyAll(WorkstationColors.heading),
              headingRowHeight: 46,
              dataRowMinHeight: 50,
              dataRowMaxHeight: 58,
              columnSpacing: 16,
              horizontalMargin: 12,
              dividerThickness: 0.8,
              columns: columns
                  .map(
                    (column) => DataColumn(
                      label: SizedBox(
                        width: column.width,
                        child: Text(
                          column.label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  )
                  .toList(),
              rows: rows
                  .map(
                    (row) => DataRow(
                      cells: columns
                          .map(
                            (column) => DataCell(
                              SizedBox(
                                width: column.width,
                                child: Text(
                                  _cellValue(column, row),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _trendPreview(List<Map<String, dynamic>> rows) {
    final series = _seriesFor(rows);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('预览：', style: TextStyle(fontWeight: FontWeight.w700)),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: VitalPreviewMetric.values
                        .map(_previewMetricButton)
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_previewMetric.label}趋势（${_previewMetric.unit}）',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: WorkstationColors.muted,
                ),
          ),
          const SizedBox(height: 4),
          Expanded(child: _VitalTrendChart(day: _selectedDate, series: series)),
        ],
      ),
    );
  }

  Widget _previewMetricButton(VitalPreviewMetric metric) {
    final selected = metric == _previewMetric;
    return TextButton(
      onPressed: () => setState(() => _previewMetric = metric),
      style: TextButton.styleFrom(
        foregroundColor:
            selected ? WorkstationColors.blue : WorkstationColors.muted,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? WorkstationColors.cyan : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(metric.label),
        ),
      ),
    );
  }

  String _cellValue(VitalColumn column, Map<String, dynamic> row) {
    return switch (column) {
      VitalColumn.measuredAt => _timeText(row['measured_at']),
      VitalColumn.temperature => _number(row['temperature'], '℃'),
      VitalColumn.pulse => _number(row['pulse'], '次/分'),
      VitalColumn.respiratoryRate => _number(row['respiratory_rate'], '次/分'),
      VitalColumn.heartRate => _number(row['heart_rate'], '次/分'),
      VitalColumn.bloodPressure => _bloodPressure(row),
      VitalColumn.spo2 => _number(row['spo2'], '%'),
      VitalColumn.painScore => _number(row['pain_score'], '分'),
      VitalColumn.analgesicPainScore =>
        _number(row['analgesic_pain_score'], '分'),
      VitalColumn.breakthroughPainScore =>
        _number(row['breakthrough_pain_score'], '分'),
      VitalColumn.height => _number(widget.patientHeightCm, 'cm'),
      VitalColumn.weight => _number(widget.patientWeightKg, 'kg'),
      VitalColumn.intake => _number(row['intake_ml'], 'ml'),
      VitalColumn.output => _number(row['output_ml'], 'ml'),
    };
  }

  String _bloodPressure(Map<String, dynamic> row) {
    final systolic = _plainNumber(row['systolic_bp']);
    final diastolic = _plainNumber(row['diastolic_bp']);
    if (systolic == null && diastolic == null) {
      return '-';
    }
    final value = '${systolic ?? '-'}/${diastolic ?? '-'}';
    return _showUnits ? '$value mmHg' : value;
  }

  String _number(dynamic value, String unit) {
    final formatted = _plainNumber(value);
    if (formatted == null) {
      return '-';
    }
    return _showUnits ? '$formatted $unit' : formatted;
  }

  String? _plainNumber(dynamic value) {
    if (value == null) {
      return null;
    }
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null) {
      return value.toString();
    }
    if (number == number.roundToDouble()) {
      return number.round().toString();
    }
    return number.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  String _timeText(dynamic value) {
    final time = _dateTime(value);
    return time == null ? '-' : DateFormat('yyyy-MM-dd\nHH:mm').format(time);
  }

  DateTime? _dateTime(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString().replaceFirst(' ', 'T'));
  }

  List<_VitalTrendSeries> _seriesFor(List<Map<String, dynamic>> rows) {
    List<_VitalTrendPoint> pointsFor(String key) => rows
        .map((row) {
          final time = _dateTime(row['measured_at']);
          final value = row[key] is num
              ? (row[key] as num).toDouble()
              : double.tryParse('${row[key]}');
          return time == null || value == null
              ? null
              : _VitalTrendPoint(time, value);
        })
        .whereType<_VitalTrendPoint>()
        .toList();

    _VitalTrendSeries single(String key, Color color) => _VitalTrendSeries(
          label: _previewMetric.label,
          color: color,
          points: pointsFor(key),
        );

    return switch (_previewMetric) {
      VitalPreviewMetric.temperature => [single('temperature', Colors.red)],
      VitalPreviewMetric.pulse => [single('pulse', WorkstationColors.cyan)],
      VitalPreviewMetric.respiratoryRate =>
        [single('respiratory_rate', Colors.deepPurple)],
      VitalPreviewMetric.heartRate =>
        [single('heart_rate', Colors.pink.shade700)],
      VitalPreviewMetric.bloodPressure => [
          _VitalTrendSeries(
            label: '收缩压',
            color: Colors.red.shade700,
            points: pointsFor('systolic_bp'),
          ),
          _VitalTrendSeries(
            label: '舒张压',
            color: WorkstationColors.blue,
            points: pointsFor('diastolic_bp'),
          ),
        ],
      VitalPreviewMetric.spo2 => [single('spo2', Colors.teal)],
      VitalPreviewMetric.painScore => [single('pain_score', Colors.orange)],
      VitalPreviewMetric.analgesicPainScore =>
        [single('analgesic_pain_score', Colors.amber.shade800)],
      VitalPreviewMetric.breakthroughPainScore =>
        [single('breakthrough_pain_score', Colors.deepOrange)],
      VitalPreviewMetric.intake => [single('intake_ml', Colors.indigo)],
      VitalPreviewMetric.output => [single('output_ml', Colors.green.shade700)],
    };
  }

  Future<void> _configureColumns() async {
    final draft = Map<VitalColumn, bool>.from(_visibleColumns);
    final result = await showDialog<Map<VitalColumn, bool>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('显示列'),
          content: SizedBox(
            width: 390,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: VitalColumn.values
                    .map(
                      (column) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: draft[column] ?? false,
                        title: Text(column.label),
                        onChanged: (value) => setDialogState(
                          () => draft[column] = value ?? false,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: draft.values.any((visible) => visible)
                  ? () => Navigator.pop(dialogContext, draft)
                  : null,
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _visibleColumns = result);
    }
  }

  Future<void> _createVitalSign() async {
    final values = await showTextFormDialog(
      context,
      title: '录入生命体征',
      fields: const [
        FieldSpec('temperature', '体温', numeric: true, decimal: true),
        FieldSpec('pulse', '脉搏', numeric: true),
        FieldSpec('heartRate', '心率', numeric: true),
        FieldSpec('respiratoryRate', '呼吸频率', numeric: true),
        FieldSpec('systolicBp', '收缩压', numeric: true),
        FieldSpec('diastolicBp', '舒张压', numeric: true),
        FieldSpec('spo2', '血氧饱和度', numeric: true, decimal: true),
        FieldSpec('painScore', '疼痛强度（0-10）', numeric: true),
        FieldSpec('analgesicPainScore', '镇痛强度（0-10）', numeric: true),
        FieldSpec('breakthroughPainScore', '突发疼痛（0-10）', numeric: true),
        FieldSpec('consciousness', '意识状态', initialValue: '清醒'),
        FieldSpec('intakeMl', '入量（ml）', numeric: true, decimal: true),
        FieldSpec('outputMl', '出量（ml）', numeric: true, decimal: true),
        FieldSpec('remark', '备注'),
      ],
    );
    if (values == null) {
      return;
    }
    try {
      await ref.read(apiClientProvider).postVoid(
            '/api/v1/workstation/admissions/${widget.admissionId}/vital-signs',
            values,
          );
      if (mounted) {
        showOperationMessage(context, '生命体征已记录。');
        _reload();
      }
    } catch (error) {
      if (mounted) {
        showOperationMessage(context, apiErrorMessage(error), error: true);
      }
    }
  }
}

class _VitalTrendPoint {
  const _VitalTrendPoint(this.time, this.value);

  final DateTime time;
  final double value;
}

class _VitalTrendSeries {
  const _VitalTrendSeries({
    required this.label,
    required this.color,
    required this.points,
  });

  final String label;
  final Color color;
  final List<_VitalTrendPoint> points;
}

class _VitalTrendChart extends StatelessWidget {
  const _VitalTrendChart({required this.day, required this.series});

  final DateTime day;
  final List<_VitalTrendSeries> series;

  @override
  Widget build(BuildContext context) {
    final hasData = series.any((item) => item.points.isNotEmpty);
    if (!hasData) {
      return const Center(
        child: Text(
          '当日暂无该指标的趋势数据。',
          style: TextStyle(color: WorkstationColors.muted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (series.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Wrap(
              spacing: 12,
              children: series
                  .map(
                    (item) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 10, height: 3, color: item.color),
                        const SizedBox(width: 4),
                        Text(item.label, style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        Expanded(
          child: CustomPaint(
            painter: _VitalTrendPainter(day: day, series: series),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

class _VitalTrendPainter extends CustomPainter {
  const _VitalTrendPainter({required this.day, required this.series});

  final DateTime day;
  final List<_VitalTrendSeries> series;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 120 || size.height < 80) {
      return;
    }
    final plot = Rect.fromLTWH(48, 10, size.width - 68, size.height - 38);
    final points = series.expand((item) => item.points).toList();
    var minimum = points
        .map((item) => item.value)
        .reduce((first, next) => first < next ? first : next);
    var maximum = points
        .map((item) => item.value)
        .reduce((first, next) => first > next ? first : next);
    if (minimum == maximum) {
      final padding = math.max(1, minimum.abs() * 0.1);
      minimum -= padding;
      maximum += padding;
    } else {
      final padding = (maximum - minimum) * 0.1;
      minimum -= padding;
      maximum += padding;
    }

    final gridPaint = Paint()
      ..color = WorkstationColors.border
      ..strokeWidth = 1;
    for (var step = 0; step <= 4; step++) {
      final y = plot.top + plot.height * step / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      final value = maximum - (maximum - minimum) * step / 4;
      _drawText(canvas, _axisValue(value), Offset(2, y - 7));
    }
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, gridPaint);

    const hourLabels = [0, 6, 12, 18, 24];
    for (final hour in hourLabels) {
      final x = plot.left + plot.width * hour / 24;
      _drawText(canvas, '${hour.toString().padLeft(2, '0')}:00', Offset(x - 13, plot.bottom + 5));
    }

    final dayStart = DateTime(day.year, day.month, day.day);
    canvas.save();
    canvas.clipRect(plot);
    for (final item in series) {
      final line = Path();
      for (var index = 0; index < item.points.length; index++) {
        final point = item.points[index];
        final hours = point.time.difference(dayStart).inMinutes / 60;
        final fraction = hours.clamp(0, 24).toDouble() / 24;
        final x = plot.left + plot.width * fraction;
        final y = plot.bottom - plot.height * ((point.value - minimum) / (maximum - minimum));
        if (index == 0) {
          line.moveTo(x, y);
        } else {
          line.lineTo(x, y);
        }
      }
      final linePaint = Paint()
        ..color = item.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawPath(line, linePaint);
      final pointPaint = Paint()..color = item.color;
      for (final point in item.points) {
        final hours = point.time.difference(dayStart).inMinutes / 60;
        final fraction = hours.clamp(0, 24).toDouble() / 24;
        final x = plot.left + plot.width * fraction;
        final y = plot.bottom - plot.height * ((point.value - minimum) / (maximum - minimum));
        canvas.drawCircle(Offset(x, y), 3, pointPaint);
      }
    }
    canvas.restore();
  }

  String _axisValue(double value) {
    if (value.abs() >= 100 || value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }

  void _drawText(Canvas canvas, String text, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 10, color: WorkstationColors.muted),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _VitalTrendPainter oldDelegate) {
    return oldDelegate.day != day || oldDelegate.series != series;
  }
}
