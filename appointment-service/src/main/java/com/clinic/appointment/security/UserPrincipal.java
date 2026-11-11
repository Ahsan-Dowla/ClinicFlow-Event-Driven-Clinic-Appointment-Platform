package com.clinic.appointment.security;

public record UserPrincipal(Long id, String email, String role) {
}
