package com.clinic.auth.security;

import com.clinic.auth.user.UserAccount;
import com.clinic.auth.user.UserRole;
import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class JwtTokenServiceTest {
    @Test
    void developmentSeedHashMatchesDocumentedPassword() {
        String hash = "$2b$10$MUaFFvRIdkniC4Vayvuj8.tRIwEr4Be3V3vC8W9sHX6fySA9V3BWG";

        assertTrue(new BCryptPasswordEncoder().matches("password", hash));
    }

    @Test
    void issuesVerifiableTokenWithRequiredIdentityClaims() {
        JwtTokenService tokenService = new JwtTokenService("test-secret-that-is-at-least-32-bytes-long", 60_000);
        UserAccount account = mock(UserAccount.class);
        when(account.getId()).thenReturn(42L);
        when(account.getEmail()).thenReturn("patient@example.test");
        when(account.getRole()).thenReturn(UserRole.PATIENT);

        var claims = tokenService.parse(tokenService.issue(account));

        assertEquals(42L, claims.get("userId", Long.class));
        assertEquals("patient@example.test", claims.get("email", String.class));
        assertEquals("PATIENT", claims.get("role", String.class));
    }
}
