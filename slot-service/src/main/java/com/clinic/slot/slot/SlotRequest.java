package com.clinic.slot.slot;

import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.NotNull;

import java.time.LocalDateTime;

public record SlotRequest(@NotNull LocalDateTime startTime, @NotNull LocalDateTime endTime) {
    @AssertTrue(message = "endTime must be after startTime")
    public boolean isEndAfterStart() {
        return startTime == null || endTime == null || endTime.isAfter(startTime);
    }
}
