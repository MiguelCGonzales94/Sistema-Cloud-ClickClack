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

@SpringBootTest
class AlmacenTokensRecuperacionJdbcTest {

    @Autowired private JdbcTemplate jdbc;

    private AlmacenTokensRecuperacionJdbc almacen;

    @BeforeEach
    void configurar() {
        jdbc.update("DELETE FROM token_recuperacion");
        almacen = new AlmacenTokensRecuperacionJdbc(jdbc);
    }

    @Test
    void generarYConsumir_devuelveElUsuarioCorrecto() {
        String token = almacen.generar(42L);

        assertThat(almacen.consumir(token)).contains(42L);
    }

    @Test
    void consumir_esDeUnSoloUso() {
        String token = almacen.generar(42L);

        almacen.consumir(token);

        assertThat(almacen.consumir(token)).isEmpty();
    }

    @Test
    void consumir_conTokenDesconocido_devuelveVacio() {
        assertThat(almacen.consumir("token-inexistente")).isEmpty();
    }

    @Test
    void elTokenSePuedeEmitirEnUnaInstanciaYConsumirseEnOtra() {
        var otraInstancia = new AlmacenTokensRecuperacionJdbc(jdbc);

        String token = almacen.generar(7L);

        assertThat(otraInstancia.consumir(token)).contains(7L);
        assertThat(almacen.consumir(token)).isEmpty();
    }

    @Test
    void elTokenNoSeGuardaEnClaro() {
        String token = almacen.generar(42L);

        Integer enClaro = jdbc.queryForObject(
                "SELECT count(*) FROM token_recuperacion WHERE token_hash = ?", Integer.class, token);
        assertThat(enClaro).isZero();
    }

    @Test
    void consumir_despuesDeLaVigencia_devuelveVacio() {
        Instant inicio = Instant.now();
        String token = new AlmacenTokensRecuperacionJdbc(jdbc, Clock.fixed(inicio, ZoneOffset.UTC)).generar(42L);

        var treintaYUnMinutosDespues = Clock.fixed(inicio.plus(Duration.ofMinutes(31)), ZoneOffset.UTC);

        assertThat(new AlmacenTokensRecuperacionJdbc(jdbc, treintaYUnMinutosDespues).consumir(token)).isEmpty();
    }
}
