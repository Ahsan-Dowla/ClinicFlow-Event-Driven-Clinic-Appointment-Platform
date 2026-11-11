package com.clinic.gateway.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.jsonwebtoken.JwtException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.cloud.gateway.filter.GlobalFilter;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import reactor.core.publisher.Mono;

import java.io.IOException;
import java.time.Instant;
import java.util.UUID;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class JwtGatewayFilter implements GlobalFilter {
    private static final Logger log = LoggerFactory.getLogger(JwtGatewayFilter.class);
    private static final String CORRELATION_HEADER = "X-Correlation-Id";
    private final JwtTokenVerifier tokenVerifier;
    private final ObjectMapper objectMapper;

    public JwtGatewayFilter(JwtTokenVerifier tokenVerifier, ObjectMapper objectMapper) {
        this.tokenVerifier = tokenVerifier;
        this.objectMapper = objectMapper;
    }

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String correlationId = exchange.getRequest().getHeaders().getFirst(CORRELATION_HEADER);
        if (correlationId == null || correlationId.isBlank()) {
            correlationId = UUID.randomUUID().toString();
        }
        final String requestCorrelationId = correlationId;
        exchange.getResponse().getHeaders().set(CORRELATION_HEADER, requestCorrelationId);

        AuthenticatedIdentity identity = null;
        if (!isPublicAuthRequest(exchange) && !HttpMethod.OPTIONS.equals(exchange.getRequest().getMethod())) {
            String authorization = exchange.getRequest().getHeaders().getFirst(HttpHeaders.AUTHORIZATION);
            if (authorization == null || !authorization.startsWith("Bearer ")) {
                return unauthorized(exchange, requestCorrelationId, "Authentication is required");
            }
            try {
                identity = tokenVerifier.verify(authorization.substring(7));
            } catch (JwtException | IllegalArgumentException exception) {
                return unauthorized(exchange, requestCorrelationId, "The access token is invalid or expired");
            }
        }

        AuthenticatedIdentity trustedIdentity = identity;
        ServerWebExchange forwarded = exchange.mutate().request(request -> request.headers(headers -> {
            headers.remove("X-User-Id");
            headers.remove("X-User-Role");
            headers.set(CORRELATION_HEADER, requestCorrelationId);
            if (trustedIdentity != null) {
                headers.set("X-User-Id", trustedIdentity.userId().toString());
                headers.set("X-User-Role", trustedIdentity.role());
            }
        })).build();
        log.info("Gateway request method={} path={} correlationId={}",
                exchange.getRequest().getMethod(), exchange.getRequest().getPath(), requestCorrelationId);
        return chain.filter(forwarded);
    }

    private boolean isPublicAuthRequest(ServerWebExchange exchange) {
        return HttpMethod.POST.equals(exchange.getRequest().getMethod())
                && ("/auth/register".equals(exchange.getRequest().getPath().value())
                || "/auth/login".equals(exchange.getRequest().getPath().value()));
    }

    private Mono<Void> unauthorized(ServerWebExchange exchange, String correlationId, String message) {
        var response = exchange.getResponse();
        response.setStatusCode(HttpStatus.UNAUTHORIZED);
        response.getHeaders().setContentType(MediaType.APPLICATION_JSON);
        response.getHeaders().set(CORRELATION_HEADER, correlationId);
        byte[] body;
        try {
            body = objectMapper.writeValueAsBytes(new GatewayError(
                    Instant.now(), 401, "Unauthorized", message, exchange.getRequest().getPath().value()));
        } catch (IOException exception) {
            return Mono.error(exception);
        }
        return response.writeWith(Mono.just(response.bufferFactory().wrap(body)));
    }

    private record GatewayError(Instant timestamp, int status, String error, String message, String path) {
    }
}
