package com.clinic.gateway.security;

public record AuthenticatedIdentity(Long userId, String email, String role) {
}
