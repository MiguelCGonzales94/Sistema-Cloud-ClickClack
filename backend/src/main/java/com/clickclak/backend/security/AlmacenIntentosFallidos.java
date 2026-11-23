package com.clickclak.backend.security;

import java.time.Duration;
import java.util.Optional;
import java.util.Set;

/**
 * Frena la fuerza bruta contra una cuenta: tras {@value #MAXIMO_FALLOS} contraseñas incorrectas
 * dentro de la ventana de 15 minutos, la cuenta queda bloqueada durante esa ventana. La clave es
 * el correo que se envió, exista o no, para que el bloqueo no delate qué cuentas existen.
 *
 * <p>La implementación de producción es {@link AlmacenIntentosFallidosJdbc}: el contador vive en
 * PostgreSQL y es el mismo para todas las instancias del backend, de modo que repartir los
 * intentos entre instancias no permite saltarse el límite.
 *
 * <p>Límite conocido: quien conozca un correo puede bloquearlo 15 minutos enviando intentos
 * fallidos; es el costo de bloquear por cuenta y el límite por IP del proxy acota cuánto puede
 * repetirlo.
 */
public interface AlmacenIntentosFallidos {

    int MAXIMO_FALLOS = 5;

    /** Tope de cuentas rastreadas, para que correos inventados no hagan crecer la tabla sin límite. */
    int MAXIMO_ENTRADAS = 10_000;

    /** Tiempo que falta para que la cuenta se desbloquee, o vacío si no está bloqueada. */
    Optional<Duration> tiempoRestanteDeBloqueo(String correo);

    /** Correos (ya normalizados) con el bloqueo vigente; el panel los usa para mostrar y filtrar el estado de cuenta. */
    Set<String> correosBloqueados();

    void registrarFallo(String correo);

    /** Un acceso correcto borra el historial de fallos de esa cuenta. */
    void limpiar(String correo);
}
