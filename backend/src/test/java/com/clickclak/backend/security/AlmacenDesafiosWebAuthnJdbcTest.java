package com.clickclak.backend.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Clock;
import java.time.Duration;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import com.yubico.webauthn.AssertionRequest;
import com.yubico.webauthn.data.ByteArray;
import com.yubico.webauthn.data.PublicKeyCredentialCreationOptions;
import com.yubico.webauthn.data.PublicKeyCredentialParameters;
import com.yubico.webauthn.data.PublicKeyCredentialRequestOptions;
import com.yubico.webauthn.data.RelyingPartyIdentity;
import com.yubico.webauthn.data.UserIdentity;

/** Desafíos WebAuthn reales (objetos de la librería Yubico) guardados y recuperados desde PostgreSQL. */
@SpringBootTest
class AlmacenDesafiosWebAuthnJdbcTest {

    @Autowired private JdbcTemplate jdbc;

    private AlmacenDesafiosWebAuthnJdbc almacen;

    @BeforeEach
    void configurar() {
        jdbc.update("DELETE FROM desafio_webauthn");
        almacen = new AlmacenDesafiosWebAuthnJdbc(jdbc);
    }

    private static PublicKeyCredentialCreationOptions opcionesDeRegistro() {
        return PublicKeyCredentialCreationOptions.builder()
                .rp(RelyingPartyIdentity.builder().id("localhost").name("ClickClak").build())
                .user(UserIdentity.builder().name("ana@example.com").displayName("Ana")
                        .id(new ByteArray(new byte[] {1, 2, 3, 4})).build())
                .challenge(new ByteArray(new byte[] {9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 1, 2, 3, 4, 5, 6}))
                .pubKeyCredParams(List.of(PublicKeyCredentialParameters.ES256))
                .build();
    }

    private static AssertionRequest peticionDeAutenticacion() {
        return AssertionRequest.builder()
                .publicKeyCredentialRequestOptions(PublicKeyCredentialRequestOptions.builder()
                        .challenge(new ByteArray(new byte[] {1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, (byte) 144, (byte) 233, 1, 2, 3}))
                        .rpId("localhost")
                        .build())
                .username("ana@example.com")
                .build();
    }

    @Test
    void guardarYRecuperarRegistro_devuelveLasMismasOpciones() {
        var opciones = opcionesDeRegistro();
        String id = almacen.guardar(opciones);

        assertThat(almacen.recuperar(id, PublicKeyCredentialCreationOptions.class)).contains(opciones);
    }

    @Test
    void guardarYRecuperarAutenticacion_devuelveLaMismaPeticion() {
        var peticion = peticionDeAutenticacion();
        String id = almacen.guardar(peticion);

        assertThat(almacen.recuperar(id, AssertionRequest.class)).contains(peticion);
    }

    @Test
    void recuperar_esDeUnSoloUso() {
        String id = almacen.guardar(opcionesDeRegistro());

        almacen.recuperar(id, PublicKeyCredentialCreationOptions.class);

        assertThat(almacen.recuperar(id, PublicKeyCredentialCreationOptions.class)).isEmpty();
    }

    @Test
    void recuperar_conIdDesconocidoOMalFormado_devuelveVacio() {
        assertThat(almacen.recuperar("id-que-no-existe", AssertionRequest.class)).isEmpty();
        assertThat(almacen.recuperar("00000000-0000-0000-0000-000000000000", AssertionRequest.class)).isEmpty();
    }

    @Test
    void recuperar_conTipoIncorrecto_devuelveVacio() {
        String id = almacen.guardar(opcionesDeRegistro());

        assertThat(almacen.recuperar(id, AssertionRequest.class)).isEmpty();
    }

    @Test
    void recuperar_despuesDeExpirar_devuelveVacio() throws InterruptedException {
        var efimero = new AlmacenDesafiosWebAuthnJdbc(jdbc, Clock.systemUTC(), Duration.ofMillis(1));
        String id = efimero.guardar(opcionesDeRegistro());

        Thread.sleep(30);

        assertThat(efimero.recuperar(id, PublicKeyCredentialCreationOptions.class)).isEmpty();
    }

    @Test
    void elDesafioIniciadoEnUnaInstanciaSeFinalizaEnOtra() {
        var otraInstancia = new AlmacenDesafiosWebAuthnJdbc(jdbc);
        var peticion = peticionDeAutenticacion();

        String id = almacen.guardar(peticion);

        assertThat(otraInstancia.recuperar(id, AssertionRequest.class)).contains(peticion);
        assertThat(almacen.recuperar(id, AssertionRequest.class)).isEmpty();
    }

    @Test
    void guardar_conUnTipoNoSoportado_fallaConClaridad() {
        assertThatThrownBy(() -> almacen.guardar("un-string"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("no soportado");
    }
}
