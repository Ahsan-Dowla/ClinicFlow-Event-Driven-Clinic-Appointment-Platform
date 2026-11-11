package com.clinic.appointment.model;

import com.clinic.appointment.messaging.AppointmentDomainEvent;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import jakarta.persistence.Version;
import org.slf4j.MDC;

import java.time.Instant;
import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "appointments", uniqueConstraints = @UniqueConstraint(
        name = "uk_appointments_active_slot", columnNames = "active_slot_id"))
public class Appointment {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(name = "slot_id", nullable = false)
    private Long slotId;
    @Column(name = "doctor_id", nullable = false)
    private Long doctorId;
    @Column(name = "patient_id", nullable = false)
    private Long patientId;
    @Column(name = "patient_email", nullable = false, length = 254)
    private String patientEmail;
    @Column(name = "start_time", nullable = false)
    private LocalDateTime startTime;
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private AppointmentStatus status;
    @Column(name = "active_slot_id")
    private Long activeSlotId;
    @Column(name = "reminder_sent", nullable = false)
    private boolean reminderSent;
    @Column(name = "created_at", insertable = false, updatable = false)
    private Instant createdAt;
    @Version
    @Column(nullable = false)
    private Long version;

    protected Appointment() {
    }

    public Appointment(Long slotId, Long doctorId, Long patientId, String patientEmail, LocalDateTime startTime) {
        this.slotId = slotId;
        this.doctorId = doctorId;
        this.patientId = patientId;
        this.patientEmail = patientEmail;
        this.startTime = startTime;
        this.status = AppointmentStatus.CONFIRMED;
        this.activeSlotId = slotId;
    }

    public void cancel() {
        this.status = AppointmentStatus.CANCELLED;
        this.activeSlotId = null;
    }

    public void markReminderSent() {
        this.reminderSent = true;
    }

    public AppointmentDomainEvent toEvent(String eventType) {
        String correlationId = MDC.get("correlationId");
        if (correlationId == null || correlationId.isBlank()) {
            correlationId = UUID.randomUUID().toString();
        }
        return new AppointmentDomainEvent(UUID.randomUUID().toString(), correlationId, eventType, Instant.now(),
                id, slotId, doctorId, patientId, patientEmail, startTime);
    }

    public Long getId() { return id; }
    public Long getSlotId() { return slotId; }
    public Long getDoctorId() { return doctorId; }
    public Long getPatientId() { return patientId; }
    public String getPatientEmail() { return patientEmail; }
    public LocalDateTime getStartTime() { return startTime; }
    public AppointmentStatus getStatus() { return status; }
    public Long getActiveSlotId() { return activeSlotId; }
    public boolean isReminderSent() { return reminderSent; }
    public Instant getCreatedAt() { return createdAt; }
}
