package com.clinic.appointment.web;

import com.clinic.appointment.model.Appointment;
import com.clinic.appointment.security.UserPrincipal;
import com.clinic.appointment.service.AppointmentService;
import com.clinic.appointment.web.dto.AppointmentResponse;
import com.clinic.appointment.web.dto.HoldResponse;
import com.clinic.appointment.web.dto.SlotIdRequest;
import jakarta.validation.Valid;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.List;

@RestController
@RequestMapping("/appointments")
public class AppointmentController {
    private final AppointmentService appointmentService;

    public AppointmentController(AppointmentService appointmentService) {
        this.appointmentService = appointmentService;
    }

    @PostMapping("/hold")
    @PreAuthorize("hasRole('PATIENT')")
    public HoldResponse hold(@Valid @RequestBody SlotIdRequest request,
                             @AuthenticationPrincipal UserPrincipal patient,
                             @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        Instant expires = appointmentService.hold(request.slotId(), patient, authorization);
        return new HoldResponse(request.slotId(), expires);
    }

    @PostMapping("/confirm")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("hasRole('PATIENT')")
    public AppointmentResponse confirm(@Valid @RequestBody SlotIdRequest request,
                                       @AuthenticationPrincipal UserPrincipal patient,
                                       @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        return AppointmentResponse.from(appointmentService.confirm(request.slotId(), patient, authorization));
    }

    @PostMapping("/{id}/cancel")
    @PreAuthorize("hasRole('PATIENT')")
    public AppointmentResponse cancel(@PathVariable("id") Long id, @AuthenticationPrincipal UserPrincipal patient) {
        return AppointmentResponse.from(appointmentService.cancel(id, patient));
    }

    @GetMapping("/my")
    @PreAuthorize("hasRole('PATIENT')")
    public List<AppointmentResponse> myAppointments(@AuthenticationPrincipal UserPrincipal patient) {
        return appointmentService.myAppointments(patient.id()).stream().map(AppointmentResponse::from).toList();
    }

    @GetMapping("/doctor/{doctorId}")
    @PreAuthorize("hasAnyRole('DOCTOR', 'ADMIN')")
    public List<AppointmentResponse> doctorAppointments(
            @PathVariable("doctorId") Long doctorId,
            @AuthenticationPrincipal UserPrincipal caller,
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        List<Appointment> appointments = appointmentService.doctorAppointments(doctorId, caller, authorization);
        return appointments.stream().map(AppointmentResponse::from).toList();
    }
}
