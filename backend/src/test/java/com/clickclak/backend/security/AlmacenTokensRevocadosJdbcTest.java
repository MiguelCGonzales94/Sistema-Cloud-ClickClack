package com.clickclak.backend.security;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.Timestamp;
import java.time.Instant;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

/** Lista de revocación sobre PostgreSQL real: lo que debe cumplir para poder escalar a varias instancias. */
@SpringBootTest
class AlmacenTokensRevocadosJdbcTest {

    @Autowired private JdbcTemplate jdbc;

    private AlmacenTokensRevocadosJdbc almacen;

    @BeforeEach
    void configurar() {
        jdbc.update("DELETE FROM token_revocado");
        almacen = new AlmacenTokensRevocadosJdbc(jdbc);
    }

    @Test
    void tokenNoRevocado_noApareceComoRevocado() {
        assertThat(almacen.estaRevocado("cualquier-token")).isFalse();
    }

    @Test
    void tokenRevocado_apareceComoRevocado() {
        almacen.revocar("token-1", Instant.now().plusSeconds(60));

        assertThat(almacen.estaRevocado("token-1")).isTrue();
        assertThat(almacen.estaRevocado("token-2")).isFalse();
    }

    @Test
    void laRevocacionEsVisibleDesdeOtraInstanciaDelBackend() {
        var otraInstancia = new AlmacenTokensRevocadosJdbc(jdbc);

        almacen.revocar("token-compartido", Instant.now().plusSeconds(60));

        assertThat(otraInstancia.estaRevocado("token-compartido")).isTrue();
    }

    @Test
    void elTokenNoSeGuardaEnClaro() {
        almacen.revocar("token-secreto", Instant.now().plusSeconds(60));

        Integer enClaro = jdbc.queryForObject(
                "SELECT count(*) FROM token_revocado WHERE token_hash = 'token-secreto'", Integer.class);
        assertThat(enClaro).isZero();
    }

    @Test
    void alRevocar_sePurganLasEntradasYaVencidas() {
        jdbc.update("INSERT INTO token_revocado (token_hash, expira_en) VALUES (?, ?)",
                "a".repeat(64), Timestamp.from(Instant.now().minusSeconds(60)));

        almacen.revocar("token-nuevo", Instant.now().plusSeconds(60));

        Integer vencidas = jdbc.queryForObject(
                "SELECT count(*) FROM token_revocado WHERE expira_en < now()", Integer.class);
        assertThat(vencidas).isZero();
    }

    @Test
    void revocarDosVecesElMismoToken_noFalla() {
        almacen.revocar("token-1", Instant.now().plusSeconds(60));
        almacen.revocar("token-1", Instant.now().plusSeconds(60));

        assertThat(almacen.estaRevocado("token-1")).isTrue();
    }
}
