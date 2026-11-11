package com.clinic.appointment.repository;

import com.clinic.appointment.model.Appointment;
import com.clinic.appointment.model.AppointmentStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface AppointmentRepository extends JpaRepository<Appointment, Long> {
    boolean existsByActiveSlotId(Long slotId);
    Optional<Appointment> findByIdAndPatientId(Long id, Long patientId);
    List<Appointment> findByPatientIdOrderByStartTimeDesc(Long patientId);
    List<Appointment> findByDoctorIdOrderByStartTimeDesc(Long doctorId);

    @Query("select a from Appointment a where a.status = :status and a.reminderSent = false "
            + "and a.startTime >= :from and a.startTime <= :to")
    List<Appointment> findRemindersDue(AppointmentStatus status, LocalDateTime from, LocalDateTime to);
}
