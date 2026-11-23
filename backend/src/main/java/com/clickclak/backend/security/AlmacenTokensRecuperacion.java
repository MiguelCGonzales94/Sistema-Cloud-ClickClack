package com.clickclak.backend.security;

import java.util.Optional;

/**
 * HU03: "el enlace o código tiene vigencia limitada". Guarda, contra un token opaco de un solo
 * uso, el id del usuario que solicitó recuperar su acceso. La implementación de producción es
 * {@link AlmacenTokensRecuperacionJdbc}: el token puede emitirse en una instancia y consumirse en
 * otra.
 */
public interface AlmacenTokensRecuperacion {

    String generar(Long usuarioId);

    /** Un solo uso: se retira al consultarlo, exista o no, para que el enlace no sirva dos veces. */
    Optional<Long> consumir(String token);
}
