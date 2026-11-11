package com.clinic.appointment.messaging;

import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

import java.util.List;

@Component
public class AppointmentEventAfterCommitHandler {
    public static final String EXCHANGE = "clinic.events";
    private static final DefaultRedisScript<Long> DELETE_IF_OWNED = new DefaultRedisScript<>(
            "if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('del', KEYS[1]) else return 0 end",
            Long.class);
    private final StringRedisTemplate redisTemplate;
    private final RabbitTemplate rabbitTemplate;

    public AppointmentEventAfterCommitHandler(StringRedisTemplate redisTemplate, RabbitTemplate rabbitTemplate) {
        this.redisTemplate = redisTemplate;
        this.rabbitTemplate = rabbitTemplate;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void afterCommit(AppointmentDomainEvent event) {
        rabbitTemplate.convertAndSend(EXCHANGE, event.eventType(), event, message -> {
            message.getMessageProperties().setDeliveryMode(
                    org.springframework.amqp.core.MessageDeliveryMode.PERSISTENT);
            return message;
        });
        if ("appointment.confirmed".equals(event.eventType())) {
            redisTemplate.execute(DELETE_IF_OWNED, List.of("hold:slot:" + event.slotId()),
                    event.patientId().toString());
        }
    }
}
