package com.clinic.slot.service;

import com.clinic.slot.doctor.Doctor;
import com.clinic.slot.doctor.DoctorRepository;
import com.clinic.slot.messaging.AppointmentEventMessage;
import com.clinic.slot.security.UserPrincipal;
import com.clinic.slot.slot.GenerateSlotsRequest;
import com.clinic.slot.slot.Slot;
import com.clinic.slot.slot.SlotRepository;
import com.clinic.slot.web.ApiException;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class SlotServiceTest {
    @Test
    void generatesOnlyCompleteSlotsForDoctorOwner() {
        DoctorRepository doctors = mock(DoctorRepository.class);
        SlotRepository slots = mock(SlotRepository.class);
        Doctor doctor = mock(Doctor.class);
        when(doctor.getUserId()).thenReturn(22L);
        when(doctors.findById(3L)).thenReturn(Optional.of(doctor));
        when(slots.saveAll(any())).thenAnswer(invocation -> invocation.getArgument(0));
        SlotService service = new SlotService(doctors, slots);
        GenerateSlotsRequest request = new GenerateSlotsRequest(
                LocalDate.now().plusDays(2), LocalTime.of(9, 0), LocalTime.of(10, 10), 30);

        var result = service.generateSlots(3L, request, new UserPrincipal(22L, "doctor@example.test", "DOCTOR"));

        assertEquals(2, result.size());
    }

    @Test
    void preventsDoctorFromCreatingAnotherDoctorsSlots() {
        DoctorRepository doctors = mock(DoctorRepository.class);
        SlotRepository slots = mock(SlotRepository.class);
        Doctor doctor = mock(Doctor.class);
        when(doctor.getUserId()).thenReturn(99L);
        when(doctors.findById(3L)).thenReturn(Optional.of(doctor));
        SlotService service = new SlotService(doctors, slots);

        assertThrows(ApiException.class, () -> service.generateSlots(3L,
                new GenerateSlotsRequest(LocalDate.now().plusDays(2), LocalTime.of(9, 0),
                        LocalTime.of(10, 0), 30),
                new UserPrincipal(22L, "doctor@example.test", "DOCTOR")));
    }

    @Test
    void appliesConfirmationAndCancellationEventsIdempotently() {
        DoctorRepository doctors = mock(DoctorRepository.class);
        SlotRepository slots = mock(SlotRepository.class);
        Slot slot = mock(Slot.class);
        when(slots.findById(11L)).thenReturn(Optional.of(slot));
        SlotService service = new SlotService(doctors, slots);

        service.applyAppointmentEvent(event("appointment.confirmed"));
        service.applyAppointmentEvent(event("appointment.cancelled"));

        verify(slot).markBooked();
        verify(slot).markAvailable();
    }

    private static AppointmentEventMessage event(String type) {
        return new AppointmentEventMessage("event", "correlation", type, java.time.Instant.now(),
                7L, 11L, 3L, 9L, "patient@example.test", java.time.LocalDateTime.now());
    }
}
