# ClickClak Cloud — Plan de trabajo por fases hasta el cierre

Fecha del plan: 2026-11-22 · Curso: Servicios Cloud (100000S91T), sección 43639 · Equipo: Cieza, Cuadros, Tapia, Villanueva.
Estado: **propuesta para aprobar**. Las duraciones son **estimaciones mías** en días-persona, no compromisos; se convierten en calendario cuando se confirme la fecha de la Semana 18 (**aún no la tengo**).

## 0. Estado y calendario comprimido (actualizado el 2026-11-23)

**Estamos en la Semana 17; la sustentación es en la Semana 18** (día exacto por confirmar). El plan de ~28 días-persona se comprime a lo esencial; el orden de recortes de la sección 7 aplica desde ya.

> **Lo que queda desde F5 está en `PLAN_DE_CIERRE.md`** (bloques A a G, calendario día a día, dependencias y decisiones pendientes). Esta tabla se mantiene como historial de lo hecho.

| Fase | Estado | Qué quedó hecho (evidencia en `docs/` y en el repo) |
|---|---|---|
| F0 | Parcial | Carpeta y documentación; **falta** iniciar git y crear el repo público |
| F1 | **Hecha en lo esencial** | Dockerfiles optimizados (caché Maven, `HEALTHCHECK`, frontends sin privilegios), redes `web`/`datos`, límites de memoria, **balanceador Estándar** con sondeo `/salud`, nodos sin IP pública (SSH por NAT, salida por regla de salida), mismo certificado en ambos nodos, IaC en `infra/azure/*.sh` |
| F2 | **Hecha (código y pruebas)** | Backend sin estado: 4 almacenes a PostgreSQL (migración V5), 324 pruebas en verde, desplegado y reparto verificado con `X-Nodo`. **Pruebas de carga k6 hechas** (P1–P5): p95 7–14 ms hasta 50 usuarios, 0 % de errores hasta 200 usuarios (~400 req/s); con 2 instancias el p95 bajo estrés baja un 73 %; ver `docs/PRUEBAS_DE_CARGA.md`. **Falta** autoescalado (hoy manual) |
| F3 | **Hecha** | Testigo `10.0.0.6` con Prometheus, Alertmanager, Grafana (21 paneles), sondas externas y 17 alertas; exportadores en los nodos; 13 objetivos `up` |
| F4 | **Hecha** (2026-11-23) | Failover guionizado con fencing, 3 ensayos reales de caída de la primaria (**RPO 0, RTO 30–36 s**), `pg_rewind` validado (12 s), guion de caída de un backend (97,4 % de éxito, el balanceador reacciona en ~11 s); ver `docs/DRP_Y_FAILOVER.md`. **Respaldos horarios a Azure Blob** con identidad administrada, restauración verificada (9,4 s, conteos iguales, rechazo de respaldos manipulados) y prueba de borrado accidental |
| F5 | **Hecha en lo esencial** (2026-11-23) | TLS 1.3 `verify-full` interno y exigido, Trivy (backend 51→7, frontends y proxy 0), Spring Boot 3.5.14, SSH restringido, prueba de humo de 66–69 comprobaciones; ver `docs/ENDURECIMIENTO_F5.md`. **Falta**: segundo factor, rol de BD sin DDL, escaneo en CI, prueba ofensiva |
| F6 | Parcial | Documentos de análisis, decisión, costos, seguridad; **falta** el informe PDF por fases y los diagramas |
| F7–F8 | Pendiente | Guiones de falla, ensayos, plan B, cierre |

**Calendario propuesto** (ajustar a la fecha real de la sustentación):

| Día | Trabajo |
|---|---|
| Lun 23 (hoy) | F1, F2 (código) y F3 hechas |
| Mar 24 | **F4**: failover, aislamiento, reincorporación y respaldos; pruebas de carga k6 |
| Mié 25 | **F5 mínima**: TLS interno, roles de BD, Trivy; diagramas físico y lógico |
| Jue 26 – Vie 27 | **F6**: informe PDF por fases, repositorio público, evidencias |
| Sáb 28 – Dom 29 | **F7**: guiones de falla cronometrados y dos ensayos completos; plan B |
| Semana 18 | Sustentación; **F8**: cierre y apagado de recursos |

## 1. Qué se entrega y cómo se evalúa

| Entregable | Evaluación |
|---|---|
| Informe técnico PDF por 3 fases (U1, U2, U3), con evidencias, código clave y diagramas | Criterios 1 a 4 (4 pts c/u) |
| Repositorio público con Dockerfiles, orquestación, manifiestos e IaC | Criterios 2 y 3 |
| Sustentación en vivo (Semana 18): sistema corriendo, tolerancia a fallos y monitoreo en tiempo real | Criterio 5 (4 pts) |

**Meta:** 4/4 en cada criterio (20 pts). Una fase solo se da por cerrada si deja evidencia verificable para el informe o la demostración.

## 2. Estado de partida (hoy)

| Hecho | Detalle |
|---|---|
| Carpeta y base de código | `ClickClak_Cloude` con código de `main` (`ebcc625`) |
| Análisis y decisiones | Brechas vs rúbrica, costos reales, topología (3 servidores), ISO 27001 y OWASP, plan de seguridad |
| Validación en Azure | Crédito USD 79; cuotas y creación validadas; sin políticas que bloqueen |
| Nodo 2 creado | `vm-clickclak-2` clonada de la VM 1 (snapshot) |
| Replicación nodo 1 → nodo 2 | Streaming asíncrono con retraso 0; backend del nodo 2 con JDBC multi-host |
| **Pendiente** | Todo lo demás: balanceador, TLS interno, estado compartido del backend, testigo y monitoreo, failover y respaldos, IaC, CI, pruebas de carga, informe, repo público, sustentación |

## 3. Visión general

```
F0 Arranque ──► F1 Nodos y red ──► F2 Backend sin estado ──► F4 Failover y DRP ──► F5 Endurecimiento
                     │                      │                       ▲
                     └────► F3 Testigo y monitoreo ───────────────────┘
F6 Informe y diagramas (continua, desde F1) ──────────────────────────► F7 Ensayo y sustentación ──► F8 Cierre
```

**Ruta crítica:** F1 → F2 → F4 → F7. F3 puede avanzar en paralelo tras F1. F6 se alimenta de cada fase, no se deja para el final.

| Fase | Contenido | Esfuerzo (días-persona, estimado) | Criterios que cubre |
|---|---|---|---|
| F0 | Arranque y gobierno | 1 | todos |
| F1 | Nodos idénticos, red, balanceador, IaC, contenedores | 4 | 2, 3 |
| F2 | Backend sin estado y pruebas de carga | 4 | 3, 4 |
| F3 | Testigo y monitoreo en vivo | 3 | 3, 5 |
| F4 | Failover, respaldos y DRP | 4 | 4, 5 |
| F5 | Endurecimiento y seguridad (ISO/OWASP) | 3 | 3, 4 |
| F6 | Informe, diagramas y repositorio | 6 | 1 a 4, entregables 1 y 2 |
| F7 | Ensayo y sustentación | 2 | 5 |
| F8 | Cierre | 1 | todos |
| | **Total** | **~28** | |

Con 4 integrantes parte del trabajo corre en paralelo; el calendario real depende de la fecha y de la disponibilidad de cada uno.

---

## F0 — Arranque y gobierno (≈1 día)

| # | Tarea | Resultado |
|---|---|---|
| 0.1 | Confirmar la **fecha de la Semana 18** y fijar el calendario real | Fechas en este plan |
| 0.2 | Iniciar el **repositorio git** de `ClickClak_Cloude` y crearlo **público** (GitHub/GitLab); primer commit con `.gitattributes` | URL del repo (entregable 2) |
| 0.3 | Proteger la rama `main`, exigir revisión por pares y activar CI | Reglas de PR |
| 0.4 | Tablero y Gantt de este curso (Jira o planilla), con las tareas de este plan | Seguimiento |
| 0.5 | Reparto de responsables y rutina de dailys breves | Roles (ver §5) |
| 0.6 | Alerta de presupuesto en Azure y etiquetas `curso=servicios-cloud` en todo recurso nuevo | Control de costos |
| 0.7 | Nota de reutilización: qué viene del Integrador II y qué es nuevo en este curso | Anexo del informe |

**Puerta:** repo público creado, calendario fijado, responsables asignados.

## F1 — Nodos idénticos, red, balanceador, IaC y contenedores (≈4 días)

Cierra la Etapa 1 de `DECISION_TOPOLOGIA.md`.

| # | Tarea | Resultado / evidencia |
|---|---|---|
| 1.1 | **Optimizar Dockerfiles**: capa de dependencias Maven, `USER` no root y `HEALTHCHECK` en frontends, imágenes mínimas | Dockerfiles y tamaños antes/después (criterio 2) |
| 1.2 | **Redes Docker** `publica` y `privada` (`internal: true`) y **límites de recursos** por servicio | Compose de producción versionado |
| 1.3 | **Imágenes en registro** (GHCR) con etiquetas versionadas; CI que construye y publica | Pipeline y registro |
| 1.4 | **IaC con Bicep**: VNet, subredes, NSG, IPs, VM, balanceador; el nodo 2 y el balanceador reproducibles | `infra/bicep/`; despliegue repetible |
| 1.5 | **Red Azure**: NSG por nodo, SSH solo desde la IP del equipo, 5432 solo entre nodos | Reglas NSG (ISO 8.20–8.22) |
| 1.6 | **Balanceador Estándar** con sondeo de salud (`/actuator/health` vía Nginx) y reparto entre los nodos | Caída de un nodo sin corte del servicio |
| 1.7 | **Dominio y certificado común** detrás del balanceador (copia/sincronización del certificado, renovación en un nodo) | HTTPS sin advertencia en la URL pública |
| 1.8 | **TLS interno** aplicación → BD y primaria → réplica; `wal_log_hints = on`, `data_checksums` | Conexiones `hostssl`; OWASP A02 |
| 1.9 | Retirar la réplica local del nodo 1 (libera una ranura de replicación) | Compose de nodo 1 limpio |
| 1.10 | Sincronización de reloj (`chrony`) y etiquetas en los 3 nodos | `chronyc tracking` |
| 1.11 | Decidir si se recrean los nodos **en zonas de disponibilidad** distintas | Decisión documentada |

**Puerta:** el servicio responde por una URL pública única; se apaga un nodo y sigue respondiendo; todo creado desde IaC.
**Corte posible:** 1.11 (zonas) y la copia de seguridad de secretos a Key Vault.

## F2 — Backend sin estado y pruebas de carga (≈4 días)

Es el trabajo de código más delicado: sin él, dos instancias del backend no son coherentes.

| # | Tarea | Resultado / evidencia |
|---|---|---|
| 2.1 | Mover a **PostgreSQL** los tokens revocados, intentos fallidos, tokens de recuperación y desafíos WebAuthn (migración Flyway + expiración) | Migración, código y pruebas |
| 2.2 | Pruebas automáticas: **login y revocación consistentes entre 2 instancias** | Prueba de integración |
| 2.3 | Misma `JWT_SECRET` y configuración en ambos nodos; verificación de sesión cruzada | Evidencia de sesión entre nodos |
| 2.4 | **Matriz de roles por endpoint** (pendiente del APF2, OWASP A01) | Pruebas automáticas |
| 2.5 | **Pruebas de carga con k6** P1 a P4 con **1 y 2 instancias** (nominal, pico, ráfaga con idempotencia, estrés) | Resultados, p95, punto de quiebre |
| 2.6 | **Política de escalabilidad** (horizontal/vertical, disparadores) con una prueba de elasticidad real | Gráficos y documento (criterio 3) |

**Puerta:** 178 pruebas del backend en verde más las nuevas; P1 a P4 ejecutadas y registradas; dos instancias activas sin inconsistencias.

## F3 — Testigo y monitoreo en vivo (≈3 días, en paralelo tras F1)

| # | Tarea | Resultado / evidencia |
|---|---|---|
| 3.1 | Crear el **tercer servidor** (testigo) por IaC, sin IP pública, tamaño decidido por costo | `vm-clickclak-3` |
| 3.2 | Añadir `micrometer-registry-prometheus` al backend y exponer métricas solo en la red interna | Endpoint interno |
| 3.3 | **Prometheus, Alertmanager, Grafana** en el testigo; en los nodos `node-exporter`, `cAdvisor`, `postgres_exporter` | Scrape de los 2 nodos |
| 3.4 | **Sonda externa** (`blackbox_exporter`) que prueba la URL pública | Disponibilidad medida desde fuera |
| 3.5 | **Tablero** con CPU, memoria, disco, p95, 5xx, conexiones y retraso de réplica; logs accesibles | Capturas del tablero |
| 3.6 | **Alertas**: nodo caído, retraso o corte de réplica, 401/429 repetidos, cuentas bloqueadas, disco | Alertas disparadas en pruebas (OWASP A09) |
| 3.7 | Acceso a Grafana solo por túnel SSH o IP autorizada | NSG y evidencia |

**Puerta:** el tablero muestra la caída y recuperación de un nodo en tiempo real y dispara su alerta.
**Corte posible:** Loki y la sonda de metamonitoreo.

## F4 — Failover, respaldos y DRP (≈4 días)

| # | Tarea | Resultado / evidencia |
|---|---|---|
| 4.1 | **Promoción guionizada** de la standby: comprobaciones previas, `pg_promote`, cambio de rol del nodo | Script y salida |
| 4.2 | **Fencing** del nodo viejo (impedir que arranque como primaria) | Procedimiento y prueba |
| 4.3 | **Reincorporación** del nodo viejo como standby con `pg_rewind`, o copia completa si falla | Prueba y tiempos |
| 4.4 | Prueba extremo a extremo: caída de la primaria con la aplicación activa → el backend sigue vía JDBC multi-host | **RTO medido** |
| 4.5 | Medir el **RPO** (replicación asíncrona) y decidir si se documenta o se pasa a síncrona | Cifra y justificación |
| 4.6 | **Respaldos a Azure Blob** (identidad administrada, contenedor privado, cifrado) y retención | Respaldos programados |
| 4.7 | **Restauración probada** desde Blob y `pg_verifybackup` | Tiempo de restauración |
| 4.8 | **DRP** documentado: escenarios, RTO/RPO, responsables y pasos | Capítulo del informe |
| 4.9 | **Mapeo de patrones cloud** al código (Health Endpoint Monitoring, Throttling, Gateway Routing, Idempotent Consumer, Queue-Based Load Leveling, Retry; Circuit Breaker si hay tiempo) | Tabla patrón → archivo |

**Puerta:** tres guiones de falla ejecutados con éxito y cronometrados (caída de un backend, caída de la primaria, restauración desde respaldo).
**Corte posible:** Circuit Breaker.

## F5 — Endurecimiento y seguridad ISO 27001 / OWASP (≈3 días)

Detalle en `SEGURIDAD_ISO27001_OWASP.md`.

| # | Tarea | Resultado / evidencia |
|---|---|---|
| 5.1 | Escaneo **Trivy** de imágenes y análisis de dependencias en el CI; imágenes fijadas por versión y digest | Informe sin críticos (A06, A08) |
| 5.2 | Roles de BD con mínimo privilegio (ejecución sin DDL, migración aparte) y `pg_hba` por CIDR | Scripts (A01, ISO 8.2) |
| 5.3 | Gestión de secretos: rotación documentada; evaluar Key Vault por costo | Procedimiento (R1) |
| 5.4 | **Segundo factor** para supervisores y RR. HH. (pendiente del APF2, A07) | Implementación o riesgo aceptado |
| 5.5 | **Modelo de amenazas** y matriz de riesgos del sistema de 3 servidores | Documento (A04) |
| 5.6 | Políticas breves: seguridad, incidentes, retención | `docs/seguridad/` |
| 5.7 | **Prueba ofensiva básica** (autenticación, autorización, cabeceras, límites) | Informe de hallazgos |
| 5.8 | **Auditoría interna simulada** del SoA: cada control *Implementado / Parcial / No implementado* | SoA final honesto |

**Puerta:** SoA revisado contra evidencias reales. **Corte posible:** 5.4 (se declara como riesgo aceptado) y Key Vault.

## F6 — Informe, diagramas y repositorio (≈6 días, continua desde F1)

El APF2 no se entrega tal cual: se **reestructura por fases** y se reescribe con enfoque cloud para no duplicar el informe de otro curso.

| # | Tarea | Contenido |
|---|---|---|
| 6.1 | **Fase 1 (Unidad 1)** | Sistema base; requerimientos cloud con **tráfico de red**; **justificación IaaS vs PaaS vs híbrido** (comparar con PostgreSQL administrado: validar su disponibilidad y precio en Chile Central); tipo de almacenamiento y decisión sobre Blob |
| 6.2 | **Fase 2 (Unidad 2)** | Dockerfiles optimizados, orquestación, topología de red y NSG, monitoreo con evidencias, escalabilidad con pruebas de elasticidad |
| 6.3 | **Fase 3 (Unidad 3)** | Patrones, balanceador, replicación, redundancia, failover, DRP con RTO/RPO medidos |
| 6.4 | **Diagramas profesionales** físico y lógico (estándar C4 o iconos de Azure) y de red | Figuras |
| 6.5 | **Seguridad** | ISO 27001 y OWASP como capítulo transversal |
| 6.6 | **Costos reales y lecciones** | Tabla de costos medidos y decisiones |
| 6.7 | **Evidencias** ordenadas por criterio | Capturas, salidas de pruebas, tableros |
| 6.8 | **Repositorio**: README de reproducción, instrucciones de despliegue desde cero, licencia, sin secretos | Entregable 2 |
| 6.9 | Revisión cruzada del informe contra la **rúbrica**, criterio por criterio | Lista de verificación |

**Puerta:** informe en PDF completo y repositorio que un tercero pueda desplegar siguiendo el README.

## F7 — Ensayo y sustentación (≈2 días)

| # | Tarea | Resultado |
|---|---|---|
| 7.1 | **Guion de la sustentación** con tiempos y reparto de temas por integrante | Guion |
| 7.2 | **Tres guiones de falla** con comandos y resultado esperado | Hoja de ejecución |
| 7.3 | **Ensayo completo cronometrado** (mínimo dos, el último con preguntas cruzadas) | Registro de ensayos |
| 7.4 | **Plan B** si falla la nube: el mismo stack con `docker compose` local y video/capturas de respaldo | Paquete de respaldo |
| 7.5 | **Lista de verificación previa**: VM encendidas en orden (primero la base), saldo de crédito, certificados, ventana de acceso | Checklist |
| 7.6 | Presentación y preguntas frecuentes (por qué IaaS, por qué 3 nodos, split-brain, RTO/RPO, costos, seguridad) | Diapositivas y banco de preguntas |

**Puerta:** un ensayo completo sin intervención manual fuera de guion.

## F8 — Cierre (≈1 día)

| # | Tarea |
|---|---|
| 8.1 | Congelar el código, etiquetar la versión final y verificar el repositorio público |
| 8.2 | Entregar el informe PDF en la fecha indicada |
| 8.3 | Tras la nota: apagar y eliminar recursos, o dejarlos desasignados; quitar el balanceador; verificar la factura |
| 8.4 | Retrospectiva y lecciones aprendidas |

---

## 4. Presupuesto estimado (referencia, precios de lista)

Costos horarios con ambos nodos: USD 0,1052/h; con balanceador +0,030/h; con testigo B2als_v2 +0,0526/h. **Fijo apagado** (3 discos + 2 IP Standard): ~USD 27,5/mes.

| Fase | Horas de máquina (estim.) | Costo aprox. (USD) |
|---|---|---|
| F1 | 24 h, 2 nodos | 2,5 |
| F2 | 30 h, 2 nodos + balanceador | 4,1 |
| F3 | 30 h, 3 servidores + balanceador | 5,6 |
| F4 | 24 h, 3 servidores + balanceador | 4,5 |
| F5 (opcional el segundo factor) | 16 h, 3 servidores + balanceador | 3,0 |
| F7 | 2 ensayos de 4 h + sustentación y margen de 8 h | 3,0 |
| **Consumo variable** | | **~22,7** |

**Fijo según el calendario:** ~27,5 por mes apagado. Con el crédito de USD 79 el tope razonable es de unas **2 meses** de proyecto; más allá habría que liberar IP y discos mientras no se usen. **Verificar el saldo real antes de cada fase** (no incluye lo ya gastado desde hoy). El balanceador se elimina al apagar.

## 5. Responsables (sugerencia, a ajustar por el equipo)

| Área | Sugerido |
|---|---|
| Infraestructura, red, IaC, failover (F1, F3, F4) | Desarrollador 1 (Cuadros) con apoyo del Scrum Master |
| Backend sin estado, pruebas de carga y de roles (F2, F5.4) | Desarrollador 2 (Tapia) |
| Seguridad, informe y diagramas (F5, F6) | Product Owner (Cieza) con revisión del equipo |
| Gestión, tablero, ensayos y sustentación (F0, F7, F8) | Scrum Master (Villanueva) |

La sustentación evalúa dominio técnico individual: **todos deben poder explicar todas las capas**; el reparto es solo de ejecución.

## 6. Riesgos del plan

| Riesgo | Efecto | Mitigación |
|---|---|---|
| Fecha de la Semana 18 desconocida | No se puede calendarizar ni decidir los recortes | Confirmarla en F0 |
| Cambio de código en F2 (estado del backend) más complejo de lo previsto | Retrasa F4 y las pruebas de carga | Empezarlo primero; alternativa: sesiones pegajosas en el balanceador como parche declarado |
| Crédito insuficiente | Recursos apagados el día de la sustentación | Presupuesto por fase, apagar y eliminar el balanceador, saldo verificado en F7 |
| Failover manual no ensayado | Falla en vivo | Tres ensayos mínimos con cronómetro (F4 y F7) |
| Portal o región con problemas el día de la demo | Demostración caída | Plan B local y video (7.4) |
| Informe copiado del APF2 | Problema académico | Reescritura por fases y nota de reutilización (0.7, F6) |
| Trabajo concentrado en una persona | Cuello de botella y sustentación débil | Rotar tareas y revisar todo en pareja |

## 7. Qué se recorta primero si falta tiempo (orden)

1. **Failover automático** (Patroni o pg_auto_failover): ya fuera del plan principal; se deja como mejora futura.
2. Circuit Breaker, Loki y la metamonitorización.
3. Zonas de disponibilidad y Key Vault.
4. Segundo factor para administradores (queda como riesgo aceptado).
5. Adjuntos de incidencias en Blob (HU19).

**No se recorta:** balanceador, replicación y promoción probada, monitoreo en vivo, respaldos con restauración medida, pruebas de carga, diagramas, informe, repositorio público y ensayo.

## 8. Criterio de "terminado" del proyecto

- [ ] Servicio accesible por una URL pública única con HTTPS válido
- [ ] Dos nodos activos tras el balanceador y un testigo con monitoreo
- [ ] Tres guiones de falla ejecutados y cronometrados, con RTO y RPO medidos
- [ ] Pruebas P1 a P4 con resultados
- [ ] Tablero en vivo y alertas funcionando
- [ ] IaC y repositorio público reproducibles, sin secretos
- [ ] Informe PDF por fases con diagramas físico y lógico y todas las evidencias
- [ ] SoA ISO 27001 y mapeo OWASP revisados contra evidencias
- [ ] Ensayo completo sin incidencias y plan B listo
- [ ] Recursos apagados o eliminados tras la entrega
