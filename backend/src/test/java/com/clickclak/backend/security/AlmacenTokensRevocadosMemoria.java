package com.clickclak.backend.security;

import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/** Doble de prueba en memoria para los tests unitarios de servicios; producción usa la versión JDBC. */
public class AlmacenTokensRevocadosMemoria implements AlmacenTokensRevocados {

    private final Map<String, Instant> revocados = new ConcurrentHashMap<>();

    @Override
    public void revocar(String token, Instant expiraEn) {
        revocados.put(token, expiraEn);
    }

    @Override
    public boolean estaRevocado(String token) {
        return revocados.containsKey(token);
    }
}
