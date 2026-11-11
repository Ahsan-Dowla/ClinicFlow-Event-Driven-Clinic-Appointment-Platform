INSERT INTO users (name, email, password_hash, role, phone) VALUES
('${admin_name}', '${admin_email}', '${admin_password_hash}', 'ADMIN', NULL),
('${doctor_one_name}', '${doctor_one_email}', '${doctor_one_password_hash}', 'DOCTOR', NULL),
('${doctor_two_name}', '${doctor_two_email}', '${doctor_two_password_hash}', 'DOCTOR', NULL);
