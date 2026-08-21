import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 每名住院患者独立保存一份待插入的报告摘要，避免切换患者后误引用。
final pendingReportCitationProvider =
    StateProvider.family<String?, int>((ref, admissionId) => null);
