CREATE TABLE appointments (
    id BIGINT NOT NULL AUTO_INCREMENT,
    slot_id BIGINT NOT NULL,
    doctor_id BIGINT NOT NULL,
    patient_id BIGINT NOT NULL,
    patient_email VARCHAR(254) NOT NULL,
    start_time DATETIME(6) NOT NULL,
    status VARCHAR(20) NOT NULL,
    active_slot_id BIGINT NULL,
    reminder_sent BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    CONSTRAINT uk_appointments_active_slot UNIQUE (active_slot_id),
    INDEX idx_appointments_patient_start (patient_id, start_time),
    INDEX idx_appointments_doctor_start (doctor_id, start_time)
);
