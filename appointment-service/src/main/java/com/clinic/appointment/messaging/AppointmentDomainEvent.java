package com.clinic.appointment.messaging;

import java.time.Instant;
import java.time.LocalDateTime;

public record AppointmentDomainEvent(String eventId, String correlationId, String eventType, Instant occurredAt, Long appointmentId,
                                     Long slotId, Long doctorId, Long patientId, String patientEmail,
                                     LocalDateTime startTime) {
}
