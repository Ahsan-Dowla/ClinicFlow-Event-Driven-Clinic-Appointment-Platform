package com.clinic.notification.messaging;

import com.clinic.notification.service.NotificationService;
import org.slf4j.MDC;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

@Component
public class NotificationEventListener {
    private final NotificationService notificationService;

    public NotificationEventListener(NotificationService notificationService) {
        this.notificationService = notificationService;
    }

    @RabbitListener(queues = NotificationMessagingConfiguration.QUEUE,
            containerFactory = "notificationRabbitListenerContainerFactory")
    public void receive(AppointmentEventMessage event) {
        MDC.put("correlationId", event.correlationId());
        try {
            notificationService.handle(event);
        } finally {
            MDC.remove("correlationId");
        }
    }
}
