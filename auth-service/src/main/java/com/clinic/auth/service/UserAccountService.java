package com.clinic.auth.service;

import com.clinic.auth.security.JwtTokenService;
import com.clinic.auth.user.UserAccount;
import com.clinic.auth.user.UserAccountRepository;
import com.clinic.auth.user.UserRole;
import com.clinic.auth.web.ApiException;
import com.clinic.auth.web.dto.AuthResponse;
import com.clinic.auth.web.dto.LoginRequest;
import com.clinic.auth.web.dto.RegisterRequest;
import com.clinic.auth.web.dto.UserResponse;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class UserAccountService {
    private final UserAccountRepository repository;
    private final PasswordEncoder passwordEncoder;
    private final JwtTokenService tokenService;

    public UserAccountService(UserAccountRepository repository, PasswordEncoder passwordEncoder,
                              JwtTokenService tokenService) {
        this.repository = repository;
        this.passwordEncoder = passwordEncoder;
        this.tokenService = tokenService;
    }

    @Transactional
    public UserResponse register(RegisterRequest request) {
        String email = request.email().trim().toLowerCase();
        if (repository.existsByEmailIgnoreCase(email)) {
            throw new ApiException(HttpStatus.CONFLICT, "An account with this email already exists");
        }
        UserAccount account = repository.save(new UserAccount(
                request.name().trim(), email, passwordEncoder.encode(request.password()), UserRole.PATIENT,
                request.phone() == null ? null : request.phone().trim()));
        return UserResponse.from(account);
    }

    @Transactional(readOnly = true)
    public AuthResponse login(LoginRequest request) {
        UserAccount account = repository.findByEmailIgnoreCase(request.email().trim())
                .filter(user -> passwordEncoder.matches(request.password(), user.getPasswordHash()))
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "Invalid email or password"));
        return new AuthResponse(tokenService.issue(account), "Bearer", account.getId(), account.getEmail(), account.getRole());
    }

    @Transactional(readOnly = true)
    public UserResponse findUser(Long id) {
        UserAccount account = repository.findById(id)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "User not found"));
        return UserResponse.from(account);
    }
}
