package com.clickclak.backend.security;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/** Doble de prueba en memoria para los tests unitarios de servicios; producción usa la versión JDBC. */
public class AlmacenTokensRecuperacionMemoria implements AlmacenTokensRecuperacion {

    private record Entrada(Long usuarioId, Instant expiraEn) {
    }

    private final Map<String, Entrada> entradas = new ConcurrentHashMap<>();

    @Override
    public String generar(Long usuarioId) {
        String token = UUID.randomUUID().toString();
        entradas.put(token, new Entrada(usuarioId, Instant.now().plus(Duration.ofMinutes(30))));
        return token;
    }

    @Override
    public Optional<Long> consumir(String token) {
        Entrada entrada = entradas.remove(token);
        if (entrada == null || entrada.expiraEn().isBefore(Instant.now())) {
            return Optional.empty();
        }
        return Optional.of(entrada.usuarioId());
    }
}
