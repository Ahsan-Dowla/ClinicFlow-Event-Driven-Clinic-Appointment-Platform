package com.clinic.slot.doctor;

public record DoctorResponse(Long id, Long userId, String name, String specialization) {
    public static DoctorResponse from(Doctor doctor) {
        return new DoctorResponse(doctor.getId(), doctor.getUserId(), doctor.getName(), doctor.getSpecialization());
    }
}
