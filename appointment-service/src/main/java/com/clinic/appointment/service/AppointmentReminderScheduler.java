package com.clinic.appointment.service;

import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class AppointmentReminderScheduler {
    private final AppointmentService appointmentService;

    public AppointmentReminderScheduler(AppointmentService appointmentService) {
        this.appointmentService = appointmentService;
    }

    @Scheduled(fixedDelayString = "${app.reminders.interval-ms:60000}")
    public void publishDueReminders() {
        appointmentService.publishDueReminders();
    }
}
