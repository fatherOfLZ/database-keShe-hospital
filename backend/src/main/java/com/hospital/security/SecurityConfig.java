package com.hospital.security;

import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

@Configuration
@EnableWebSecurity
@EnableMethodSecurity
/** 配置无状态 JWT 安全链、跨域规则及密码哈希器。 */
public class SecurityConfig {
    /** 注册请求安全链，并将 JWT 过滤器置于用户名密码过滤器之前。 */
    @Bean
    SecurityFilterChain filterChain(
            HttpSecurity http,
            JwtAuthenticationFilter jwtFilter,
            RestSecurityHandlers handlers) throws Exception {
        return http
                // JWT 是无状态认证，不使用基于 Session 的 CSRF 防护。
                .csrf(csrf -> csrf.disable())
                .cors(cors -> {})
                .sessionManagement(session ->
                        session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        // 只有登录接口匿名可访问，其他 API 均须在过滤器完成身份认证后调用。
                        .requestMatchers("/api/v1/auth/**", "/error").permitAll()
                        .anyRequest().authenticated())
                .exceptionHandling(errors -> errors.authenticationEntryPoint(handlers).accessDeniedHandler(handlers))
                .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class)
                .build();
    }

    /** 使用 BCrypt 对数据库中的账号密码做不可逆哈希。 */
    @Bean
    PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    /** 为 Flutter Web 与本地调试地址开放跨域请求。 */
    @Bean
    CorsConfigurationSource corsConfigurationSource(
            @Value("${app.cors.allowed-origin-patterns}") String originPatterns) {
        CorsConfiguration config = new CorsConfiguration();
        // Flutter Web 会随机分配调试端口，因此本地开发用来源模式而非固定端口。
        // 生产环境应使用环境变量收紧为实际部署域名。
        config.setAllowedOriginPatterns(List.of(originPatterns.split(",")));
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        config.setAllowedHeaders(List.of("Authorization", "Content-Type"));
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }
}
