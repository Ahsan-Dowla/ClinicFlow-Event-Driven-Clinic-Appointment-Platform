package com.clinic.slot.slot;

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

import java.time.LocalDateTime;

@Entity
@Table(name = "slots", uniqueConstraints = @UniqueConstraint(
        name = "uk_slots_doctor_start", columnNames = {"doctor_id", "start_time"}))
public class Slot {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(name = "doctor_id", nullable = false)
    private Long doctorId;
    @Column(name = "start_time", nullable = false)
    private LocalDateTime startTime;
    @Column(name = "end_time", nullable = false)
    private LocalDateTime endTime;
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private SlotStatus status;
    @Version
    @Column(nullable = false)
    private Long version;

    protected Slot() {
    }

    public Slot(Long doctorId, LocalDateTime startTime, LocalDateTime endTime) {
        this.doctorId = doctorId;
        this.startTime = startTime;
        this.endTime = endTime;
        this.status = SlotStatus.AVAILABLE;
    }

    public Long getId() { return id; }
    public Long getDoctorId() { return doctorId; }
    public LocalDateTime getStartTime() { return startTime; }
    public LocalDateTime getEndTime() { return endTime; }
    public SlotStatus getStatus() { return status; }
    public Long getVersion() { return version; }

    public void markBooked() { status = SlotStatus.BOOKED; }
    public void markAvailable() { status = SlotStatus.AVAILABLE; }
}
