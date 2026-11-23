package com.clickclak.backend.security;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

@SpringBootTest
class AlmacenIntentosFallidosJdbcTest {

    /** Reloj que se mueve a mano, para probar la ventana de 15 minutos sin esperar. */
    private static final class RelojManual extends Clock {
        private Instant ahora = Instant.parse("2026-10-03T12:00:00Z");

        void avanzar(Duration tiempo) {
            ahora = ahora.plus(tiempo);
        }

        @Override public java.time.ZoneId getZone() { return ZoneOffset.UTC; }
        @Override public Clock withZone(java.time.ZoneId zona) { return this; }
        @Override public Instant instant() { return ahora; }
    }

    private static final int TOPE_DE_PRUEBA = 50;

    @Autowired private JdbcTemplate jdbc;
    @Autowired private NamedParameterJdbcTemplate jdbcNombrado;
    @Autowired private PlatformTransactionManager transacciones;
    @Autowired private AlmacenIntentosFallidos almacenDeLaAplicacion;

    private RelojManual reloj;
    private AlmacenIntentosFallidosJdbc almacen;

    @BeforeEach
    void configurar() {
        jdbc.update("DELETE FROM intento_fallido");
        reloj = new RelojManual();
        almacen = new AlmacenIntentosFallidosJdbc(jdbcNombrado, reloj, TOPE_DE_PRUEBA);
    }

    @Test
    void conMenosDeCincoFallos_noHayBloqueo() {
        fallar(almacen, "ana@example.com", 4);

        assertThat(almacen.tiempoRestanteDeBloqueo("ana@example.com")).isEmpty();
    }

    @Test
    void alQuintoFallo_bloqueaQuinceMinutos() {
        fallar(almacen, "ana@example.com", 5);

        assertThat(almacen.tiempoRestanteDeBloqueo("ana@example.com")).contains(Duration.ofMinutes(15));
    }

    @Test
    void elBloqueoVenceConElTiempo() {
        fallar(almacen, "ana@example.com", 5);

        reloj.avanzar(Duration.ofMinutes(14));
        assertThat(almacen.tiempoRestanteDeBloqueo("ana@example.com")).contains(Duration.ofMinutes(1));

        reloj.avanzar(Duration.ofMinutes(1));
        assertThat(almacen.tiempoRestanteDeBloqueo("ana@example.com")).isEmpty();
    }

    @Test
    void trasElVencimiento_losFallosEmpiezanDeCero() {
        fallar(almacen, "ana@example.com", 5);
        reloj.avanzar(Duration.ofMinutes(16));

        fallar(almacen, "ana@example.com", 4);

        assertThat(almacen.tiempoRestanteDeBloqueo("ana@example.com")).isEmpty();
    }

    @Test
    void losFallosViejosFueraDeLaVentanaNoSeAcumulan() {
        fallar(almacen, "ana@example.com", 4);
        reloj.avanzar(Duration.ofMinutes(20));
        almacen.registrarFallo("ana@example.com");

        assertThat(almacen.tiempoRestanteDeBloqueo("ana@example.com")).isEmpty();
    }

    @Test
    void limpiarBorraElHistorialDeLaCuenta() {
        fallar(almacen, "ana@example.com", 5);

        almacen.limpiar("ana@example.com");

        assertThat(almacen.tiempoRestanteDeBloqueo("ana@example.com")).isEmpty();
    }

    @Test
    void cadaCuentaTieneSuPropioContador() {
        fallar(almacen, "ana@example.com", 5);

        assertThat(almacen.tiempoRestanteDeBloqueo("luis@example.com")).isEmpty();
    }

    @Test
    void ignoraMayusculasYEspaciosEnElCorreo() {
        for (int i = 0; i < 5; i++) {
            almacen.registrarFallo("  Ana@Example.COM ");
        }

        assertThat(almacen.tiempoRestanteDeBloqueo("ana@example.com")).isPresent();
    }

    @Test
    void correosBloqueados_listaSoloLosQueTienenBloqueoVigente() {
        fallar(almacen, "ana@example.com", 5);
        fallar(almacen, "luis@example.com", 2);

        assertThat(almacen.correosBloqueados()).containsExactly("ana@example.com");
    }

    @Test
    void conMuchasCuentasNuevas_noCreceSinLimite() {
        for (int i = 0; i < TOPE_DE_PRUEBA + 20; i++) {
            almacen.registrarFallo("cuenta" + i + "@example.com");
        }
        // Una cuenta nueva ya no se rastrea, pero tampoco rompe nada...
        almacen.registrarFallo("extra@example.com");
        assertThat(almacen.tiempoRestanteDeBloqueo("extra@example.com")).isEmpty();
        assertThat(jdbc.queryForObject("SELECT count(*) FROM intento_fallido", Integer.class))
                .isLessThanOrEqualTo(TOPE_DE_PRUEBA);

        // ...y una cuenta ya rastreada sigue pudiendo bloquearse.
        fallar(almacen, "cuenta0@example.com", 4);
        assertThat(almacen.tiempoRestanteDeBloqueo("cuenta0@example.com")).isPresent();
    }

    @Test
    void conUnCorreoMuyLargo_noRompeElRegistro() {
        String largo = "a".repeat(1000) + "@example.com";

        almacen.registrarFallo(largo);

        assertThat(jdbc.queryForObject("SELECT count(*) FROM intento_fallido", Integer.class)).isEqualTo(1);
    }

    @Test
    void elContadorEsCompartidoEntreInstanciasDelBackend() {
        var otraInstancia = new AlmacenIntentosFallidosJdbc(jdbcNombrado, reloj, TOPE_DE_PRUEBA);

        // Los 5 intentos se reparten entre dos instancias: aun así la cuenta se bloquea.
        fallar(almacen, "ana@example.com", 3);
        fallar(otraInstancia, "ana@example.com", 2);

        assertThat(almacen.tiempoRestanteDeBloqueo("ana@example.com")).isPresent();
        assertThat(otraInstancia.tiempoRestanteDeBloqueo("ana@example.com")).isPresent();
    }

    /**
     * AutenticacionService registra el fallo dentro de una transacción de solo lectura que se revierte
     * al lanzar la excepción de credenciales inválidas. El contador no debe revertirse con ella: si lo
     * hiciera, la protección contra fuerza bruta no funcionaría.
     */
    @Test
    void elFalloSeConservaAunqueLaTransaccionDelLlamadorSeRevierta() {
        String correo = "rollback.intentos@example.com";
        new TransactionTemplate(transacciones).executeWithoutResult(estado -> {
            for (int i = 0; i < 5; i++) {
                almacenDeLaAplicacion.registrarFallo(correo);
            }
            estado.setRollbackOnly();
        });

        assertThat(almacenDeLaAplicacion.tiempoRestanteDeBloqueo(correo)).isPresent();
        almacenDeLaAplicacion.limpiar(correo);
    }

    private static void fallar(AlmacenIntentosFallidos almacen, String correo, int veces) {
        for (int i = 0; i < veces; i++) {
            almacen.registrarFallo(correo);
        }
    }
}
