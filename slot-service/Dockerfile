FROM maven:3.9.9-eclipse-temurin-17 AS build
WORKDIR /workspace

COPY pom.xml .
RUN mvn -B dependency:go-offline
COPY src ./src
RUN mvn -B -DskipTests package spring-boot:repackage

FROM eclipse-temurin:17-jre-jammy
WORKDIR /app

# curl is used by the container healthcheck to probe Spring Actuator.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app

COPY --from=build --chown=app:app /workspace/target/*.jar /app/app.jar

ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+UseContainerSupport"
USER app
EXPOSE 8083
HEALTHCHECK --interval=10s --timeout=3s --start-period=60s --retries=12 \
    CMD curl --fail --silent http://127.0.0.1:8083/actuator/health || exit 1

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
