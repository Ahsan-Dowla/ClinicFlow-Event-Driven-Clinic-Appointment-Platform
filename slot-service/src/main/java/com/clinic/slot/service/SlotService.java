package com.clinic.slot.service;

import com.clinic.slot.doctor.Doctor;
import com.clinic.slot.doctor.DoctorRepository;
import com.clinic.slot.doctor.DoctorRequest;
import com.clinic.slot.doctor.DoctorResponse;
import com.clinic.slot.security.UserPrincipal;
import com.clinic.slot.slot.GenerateSlotsRequest;
import com.clinic.slot.slot.Slot;
import com.clinic.slot.slot.SlotRepository;
import com.clinic.slot.slot.SlotRequest;
import com.clinic.slot.slot.SlotResponse;
import com.clinic.slot.slot.SlotStatus;
import com.clinic.slot.messaging.AppointmentEventMessage;
import com.clinic.slot.web.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Service
public class SlotService {
    private final DoctorRepository doctorRepository;
    private final SlotRepository slotRepository;

    public SlotService(DoctorRepository doctorRepository, SlotRepository slotRepository) {
        this.doctorRepository = doctorRepository;
        this.slotRepository = slotRepository;
    }

    @Transactional(readOnly = true)
    public List<DoctorResponse> doctors() {
        return doctorRepository.findAll().stream().map(DoctorResponse::from).toList();
    }

    @Transactional
    public DoctorResponse createDoctor(DoctorRequest request) {
        if (doctorRepository.existsByUserId(request.userId())) {
            throw new ApiException(HttpStatus.CONFLICT, "A doctor profile already exists for this user");
        }
        return DoctorResponse.from(doctorRepository.save(new Doctor(
                request.userId(), request.name().trim(), request.specialization().trim())));
    }

    @Transactional(readOnly = true)
    public List<SlotResponse> slots(Long doctorId, java.time.LocalDate date, SlotStatus status) {
        requireDoctor(doctorId);
        LocalDateTime from = date.atStartOfDay();
        LocalDateTime to = date.plusDays(1).atStartOfDay();
        return slotRepository.findByDoctorIdAndStartTimeGreaterThanEqualAndStartTimeLessThan(doctorId, from, to)
                .stream().filter(slot -> status == null || slot.getStatus() == status)
                .map(SlotResponse::from).toList();
    }

    @Transactional
    public SlotResponse createSlot(Long doctorId, SlotRequest request, UserPrincipal caller) {
        Doctor doctor = requireDoctor(doctorId);
        requireDoctorOwnerOrAdmin(doctor, caller);
        if (request.startTime().isBefore(LocalDateTime.now())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "A slot cannot start in the past");
        }
        return SlotResponse.from(slotRepository.save(
                new Slot(doctorId, request.startTime(), request.endTime())));
    }

    @Transactional
    public List<SlotResponse> generateSlots(Long doctorId, GenerateSlotsRequest request, UserPrincipal caller) {
        Doctor doctor = requireDoctor(doctorId);
        requireDoctorOwnerOrAdmin(doctor, caller);
        LocalDateTime start = request.date().atTime(request.startTime());
        LocalDateTime end = request.date().atTime(request.endTime());
        if (start.isBefore(LocalDateTime.now())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Slots cannot be generated in the past");
        }
        List<Slot> newSlots = new java.util.ArrayList<>();
        for (LocalDateTime slotStart = start;
             !slotStart.plusMinutes(request.durationMinutes()).isAfter(end);
             slotStart = slotStart.plusMinutes(request.durationMinutes())) {
            newSlots.add(new Slot(doctorId, slotStart, slotStart.plusMinutes(request.durationMinutes())));
        }
        return slotRepository.saveAll(newSlots).stream().map(SlotResponse::from).toList();
    }

    @Transactional(readOnly = true)
    public SlotResponse getSlot(Long id) {
        return SlotResponse.from(slotRepository.findById(id)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Slot not found")));
    }

    @Transactional
    public void applyAppointmentEvent(AppointmentEventMessage event) {
        Slot slot = slotRepository.findById(event.slotId())
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Slot for appointment event not found"));
        if ("appointment.confirmed".equals(event.eventType())) {
            slot.markBooked();
        } else if ("appointment.cancelled".equals(event.eventType())) {
            slot.markAvailable();
        } else {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Unsupported slot event type");
        }
    }

    private Doctor requireDoctor(Long id) {
        return doctorRepository.findById(id)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Doctor not found"));
    }

    private void requireDoctorOwnerOrAdmin(Doctor doctor, UserPrincipal caller) {
        if (!"ADMIN".equals(caller.role()) && !doctor.getUserId().equals(caller.id())) {
            throw new ApiException(HttpStatus.FORBIDDEN, "Doctors can manage only their own slots");
        }
    }
}
