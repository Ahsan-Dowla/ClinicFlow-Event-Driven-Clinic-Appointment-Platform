package com.clinic.slot.doctor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public record DoctorRequest(
        @NotNull Long userId,
        @NotBlank @Size(max = 120) String name,
        @NotBlank @Size(max = 120) String specialization) {
}
