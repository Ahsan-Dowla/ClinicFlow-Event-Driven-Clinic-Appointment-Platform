package com.clinic.slot.web;

import com.clinic.slot.doctor.DoctorRequest;
import com.clinic.slot.doctor.DoctorResponse;
import com.clinic.slot.security.UserPrincipal;
import com.clinic.slot.service.SlotService;
import com.clinic.slot.service.DoctorLookupService;
import com.clinic.slot.slot.GenerateSlotsRequest;
import com.clinic.slot.slot.SlotRequest;
import com.clinic.slot.slot.SlotResponse;
import com.clinic.slot.slot.SlotStatus;
import jakarta.validation.Valid;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.List;

@RestController
@RequestMapping("/doctors")
public class DoctorController {
    private final SlotService slotService;
    private final DoctorLookupService doctorLookupService;

    public DoctorController(SlotService slotService, DoctorLookupService doctorLookupService) {
        this.slotService = slotService;
        this.doctorLookupService = doctorLookupService;
    }

    @GetMapping
    public List<DoctorResponse> doctors() {
        return slotService.doctors();
    }

    @GetMapping("/{id}")
    public DoctorResponse getDoctor(@PathVariable("id") Long id) {
        return doctorLookupService.getDoctor(id);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("hasRole('ADMIN')")
    public DoctorResponse createDoctor(@Valid @RequestBody DoctorRequest request) {
        return slotService.createDoctor(request);
    }

    @GetMapping("/{id}/slots")
    public List<SlotResponse> slots(@PathVariable("id") Long id,
            @RequestParam(name = "date") @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date,
            @RequestParam(name = "status", required = false) SlotStatus status) {
        return slotService.slots(id, date, status);
    }

    @PostMapping("/{id}/slots")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("hasAnyRole('DOCTOR', 'ADMIN')")
    public SlotResponse createSlot(@PathVariable("id") Long id, @Valid @RequestBody SlotRequest request,
                                   @AuthenticationPrincipal UserPrincipal caller) {
        return slotService.createSlot(id, request, caller);
    }

    @PostMapping("/{id}/slots/generate")
    @PreAuthorize("hasAnyRole('DOCTOR', 'ADMIN')")
    public List<SlotResponse> generate(@PathVariable("id") Long id, @Valid @RequestBody GenerateSlotsRequest request,
                                       @AuthenticationPrincipal UserPrincipal caller) {
        return slotService.generateSlots(id, request, caller);
    }
}
