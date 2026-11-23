package com.clickclak.backend.security;

import java.util.Optional;

/**
 * Retiene el desafío criptográfico entre "iniciar" y "finalizar" de cada ceremonia WebAuthn. No
 * hay sesión de servidor (API stateless, ver SecurityConfig), así que este almacén hace ese
 * papel: de un solo uso y con expiración corta, porque el desafío solo tiene sentido durante los
 * segundos que dura la interacción biométrica.
 *
 * <p>La implementación de producción es {@link AlmacenDesafiosWebAuthnJdbc}: "iniciar" y
 * "finalizar" pueden caer en instancias distintas del backend.
 */
public interface AlmacenDesafiosWebAuthn {

    /** Guarda el desafío y devuelve el identificador que el cliente presentará al finalizar. */
    String guardar(Object valor);

    /** Un solo uso: se retira al consultarlo, exista o no, para impedir reintentos del mismo desafío. */
    <T> Optional<T> recuperar(String id, Class<T> tipo);
}
