package com.clickclak.backend.security;

import java.sql.Timestamp;
import java.time.Clock;
import java.time.Instant;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * Lista de revocación en PostgreSQL, compartida por todas las instancias del backend.
 *
 * <p>La revocación se escribe en su <b>propia transacción</b> ({@code REQUIRES_NEW}): quien la
 * llama puede estar en una transacción de solo lectura o que se revierte, y un cierre de sesión
 * no debe perderse por eso.
 */
@Component
public class AlmacenTokensRevocadosJdbc implements AlmacenTokensRevocados {

    private final JdbcTemplate jdbc;
    private final Clock reloj;

    @Autowired
    public AlmacenTokensRevocadosJdbc(JdbcTemplate jdbc) {
        this(jdbc, Clock.systemUTC());
    }

    AlmacenTokensRevocadosJdbc(JdbcTemplate jdbc, Clock reloj) {
        this.jdbc = jdbc;
        this.reloj = reloj;
    }

    @Override
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void revocar(String token, Instant expiraEn) {
        // Se purgan las ya vencidas para que la tabla no crezca sin límite.
        jdbc.update("DELETE FROM token_revocado WHERE expira_en < ?", Timestamp.from(reloj.instant()));
        jdbc.update("""
                INSERT INTO token_revocado (token_hash, expira_en) VALUES (?, ?)
                ON CONFLICT (token_hash) DO NOTHING
                """, HuellaToken.sha256(token), Timestamp.from(expiraEn));
    }

    @Override
    public boolean estaRevocado(String token) {
        Integer cantidad = jdbc.queryForObject(
                "SELECT count(*) FROM token_revocado WHERE token_hash = ?", Integer.class, HuellaToken.sha256(token));
        return cantidad != null && cantidad > 0;
    }
}
