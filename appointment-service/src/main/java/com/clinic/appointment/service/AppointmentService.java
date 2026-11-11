package com.clinic.appointment.service;

import com.clinic.appointment.messaging.AppointmentDomainEvent;
import com.clinic.appointment.model.Appointment;
import com.clinic.appointment.model.AppointmentStatus;
import com.clinic.appointment.repository.AppointmentRepository;
import com.clinic.appointment.security.UserPrincipal;
import com.clinic.appointment.slot.DoctorDetails;
import com.clinic.appointment.slot.SlotClient;
import com.clinic.appointment.slot.SlotDetails;
import com.clinic.appointment.web.ApiException;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Objects;

@Service
public class AppointmentService {
    private static final Duration HOLD_DURATION = Duration.ofMinutes(5);
    private final AppointmentRepository appointmentRepository;
    private final SlotClient slotClient;
    private final StringRedisTemplate redisTemplate;
    private final ApplicationEventPublisher eventPublisher;

    public AppointmentService(AppointmentRepository appointmentRepository, SlotClient slotClient,
                              StringRedisTemplate redisTemplate, ApplicationEventPublisher eventPublisher) {
        this.appointmentRepository = appointmentRepository;
        this.slotClient = slotClient;
        this.redisTemplate = redisTemplate;
        this.eventPublisher = eventPublisher;
    }

    public Instant hold(Long slotId, UserPrincipal patient, String authorization) {
        SlotDetails slot = slotClient.getSlot(slotId, authorization);
        requireAvailable(slot);
        if (appointmentRepository.existsByActiveSlotId(slotId)) {
            throw new ApiException(HttpStatus.CONFLICT, "This slot already has a confirmed appointment");
        }
        String key = holdKey(slotId);
        Boolean acquired = redisTemplate.opsForValue().setIfAbsent(
                key, patient.id().toString(), HOLD_DURATION);
        if (!Boolean.TRUE.equals(acquired)) {
            throw new ApiException(HttpStatus.CONFLICT, "slot is being booked by someone else");
        }
        return Instant.now().plus(HOLD_DURATION);
    }

    @Transactional
    public Appointment confirm(Long slotId, UserPrincipal patient, String authorization) {
        String heldBy = redisTemplate.opsForValue().get(holdKey(slotId));
        if (heldBy == null) {
            throw new ApiException(HttpStatus.GONE, "The booking hold expired; please hold the slot again");
        }
        if (!Objects.equals(heldBy, patient.id().toString())) {
            throw new ApiException(HttpStatus.CONFLICT, "The slot hold belongs to another patient");
        }
        SlotDetails slot = slotClient.getSlot(slotId, authorization);
        requireAvailable(slot);
        Appointment appointment = new Appointment(
                slot.id(), slot.doctorId(), patient.id(), patient.email(), slot.startTime());
        try {
            // Redis gives an expiring early hold; this unique database constraint is still the final race-safety guarantee.
            appointment = appointmentRepository.saveAndFlush(appointment);
        } catch (DataIntegrityViolationException exception) {
            throw new ApiException(HttpStatus.CONFLICT, "This slot has already been booked");
        }
        eventPublisher.publishEvent(appointment.toEvent("appointment.confirmed"));
        return appointment;
    }

    @Transactional
    public Appointment cancel(Long appointmentId, UserPrincipal patient) {
        Appointment appointment = appointmentRepository.findByIdAndPatientId(appointmentId, patient.id())
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Appointment not found"));
        if (appointment.getStatus() != AppointmentStatus.CONFIRMED) {
            throw new ApiException(HttpStatus.CONFLICT, "Only a confirmed appointment can be cancelled");
        }
        appointment.cancel();
        eventPublisher.publishEvent(appointment.toEvent("appointment.cancelled"));
        return appointment;
    }

    @Transactional(readOnly = true)
    public List<Appointment> myAppointments(Long patientId) {
        return appointmentRepository.findByPatientIdOrderByStartTimeDesc(patientId);
    }

    @Transactional(readOnly = true)
    public List<Appointment> doctorAppointments(Long doctorId, UserPrincipal caller, String authorization) {
        if (!"ADMIN".equals(caller.role())) {
            DoctorDetails doctor = slotClient.getDoctor(doctorId, authorization);
            if (!doctor.userId().equals(caller.id())) {
                throw new ApiException(HttpStatus.FORBIDDEN, "Doctors can view only their own appointments");
            }
        }
        return appointmentRepository.findByDoctorIdOrderByStartTimeDesc(doctorId);
    }

    @Transactional
    public int publishDueReminders() {
        LocalDateTime now = LocalDateTime.now();
        List<Appointment> due = appointmentRepository.findRemindersDue(
                AppointmentStatus.CONFIRMED, now, now.plusHours(24));
        due.forEach(appointment -> {
            appointment.markReminderSent();
            eventPublisher.publishEvent(appointment.toEvent("appointment.reminder.due"));
        });
        return due.size();
    }

    private void requireAvailable(SlotDetails slot) {
        if (!"AVAILABLE".equals(slot.status())) {
            throw new ApiException(HttpStatus.CONFLICT, "This slot is not available");
        }
    }

    private String holdKey(Long slotId) {
        return "hold:slot:" + slotId;
    }
}
