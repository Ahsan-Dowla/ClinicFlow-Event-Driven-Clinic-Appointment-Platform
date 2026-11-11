package com.clinic.slot.slot;

import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

import java.time.LocalDate;
import java.time.LocalTime;

public record GenerateSlotsRequest(
        @NotNull LocalDate date,
        @NotNull LocalTime startTime,
        @NotNull LocalTime endTime,
        @Min(5) @Max(480) int durationMinutes) {
    @AssertTrue(message = "endTime must be after startTime")
    public boolean isEndAfterStart() {
        return startTime == null || endTime == null || endTime.isAfter(startTime);
    }

    @AssertTrue(message = "The schedule must contain at least one full slot")
    public boolean hasAtLeastOneSlot() {
        return startTime == null || endTime == null || durationMinutes <= 0
                || !endTime.isBefore(startTime.plusMinutes(durationMinutes));
    }
}
