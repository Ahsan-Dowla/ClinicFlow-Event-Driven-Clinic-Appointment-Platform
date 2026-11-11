package com.clinic.auth.web.dto;

import com.clinic.auth.user.UserRole;

public record AuthResponse(String token, String tokenType, Long userId, String email, UserRole role) {
}
