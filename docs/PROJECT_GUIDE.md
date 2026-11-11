# Clinic Booking Platform — Project Guide

This is the practical reference for setting up, running, testing, and operating the clinic booking platform. It covers both supported modes:

- **Phase 1:** Spring services and React run on the host; MySQL, Redis, and RabbitMQ run in Docker.
- **Phase 2:** The complete stack runs in Docker Compose; Nginx is the only public application entry point.

For architecture and the reasoning behind implementation choices, see [PROJECT_EXPLANATION.md](./PROJECT_EXPLANATION.md). The root [README.md](../README.md) remains the short introduction.

## What the platform does

- Patients register, sign in, browse doctors and available slots, hold and confirm appointments, cancel appointments, and view notifications.
- Doctors and administrators can manage doctor profiles and availability.
- Appointment holds expire after five minutes.
- Booking and cancellation events update slot availability and trigger notifications.
- JWT bearer tokens protect authenticated operations; roles distinguish patients, doctors, and administrators.

## Technology

| Area | Technology |
| --- | --- |
| Backend | Java 17, Spring Boot, Maven |
| Web UI | React, Vite, Node.js |
| Persistence | MySQL 8, Flyway |
| Temporary holds | Redis |
| Asynchronous events | RabbitMQ |
| Container web entry point | Nginx |
| Container orchestration | Docker Compose v2 |

## Services and ports

| Service | Responsibility | Phase 1 host port | Compose access |
| --- | --- | ---: | --- |
| Frontend | React UI | 5173 | Served by Nginx |
| API gateway | Public API routing and token validation | 8081 | Private; reached by Nginx |
| Auth service | Registration, login, and user accounts | 8082 | Private |
| Slot service | Doctors and bookable slots | 8083 | Private |
| Appointment service | Holds, confirmations, cancellations, reminders | 8084 | Private |
| Notification service | Event consumption and user notifications | 8085 | Private |
| MySQL | Four service schemas | 3306 | Private |
| Redis | Temporary booking holds | 6379 | Private |
| RabbitMQ | Durable application events | 5672 | Private |
| RabbitMQ management UI | Development administration | 15672 | Published for development |

In the full Compose stack, browser traffic enters Nginx on host port 80 by default; RabbitMQ management is published on host port 15672. Only those two ports are published. If either conflicts with another program, set `HTTP_PORT` or `RABBITMQ_MANAGEMENT_PORT` in `.env` before starting the stack.

### Current workspace port overrides

In this Windows workspace, IIS owns port 80 and the Phase 1 RabbitMQ uses port 15672. The Phase 2 stack was validated at [http://localhost:8092](http://localhost:8092), with management at [http://localhost:15673](http://localhost:15673). The tracked example retains the standard defaults. To use these overrides after a restart, set the following values in the ignored local `.env`:

```dotenv
HTTP_PORT=8092
RABBITMQ_MANAGEMENT_PORT=15673
```

Do not stop IIS or tear down the Phase 1 infrastructure just to free these ports.

## Requirements

### Phase 1 host development

- Java 17 and Maven
- Node.js and npm
- Docker Desktop or Docker Engine with Docker Compose v2
- Available ports 3306, 6379, 5672, 15672, 8081–8085, and 5173 (or adjust configuration where supported)

### Phase 2 full Compose stack

- Docker Desktop or Docker Engine with Docker Compose v2
- Available host ports 80 and 15672, or custom `HTTP_PORT` and `RABBITMQ_MANAGEMENT_PORT`
- A configured `.env` based on [.env.example](../.env.example)

## Configure secrets and environment

Create the ignored local environment file:

```powershell
Copy-Item .env.example .env
```

Edit `.env` before running the full stack. Replace every placeholder:

- `MYSQL_ROOT_PASSWORD`, `MYSQL_APP_PASSWORD`, and `RABBITMQ_PASSWORD`: use strong, unique values.
- `JWT_SECRET`: generate a random secret of at least 32 bytes and use the exact same value for every service.
- `INITIAL_ADMIN_PASSWORD_HASH`, `INITIAL_DOCTOR_ONE_PASSWORD_HASH`, and `INITIAL_DOCTOR_TWO_PASSWORD_HASH`: use BCrypt hashes of strong, distinct passwords. The example text is not a valid login password/hash.
- Change seeded account names and email addresses to appropriate values.
- Set `HTTP_PORT` and `RABBITMQ_MANAGEMENT_PORT` if the defaults are already occupied.

Do not commit `.env` or paste secret values into logs, tickets, or source files. `.env.example` contains placeholders only. The Compose stack uses the `prod` Spring profile and the environment-provided seed hashes. The Phase 1 development-only seed accounts use password `password`; never reuse those credentials outside a local demo.

Spring connection properties, ports, credentials, JWT settings, CORS origin, and downstream URLs are environment-backed. The `*_DOCKER_*` variables use Compose DNS names such as `mysql` and `auth-service`; do not change these to `localhost` for container-to-container communication.

## Run the full Docker Compose stack (Phase 2)

From the project root, after configuring `.env`:

```powershell
docker compose up -d --build
docker compose ps
```

Wait until all nine containers are healthy. Open the frontend at `http://localhost` (or `http://localhost:<HTTP_PORT>` if overridden). RabbitMQ management is at `http://localhost:15672` (or the configured management port).

Useful operational commands:

```powershell
docker compose ps
docker compose logs -f
docker compose logs -f api-gateway
docker compose logs -f appointment-service
docker compose stop
docker compose start
docker compose down
```

`docker compose down` removes the containers and network but preserves named volumes. To permanently delete **only Phase 2** database and broker data:

```powershell
docker compose down -v --remove-orphans
```

The Phase 1 infrastructure uses `infra/docker-compose.infra.yml` and a separate Compose project. Do not use its `down -v` command unless you intend to erase Phase 1 data.

## Run Phase 1 locally

Copy and configure `.env` as described above. Load it in each PowerShell terminal that will start a Spring service:

```powershell
Get-Content .env | Where-Object { $_ -match '^[A-Za-z_][A-Za-z0-9_]*=' } | ForEach-Object {
    $name, $value = $_ -split '=', 2
    Set-Item "Env:$name" $value
}
```

Start the infrastructure:

```powershell
docker compose --env-file .env -f infra/docker-compose.infra.yml up -d
docker compose --env-file .env -f infra/docker-compose.infra.yml ps
```

In separate terminals, start each backend service:

```powershell
mvn -f auth-service\pom.xml spring-boot:run
mvn -f api-gateway\pom.xml spring-boot:run
mvn -f slot-service\pom.xml spring-boot:run
mvn -f appointment-service\pom.xml spring-boot:run
mvn -f notification-service\pom.xml spring-boot:run
```

Start the frontend:

```powershell
npm install --prefix frontend
npm run dev --prefix frontend
```

Open `http://localhost:5173`. The API gateway is at `http://localhost:8081`. The development migration seeds `admin@clinic.local`, `doctor1@clinic.local`, and `doctor2@clinic.local` with the local-only password `password`.

## Main API routes

In Phase 1, use `http://localhost:8081`. In Phase 2, prepend the same paths with `http://localhost:<HTTP_PORT>/api`; Nginx strips `/api` before forwarding to the gateway.

| Method | Route | Purpose |
| --- | --- | --- |
| `POST` | `/auth/register` | Register a patient (`name`, `email`, `password`, optional `phone`) |
| `POST` | `/auth/login` | Sign in and receive a bearer JWT |
| `GET` | `/auth/me` | Read the authenticated profile |
| `GET` | `/doctors` | List doctors |
| `GET` | `/doctors/{id}` | Read a doctor profile |
| `GET` | `/doctors/{id}/slots?date=YYYY-MM-DD&status=AVAILABLE` | List a doctor's slots |
| `POST` | `/doctors/{id}/slots` | Create a slot (doctor owner or admin) |
| `POST` | `/doctors/{id}/slots/generate` | Generate a day's slots (doctor owner or admin) |
| `GET` | `/slots/{id}` | Read a slot |
| `POST` | `/appointments/hold` | Hold a slot for five minutes (`slotId`) |
| `POST` | `/appointments/confirm` | Confirm a held slot (`slotId`) |
| `POST` | `/appointments/{id}/cancel` | Cancel the caller's confirmed appointment |
| `GET` | `/appointments/my` | List the caller's appointments |
| `GET` | `/appointments/doctor/{doctorId}` | List a doctor's appointments |
| `GET` | `/notifications/my` | List the caller's notifications |

Protected routes require `Authorization: Bearer <token>`. Swagger UI is available at `/swagger-ui.html` on each Spring service; health is available at `/actuator/health`.

## Build and test

Run from the project root:

```powershell
mvn -f auth-service\pom.xml test
mvn -f api-gateway\pom.xml test
mvn -f slot-service\pom.xml test
mvn -f appointment-service\pom.xml test
mvn -f notification-service\pom.xml test
npm run build --prefix frontend
npm audit --prefix frontend
```

For the 20-client booking concurrency check, set `PATIENT_EMAIL`, `PATIENT_PASSWORD`, and a fresh `CONCURRENCY_SLOT_ID`, then run:

```powershell
node scripts\test-booking-concurrency.mjs
```

The expected result is exactly one successful hold and confirmation; the remaining contenders receive HTTP 409. Verified full-stack results, including notification queue recovery, are in [TEST_RESULTS.md](./TEST_RESULTS.md).

### Demo data and full stack verification

From the project root, after configuring `.env` and starting the Phase 2 stack:

```powershell
.\scripts\seed-demo-data.ps1
.\scripts\verify-stack.ps1
```

The seeder prompts for the seeded administrator password using a secure prompt. It preserves existing doctor profiles, skips existing patient accounts and slot times, and prints each newly generated demo-patient password once; save those passwords immediately if you need to use those accounts. The verifier prompts for the administrator password and, if absent from `.env`, the RabbitMQ management credentials; it securely prompts again if the RabbitMQ password is rejected. It runs the six containerized checks, restarts the stack with `docker compose down` (without removing volumes) and `docker compose up -d --wait`, then appends timestamped PASS/FAIL results to [TEST_RESULTS.md](./TEST_RESULTS.md). It requires Node.js for the 20-contender test and a configured `.env` whose Compose credentials and published ports match the persistent Phase 2 stack. Before `down`, it checks those values against running-container configuration; if they do not match, it reports failure and leaves the stack running.

## Troubleshooting

- **Compose reports a missing variable:** confirm `.env` exists and replace all required placeholders. Use the same JWT secret across services.
- **A host port is occupied:** change `HTTP_PORT` or `RABBITMQ_MANAGEMENT_PORT`; do not expose backend or database ports just for browser access.
- **A container is unhealthy:** inspect `docker compose ps` and `docker compose logs <service>`. Check MySQL/RabbitMQ credentials, service DNS values, and health endpoints.
- **A browser API request fails in Phase 2:** access the UI and API through the same Nginx origin and `/api` path. Do not set the browser API URL to a Docker-only service name.
- **A user cannot log in in Phase 2:** the `INITIAL_*_PASSWORD_HASH` value must be a BCrypt hash generated for the corresponding password. The placeholder is not usable.
- **A notification is delayed:** check `docker compose logs notification-service` and RabbitMQ queue depth. Durable queue behavior and the tested recovery procedure are recorded in [TEST_RESULTS.md](./TEST_RESULTS.md).

## Verification snapshot

The Phase 2 stack was verified with all nine containers healthy. The tested host mapping was Nginx `8092` and RabbitMQ management `15673` due to existing host port owners. End-to-end booking and cancellation passed, as did the 20-contender concurrency proof and notification-service stop/restart delivery proof.

The recorded clean `docker compose up -d --build` cold start was 217.5 seconds. Recorded image sizes: frontend/Nginx 74 MB, API gateway 464 MB, auth 499 MB, slot 503 MB, notification 503 MB, and appointment 521 MB. Detailed test evidence is in [TEST_RESULTS.md](./TEST_RESULTS.md).

## Related documentation

- [Project explanation and design decisions](./PROJECT_EXPLANATION.md)
- [Test results](./TEST_RESULTS.md)
- [Learning notes and interview answers](./LEARNING_NOTES.md)
- [Assumptions](./ASSUMPTIONS.md)
- [Root README](../README.md)
> **Development-only seed accounts:** Demo accounts created by the development seed migrations use the password `password` only with the development profile. Do not use these accounts outside local development.
