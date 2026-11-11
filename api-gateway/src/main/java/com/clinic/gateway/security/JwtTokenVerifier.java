package com.clinic.gateway.security;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;

@Component
public class JwtTokenVerifier {
    private final SecretKey key;

    public JwtTokenVerifier(@Value("${app.jwt.secret}") String secret) {
        byte[] secretBytes = secret.getBytes(StandardCharsets.UTF_8);
        if (secretBytes.length < 32) {
            throw new IllegalArgumentException("JWT_SECRET must be at least 32 bytes for HS256");
        }
        this.key = Keys.hmacShaKeyFor(secretBytes);
    }

    public AuthenticatedIdentity verify(String token) {
        Claims claims = Jwts.parser().verifyWith(key).build().parseSignedClaims(token).getPayload();
        Object id = claims.get("userId");
        Object email = claims.get("email");
        Object role = claims.get("role");
        if (!(id instanceof Number userId) || !(email instanceof String emailValue)
                || emailValue.isBlank() || !(role instanceof String roleValue)
                || !roleValue.matches("PATIENT|DOCTOR|ADMIN")) {
            throw new IllegalArgumentException("JWT is missing required identity claims");
        }
        return new AuthenticatedIdentity(userId.longValue(), emailValue, roleValue);
    }
}
