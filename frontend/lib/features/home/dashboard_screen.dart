import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/workstation_ui.dart';
import '../admin/admin_workspace.dart';
import '../admission/admission_workspace.dart';
import '../auth/auth_controller.dart';
import '../clinical/clinical_workspace.dart';
import '../clinical/clinical_workstation.dart';

/// 三种角色共用的临床工作站外壳；具体业务页面仍按岗位独立实现。
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  var _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/login'));
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final isClinicalWorkstation = user.role == 'DOCTOR' || user.role == 'NURSE';
    final content =
        _selectedIndex == 0 ? _workspaceFor(user.role) : _accountPanel(user);

    return Scaffold(
      body: Column(
        children: [
          _ConsoleHeader(
            userName: user.realName,
            roleName: _roleName(user.role),
            onLogout: () async {
              await ref.read(authControllerProvider).logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
          Expanded(
            child: isClinicalWorkstation && _selectedIndex == 0
                ? content
                : isDesktop
                    ? Row(
                        children: [
                          _WorkstationSidebar(
                            selectedIndex: _selectedIndex,
                            roleName: _roleName(user.role),
                            onSelected: (index) =>
                                setState(() => _selectedIndex = index),
                          ),
                          Expanded(child: content),
                        ],
                      )
                    : content,
          ),
        ],
      ),
      bottomNavigationBar: isDesktop
          ? null
          : isClinicalWorkstation
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) =>
                      setState(() => _selectedIndex = index),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.grid_view_outlined),
                      selectedIcon: Icon(Icons.grid_view),
                      label: '工作台',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.account_circle_outlined),
                      selectedIcon: Icon(Icons.account_circle),
                      label: '账户',
                    ),
                  ],
                ),
    );
  }

  Widget _workspaceFor(String role) {
    return switch (role) {
      'SUPER_ADMIN' => const AdminWorkspace(),
      'ADMISSION' => const AdmissionWorkspace(),
      'DOCTOR' => const ClinicalWorkstation(role: 'DOCTOR'),
      'NURSE' => const ClinicalWorkstation(role: 'NURSE'),
      _ => const ClinicalWorkspace(),
    };
  }

  Widget _accountPanel(dynamic user) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: WorkSurface(
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const WorkspaceToolbar(
                  title: '个人账户',
                  subtitle: '当前登录身份与工作岗位信息',
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: WorkstationColors.heading,
                        foregroundColor: WorkstationColors.blue,
                        child: Icon(Icons.person, size: 32),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.realName,
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Text('登录名：${user.username}'),
                          Text('岗位：${_roleName(user.role)}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _roleName(String role) {
    return switch (role) {
      'SUPER_ADMIN' => '最高管理员',
      'ADMISSION' => '住院处',
      'DOCTOR' => '医师',
      'NURSE' => '护士',
      _ => role,
    };
  }
}

class _ConsoleHeader extends StatelessWidget {
  const _ConsoleHeader({
    required this.userName,
    required this.roleName,
    required this.onLogout,
  });

  final String userName;
  final String roleName;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: WorkstationColors.navy,
      child: Row(
        children: [
          const Icon(Icons.local_hospital, color: Colors.white, size: 24),
          const SizedBox(width: 10),
          const Text(
            '住院信息管理系统',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 18),
          Container(width: 1, height: 22, color: Colors.white24),
          const SizedBox(width: 18),
          Text(roleName, style: const TextStyle(color: Color(0xFFD8E8EE))),
          const Spacer(),
          Text(userName, style: const TextStyle(color: Colors.white)),
          IconButton(
            tooltip: '退出登录',
            color: Colors.white,
            icon: const Icon(Icons.logout_outlined),
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}

class _WorkstationSidebar extends StatelessWidget {
  const _WorkstationSidebar({
    required this.selectedIndex,
    required this.roleName,
    required this.onSelected,
  });

  final int selectedIndex;
  final String roleName;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 218,
      color: WorkstationColors.blue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Text(
              roleName,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
          ),
          _SideItem(
            icon: Icons.grid_view_outlined,
            label: '工作台',
            selected: selectedIndex == 0,
            onTap: () => onSelected(0),
          ),
          _SideItem(
            icon: Icons.account_circle_outlined,
            label: '个人账户',
            selected: selectedIndex == 1,
            onTap: () => onSelected(1),
          ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              '住院业务工作站',
              style: TextStyle(color: Color(0xFFB9DBE8), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF0089B5) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 21),
              const SizedBox(width: 12),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
