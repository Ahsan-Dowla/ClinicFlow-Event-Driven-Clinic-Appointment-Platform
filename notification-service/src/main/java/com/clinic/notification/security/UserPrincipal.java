package com.clinic.notification.security;

public record UserPrincipal(Long id, String email, String role) {
}
