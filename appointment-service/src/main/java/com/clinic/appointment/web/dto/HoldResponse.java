package com.clinic.appointment.web.dto;

import java.time.Instant;

public record HoldResponse(Long slotId, Instant holdExpiresAt) {
}
