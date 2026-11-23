package com.clickclak.backend.config;

import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.CsrfConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import com.clickclak.backend.security.JwtAuthenticationFilter;
import com.clickclak.backend.security.ManejadorErroresAutenticacion;

/**
 * API REST sin estado: sin CSRF (no hay cookies de sesión que proteger), sin sesión de
 * servidor, autenticación exclusivamente por JWT. Los colaboradores no pasan por aquí con
 * usuario/contraseña — su flujo es WebAuthn (pendiente, ver dispositivo).
 */
@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtAuthenticationFilter;
    private final ManejadorErroresAutenticacion manejadorErrores;
    private final List<String> origenesPermitidos;

    public SecurityConfig(
            JwtAuthenticationFilter jwtAuthenticationFilter,
            ManejadorErroresAutenticacion manejadorErrores,
            @Value("${clickclak.seguridad.cors.origenes:}") List<String> origenesPermitidos) {
        this.jwtAuthenticationFilter = jwtAuthenticationFilter;
        this.manejadorErrores = manejadorErrores;
        this.origenesPermitidos = origenesPermitidos;
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    /**
     * Orígenes que pueden llamar a la API desde otro origen, tomados de
     * {@code clickclak.seguridad.cors.origenes} (lista separada por comas). En desarrollo son los
     * servidores de Vite; en producción la lista va vacía porque el proxy sirve los frontends y la
     * API bajo el mismo origen, así que ningún origen externo queda autorizado.
     */
    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration configuracion = new CorsConfiguration();
        configuracion.setAllowedOrigins(origenesPermitidos);
        configuracion.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        configuracion.setAllowedHeaders(List.of("Authorization", "Content-Type"));

        UrlBasedCorsConfigurationSource fuente = new UrlBasedCorsConfigurationSource();
        fuente.registerCorsConfiguration("/api/**", configuracion);
        return fuente;
    }

    /**
     * Métricas para Prometheus. Es una cadena aparte y de mayor prioridad que la de la API: no usa
     * JWT sino HTTP Basic con un único usuario, {@code prometheus}, que solo puede leer
     * {@code /actuator/prometheus}. La clave llega por {@code METRICAS_CLAVE}; sin ella no existe
     * ningún usuario y el endpoint responde 401 a todo el mundo. El proxy ya no enruta /actuator,
     * así que solo llega aquí tráfico de la red interna.
     */
    @Bean
    @Order(1)
    public SecurityFilterChain cadenaMetricas(
            HttpSecurity http, @Value("${clickclak.seguridad.metricas.clave:}") String clave) throws Exception {
        InMemoryUserDetailsManager usuarios = new InMemoryUserDetailsManager();
        if (!clave.isBlank()) {
            usuarios.createUser(User.withUsername("prometheus")
                    .password(passwordEncoder().encode(clave))
                    .roles("METRICAS")
                    .build());
        }
        http
                .securityMatcher("/actuator/prometheus")
                .csrf(CsrfConfigurer::disable)
                .sessionManagement(sesion -> sesion.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .userDetailsService(usuarios)
                .authorizeHttpRequests(auth -> auth.anyRequest().hasRole("METRICAS"))
                .httpBasic(Customizer.withDefaults());
        return http.build();
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
                .csrf(CsrfConfigurer::disable)
                .cors(cors -> cors.configurationSource(corsConfigurationSource()))
                .sessionManagement(sesion -> sesion.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        // Ojo: solo /login es público. "/api/auth/**" también cubriría "/api/auth/yo"
                        // y lo dejaría sin exigir autenticación — se detectó con un test real.
                        .requestMatchers("/api/auth/login").permitAll()
                        // HU03: quien pide o completa una recuperación de clave, por definición,
                        // todavía no puede autenticarse.
                        .requestMatchers("/api/auth/recuperacion/**").permitAll()
                        // La autenticación WebAuthn ES el mecanismo de login: no puede exigir un
                        // JWT previo. El enrolamiento ("/api/webauthn/registro/**") sí lo exige
                        // (además del rol vía @PreAuthorize) y por eso NO está aquí.
                        .requestMatchers("/api/webauthn/autenticacion/**").permitAll()
                        .requestMatchers("/actuator/health", "/actuator/info").permitAll()
                        .anyRequest().authenticated())
                .exceptionHandling(manejo -> manejo
                        .authenticationEntryPoint(manejadorErrores)
                        .accessDeniedHandler(manejadorErrores))
                .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }
}
