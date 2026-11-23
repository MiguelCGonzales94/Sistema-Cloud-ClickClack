package com.clickclak.backend.security;

import java.time.Instant;

/**
 * HU02: "el cierre invalida la sesión activa". Los JWT de este sistema son *stateless* por
 * diseño (ver {@link JwtAuthenticationFilter}), así que cerrar sesión no "borra" nada en el
 * servidor por sí solo: el token seguiría siendo válido hasta su expiración natural (hasta 8 h).
 * Esta lista de revocación es lo que hace que, tras un logout explícito, ese mismo token deje de
 * servir de inmediato.
 *
 * <p>Es un contrato porque el estado debe ser <b>compartido entre instancias</b>: la
 * implementación de producción es {@link AlmacenTokensRevocadosJdbc} (PostgreSQL).
 */
public interface AlmacenTokensRevocados {

    void revocar(String token, Instant expiraEn);

    boolean estaRevocado(String token);
}
