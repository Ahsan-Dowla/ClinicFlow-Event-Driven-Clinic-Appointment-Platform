package com.clinic.notification.web.dto;

import com.clinic.notification.model.Notification;
import com.clinic.notification.model.NotificationStatus;
import com.clinic.notification.model.NotificationType;

import java.time.Instant;

public record NotificationResponse(Long id, Long appointmentId, String recipientEmail,
                                   NotificationType type, String message, NotificationStatus status,
                                   Instant createdAt) {
    public static NotificationResponse from(Notification notification) {
        return new NotificationResponse(notification.getId(), notification.getAppointmentId(),
                notification.getRecipientEmail(), notification.getType(), notification.getMessage(),
                notification.getStatus(), notification.getCreatedAt());
    }
}
