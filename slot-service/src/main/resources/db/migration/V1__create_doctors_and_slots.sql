CREATE TABLE doctors (
    id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    name VARCHAR(120) NOT NULL,
    specialization VARCHAR(120) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT uk_doctors_user UNIQUE (user_id)
);

CREATE TABLE slots (
    id BIGINT NOT NULL AUTO_INCREMENT,
    doctor_id BIGINT NOT NULL,
    start_time DATETIME(6) NOT NULL,
    end_time DATETIME(6) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'AVAILABLE',
    version BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    CONSTRAINT uk_slots_doctor_start UNIQUE (doctor_id, start_time),
    INDEX idx_slots_doctor_start (doctor_id, start_time)
);
