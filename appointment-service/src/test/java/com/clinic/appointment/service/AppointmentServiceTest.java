package com.clinic.appointment.service;

import com.clinic.appointment.messaging.AppointmentDomainEvent;
import com.clinic.appointment.repository.AppointmentRepository;
import com.clinic.appointment.security.UserPrincipal;
import com.clinic.appointment.slot.SlotClient;
import com.clinic.appointment.slot.SlotDetails;
import com.clinic.appointment.web.ApiException;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.http.HttpStatus;
import org.springframework.context.ApplicationEventPublisher;

import java.time.Duration;
import java.time.LocalDateTime;

import org.mockito.ArgumentCaptor;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AppointmentServiceTest {
    @Test
    void holdUsesRedisAtomicSetIfAbsentWithFiveMinuteExpiry() {
        AppointmentRepository appointments = mock(AppointmentRepository.class);
        SlotClient slotClient = mock(SlotClient.class);
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        @SuppressWarnings("unchecked")
        ValueOperations<String, String> values = mock(ValueOperations.class);
        ApplicationEventPublisher events = mock(ApplicationEventPublisher.class);
        when(redis.opsForValue()).thenReturn(values);
        when(slotClient.getSlot(11L, "Bearer token"))
                .thenReturn(new SlotDetails(11L, 3L, LocalDateTime.now().plusDays(1),
                        LocalDateTime.now().plusDays(1).plusMinutes(30), "AVAILABLE"));
        when(values.setIfAbsent(eq("hold:slot:11"), eq("52"), any())).thenReturn(true);
        AppointmentService service = new AppointmentService(appointments, slotClient, redis, events);

        service.hold(11L, new UserPrincipal(52L, "patient@example.test", "PATIENT"), "Bearer token");

        ArgumentCaptor<Duration> ttl = ArgumentCaptor.forClass(Duration.class);
        verify(values).setIfAbsent(eq("hold:slot:11"), eq("52"), ttl.capture());
        assertEquals(Duration.ofSeconds(300), ttl.getValue());
    }

    @Test
    void reportsExpiredHoldInsteadOfConfirmingWithoutOwnership() {
        AppointmentRepository appointments = mock(AppointmentRepository.class);
        SlotClient slotClient = mock(SlotClient.class);
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        @SuppressWarnings("unchecked")
        ValueOperations<String, String> values = mock(ValueOperations.class);
        ApplicationEventPublisher events = mock(ApplicationEventPublisher.class);
        when(redis.opsForValue()).thenReturn(values);
        when(values.get("hold:slot:11")).thenReturn(null);
        AppointmentService service = new AppointmentService(appointments, slotClient, redis, events);

        ApiException error = assertThrows(ApiException.class, () -> service.confirm(
                11L, new UserPrincipal(52L, "patient@example.test", "PATIENT"), "Bearer token"));

        assertEquals(HttpStatus.GONE, error.getStatus());
    }

    @Test
    void rejectsAnotherPatientsHold() {
        AppointmentRepository appointments = mock(AppointmentRepository.class);
        SlotClient slotClient = mock(SlotClient.class);
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        @SuppressWarnings("unchecked")
        ValueOperations<String, String> values = mock(ValueOperations.class);
        ApplicationEventPublisher events = mock(ApplicationEventPublisher.class);
        when(redis.opsForValue()).thenReturn(values);
        when(values.get("hold:slot:11")).thenReturn("99");
        AppointmentService service = new AppointmentService(appointments, slotClient, redis, events);

        ApiException error = assertThrows(ApiException.class, () -> service.confirm(
                11L, new UserPrincipal(52L, "patient@example.test", "PATIENT"), "Bearer token"));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
    }
}
