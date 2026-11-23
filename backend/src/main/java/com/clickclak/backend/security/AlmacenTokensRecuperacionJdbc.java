package com.clickclak.backend.security;

import java.sql.Timestamp;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * Tokens de recuperación en PostgreSQL. Se guarda la huella SHA-256, no el token. El consumo es un
 * {@code DELETE ... RETURNING}: atómico, así dos instancias no pueden aceptar el mismo enlace.
 */
@Component
public class AlmacenTokensRecuperacionJdbc implements AlmacenTokensRecuperacion {

    private static final Duration VIGENCIA = Duration.ofMinutes(30);

    private final JdbcTemplate jdbc;
    private final Clock reloj;

    @Autowired
    public AlmacenTokensRecuperacionJdbc(JdbcTemplate jdbc) {
        this(jdbc, Clock.systemUTC());
    }

    AlmacenTokensRecuperacionJdbc(JdbcTemplate jdbc, Clock reloj) {
        this.jdbc = jdbc;
        this.reloj = reloj;
    }

    @Override
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public String generar(Long usuarioId) {
        Instant ahora = reloj.instant();
        jdbc.update("DELETE FROM token_recuperacion WHERE expira_en < ?", Timestamp.from(ahora));
        String token = UUID.randomUUID().toString();
        jdbc.update("INSERT INTO token_recuperacion (token_hash, usuario_id, expira_en) VALUES (?, ?, ?)",
                HuellaToken.sha256(token), usuarioId, Timestamp.from(ahora.plus(VIGENCIA)));
        return token;
    }

    @Override
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public Optional<Long> consumir(String token) {
        record Fila(Long usuarioId, Instant expiraEn) {
        }
        List<Fila> filas = jdbc.query(
                "DELETE FROM token_recuperacion WHERE token_hash = ? RETURNING usuario_id, expira_en",
                (rs, i) -> new Fila(rs.getLong(1), rs.getTimestamp(2).toInstant()),
                HuellaToken.sha256(token));
        if (filas.isEmpty() || filas.get(0).expiraEn().isBefore(reloj.instant())) {
            return Optional.empty();
        }
        return Optional.of(filas.get(0).usuarioId());
    }
}
