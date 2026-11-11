-- Development-only seeded accounts use BCrypt("password"). Change these credentials before any shared deployment.
INSERT INTO users (name, email, password_hash, role, phone) VALUES
('Clinic Administrator', 'admin@clinic.local', '$2b$10$MUaFFvRIdkniC4Vayvuj8.tRIwEr4Be3V3vC8W9sHX6fySA9V3BWG', 'ADMIN', NULL),
('Doctor One', 'doctor1@clinic.local', '$2b$10$MUaFFvRIdkniC4Vayvuj8.tRIwEr4Be3V3vC8W9sHX6fySA9V3BWG', 'DOCTOR', NULL),
('Doctor Two', 'doctor2@clinic.local', '$2b$10$MUaFFvRIdkniC4Vayvuj8.tRIwEr4Be3V3vC8W9sHX6fySA9V3BWG', 'DOCTOR', NULL);
