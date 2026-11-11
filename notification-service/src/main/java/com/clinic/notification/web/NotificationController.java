package com.clinic.notification.web;

import com.clinic.notification.repository.NotificationRepository;
import com.clinic.notification.security.UserPrincipal;
import com.clinic.notification.web.dto.NotificationResponse;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/notifications")
public class NotificationController {
    private final NotificationRepository notificationRepository;

    public NotificationController(NotificationRepository notificationRepository) {
        this.notificationRepository = notificationRepository;
    }

    @GetMapping("/my")
    public List<NotificationResponse> myNotifications(@AuthenticationPrincipal UserPrincipal principal) {
        return notificationRepository.findByRecipientUserIdOrderByCreatedAtDesc(principal.id())
                .stream().map(NotificationResponse::from).toList();
    }
}
