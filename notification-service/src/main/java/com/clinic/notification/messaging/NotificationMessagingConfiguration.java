package com.clinic.notification.messaging;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.amqp.rabbit.config.RetryInterceptorBuilder;
import org.springframework.amqp.rabbit.config.SimpleRabbitListenerContainerFactory;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.amqp.rabbit.retry.RepublishMessageRecoverer;
import org.springframework.amqp.support.converter.Jackson2JsonMessageConverter;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.retry.interceptor.RetryOperationsInterceptor;

@Configuration
public class NotificationMessagingConfiguration {
    public static final String EXCHANGE = "clinic.events";
    public static final String QUEUE = "notification.appointment-events";
    public static final String DLQ = "notification.appointment-events.dlq";
    public static final String DLQ_ROUTING_KEY = "notification.appointment-events.dlq";

    @Bean
    TopicExchange clinicEventsExchange() {
        return new TopicExchange(EXCHANGE, true, false);
    }

    @Bean
    Queue notificationAppointmentEventsQueue() {
        return new Queue(QUEUE, true);
    }

    @Bean
    Queue notificationDeadLetterQueue() {
        return new Queue(DLQ, true);
    }

    @Bean
    Binding confirmedBinding(@Qualifier("notificationAppointmentEventsQueue") Queue notificationAppointmentEventsQueue,
                             TopicExchange clinicEventsExchange) {
        return BindingBuilder.bind(notificationAppointmentEventsQueue).to(clinicEventsExchange)
                .with("appointment.confirmed");
    }

    @Bean
    Binding cancelledBinding(@Qualifier("notificationAppointmentEventsQueue") Queue notificationAppointmentEventsQueue,
                             TopicExchange clinicEventsExchange) {
        return BindingBuilder.bind(notificationAppointmentEventsQueue).to(clinicEventsExchange)
                .with("appointment.cancelled");
    }

    @Bean
    Binding reminderBinding(@Qualifier("notificationAppointmentEventsQueue") Queue notificationAppointmentEventsQueue,
                            TopicExchange clinicEventsExchange) {
        return BindingBuilder.bind(notificationAppointmentEventsQueue).to(clinicEventsExchange)
                .with("appointment.reminder.due");
    }

    @Bean
    Binding deadLetterBinding(@Qualifier("notificationDeadLetterQueue") Queue notificationDeadLetterQueue,
                              TopicExchange clinicEventsExchange) {
        return BindingBuilder.bind(notificationDeadLetterQueue).to(clinicEventsExchange).with(DLQ_ROUTING_KEY);
    }

    @Bean
    MessageConverter rabbitJacksonMessageConverter() {
        return new Jackson2JsonMessageConverter();
    }

    @Bean
    SimpleRabbitListenerContainerFactory notificationRabbitListenerContainerFactory(
            ConnectionFactory connectionFactory, MessageConverter rabbitJacksonMessageConverter,
            RetryOperationsInterceptor notificationRetryInterceptor) {
        SimpleRabbitListenerContainerFactory factory = new SimpleRabbitListenerContainerFactory();
        factory.setConnectionFactory(connectionFactory);
        factory.setMessageConverter(rabbitJacksonMessageConverter);
        factory.setAdviceChain(notificationRetryInterceptor);
        factory.setDefaultRequeueRejected(false);
        return factory;
    }

    @Bean
    RetryOperationsInterceptor notificationRetryInterceptor(RabbitTemplate rabbitTemplate) {
        return RetryInterceptorBuilder.stateless().maxAttempts(3)
                .backOffOptions(1000, 2.0, 10000)
                .recoverer(new RepublishMessageRecoverer(rabbitTemplate, EXCHANGE, DLQ_ROUTING_KEY))
                .build();
    }
}
