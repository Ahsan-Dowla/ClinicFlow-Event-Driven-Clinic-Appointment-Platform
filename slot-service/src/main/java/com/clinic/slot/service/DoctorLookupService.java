package com.clinic.slot.service;

import com.clinic.slot.doctor.DoctorRepository;
import com.clinic.slot.doctor.DoctorResponse;
import com.clinic.slot.web.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DoctorLookupService {
    private final DoctorRepository doctorRepository;

    public DoctorLookupService(DoctorRepository doctorRepository) {
        this.doctorRepository = doctorRepository;
    }

    @Transactional(readOnly = true)
    public DoctorResponse getDoctor(Long id) {
        return DoctorResponse.from(doctorRepository.findById(id)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Doctor not found")));
    }
}
