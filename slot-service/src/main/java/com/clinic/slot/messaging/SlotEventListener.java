package com.clinic.slot.messaging;

import com.clinic.slot.service.SlotService;
import org.slf4j.MDC;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

@Component
public class SlotEventListener {
    private final SlotService slotService;

    public SlotEventListener(SlotService slotService) {
        this.slotService = slotService;
    }

    @RabbitListener(queues = SlotMessagingConfiguration.QUEUE,
            containerFactory = "slotRabbitListenerContainerFactory")
    public void receive(AppointmentEventMessage event) {
        MDC.put("correlationId", event.correlationId());
        try {
            slotService.applyAppointmentEvent(event);
        } finally {
            MDC.remove("correlationId");
        }
    }
}
