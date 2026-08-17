package com.hospital.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import org.springframework.http.HttpHeaders;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/** 在每个请求进入控制器前，将有效 JWT 转换为 Spring Security 认证对象。 */
@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {
    private final JwtService jwtService;

    public JwtAuthenticationFilter(JwtService jwtService) {
        this.jwtService = jwtService;
    }

    /** 只读取 Bearer 令牌；错误令牌交由统一安全处理器返回 401。 */
    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String header = request.getHeader(HttpHeaders.AUTHORIZATION);
        if (header != null
                && header.startsWith("Bearer ")
                && SecurityContextHolder.getContext().getAuthentication() == null) {
            try {
                JwtUser user = jwtService.parse(header.substring(7));
                // Spring Security 识别 ROLE_ 前缀权限，供控制器的 hasRole / hasAnyRole 规则使用。
                var auth = new UsernamePasswordAuthenticationToken(
                        user,
                        null,
                        List.of(new SimpleGrantedAuthority("ROLE_" + user.roleCode())));
                SecurityContextHolder.getContext().setAuthentication(auth);
            } catch (RuntimeException ignored) {
                // 无效令牌不在过滤器内直接写响应，交由 Spring Security 统一返回 401 JSON。
            }
        }
        // 无论是否携带令牌都继续安全链，由后续规则决定匿名请求是否允许访问。
        chain.doFilter(request, response);
    }
}
