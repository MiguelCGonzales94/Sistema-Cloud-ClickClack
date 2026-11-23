package com.clickclak.backend.security;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

/** Doble de prueba en memoria para los tests unitarios de servicios; producción usa la versión JDBC. */
public class AlmacenIntentosFallidosMemoria implements AlmacenIntentosFallidos {

    private static final Duration VENTANA = Duration.ofMinutes(15);

    private record Registro(int fallos, Instant inicioVentana, Instant bloqueadoHasta) {
        boolean vencido(Instant ahora) {
            return (bloqueadoHasta == null || !bloqueadoHasta.isAfter(ahora))
                    && !inicioVentana.plus(VENTANA).isAfter(ahora);
        }
    }

    private final Map<String, Registro> registros = new ConcurrentHashMap<>();
    private final Clock reloj;

    public AlmacenIntentosFallidosMemoria() {
        this(Clock.systemUTC());
    }

    public AlmacenIntentosFallidosMemoria(Clock reloj) {
        this.reloj = reloj;
    }

    @Override
    public Optional<Duration> tiempoRestanteDeBloqueo(String correo) {
        Instant ahora = reloj.instant();
        Registro registro = registros.get(normalizar(correo));
        if (registro == null || registro.bloqueadoHasta() == null || !registro.bloqueadoHasta().isAfter(ahora)) {
            return Optional.empty();
        }
        return Optional.of(Duration.between(ahora, registro.bloqueadoHasta()));
    }

    @Override
    public Set<String> correosBloqueados() {
        Instant ahora = reloj.instant();
        return registros.entrySet().stream()
                .filter(e -> e.getValue().bloqueadoHasta() != null && e.getValue().bloqueadoHasta().isAfter(ahora))
                .map(Map.Entry::getKey)
                .collect(Collectors.toSet());
    }

    @Override
    public void registrarFallo(String correo) {
        Instant ahora = reloj.instant();
        registros.compute(normalizar(correo), (k, actual) -> {
            if (actual == null || actual.vencido(ahora)) {
                return new Registro(1, ahora, null);
            }
            int fallos = actual.fallos() + 1;
            Instant bloqueadoHasta = fallos >= MAXIMO_FALLOS ? ahora.plus(VENTANA) : actual.bloqueadoHasta();
            return new Registro(fallos, actual.inicioVentana(), bloqueadoHasta);
        });
    }

    @Override
    public void limpiar(String correo) {
        registros.remove(normalizar(correo));
    }

    private String normalizar(String correo) {
        return correo == null ? "" : correo.trim().toLowerCase(Locale.ROOT);
    }
}
