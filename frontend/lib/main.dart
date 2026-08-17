import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/workstation_ui.dart';
import 'features/auth/login_screen.dart';
import 'features/home/dashboard_screen.dart';

void main() {
  // ProviderScope 在根节点创建，保证路由中的所有页面共享同一份认证状态。
  runApp(const ProviderScope(child: HospitalApp()));
}

/// Flutter 应用入口；ProviderScope 为登录状态和 API 客户端提供共享依赖。
class HospitalApp extends StatelessWidget {
  const HospitalApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 路由只控制页面流转；真正的角色授权仍由后端 JWT 安全链负责。
    final router = GoRouter(
      // 未实现令牌恢复时始终先显示登录页，避免把过期会话直接带入工作台。
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, __) => const LoginScreen(),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (_, __) => const DashboardScreen(),
        ),
      ],
    );
    return MaterialApp.router(
      title: '住院信息管理系统',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: WorkstationColors.blue,
          primary: WorkstationColors.blue,
          surface: Colors.white,
          error: const Color(0xFFC22E2E),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: WorkstationColors.canvas,
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: WorkstationColors.ink,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: WorkstationColors.ink,
          ),
          bodyMedium: TextStyle(fontSize: 14, color: WorkstationColors.ink),
        ),
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            borderSide: BorderSide(color: WorkstationColors.border),
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            borderSide: BorderSide(color: WorkstationColors.border),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            borderSide: BorderSide(color: WorkstationColors.cyan, width: 1.5),
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: WorkstationColors.blue,
          unselectedLabelColor: WorkstationColors.muted,
          indicatorColor: WorkstationColors.cyan,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 38),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
          ),
        ),
      ),
      routerConfig: router,
    );
  }
}
