package com.clinic.gateway.security;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.Test;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class JwtTokenVerifierTest {
    private static final String SECRET = "a-local-test-secret-that-is-at-least-32-bytes";

    @Test
    void acceptsValidIdentityToken() {
        JwtTokenVerifier verifier = new JwtTokenVerifier(SECRET);

        AuthenticatedIdentity identity = verifier.verify(token(SECRET, 17, "doctor@example.test", "DOCTOR"));

        assertEquals(17L, identity.userId());
        assertEquals("doctor@example.test", identity.email());
        assertEquals("DOCTOR", identity.role());
    }

    @Test
    void rejectsTokenSignedWithAnotherSecret() {
        JwtTokenVerifier verifier = new JwtTokenVerifier(SECRET);

        assertThrows(io.jsonwebtoken.JwtException.class,
                () -> verifier.verify(token("another-secret-that-is-also-over-32-bytes", 17,
                        "doctor@example.test", "DOCTOR")));
    }

    private static String token(String secret, long userId, String email, String role) {
        SecretKey key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        Instant now = Instant.now();
        return Jwts.builder().subject(email).claim("userId", userId).claim("email", email).claim("role", role)
                .issuedAt(Date.from(now)).expiration(Date.from(now.plusSeconds(60))).signWith(key).compact();
    }
}
