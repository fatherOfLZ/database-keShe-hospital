package com.hospital.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.hospital.common.ApiResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.http.MediaType;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.access.AccessDeniedHandler;
import org.springframework.stereotype.Component;

/** 将 Spring Security 的认证与授权异常转换为统一 JSON 响应。 */
@Component
public class RestSecurityHandlers implements AuthenticationEntryPoint, AccessDeniedHandler {
    private final ObjectMapper objectMapper;

    public RestSecurityHandlers(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @Override
    /** 未携带、过期或非法令牌时返回 401。 */
    public void commence(
            HttpServletRequest request,
            HttpServletResponse response,
            AuthenticationException exception) throws IOException {
        write(response, 401, ApiResponse.error(401, "未登录或登录凭证已失效"));
    }

    @Override
    /** 已登录但角色权限不足时返回 403。 */
    public void handle(
            HttpServletRequest request,
            HttpServletResponse response,
            AccessDeniedException exception) throws IOException {
        write(response, 403, ApiResponse.error(403, "没有权限执行此操作"));
    }

    private void write(HttpServletResponse response, int status, ApiResponse<Void> body) throws IOException {
        // 直接输出 JSON，避免 Spring Security 的默认 HTML 错误页破坏前后端统一响应约定。
        response.setStatus(status);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding("UTF-8");
        objectMapper.writeValue(response.getOutputStream(), body);
    }
}
