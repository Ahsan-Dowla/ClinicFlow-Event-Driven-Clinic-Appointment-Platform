package com.clinic.slot.slot;

import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;

public interface SlotRepository extends JpaRepository<Slot, Long> {
    List<Slot> findByDoctorIdAndStartTimeGreaterThanEqualAndStartTimeLessThan(
            Long doctorId, LocalDateTime from, LocalDateTime to);
}
