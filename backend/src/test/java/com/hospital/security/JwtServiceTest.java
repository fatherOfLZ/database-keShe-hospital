package com.hospital.security;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import org.junit.jupiter.api.Test;

class JwtServiceTest {
    @Test
    void issuesAndParsesRoleBoundToken() {
        JwtService service = new JwtService("test-development-secret-must-have-at-least-32-bytes", 30);
        String token = service.issue(new JwtUser(7L, "doctor", "DOCTOR"));
        JwtUser result = service.parse(token);
        assertNotNull(token);
        assertEquals(7L, result.userId());
        assertEquals("doctor", result.username());
        assertEquals("DOCTOR", result.roleCode());
    }
}
