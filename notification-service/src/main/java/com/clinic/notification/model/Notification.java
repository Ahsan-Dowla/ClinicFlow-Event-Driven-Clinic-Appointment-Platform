package com.clinic.notification.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import java.time.Instant;

@Entity
@Table(name = "notifications", uniqueConstraints = @UniqueConstraint(
        name = "uk_notifications_appointment_type", columnNames = {"appointment_id", "type"}))
public class Notification {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(name = "appointment_id", nullable = false)
    private Long appointmentId;
    @Column(name = "recipient_user_id", nullable = false)
    private Long recipientUserId;
    @Column(name = "recipient_email", nullable = false, length = 254)
    private String recipientEmail;
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private NotificationType type;
    @Column(nullable = false, length = 500)
    private String message;
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private NotificationStatus status;
    @Column(name = "created_at", insertable = false, updatable = false)
    private Instant createdAt;

    protected Notification() {
    }

    public Notification(Long appointmentId, Long recipientUserId, String recipientEmail,
                        NotificationType type, String message) {
        this.appointmentId = appointmentId;
        this.recipientUserId = recipientUserId;
        this.recipientEmail = recipientEmail;
        this.type = type;
        this.message = message;
        this.status = NotificationStatus.SENT;
    }

    public Long getId() { return id; }
    public Long getAppointmentId() { return appointmentId; }
    public Long getRecipientUserId() { return recipientUserId; }
    public String getRecipientEmail() { return recipientEmail; }
    public NotificationType getType() { return type; }
    public String getMessage() { return message; }
    public NotificationStatus getStatus() { return status; }
    public Instant getCreatedAt() { return createdAt; }
}
