package com.clickclak.backend.controller;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.httpBasic;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.actuate.observability.AutoConfigureObservability;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

/**
 * Las métricas de Prometheus solo las lee el usuario {@code prometheus} con su clave; el resto del
 * mundo (sin credenciales, con otra clave o con otro usuario) recibe 401.
 */
@SpringBootTest
@AutoConfigureMockMvc
// En pruebas Spring Boot desactiva los exportadores de métricas; este habilita /actuator/prometheus.
@AutoConfigureObservability
@TestPropertySource(properties = "clickclak.seguridad.metricas.clave=clave-de-metricas-de-prueba")
class MetricasPrometheusTest {

    @Autowired private MockMvc mockMvc;

    @Test
    void conLasCredencialesDeMetricas_devuelveLasMetricas() throws Exception {
        mockMvc.perform(get("/actuator/prometheus").with(httpBasic("prometheus", "clave-de-metricas-de-prueba")))
                .andExpect(status().isOk())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("jvm_memory_used_bytes")));
    }

    @Test
    void sinCredenciales_responde401() throws Exception {
        mockMvc.perform(get("/actuator/prometheus")).andExpect(status().isUnauthorized());
    }

    @Test
    void conClaveIncorrecta_responde401() throws Exception {
        mockMvc.perform(get("/actuator/prometheus").with(httpBasic("prometheus", "otra-clave")))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void otroUsuarioNoPuedeLeerLasMetricas() throws Exception {
        mockMvc.perform(get("/actuator/prometheus").with(httpBasic("admin", "clave-de-metricas-de-prueba")))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void lasCredencialesDeMetricasNoSirvenParaLaApi() throws Exception {
        mockMvc.perform(get("/api/proyectos").with(httpBasic("prometheus", "clave-de-metricas-de-prueba")))
                .andExpect(status().isUnauthorized());
    }
}
