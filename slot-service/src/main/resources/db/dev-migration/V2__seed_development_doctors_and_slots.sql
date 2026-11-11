INSERT INTO doctors (user_id, name, specialization) VALUES
(2, 'Doctor One', 'Family Medicine'),
(3, 'Doctor Two', 'Cardiology');

INSERT INTO slots (doctor_id, start_time, end_time, status, version)
SELECT d.id,
       TIMESTAMP(DATE_ADD(CURDATE(), INTERVAL days.day_offset DAY), times.slot_time),
       TIMESTAMPADD(MINUTE, 30, TIMESTAMP(DATE_ADD(CURDATE(), INTERVAL days.day_offset DAY), times.slot_time)),
       'AVAILABLE',
       0
FROM doctors d
CROSS JOIN (SELECT 0 AS day_offset UNION ALL SELECT 1 UNION ALL SELECT 2) days
CROSS JOIN (SELECT '09:00:00' AS slot_time UNION ALL SELECT '10:00:00' UNION ALL SELECT '11:00:00') times;
