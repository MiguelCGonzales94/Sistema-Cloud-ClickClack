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

import com.fasterxml.jackson.core.JsonProcessingException;
import com.yubico.webauthn.AssertionRequest;
import com.yubico.webauthn.data.PublicKeyCredentialCreationOptions;

/**
 * Desafíos WebAuthn en PostgreSQL. Los dos tipos que maneja el servicio (opciones de registro y
 * petición de aserción) se guardan como el JSON oficial de la librería Yubico ({@code toJson} /
 * {@code fromJson}), no como objetos serializados de Java.
 */
@Component
public class AlmacenDesafiosWebAuthnJdbc implements AlmacenDesafiosWebAuthn {

    private static final Duration VIGENCIA_POR_DEFECTO = Duration.ofMinutes(5);
    private static final String REGISTRO = "REGISTRO";
    private static final String AUTENTICACION = "AUTENTICACION";

    private final JdbcTemplate jdbc;
    private final Clock reloj;
    private final Duration vigencia;

    @Autowired
    public AlmacenDesafiosWebAuthnJdbc(JdbcTemplate jdbc) {
        this(jdbc, Clock.systemUTC(), VIGENCIA_POR_DEFECTO);
    }

    /** Vigencia configurable solo para poder probar la expiración sin esperar minutos reales. */
    AlmacenDesafiosWebAuthnJdbc(JdbcTemplate jdbc, Clock reloj, Duration vigencia) {
        this.jdbc = jdbc;
        this.reloj = reloj;
        this.vigencia = vigencia;
    }

    @Override
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public String guardar(Object valor) {
        String tipo;
        String contenido;
        try {
            if (valor instanceof PublicKeyCredentialCreationOptions opciones) {
                tipo = REGISTRO;
                contenido = opciones.toJson();
            } else if (valor instanceof AssertionRequest peticion) {
                tipo = AUTENTICACION;
                contenido = peticion.toJson();
            } else {
                throw new IllegalArgumentException("Tipo de desafío no soportado: "
                        + (valor == null ? "null" : valor.getClass().getName()));
            }
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("No se pudo serializar el desafío WebAuthn", e);
        }

        Instant ahora = reloj.instant();
        jdbc.update("DELETE FROM desafio_webauthn WHERE expira_en < ?", Timestamp.from(ahora));
        UUID id = UUID.randomUUID();
        jdbc.update("INSERT INTO desafio_webauthn (id, tipo, contenido, expira_en) VALUES (?, ?, ?, ?)",
                id, tipo, contenido, Timestamp.from(ahora.plus(vigencia)));
        return id.toString();
    }

    @Override
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public <T> Optional<T> recuperar(String id, Class<T> tipo) {
        UUID clave;
        try {
            clave = UUID.fromString(id);
        } catch (IllegalArgumentException e) {
            return Optional.empty();
        }

        record Fila(String tipo, String contenido, Instant expiraEn) {
        }
        // DELETE ... RETURNING: atómico y de un solo uso aunque dos instancias lo pidan a la vez.
        List<Fila> filas = jdbc.query(
                "DELETE FROM desafio_webauthn WHERE id = ? RETURNING tipo, contenido, expira_en",
                (rs, i) -> new Fila(rs.getString(1), rs.getString(2), rs.getTimestamp(3).toInstant()),
                clave);
        if (filas.isEmpty() || filas.get(0).expiraEn().isBefore(reloj.instant())) {
            return Optional.empty();
        }

        Fila fila = filas.get(0);
        try {
            if (REGISTRO.equals(fila.tipo()) && tipo.isAssignableFrom(PublicKeyCredentialCreationOptions.class)) {
                return Optional.of(tipo.cast(PublicKeyCredentialCreationOptions.fromJson(fila.contenido())));
            }
            if (AUTENTICACION.equals(fila.tipo()) && tipo.isAssignableFrom(AssertionRequest.class)) {
                return Optional.of(tipo.cast(AssertionRequest.fromJson(fila.contenido())));
            }
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("No se pudo leer el desafío WebAuthn guardado", e);
        }
        return Optional.empty();
    }
}
