# Learning Notes

## M0 — Infrastructure and project foundation

The local foundation now describes the service boundaries, ports, environment variables, and infrastructure dependencies. MySQL creates one schema per service at first initialization; Redis and RabbitMQ use named volumes so local data survives container restarts. Only infrastructure dependencies are containerized in Phase 1.

**Interview questions**

1. **Why does each service have its own schema?**  
   It lets each service own its data and migrations without cross-service database coupling. Other services communicate through APIs or events instead of querying its tables.

2. **Why use a named volume for MySQL?**  
   A named volume keeps database files when a container is recreated. It makes local restarts convenient while remaining removable for a clean development reset.

3. **What is the role of the API gateway?**  
   It gives the frontend one public entry point and centralizes routing and request-level concerns. Service implementations remain independently deployable and responsible for their own data.

## M1 — Auth service

The auth service stores accounts in its own MySQL schema, hashes new passwords with BCrypt, and issues signed HS256 JWTs with the user id, email, role, and expiration. A stateless security filter verifies those tokens on protected endpoints. Dev Flyway seeds use documented development-only credentials; the prod profile seeds from environment-provided BCrypt hashes instead.

**Interview questions**

1. **Why hash passwords with BCrypt instead of encrypting them?**  
   Passwords should not be recoverable, so a one-way adaptive hash is appropriate. BCrypt also salts each password and makes offline guessing more expensive.

2. **Why does the service use stateless JWT authentication?**  
   The signed token carries the identity claims needed by later requests, so the service does not keep a server-side login session. Each request still verifies the signature and expiry.

3. **Why does registration always assign the PATIENT role?**  
   A public registration request must not be able to grant privileged roles. Doctor and administrator accounts are provisioned through trusted development seeds or administrative flows.

## M2 — API gateway

The gateway is the frontend's single API entry point on port `8081`. It routes to service URLs from environment variables, allows registration and login without a token, verifies JWT signatures and expiry on other routes, and replaces client-supplied identity headers with claims from the verified token. It also adds or forwards a correlation ID and applies the configured frontend CORS policy.

**Interview questions**

1. **Why validate a JWT at both the gateway and each service?**  
   The gateway rejects unauthenticated traffic early and forwards trusted identity headers. Each service still verifies the signed token, so direct calls that bypass the gateway do not bypass authentication.

2. **Why remove client-supplied user headers?**  
   A caller could forge an identity header to impersonate another user. The gateway must derive these headers only from a successfully verified token.

3. **What does a correlation ID help with?**  
   It lets logs from one request be linked across the gateway and downstream services. The gateway creates one when absent and propagates it to every routed service.

## M3 — Slot service

The slot service owns doctor profiles and the bookable-slot schedule. Doctors may create slots only for their own profile, while administrators may manage any profile. The schema enforces one start time per doctor, and the slot version supports optimistic updates when appointment events later change availability. Seed data creates two doctors with slots for the next three days.

**Interview questions**

1. **Why keep doctor and slot data in the slot service?**  
   The service that owns scheduling can enforce its rules and evolve its schema independently. Appointment records keep their own needed doctor and slot identifiers instead of using cross-schema foreign keys.

2. **Why use a unique constraint on doctor and slot start time?**  
   It prevents duplicate schedule entries even if concurrent requests attempt to create the same slot. Input checks improve feedback, but the database constraint remains the final integrity guarantee.

3. **What is optimistic locking used for on a slot?**  
   A version detects when a row changed after it was read, avoiding a silent lost update. Appointment events can retry or surface a conflict instead of overwriting newer state.

## M4 — Appointment service

The appointment service validates a slot through the slot API, then acquires `hold:slot:{slotId}` with Redis `SET NX EX` semantics and a five-minute expiry. Confirmation requires that the hold still belongs to the patient and inserts an appointment with a unique active-slot value. Both the expiring Redis hold and the database uniqueness constraint are required: Redis gives early feedback and frees abandoned holds, while the database remains correct if Redis expires or restarts. The hold is released only after commit with an atomic compare-and-delete script, so another patient's replacement hold is not removed. Reminder scheduling marks upcoming appointments and raises a domain event after the database transaction commits.

**Interview questions**

1. **Why use both Redis and a database unique constraint for booking?**  
   Redis quickly serializes attempts and expires abandoned holds. The unique constraint is the durable correctness guarantee if Redis state is lost, expires unexpectedly, or application logic races.

2. **Why release the hold after the database commit?**  
   Releasing it earlier could let another patient enter while the booking transaction later fails. After commit, compare-and-delete ensures cleanup cannot delete a new hold belonging to someone else.

3. **Why use `active_slot_id` instead of a unique `slot_id`?**  
   A cancelled appointment retains its history but clears `active_slot_id`. MySQL permits multiple NULLs in a unique index, allowing the slot to be booked again without losing the cancelled record.

## M5 — Events and notifications

The appointment service publishes persistent JSON events only after the appointment transaction commits. The slot service binds a durable queue to confirmation/cancellation and applies updates idempotently. The notification service binds all three event keys, stores mock-email notifications with a unique `(appointment_id, type)` constraint, retries listener failures three times with backoff, and republishes exhausted messages to its durable DLQ.

**Interview questions**

1. **Why publish only after the appointment transaction commits?**  
   Publishing before commit could tell other services a booking exists even if the database rolls it back. The after-commit listener emits only once the appointment is durable.

2. **How does the notification service handle duplicate delivery?**  
   It checks the appointment and notification type before insertion and has a matching unique database constraint. If two consumers race on the same event, it treats the resulting unique conflict as an already-processed duplicate.

3. **What happens after a notification message fails repeatedly?**  
   The listener retries it three times using exponential backoff. The recoverer republishes the persistent message to a durable dead-letter queue for inspection or later replay.

## M6 — Frontend

The React/Vite client uses one Axios instance configured with `VITE_API_BASE_URL`, which points to the gateway. The authentication context keeps the JWT in memory and local storage, and the request interceptor attaches it to protected calls. Patients can register, browse doctors, hold a slot with a five-minute countdown, confirm, cancel, and review notifications; doctors and admins have a schedule dashboard.

**Interview questions**

1. **Why does the frontend call only the gateway?**  
   It keeps service addresses out of browser code and gives the backend one place to enforce JWT validation, CORS, and routing. Individual services can move without changing frontend request logic.

2. **Why keep the token in memory and local storage?**  
   In-memory state makes it available to requests during the current app session, while local storage survives a page refresh. The trade-off is that local storage is accessible to same-origin JavaScript, so the app should also prevent cross-site scripting.

3. **How does the hold countdown improve the booking flow?**  
   It shows the expiry from the server's hold response and disables confirmation after expiration. The backend remains authoritative and returns a clear conflict or expired-hold response if the state changed.

## M7 — Reliability tests

The concurrency test script starts 20 parallel hold attempts for a single fresh slot and confirms the contender that acquired the hold. A manual RabbitMQ walkthrough proves the notification queue buffers events while notification-service is stopped and drains them after it restarts. These runtime tests could not be executed in this environment because the Docker Desktop engine pipe was unavailable; the limitation and exact runbook are recorded in `docs/TEST_RESULTS.md`.

**Interview questions**

1. **Why is a test with many simultaneous contenders different from sequential tests?**  
   Concurrency exposes timing windows where two requests may both observe an available slot. It verifies the actual coordination mechanism under contention, not just the happy path.

2. **How can a durable queue help during a consumer outage?**  
   A persistent message in a durable queue remains available after the consumer stops or restarts. The consumer can catch up when it returns, provided the broker and queue remain available.

3. **Why document a test that could not be run?**  
   A clear status avoids presenting an unverified claim as evidence. The repeatable commands and expected observations let the test be completed when its infrastructure is available.

## M8 — Documentation and Phase 1 polish

The README now describes local setup, ports, API routes, test commands, and the complete service/event topology. The architecture guide records design trade-offs for interviews, and all later phases remain explicitly out of scope.

**Interview questions**

1. **Why use a service-owned schema instead of shared tables?**  
   Ownership keeps each service's migrations and business rules independent. It also avoids hidden coupling where one service depends on another service's internal SQL schema.

2. **What does eventual consistency mean for the slot status?**  
   An appointment can be committed before the slot-service consumes the confirmation event. The slot list may briefly lag, but the appointment database constraint still prevents another active booking.

3. **How do the docs make a multi-service project easier to operate?**  
   A port map, startup sequence, API summary, and failure test instructions make local setup reproducible. Architecture and learning notes also explain why the mechanisms were chosen, not just how to launch them.

## Phase 2 — Docker

### D0 — Configuration audit and externalization

Audited all five Spring configurations and the frontend. Database, Redis, RabbitMQ, downstream service, service-port, CORS, and browser API settings are environment-backed; the existing `localhost` values are Phase 1 host-run defaults. Removed literal database/RabbitMQ passwords and the JWT signing key from Spring configuration files: developers now provide these through their local `.env`, while containers will require them at runtime. The Phase 1 seed migration still intentionally includes the BCrypt hash for the dev-only password `password`; the prod seed uses environment-provided hashes. The local frontend API fallback remains `http://localhost:8081`; a container build will use same-origin `/api`.

The host ports `8081`–`8085` and `5173` were free at the audit. Port `80` is owned by Windows IIS (W3SVC/WAS), and `15672` is published by the existing Phase 1 RabbitMQ container; neither was stopped or modified during the audit.

**D0 verification:** All five Maven test suites passed, the frontend production build passed, and all five host-run Spring services reported `UP` using the existing local `.env`. This confirms Phase 1 defaults still work when environment values are loaded as described in the README.

**Interview questions**

1. **Why keep local defaults while moving connection settings to environment variables?**  
   The same application artifact can run on a developer machine or inside Compose without source edits. Local defaults are only for non-secret host addresses; credentials are supplied through the ignored `.env`.

2. **Why must all services use the same JWT secret?**  
   The issuer signs tokens with that key and each validating service verifies the signature with it. A mismatch causes valid logins to fail at protected endpoints.

3. **Why is the seeded `password` still present in the dev migration?**  
   It makes the Phase 1 demo accounts reproducible and is explicitly limited to the dev profile. Containerized services use the prod profile, whose seed hashes are injected through environment variables.

### D1 — Auth-service image

Added a two-stage auth-service Dockerfile. Maven first resolves dependencies from the POM-only layer, then packages and repackages the application as an executable Spring Boot JAR; the JRE runtime installs curl for the Actuator healthcheck, copies only the executable JAR, sets container-aware heap sizing, and runs as an unprivileged user. The first run exposed that this project does not inherit Spring Boot's parent POM, so `mvn package` alone creates a non-executable JAR; the Docker build explicitly invokes the `repackage` goal.

**D1 verification:** Built `clinic-p2-auth:local` and ran it on port `8082` against the existing Phase 1 MySQL container, using a separate test schema and the `prod` profile. The container ran as user `app`, passed its Docker healthcheck, and `/actuator/health` returned `UP`.

**Interview questions**

1. **Why use a multi-stage build?**  
   Maven and the JDK are needed only to compile the application. The runtime image contains the JRE and packaged JAR, so build tooling and source files do not ship with the service.

2. **Why resolve Maven dependencies before copying source?**  
   Docker can reuse the dependency layer while source files change. This avoids downloading the same dependencies on every code edit.

3. **Why run the service as a non-root user and include curl?**  
   A non-root process limits the impact of a compromised application. Curl is installed only because the configured Docker healthcheck uses it to query Actuator.

### D2 — Backend service images

Added multi-stage images and matching `.dockerignore` files for the slot, appointment, notification, and gateway services. Each build caches Maven dependencies before copying source, invokes Spring Boot's `repackage` goal to create an executable JAR, and runs the JRE image as a non-root user with the service's Actuator healthcheck.

**D2 verification:** All four images built successfully. All five backend images, including auth from D1, then ran together on the existing infrastructure network with isolated test schemas; each container ran as its non-root application user and reached Docker health status `healthy`.

**Interview questions**

1. **How does Docker DNS let services find one another?**  
   Containers on the same Compose network resolve service names such as `mysql` or `auth-service` to container IP addresses. `localhost` inside a container refers only to that same container.

2. **Why are backend ports not published on the host?**  
   The frontend Nginx container is the public entry point and can reach the backend over the private bridge network. Keeping service ports private reduces unnecessary host exposure.

3. **Why give each service its own healthcheck?**  
   A running process is not necessarily ready to handle requests. Actuator health provides Compose a service-level readiness signal after application startup.

### D3 — Frontend and Nginx

Added a Node build stage that runs `npm ci` and builds React with `VITE_API_BASE_URL=/api`, then a small Nginx runtime image that serves only the generated static assets. Nginx supplies the SPA fallback, gzip, immutable caching for fingerprinted assets, and a same-origin `/api/` proxy to the gateway.

**D3 verification:** Built the frontend image, validated the Nginx configuration on a Docker network with the gateway alias, and ran it on an available local test port. The root and `/register` returned HTTP 200, `/api/doctors` reached the gateway and returned its expected unauthenticated HTTP 401 with the correlation ID preserved, and a fingerprinted JavaScript asset returned `Cache-Control: public, immutable`. Port 80 remains unavailable on this host because Windows IIS owns it.

**Interview questions**

1. **Why build the frontend into static files and serve them with Nginx?**  
   The Node toolchain is needed only during compilation. Nginx can serve the finished assets without shipping Node, source code, or development dependencies.

2. **Why does the browser use `/api` instead of a backend hostname?**  
   The browser uses the same origin for both the UI and API, avoiding CORS setup for the containerized path. Nginx resolves the gateway's Docker service name internally.

3. **Why does the proxy target end in a slash?**  
   With `location /api/` and `proxy_pass .../`, Nginx replaces the matched prefix so the gateway receives `/auth/...` or `/doctors/...`. The gateway routes remain unchanged from Phase 1.

### D4 — Full-stack Compose

Added a separate root Compose project with one private bridge network, ordered health dependencies, environment-driven Docker DNS hosts and service URLs, environment-provided credentials, and project-specific MySQL/RabbitMQ volumes. The existing Phase 1 infrastructure Compose file remains independent. The MySQL image initializes all four schemas and grants a dedicated application user access to them; only Nginx and the development RabbitMQ management UI publish host ports.

**D4 verification:** A clean Phase 2 volume reset followed by `docker compose up -d --build` completed in 217.5 seconds; all nine containers subsequently reached `healthy`. The Compose configuration also passed validation after Docker DNS hosts and downstream URLs were exposed as `.env` variables. Application containers use the dedicated MySQL account and do not receive the MySQL root password.

**Interview questions**

1. **Why use `depends_on` with `condition: service_healthy`?**  
   Plain `depends_on` waits only for a dependency container to start, not for MySQL or an application to accept requests. The health condition delays dependent services until the dependency's healthcheck succeeds.

2. **How does the full Compose stack avoid coupling to host-installed services?**  
   Containers reach each other by service DNS names on a private bridge network. Only Nginx and the optional management UI publish host ports; the backend, database, cache, and AMQP ports stay private.

3. **How are Phase 1 data and Phase 2 data kept separate?**  
   The root Compose project has its own project name and named MySQL/RabbitMQ volumes. The existing `infra` project retains its current volumes and containers unless explicitly operated on with its own Compose file.

### D5 — End-to-end container flow

Verified the browser and API through the Nginx public entry point. The admin/doctor/patient workflow created a doctor and slots, registered a patient, held and confirmed a booking, and cancelled it; slot states and persisted notifications matched each transition. The final smoke test through the currently available local mapping returned HTTP 200 for the UI and health endpoint, HTTP 401 for unauthenticated protected routes, HTTP 201 for registration, and HTTP 200 for login.

**Interview questions**

1. **Why proxy API requests through the same Nginx origin as the UI?**  
   The browser needs only one public origin, while Nginx handles the internal gateway hostname. This avoids exposing backend ports and simplifies browser CORS behavior.

2. **Why did the unauthenticated doctor endpoint return HTTP 401?**  
   The request reached the gateway through Nginx and the route requires a bearer token. A 401 is expected authorization behavior, not a proxy or service-health failure.

3. **How was the booking flow verified beyond checking HTTP responses?**  
   The test also checked the slot's persisted state and the confirmation/cancellation notification records. That verifies the asynchronous side effects as well as the synchronous API result.

### D6 — Containerized reliability proofs

Ran the 20-contender booking test against the containerized `/api` path: exactly one hold returned HTTP 200 and its confirmation returned HTTP 201; the remaining 19 hold attempts returned HTTP 409. Then stopped notification-service, confirmed a booking while it was down, observed one ready RabbitMQ message (`ready=1`, `unacked=0`), restarted the service, and verified delivery (`SENT`) and queue drain (`ready=0`).

**Interview questions**

1. **Why should a concurrent booking test have exactly one winner?**  
   The hold operation must make the availability check and reservation atomic. A single winner demonstrates competing requests cannot reserve the same slot.

2. **Why does a queued message survive a notification-service restart?**  
   The queue and message are durable, and RabbitMQ data is stored in a named volume. The consumer can resume processing after it reconnects.

3. **Why test service downtime rather than only a healthy booking flow?**  
   It proves the producer is decoupled from notification delivery and that transient consumer outages do not silently discard events. Queue counters and the persisted `SENT` state verify recovery.

### D7 — Operational documentation and image review

Updated the README with Compose prerequisites, first-run commands, URLs, logs, safe stop/data-wipe commands, and a Phase 2 architecture diagram. Recorded the image sizes and full cold-start timing in the test results. The documented host-port override is important on this machine because IIS owns port 80 and the Phase 1 RabbitMQ uses port 15672.

**Interview questions**

1. **Why is the image size much smaller than the source/build environment?**  
   Multi-stage builds leave Maven, the JDK, and frontend build dependencies in intermediate stages. The final images contain only the JRE and executable JAR, or Nginx and static assets.

2. **How do Docker DNS and Compose health dependencies work together?**  
   Service names resolve containers on the private network, avoiding hardcoded IP addresses. Health-conditioned dependencies delay startup until dependencies are ready, unlike basic start-order dependencies.

3. **Why keep named volumes and document `down` separately from `down -v`?**  
   Ordinary teardown should preserve database and broker data for the next run. Removing volumes is destructive, so the README distinguishes stopping/removing containers from intentionally wiping Phase 2 data.
