package com.clinic.notification.service;

import com.clinic.notification.model.Notification;
import com.clinic.notification.model.NotificationType;
import com.clinic.notification.repository.NotificationRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class NotificationStore {
    private final NotificationRepository repository;

    public NotificationStore(NotificationRepository repository) {
        this.repository = repository;
    }

    @Transactional
    public boolean storeIfAbsent(Notification notification) {
        if (repository.existsByAppointmentIdAndType(notification.getAppointmentId(), notification.getType())) {
            return false;
        }
        repository.saveAndFlush(notification);
        return true;
    }

    @Transactional(readOnly = true)
    public boolean exists(Long appointmentId, NotificationType type) {
        return repository.existsByAppointmentIdAndType(appointmentId, type);
    }
}
