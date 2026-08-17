import 'package:flutter/material.dart';

/// 参考临床工作站界面提炼的基础色，集中定义以保证三类岗位页面一致。
abstract final class WorkstationColors {
  static const navy = Color(0xFF0B2F40);
  static const blue = Color(0xFF006B91);
  static const cyan = Color(0xFF008EBA);
  static const amber = Color(0xFFF6E1B8);
  static const canvas = Color(0xFFF1F4F6);
  static const border = Color(0xFFD4DEE3);
  static const heading = Color(0xFFE7F1F5);
  static const ink = Color(0xFF1E2D35);
  static const muted = Color(0xFF61727C);
}

/// 工作区统一标题栏，替代每个页面各自零散的标题与操作按钮布局。
class WorkspaceToolbar extends StatelessWidget {
  const WorkspaceToolbar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: WorkstationColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 32,
            color: WorkstationColors.cyan,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: WorkstationColors.muted,
                        ),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// 统一的白底业务面板，保留医院系统常见的细边框和紧凑留白。
class WorkSurface extends StatelessWidget {
  const WorkSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border.fromBorderSide(
          BorderSide(color: WorkstationColors.border),
        ),
      ),
      child: child,
    );
  }
}

/// 医师工作台的患者上下文带，避免医嘱和病历在无患者信息的状态下操作。
class PatientContextBar extends StatelessWidget {
  const PatientContextBar({
    super.key,
    required this.name,
    required this.inpatientNo,
    required this.department,
    required this.bedNo,
    this.doctor,
  });

  final String name;
  final String inpatientNo;
  final String department;
  final String bedNo;
  final String? doctor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: WorkstationColors.amber,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 28,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white70,
                foregroundColor: WorkstationColors.blue,
                child: Icon(Icons.person),
              ),
              const SizedBox(width: 10),
              Text(name, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          _PatientFact(label: '住院号', value: inpatientNo),
          _PatientFact(label: '科室', value: department),
          _PatientFact(label: '床位', value: bedNo),
          if (doctor != null) _PatientFact(label: '责任医师', value: doctor!),
        ],
      ),
    );
  }
}

class _PatientFact extends StatelessWidget {
  const _PatientFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: WorkstationColors.ink,
            ),
        children: [
          TextSpan(
              text: '$label  ',
              style: const TextStyle(color: WorkstationColors.muted)),
          TextSpan(
              text: value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// 统一二级模块页签，强调当前工作模块并与主体内容以细线分隔。
class WorkstationTabBar extends StatelessWidget implements PreferredSizeWidget {
  const WorkstationTabBar(
      {super.key, required this.tabs, this.isScrollable = true});

  final List<Widget> tabs;
  final bool isScrollable;

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: WorkstationColors.border)),
      ),
      child: TabBar(isScrollable: isScrollable, tabs: tabs),
    );
  }
}
