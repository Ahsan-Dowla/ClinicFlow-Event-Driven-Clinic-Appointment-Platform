package com.clinic.slot.slot;

import java.time.LocalDateTime;

public record SlotResponse(Long id, Long doctorId, LocalDateTime startTime, LocalDateTime endTime, SlotStatus status) {
    public static SlotResponse from(Slot slot) {
        return new SlotResponse(slot.getId(), slot.getDoctorId(), slot.getStartTime(), slot.getEndTime(), slot.getStatus());
    }
}
