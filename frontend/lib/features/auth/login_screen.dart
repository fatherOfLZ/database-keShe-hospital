import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/workstation_ui.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController(text: 'doctor');
  final _password = TextEditingController(text: 'Doctor123!');
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // 登录控制器保存 JWT，并同步工作台所需的当前用户角色。
      await ref.read(authControllerProvider).login(
            _username.text.trim(),
            _password.text,
          );
      if (mounted) {
        context.go('/dashboard');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '登录失败，请检查服务地址与账号密码。');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 58,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            color: WorkstationColors.navy,
            child: const Row(
              children: [
                Icon(Icons.local_hospital, color: Colors.white),
                SizedBox(width: 10),
                Text(
                  '住院信息管理系统',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: const EdgeInsets.all(30),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border.fromBorderSide(
                      BorderSide(color: WorkstationColors.border),
                    ),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '工作站登录',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '请使用已分配的系统账号登录',
                          style: TextStyle(color: WorkstationColors.muted),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _username,
                          decoration: const InputDecoration(
                            labelText: '用户名',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (value) =>
                              value == null || value.isEmpty ? '请输入用户名' : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _password,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (!_submitting) {
                              _submit();
                            }
                          },
                          decoration: const InputDecoration(
                            labelText: '密码',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          validator: (value) =>
                              value == null || value.isEmpty ? '请输入密码' : null,
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error),
                            ),
                          ),
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: _submitting ? null : _submit,
                          icon: const Icon(Icons.login),
                          label: Text(_submitting ? '正在验证身份...' : '登录工作站'),
                        ),
                      ],
                    ),
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
