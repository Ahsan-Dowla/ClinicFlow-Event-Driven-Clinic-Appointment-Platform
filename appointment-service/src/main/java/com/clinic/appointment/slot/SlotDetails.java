package com.clinic.appointment.slot;

import java.time.LocalDateTime;

public record SlotDetails(Long id, Long doctorId, LocalDateTime startTime, LocalDateTime endTime, String status) {
}
