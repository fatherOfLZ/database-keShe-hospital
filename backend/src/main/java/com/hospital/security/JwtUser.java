package com.hospital.security;

/** JWT 中保存的最小认证主体：用户 ID、登录名和角色编码。 */
public record JwtUser(long userId, String username, String roleCode) {}
