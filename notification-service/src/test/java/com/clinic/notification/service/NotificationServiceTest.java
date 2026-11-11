package com.clinic.notification.service;

import com.clinic.notification.messaging.AppointmentEventMessage;
import com.clinic.notification.model.Notification;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;

import java.time.Instant;
import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class NotificationServiceTest {
    @Test
    void ignoresDuplicateAppointmentType() {
        NotificationStore store = mock(NotificationStore.class);
        when(store.storeIfAbsent(any(Notification.class))).thenReturn(false);
        NotificationService service = new NotificationService(store);

        service.handle(event("appointment.confirmed"));

        verify(store).storeIfAbsent(any(Notification.class));
    }

    @Test
    void retriesMalformedMessageInsteadOfWritingIncompleteNotification() {
        NotificationStore store = mock(NotificationStore.class);
        NotificationService service = new NotificationService(store);
        AppointmentEventMessage malformed = new AppointmentEventMessage(
                "event", "correlation", "appointment.confirmed", Instant.now(),
                9L, 3L, 2L, 5L, "", LocalDateTime.now());

        assertThrows(IllegalArgumentException.class, () -> service.handle(malformed));
        verify(store, never()).storeIfAbsent(any(Notification.class));
    }

    @Test
    void rethrowsNonDuplicateDatabaseFailuresForRetryAndDeadLetter() {
        NotificationStore store = mock(NotificationStore.class);
        when(store.storeIfAbsent(any(Notification.class))).thenThrow(new DataIntegrityViolationException("database"));
        when(store.exists(9L, com.clinic.notification.model.NotificationType.CONFIRMATION)).thenReturn(false);
        NotificationService service = new NotificationService(store);

        assertThrows(DataIntegrityViolationException.class, () -> service.handle(event("appointment.confirmed")));
    }

    private static AppointmentEventMessage event(String type) {
        return new AppointmentEventMessage("event", "correlation", type, Instant.now(), 9L, 3L, 2L, 5L,
                "patient@example.test", LocalDateTime.now().plusDays(1));
    }
}
