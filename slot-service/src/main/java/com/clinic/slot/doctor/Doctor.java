package com.clinic.slot.doctor;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "doctors")
public class Doctor {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(name = "user_id", nullable = false, unique = true)
    private Long userId;
    @Column(nullable = false, length = 120)
    private String name;
    @Column(nullable = false, length = 120)
    private String specialization;
    @Column(name = "created_at", insertable = false, updatable = false)
    private Instant createdAt;

    protected Doctor() {
    }

    public Doctor(Long userId, String name, String specialization) {
        this.userId = userId;
        this.name = name;
        this.specialization = specialization;
    }

    public Long getId() { return id; }
    public Long getUserId() { return userId; }
    public String getName() { return name; }
    public String getSpecialization() { return specialization; }
    public Instant getCreatedAt() { return createdAt; }
}
