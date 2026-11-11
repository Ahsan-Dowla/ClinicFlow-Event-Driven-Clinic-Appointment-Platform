CREATE TABLE notifications (
    id BIGINT NOT NULL AUTO_INCREMENT,
    appointment_id BIGINT NOT NULL,
    recipient_user_id BIGINT NOT NULL,
    recipient_email VARCHAR(254) NOT NULL,
    type VARCHAR(20) NOT NULL,
    message VARCHAR(500) NOT NULL,
    status VARCHAR(20) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT uk_notifications_appointment_type UNIQUE (appointment_id, type),
    INDEX idx_notifications_recipient_created (recipient_user_id, created_at)
);
