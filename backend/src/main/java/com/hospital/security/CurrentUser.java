package com.hospital.security;

import com.hospital.common.BusinessException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

public final class CurrentUser {
    private CurrentUser() {
        // 工具类不应被实例化，当前用户只能从线程绑定的安全上下文读取。
    }

    public static JwtUser get() {
        // SecurityContext 与当前请求线程关联，保证并发请求间不会串用登录身份。
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        // 只接受 JWT 过滤器写入的 JwtUser，避免控制器从请求参数伪造用户身份。
        if (authentication == null || !(authentication.getPrincipal() instanceof JwtUser user)) {
            throw new BusinessException("未登录");
        }
        return user;
    }
}
