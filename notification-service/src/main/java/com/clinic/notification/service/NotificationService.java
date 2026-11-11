package com.clinic.notification.service;

import com.clinic.notification.messaging.AppointmentEventMessage;
import com.clinic.notification.model.Notification;
import com.clinic.notification.model.NotificationType;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;

import java.time.format.DateTimeFormatter;

@Service
public class NotificationService {
    private static final Logger log = LoggerFactory.getLogger(NotificationService.class);
    private final NotificationStore notificationStore;

    public NotificationService(NotificationStore notificationStore) {
        this.notificationStore = notificationStore;
    }

    public void handle(AppointmentEventMessage event) {
        NotificationType type = notificationType(event.eventType());
        if (event.appointmentId() == null || event.patientId() == null
                || event.patientEmail() == null || event.patientEmail().isBlank()
                || event.startTime() == null) {
            throw new IllegalArgumentException("Appointment event is missing notification fields");
        }
        Notification notification = new Notification(event.appointmentId(), event.patientId(),
                event.patientEmail(), type, message(type, event));
        try {
            boolean created = notificationStore.storeIfAbsent(notification);
            log.info("Notification {} type={} appointmentId={} eventId={}",
                    created ? "recorded" : "duplicate-ignored", type, event.appointmentId(), event.eventId());
        } catch (DataIntegrityViolationException exception) {
            if (notificationStore.exists(event.appointmentId(), type)) {
                log.info("Duplicate notification ignored type={} appointmentId={} eventId={}",
                        type, event.appointmentId(), event.eventId());
                return;
            }
            throw exception;
        }
    }

    private NotificationType notificationType(String eventType) {
        return switch (eventType) {
            case "appointment.confirmed" -> NotificationType.CONFIRMATION;
            case "appointment.cancelled" -> NotificationType.CANCELLATION;
            case "appointment.reminder.due" -> NotificationType.REMINDER;
            default -> throw new IllegalArgumentException("Unsupported appointment event type");
        };
    }

    private String message(NotificationType type, AppointmentEventMessage event) {
        String time = event.startTime().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME);
        return switch (type) {
            case CONFIRMATION -> "Your appointment is confirmed for " + time + ".";
            case CANCELLATION -> "Your appointment for " + time + " has been cancelled.";
            case REMINDER -> "Reminder: your appointment is scheduled for " + time + ".";
        };
    }
}
