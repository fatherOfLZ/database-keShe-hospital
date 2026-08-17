package com.hospital.security;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Date;
import javax.crypto.SecretKey;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/** 负责 JWT 的签发与解析，不在此处承担用户密码校验。 */
@Service
public class JwtService {
    private final SecretKey key;
    private final Duration expiration;

    public JwtService(
            @Value("${app.jwt.secret}") String secret,
            @Value("${app.jwt.expiration-minutes}") long expirationMinutes) {
        // HS256 密钥长度不足会削弱签名安全性，因此应用启动时直接拒绝不合规配置。
        if (secret.getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new IllegalArgumentException("JWT_SECRET 至少需要 32 个字节");
        }
        // 密钥仅驻留在内存中，JWT 签发和验证使用同一个对称密钥。
        this.key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.expiration = Duration.ofMinutes(expirationMinutes);
    }

    public String issue(JwtUser user) {
        // 令牌只保存授权所需的最小声明，用户详细资料仍以数据库为准。
        Date now = new Date();
        return Jwts.builder()
                .subject(user.username())
                .claim("uid", user.userId())
                .claim("role", user.roleCode())
                .issuedAt(now)
                .expiration(Date.from(now.toInstant().plus(expiration)))
                .signWith(key)
                .compact();
    }

    public JwtUser parse(String token) {
        // JJWT 会在签名、格式或过期校验失败时抛出异常。
        Claims claims = Jwts.parser()
                .verifyWith(key)
                .build()
                .parseSignedClaims(token)
                .getPayload();
        Number uid = claims.get("uid", Number.class);
        return new JwtUser(uid.longValue(), claims.getSubject(), claims.get("role", String.class));
    }
}
