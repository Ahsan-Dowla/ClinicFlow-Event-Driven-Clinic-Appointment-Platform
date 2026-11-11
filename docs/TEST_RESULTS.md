# Test Results

## M7 — Reliability proof

### Booking concurrency test

Status: **Passed.** Ran `scripts/test-booking-concurrency.mjs` against a fresh available slot with 20 parallel contenders. Exactly one hold returned HTTP 200 and its confirmation returned HTTP 201; the other 19 hold attempts returned HTTP 409. The test script reported `PASS`.

To repeat with another fresh slot, set these environment variables in PowerShell:

```powershell
$env:PATIENT_EMAIL = 'patient@example.test'
$env:PATIENT_PASSWORD = '<the patient password>'
$env:CONCURRENCY_SLOT_ID = '<fresh available slot id>'
node scripts\test-booking-concurrency.mjs
```

### Notification-service downtime and recovery

Status: **Passed.** With the durable `notification.appointment-events` queue initially empty (`ready=0`, `unacked=0`), notification-service was stopped. A booking confirmed successfully while it was down, and the queue retained one ready message (`ready=1`, `unacked=0`). After notification-service restarted, its health endpoint returned `UP`, the queue drained to `ready=0`, and the patient's confirmation notification was persisted with status `SENT`.

### Booking and cancellation event flow

Status: **Passed.** Through the gateway, a patient held and confirmed a slot; the slot service observed `BOOKED`, and a confirmation notification was persisted. Cancelling the appointment returned `CANCELLED`; the slot returned to `AVAILABLE`, and a cancellation notification was persisted.

## Automated checks completed in this workspace

- `auth-service`: 2 Maven tests passed.
- `api-gateway`: 2 Maven tests passed. A runtime dependency mismatch that initially closed proxied requests was fixed by aligning the gateway on Spring Boot 3.3.7 and Spring Cloud 2023.0.5; registration and protected gateway requests then succeeded.
- `slot-service`: 3 Maven tests passed.
- `appointment-service`: 3 Maven tests passed.
- `notification-service`: 3 Maven tests passed.
- `frontend`: production Vite build passed; `npm audit` reported zero vulnerabilities.
- `infra/docker-compose.infra.yml`: `docker compose config` passed; MySQL, Redis, and RabbitMQ were started and healthy.
- API gateway runtime checks: health returned `UP`, patient registration/login succeeded, and booking/confirmation/cancellation routes completed successfully.

## Phase 2 — Docker

### D0 — Configuration audit

Passed. All five backend modules' Maven tests passed, the frontend production build passed, and the five Spring services started with their local `.env` values and reported `UP`. Credentials and the JWT signing key are now required environment values rather than literals in the Spring application YAML.

Port audit: ports `8081`–`8085` and `5173` were free before the host-run Phase 1 verification. Windows IIS (W3SVC/WAS) currently owns port `80`, and the existing Phase 1 RabbitMQ container publishes port `15672`. Neither process nor existing Phase 1 volume data was stopped or deleted.

### D1 — Auth-service image

Passed. Built `clinic-p2-auth:local` and ran it on host port `8082` with the `prod` profile against the existing Phase 1 MySQL container and a separate `auth_phase2_d1_db` test schema. The image runs as the non-root `app` user, its Docker healthcheck reported `healthy`, and `/actuator/health` returned `UP`.

### D2 — Backend service images

Passed. Built the slot, appointment, notification, and gateway images and ran all five backend containers on the infrastructure network. Each service used its own test schema, ran as the non-root application user, and reached `healthy`.

### D3 — Frontend and Nginx

Passed. Built the React/Nginx image and verified the UI and SPA fallback, same-origin `/api/` forwarding with prefix stripping, correlation-ID forwarding, and immutable caching for fingerprinted assets. Port 80 could not be bound in this environment because Windows IIS owns it; the final stack was validated on port `8092`.

### D4 — Full Compose stack

Passed. After a clean reset of only the Phase 2 volumes, `docker compose up -d --build` completed in **217.5 seconds**. All nine services subsequently reported `healthy`. Compose uses its own bridge network and named MySQL/RabbitMQ volumes, initializes all four databases, and grants the services a dedicated MySQL account. Compose configuration passed validation after the Docker DNS hostnames and downstream service URLs were made environment-driven. Inspection confirmed application containers do not receive `MYSQL_ROOT_PASSWORD`.

Host-port notes: IIS owns port `80`; port `8091` was also occupied by another process/container, so Nginx used `8092`. The Phase 1 RabbitMQ already publishes `15672`, so management was mapped to `15673`. The Compose defaults remain `80` and `15672` for a clean host.

### D5 — End-to-end container flow

Passed through Nginx: the admin created a doctor, the doctor created slots, a patient registered and logged in, held and confirmed a slot, then cancelled the appointment. The slot changed to `BOOKED` and back to `AVAILABLE`; confirmation and cancellation notifications were persisted as `SENT`. Final smoke requests through `http://localhost:8092` returned HTTP 200 for `/` and `/api/actuator/health`, HTTP 401 for unauthenticated `/api/doctors` and `/api/slots`, HTTP 201 for registration, and HTTP 200 for login.

### D6 — Reliability proofs in Compose

The 20-parallel booking test passed through `/api`: exactly one hold returned HTTP 200 and its confirmation returned HTTP 201; the other 19 holds returned HTTP 409.

### D7 — Image sizes and cold start

Measured the built images with `docker images`:

| Image | Size |
| --- | ---: |
| Frontend/Nginx | 74 MB |
| API gateway | 464 MB |
| Auth service | 499 MB |
| Slot service | 503 MB |
| Notification service | 503 MB |
| Appointment service | 521 MB |

Cold start: **217.5 seconds** for the clean `docker compose up -d --build` command; all nine containers were then confirmed healthy. No screenshot files were captured; reproducible URLs, HTTP status codes, health states, queue counters, and persisted booking/notification states are recorded above.

## Phase 2 - containerized verification

Checks a-d passed through Nginx: container health, Nginx login, patient hold/confirm/cancel, and 20 parallel booking attempts produced 1 success and 19 HTTP 409 responses.

The notification-downtime and restart-persistence checks were verified manually; the automated script for them is still being fixed.
