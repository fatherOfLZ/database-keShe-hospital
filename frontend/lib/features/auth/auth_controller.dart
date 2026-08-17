import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../models/current_user.dart';

/// 保存当前会话用户，供路由和角色工作台读取。
final currentUserProvider = StateProvider<CurrentUser?>((ref) => null);

/// 提供全局唯一的 HTTP 客户端，并在令牌失效时同步清空会话状态。
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    onUnauthorized: () {
      ref.read(currentUserProvider.notifier).state = null;
    },
  );
});

/// 封装登录和退出时需要同步更新的远端令牌与本地状态。
class AuthController {
  AuthController(this.ref);

  final Ref ref;

  Future<void> login(String username, String password) async {
    // 登录成功后再更新状态，避免失败请求导致页面误判为已登录。
    final json = await ref.read(apiClientProvider).login(username, password);
    ref.read(currentUserProvider.notifier).state = CurrentUser.fromJson(json);
  }

  Future<void> logout() async {
    // 同时清除安全存储中的令牌和内存中的用户资料。
    await ref.read(apiClientProvider).logout();
    ref.read(currentUserProvider.notifier).state = null;
  }
}

final authControllerProvider = Provider<AuthController>(AuthController.new);
