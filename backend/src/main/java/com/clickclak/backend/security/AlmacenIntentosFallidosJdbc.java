package com.clickclak.backend.security;

import java.sql.Timestamp;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * Contador de intentos fallidos en PostgreSQL, compartido por todas las instancias.
 *
 * <p>Dos decisiones que importan:
 * <ul>
 *   <li><b>Escritura atómica.</b> El incremento es un único {@code INSERT ... ON CONFLICT DO
 *       UPDATE}, así dos instancias que reciben intentos a la vez no pierden ninguno ni se pisan.</li>
 *   <li><b>Transacción propia ({@code REQUIRES_NEW}).</b> {@code AutenticacionService} registra el
 *       fallo dentro de una transacción de solo lectura que enseguida se revierte al lanzar la
 *       excepción de credenciales inválidas; si el contador viviera en esa transacción, el fallo
 *       se desharía y la protección contra fuerza bruta no funcionaría.</li>
 * </ul>
 */
@Component
public class AlmacenIntentosFallidosJdbc implements AlmacenIntentosFallidos {

    private static final Duration VENTANA = Duration.ofMinutes(15);
    private static final int LONGITUD_MAXIMA_CORREO = 320;

    /** Ventana ya vencida y sin bloqueo vigente: el siguiente fallo empieza el conteo de cero. */
    private static final String VENCIDO = """
            ((intento_fallido.bloqueado_hasta IS NULL OR intento_fallido.bloqueado_hasta <= :ahora)
              AND intento_fallido.inicio_ventana + interval '15 minutes' <= :ahora)""";

    private static final String REGISTRAR_FALLO = """
            INSERT INTO intento_fallido (correo, fallos, inicio_ventana, bloqueado_hasta)
            VALUES (:correo, 1, :ahora, NULL)
            ON CONFLICT (correo) DO UPDATE SET
                fallos = CASE WHEN %1$s THEN 1 ELSE intento_fallido.fallos + 1 END,
                inicio_ventana = CASE WHEN %1$s THEN :ahora ELSE intento_fallido.inicio_ventana END,
                bloqueado_hasta = CASE WHEN %1$s THEN NULL
                                       WHEN intento_fallido.fallos + 1 >= %2$d THEN :hasta
                                       ELSE intento_fallido.bloqueado_hasta END
            """.formatted(VENCIDO, MAXIMO_FALLOS);

    private final NamedParameterJdbcTemplate jdbc;
    private final Clock reloj;
    private final int maximoEntradas;

    @Autowired
    public AlmacenIntentosFallidosJdbc(NamedParameterJdbcTemplate jdbc) {
        this(jdbc, Clock.systemUTC(), MAXIMO_ENTRADAS);
    }

    /** Reloj y tope configurables solo para probar la ventana y el límite sin esperar ni insertar miles de filas. */
    AlmacenIntentosFallidosJdbc(NamedParameterJdbcTemplate jdbc, Clock reloj, int maximoEntradas) {
        this.jdbc = jdbc;
        this.reloj = reloj;
        this.maximoEntradas = maximoEntradas;
    }

    @Override
    public Optional<Duration> tiempoRestanteDeBloqueo(String correo) {
        Instant ahora = reloj.instant();
        List<Timestamp> filas = jdbc.query(
                "SELECT bloqueado_hasta FROM intento_fallido WHERE correo = :correo AND bloqueado_hasta > :ahora",
                Map.of("correo", normalizar(correo), "ahora", Timestamp.from(ahora)),
                (rs, i) -> rs.getTimestamp(1));
        return filas.isEmpty() ? Optional.empty() : Optional.of(Duration.between(ahora, filas.get(0).toInstant()));
    }

    @Override
    public Set<String> correosBloqueados() {
        List<String> correos = jdbc.query(
                "SELECT correo FROM intento_fallido WHERE bloqueado_hasta > :ahora",
                Map.of("ahora", Timestamp.from(reloj.instant())),
                (rs, i) -> rs.getString(1));
        return new HashSet<>(correos);
    }

    @Override
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void registrarFallo(String correo) {
        Instant ahora = reloj.instant();
        Map<String, Object> parametros = Map.of(
                "correo", normalizar(correo),
                "ahora", Timestamp.from(ahora),
                "hasta", Timestamp.from(ahora.plus(VENTANA)));

        if (!existe(parametros) && cantidadRastreada() >= maximoEntradas) {
            // Se intenta hacer sitio con las cuentas ya vencidas; si no alcanza, la cuenta nueva no se
            // rastrea (el límite por IP del proxy cubre ese caso).
            jdbc.update("""
                    DELETE FROM intento_fallido
                    WHERE (bloqueado_hasta IS NULL OR bloqueado_hasta <= :ahora)
                      AND inicio_ventana + interval '15 minutes' <= :ahora
                    """, parametros);
            if (cantidadRastreada() >= maximoEntradas) {
                return;
            }
        }
        jdbc.update(REGISTRAR_FALLO, parametros);
    }

    @Override
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void limpiar(String correo) {
        jdbc.update("DELETE FROM intento_fallido WHERE correo = :correo", Map.of("correo", normalizar(correo)));
    }

    private boolean existe(Map<String, Object> parametros) {
        Integer cantidad = jdbc.queryForObject(
                "SELECT count(*) FROM intento_fallido WHERE correo = :correo", parametros, Integer.class);
        return cantidad != null && cantidad > 0;
    }

    private int cantidadRastreada() {
        Integer cantidad = jdbc.getJdbcOperations().queryForObject("SELECT count(*) FROM intento_fallido", Integer.class);
        return cantidad == null ? 0 : cantidad;
    }

    private String normalizar(String correo) {
        String normalizado = correo == null ? "" : correo.trim().toLowerCase(Locale.ROOT);
        return normalizado.length() > LONGITUD_MAXIMA_CORREO
                ? normalizado.substring(0, LONGITUD_MAXIMA_CORREO)
                : normalizado;
    }
}
