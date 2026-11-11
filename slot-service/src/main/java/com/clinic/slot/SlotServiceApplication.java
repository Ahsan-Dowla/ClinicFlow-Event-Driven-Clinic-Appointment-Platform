package com.clinic.slot;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;

@SpringBootApplication
@EnableMethodSecurity
public class SlotServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(SlotServiceApplication.class, args);
    }
}
