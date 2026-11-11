package com.clinic.slot.messaging;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.amqp.rabbit.config.SimpleRabbitListenerContainerFactory;
import org.springframework.amqp.rabbit.config.RetryInterceptorBuilder;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.amqp.rabbit.retry.RejectAndDontRequeueRecoverer;
import org.springframework.amqp.support.converter.Jackson2JsonMessageConverter;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.retry.interceptor.RetryOperationsInterceptor;

@Configuration
public class SlotMessagingConfiguration {
    public static final String EXCHANGE = "clinic.events";
    public static final String QUEUE = "slot.appointment-events";

    @Bean
    TopicExchange clinicEventsExchange() {
        return new TopicExchange(EXCHANGE, true, false);
    }

    @Bean
    Queue slotAppointmentEventsQueue() {
        return new Queue(QUEUE, true);
    }

    @Bean
    MessageConverter rabbitJacksonMessageConverter() {
        return new Jackson2JsonMessageConverter();
    }

    @Bean
    Binding confirmedBinding(Queue slotAppointmentEventsQueue, TopicExchange clinicEventsExchange) {
        return BindingBuilder.bind(slotAppointmentEventsQueue).to(clinicEventsExchange)
                .with("appointment.confirmed");
    }

    @Bean
    Binding cancelledBinding(Queue slotAppointmentEventsQueue, TopicExchange clinicEventsExchange) {
        return BindingBuilder.bind(slotAppointmentEventsQueue).to(clinicEventsExchange)
                .with("appointment.cancelled");
    }

    @Bean
    SimpleRabbitListenerContainerFactory slotRabbitListenerContainerFactory(
            ConnectionFactory connectionFactory, MessageConverter rabbitJacksonMessageConverter,
            RetryOperationsInterceptor slotRetryInterceptor) {
        SimpleRabbitListenerContainerFactory factory = new SimpleRabbitListenerContainerFactory();
        factory.setConnectionFactory(connectionFactory);
        factory.setMessageConverter(rabbitJacksonMessageConverter);
        factory.setAdviceChain(slotRetryInterceptor);
        factory.setDefaultRequeueRejected(false);
        return factory;
    }

    @Bean
    RetryOperationsInterceptor slotRetryInterceptor() {
        return RetryInterceptorBuilder.stateless().maxAttempts(3)
                .backOffOptions(500, 2.0, 5000)
                .recoverer(new RejectAndDontRequeueRecoverer())
                .build();
    }
}
