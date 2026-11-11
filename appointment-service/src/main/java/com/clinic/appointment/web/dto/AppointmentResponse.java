package com.clinic.appointment.web.dto;

import com.clinic.appointment.model.Appointment;
import com.clinic.appointment.model.AppointmentStatus;

import java.time.Instant;
import java.time.LocalDateTime;

public record AppointmentResponse(Long id, Long slotId, Long doctorId, Long patientId,
                                 LocalDateTime startTime, AppointmentStatus status, Instant createdAt) {
    public static AppointmentResponse from(Appointment appointment) {
        return new AppointmentResponse(appointment.getId(), appointment.getSlotId(), appointment.getDoctorId(),
                appointment.getPatientId(), appointment.getStartTime(), appointment.getStatus(),
                appointment.getCreatedAt());
    }
}
