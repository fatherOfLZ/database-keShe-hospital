/// JWT 登录接口返回的最小用户资料，用于前端展示与角色导航。
class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.username,
    required this.role,
    required this.realName,
  });

  final int id;
  final String username;
  final String role;
  final String realName;

  factory CurrentUser.fromJson(Map<String, dynamic> json) {
    return CurrentUser(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String,
      role: json['role'] as String,
      realName: json['realName'] as String,
    );
  }
}
