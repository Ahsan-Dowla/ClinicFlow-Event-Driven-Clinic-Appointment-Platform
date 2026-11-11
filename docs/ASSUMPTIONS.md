# Assumptions

- The requested backend port `8081` is assigned to the API gateway, the public backend entry point.
- To keep all Spring Boot services independently runnable, auth-service uses `8082`, slot-service `8083`, appointment-service `8084`, and notification-service `8085`.
- Development credentials and default values in `.env.example` are local-only examples; deployments must provide their own values.
- Phase 1 runs the application services and frontend directly on the host. Compose runs only MySQL, Redis, and RabbitMQ.
- Appointment records keep the patient's email as a booking-time snapshot so scheduled reminder events do not need a synchronous auth-service lookup later.
- Development seed users are installed only by the auth service's dev-profile Flyway migration. The prod profile seeds the initial administrator and doctors from environment-provided BCrypt hashes instead of development credentials.
- The Phase 1 development seed migration intentionally contains the documented password `password` as a BCrypt hash; it is dev-only and must never be enabled for a shared deployment. Containerized services use the `prod` profile and environment-provided seed hashes.
- Application credentials and the JWT signing key are environment-only values. Host-run development still uses the local `.env` defaults; the containerized Compose stack requires its shared JWT key at runtime and activates the `prod` profile.
- The frontend image uses the repository root as its build context so the Dockerfile can copy the canonical `nginx/nginx.conf` without duplicating it. The root `.dockerignore` excludes local build outputs, dependencies, and environment files; `frontend/.dockerignore` documents the frontend-specific exclusions for a standalone context.
- Windows IIS already owns host port `80` in this environment, and the Phase 1 RabbitMQ container owns host port `15672`. Port `8091` was also occupied during validation. The Compose defaults remain `80` and `15672` as requested; local validation therefore uses `HTTP_PORT=8092` and `RABBITMQ_MANAGEMENT_PORT=15673` without stopping IIS or disrupting Phase 1 infrastructure.
