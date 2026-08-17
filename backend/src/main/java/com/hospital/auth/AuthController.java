package com.hospital.auth;

import com.hospital.common.ApiResponse;
import com.hospital.common.BusinessException;
import com.hospital.security.CurrentUser;
import com.hospital.security.JwtService;
import com.hospital.security.JwtUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import java.util.HashMap;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/auth")
/** 登录、当前用户查询和密码修改接口。 */
public class AuthController {
    private final JdbcTemplate jdbc;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;

    public AuthController(JdbcTemplate jdbc, PasswordEncoder passwordEncoder, JwtService jwtService) {
        this.jdbc = jdbc;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
    }

    @PostMapping("/login")
    /** 校验账号密码后签发包含用户身份和角色的 JWT。 */
    public ApiResponse<?> login(@Valid @RequestBody LoginRequest request) {
        // 登录仅查询启用账号，并同时取得角色；停用账号即使密码正确也不能获取令牌。
        var rows = jdbc.query(
                "SELECT u.user_id,u.username,u.password_hash,r.role_code,u.real_name "
                        + "FROM system_user u JOIN role r ON r.role_id=u.role_id "
                        + "WHERE u.username=? AND u.status='ACTIVE'",
                (rs, i) -> {
                    Map<String, Object> account = new HashMap<>();
                    account.put("id", rs.getLong("user_id"));
                    account.put("username", rs.getString("username"));
                    account.put("hash", rs.getString("password_hash"));
                    account.put("role", rs.getString("role_code"));
                    account.put("name", rs.getString("real_name"));
                    return account;
                },
                request.username());
        // 密码比较始终交给 BCrypt，不能以字符串直接比较数据库中的密码哈希。
        if (rows.isEmpty()
                || !passwordEncoder.matches(request.password(), (String) rows.get(0).get("hash"))) {
            throw new BusinessException("用户名或密码错误");
        }
        Map<String, Object> account = rows.get(0);
        // JWT 只承载身份和角色，真实姓名等展示资料随本次登录响应返回。
        JwtUser user = new JwtUser(
                (Long) account.get("id"),
                (String) account.get("username"),
                (String) account.get("role"));
        return ApiResponse.ok(Map.of(
                "accessToken", jwtService.issue(user),
                "tokenType", "Bearer",
                "user", Map.of(
                        "id", user.userId(),
                        "username", user.username(),
                        "role", user.roleCode(),
                        "realName", account.get("name"))));
    }

    @GetMapping("/me")
    /** 返回已由 JWT 过滤器解析出的当前登录用户。 */
    public ApiResponse<JwtUser> me() {
        return ApiResponse.ok(CurrentUser.get());
    }

    @PutMapping("/password")
    /** 先验证原密码，再持久化新的 BCrypt 密码哈希。 */
    public ApiResponse<Void> changePassword(@Valid @RequestBody ChangePasswordRequest request) {
        JwtUser user = CurrentUser.get();
        // 修改密码前必须再次核验旧密码，已登录状态本身不能替代敏感操作确认。
        String current = jdbc.queryForObject(
                "SELECT password_hash FROM system_user WHERE user_id=?",
                String.class,
                user.userId());
        if (!passwordEncoder.matches(request.oldPassword(), current)) {
            throw new BusinessException("原密码错误");
        }
        // 新密码覆盖时仍使用 BCrypt 编码，保持账号表中只保存不可逆哈希。
        jdbc.update(
                "UPDATE system_user SET password_hash=? WHERE user_id=?",
                passwordEncoder.encode(request.newPassword()),
                user.userId());
        return ApiResponse.ok(null);
    }

    /** 登录请求只包含用户主动提供的账号凭据。 */
    public record LoginRequest(@NotBlank String username, @NotBlank String password) {
    }

    /** 修改密码请求同时包含旧密码验证和新密码值。 */
    public record ChangePasswordRequest(@NotBlank String oldPassword, @NotBlank String newPassword) {
    }
}
