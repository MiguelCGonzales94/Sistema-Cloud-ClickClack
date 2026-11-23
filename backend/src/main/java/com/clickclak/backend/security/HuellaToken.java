package com.clickclak.backend.security;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

/**
 * Huella SHA-256 (64 caracteres hexadecimales) de un token opaco. Los almacenes compartidos
 * guardan la huella y no el token: quien lea la base no puede reutilizarlo (OWASP A02).
 */
final class HuellaToken {

    private HuellaToken() {
    }

    static String sha256(String token) {
        try {
            byte[] resumen = MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(resumen);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 no está disponible en esta JVM", e);
        }
    }
}
