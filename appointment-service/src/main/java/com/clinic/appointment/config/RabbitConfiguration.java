package com.clinic.appointment.config;

import com.clinic.appointment.messaging.AppointmentEventAfterCommitHandler;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.amqp.support.converter.Jackson2JsonMessageConverter;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class RabbitConfiguration {
    @Bean
    TopicExchange clinicEventsExchange() {
        return new TopicExchange(AppointmentEventAfterCommitHandler.EXCHANGE, true, false);
    }

    @Bean
    MessageConverter rabbitJacksonMessageConverter() {
        return new Jackson2JsonMessageConverter();
    }
}
