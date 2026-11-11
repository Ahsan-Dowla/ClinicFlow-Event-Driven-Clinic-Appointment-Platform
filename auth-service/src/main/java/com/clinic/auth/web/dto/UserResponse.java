package com.clinic.auth.web.dto;

import com.clinic.auth.user.UserAccount;
import com.clinic.auth.user.UserRole;

public record UserResponse(Long id, String name, String email, UserRole role) {
    public static UserResponse from(UserAccount account) {
        return new UserResponse(account.getId(), account.getName(), account.getEmail(), account.getRole());
    }
}
