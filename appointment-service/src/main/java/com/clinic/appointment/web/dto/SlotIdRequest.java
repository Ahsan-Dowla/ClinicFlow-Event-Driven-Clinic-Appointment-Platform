package com.clinic.appointment.web.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

public record SlotIdRequest(@NotNull @Positive Long slotId) {
}
