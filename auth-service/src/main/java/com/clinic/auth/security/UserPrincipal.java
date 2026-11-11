package com.clinic.auth.security;

import com.clinic.auth.user.UserRole;

public record UserPrincipal(Long id, String email, UserRole role) {
}
