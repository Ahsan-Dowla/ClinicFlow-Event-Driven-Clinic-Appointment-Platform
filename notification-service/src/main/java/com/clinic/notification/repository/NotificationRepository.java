package com.clinic.notification.repository;

import com.clinic.notification.model.Notification;
import com.clinic.notification.model.NotificationType;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface NotificationRepository extends JpaRepository<Notification, Long> {
    boolean existsByAppointmentIdAndType(Long appointmentId, NotificationType type);
    List<Notification> findByRecipientUserIdOrderByCreatedAtDesc(Long recipientUserId);
}
