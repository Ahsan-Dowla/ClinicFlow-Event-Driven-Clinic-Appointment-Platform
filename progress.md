# Clinic Booking Platform — Progress

## Status

Phase 1 is complete. Phase 2 Dockerization is implemented and the full Compose stack is currently running. On this host, Nginx is available at [http://localhost:8092](http://localhost:8092), and RabbitMQ management is at [http://localhost:15673](http://localhost:15673). The configured defaults remain ports 80 and 15672; this machine's IIS and Phase 1 RabbitMQ already own those ports.

## Phase 2 delivered

- Externalized service ports, database/cache/broker hosts, credentials, JWT key, downstream URLs, and gateway CORS origin.
- Added multi-stage images for all five Spring services and the React/Nginx frontend, including non-root backend runtime users and healthchecks.
- Added a private full-stack Compose network, MySQL schema initialization, environment example, and Phase 2-specific named volumes while preserving `infra/docker-compose.infra.yml`.
- Documented container startup, service health, request routing, cleanup, and architecture in the README and Phase 2 learning notes.

## Verification

- All five Maven suites and the frontend production build passed during D0.
- All nine Compose containers reached `healthy`; the root Compose file passed configuration validation.
- The UI and API gateway were exercised through Nginx. Registration/login returned HTTP 201/200; unauthenticated protected routes correctly returned HTTP 401.
- The end-to-end booking/cancellation flow passed, as did the 20-contender test (one successful hold/confirmation) and notification queue downtime/recovery test.
- Image sizes and the 217.5-second clean Compose startup are recorded in [docs/TEST_RESULTS.md](./docs/TEST_RESULTS.md).

## Run

Copy `.env.example` to `.env`, replace all example secrets and BCrypt hashes, then run `docker compose up -d --build`. See [README.md](./README.md) for logs, port overrides, stop commands, and the Phase 2-only data wipe procedure. Do not use the Phase 1 infrastructure Compose project to manage Phase 2 volumes.
