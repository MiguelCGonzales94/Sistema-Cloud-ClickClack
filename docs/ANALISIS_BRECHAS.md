# ClickClak Cloud — Análisis de brechas contra la Guía y Rúbrica

Curso: Servicios Cloud (100000S91T), sección 43639 · Proyecto final, 40 % de la nota · Sustentación: **Semana 18**
Fecha del análisis: 2026-11-22 · Base analizada: `ClickClak/main` (commit `ebcc625`, etiqueta `v1-apf2` + cambios posteriores)

> Fuentes: `docs/referencia/Guia y Rubrica…pdf`, `ClickClak - Informe APF2.docx` (curso Integrador II), `Gannt, dailys, sprint review.xlsx` y el código/infraestructura del repositorio. Las puntuaciones de la sección 2 son una **estimación propia** con la rúbrica, no una nota oficial.

---

## 1. Qué pide el curso (resumen)

| Entregable | Detalle |
|---|---|
| 1. Informe técnico PDF | Estructurado en **3 fases** (Unidad 1, 2 y 3), con evidencias de configuración, código clave y diagramas |
| 2. Repositorio público (GitHub/GitLab) | Dockerfiles, scripts de orquestación, manifiestos, configuración — **IaC** |
| 3. Sustentación en vivo (Sem. 18) | Sistema corriendo en cloud/simulado, mostrando **tolerancia a fallos** y **monitoreo en tiempo real** |

Rúbrica: 5 criterios × 4 pts = 20 pts (Excelente 4 · Bueno 3 · En proceso 1-2 · Insuficiente 0).

## 2. Estado por criterio

| # | Criterio | Qué tenemos | Qué falta | Estimación hoy | Meta |
|---|---|---|---|---|---|
| 1 | Análisis y arquitectura base (U1) | Descripción del sistema, BD, arquitectura en capas, línea base medida y demanda proyectada (APF2 cap. V, 7.2, 10.1) | Reescribir con enfoque cloud: **justificar IaaS vs PaaS vs híbrido** y el tipo de almacenamiento; estimar **tráfico de red**; decidir almacenamiento de objetos (adjuntos HU19 sin hacer) | 3 | 4 |
| 2 | Contenedorización y orquestación (U2) | 3 Dockerfiles multi-etapa, compose de dev y prod, healthchecks, `depends_on`, solo el proxy publica puertos, 52/52 comprobaciones de humo | Optimizar Dockerfiles; **redes Docker explícitas**; límites de recursos; imágenes en registro; (opcional) manifiestos K8s | 3 | 4 |
| 3 | Infraestructura, monitoreo y escalabilidad (U2) | VM Azure, NSG implícito (22/80/443/8443), alerta de presupuesto, `actuator/health` | **Monitoreo no implementado**; **topología de red cloud sin diseñar**; **cero pruebas de elasticidad/carga** | 1-2 | 4 |
| 4 | Resiliencia y patrones (U3) | Réplica PostgreSQL por streaming (misma VM), rate limiting, cola offline + idempotencia, promoción manual probada en entorno local | **Sin balanceador, sin segunda instancia**, sin backups ni DRP, estado en memoria que impide escalar, patrones no mapeados | 1-2 | 4 |
| 5 | Sustentación y demostración (S17-18) | Sistema desplegado con HTTPS válido; guion de sustentación del otro curso como modelo | Escenarios de falla ensayables, tablero en vivo, VM encendida (se apaga a las 23:00), guion y ensayo | pendiente | 4 |

**Lectura global:** el sistema funciona y está bien desplegado, pero el APF2 se evaluó como proyecto de ingeniería, no como arquitectura cloud. Los criterios 3 y 4 son donde está el mayor riesgo, porque la rúbrica castiga explícitamente lo "puramente teórico sin evidencias prácticas" y pide demostrar tolerancia a fallos en vivo.

---

## 3. Detalle de brechas

### Criterio 1 — Análisis y arquitectura base

- [ ] **Justificación del modelo de despliegue.** Hoy es IaaS (VM + Docker Compose) por restricción de crédito, pero no hay comparación formal con PaaS (App Service, Azure Database for PostgreSQL Flexible Server, Container Apps) ni con híbrido.
- [ ] **Requerimientos cloud en una sola tabla:** cómputo, RAM, disco y **tráfico/egreso de red** (el APF2 mide req/s y MB/año, pero no ancho de banda).
- [ ] **Almacenamiento:** justificar PostgreSQL/PostGIS (SQL) y decidir si los adjuntos de incidencias (HU19, pendiente) usan Azure Blob Storage. Es la oportunidad natural de cubrir "Cloud Storage" de la guía.
- [ ] Reaprovechable casi tal cual: caps. V (BD/UML), 7.2.1 (recursos Azure y costos), 10.1.1–10.1.3 (línea base, demanda, cuellos de botella).

### Criterio 2 — Contenedorización y orquestación

Hallazgos verificados en el código:

- [ ] `backend/Dockerfile` copia `src/` antes de resolver dependencias → **cada cambio de código re-descarga Maven**. Separar `dependency:go-offline` en su propia capa.
- [ ] Los frontends usan `nginx:1.27-alpine` **sin `USER`** (el proceso maestro corre como root); el backend sí usa usuario no root.
- [ ] Sin `HEALTHCHECK` en los Dockerfiles de frontends.
- [ ] `docker-compose.prod.yml` **no declara `networks:`** (una sola red por defecto) y **no define límites** `mem_limit`/`cpus` por servicio; solo acota el heap de Java.
- [ ] Las imágenes se construyen en la VM; falta publicarlas en un registro (GHCR o Azure Container Registry) con etiquetas versionadas.
- [ ] Decidir si se incluye Kubernetes. La guía permite Compose **o** K8s: Compose bien hecho alcanza el 4; K8s (k3s/minikube) solo suma si da tiempo.

### Criterio 3 — Infraestructura, monitoreo y escalabilidad

- [ ] **Monitoreo inexistente.** `infra/monitoring/prometheus/` y `infra/monitoring/grafana/dashboards/` están **vacíos**, aunque el README del repo anuncia "Prometheus + Grafana". El `pom.xml` solo trae `spring-boot-starter-actuator`; **falta `micrometer-registry-prometheus`**. Hay que implementar: Prometheus + Grafana + cAdvisor + node-exporter + postgres-exporter, con tablero de CPU, memoria, disco, latencia p95, errores 5xx, retraso de réplica y logs (Loki o `docker logs`).
- [ ] **Topología de red cloud.** El APF2 solo lista puertos abiertos. Falta diseñar y documentar **VNet, subred pública y subred privada, NSG con reglas por subred**, SSH restringido por IP y acceso a la base solo desde la subred privada. Con una sola VM no existen subredes reales (ver decisión A/B en la sección 5).
- [ ] **Pruebas de carga y elasticidad.** Los escenarios P1–P4 (k6/JMeter) están definidos pero **todos figuran "Por medir"**. Sin ellos el criterio 3 cae a "En proceso".
- [ ] **Política de escalabilidad con evidencia:** reglas de horizontal (réplicas del backend) y vertical (resize de VM), disparadores por CPU/memoria/p95, y una prueba donde se vea escalar y volver.
- [ ] **Bloqueo para escalar horizontalmente:** el APF2 (10.1.3) declara que tokens revocados, intentos fallidos y desafíos WebAuthn viven en memoria del backend. Con 2 instancias, un login puede fallar según a cuál llegue. Hay que externalizarlo (tabla en PostgreSQL o Redis) **antes** de balancear.

### Criterio 4 — Resiliencia y patrones de diseño

- [ ] **Balanceador de carga:** hoy `proxy_pass http://backend:8080` apunta a un único contenedor. Pasar a `upstream` con ≥2 instancias (o Azure Load Balancer / Application Gateway) con health checks.
- [ ] **Alta disponibilidad real de la base:** la réplica corre en **la misma VM** (límite declarado en 6.2 y 7.2.5). Moverla a otra VM/subred, y automatizar o al menos guionizar la promoción con la app apuntando a la nueva primaria.
- [ ] **DRP:** no hay respaldos automatizados ni restauración probada. Hacer `pg_dump`/WAL archiving a Azure Blob, **restaurar y medir RTO/RPO de extremo a extremo** (el APF2 deja RTO "a medir").
- [ ] **Mapeo de patrones cloud** (documentarlo y señalar dónde está en el código). Candidatos que ya existen y solo hay que nombrar: *Health Endpoint Monitoring*, *Throttling/Rate Limiting* (Nginx `limit_req`), *Gateway Routing* (proxy), *Idempotent Consumer* + *Queue-Based Load Leveling* (cola offline con id de cliente), *Retry*. Candidatos a añadir con poco esfuerzo: *Circuit Breaker* (Resilience4j en llamadas críticas) y *Competing Consumers*/réplicas stateless tras el balanceador.
- [ ] **Diagramas de arquitectura física y lógica** con estándar profesional (iconos de Azure o C4). El APF2 tiene un diagrama del despliegue, pero no el par físico/lógico que pide la guía.

### Criterio 5 — Sustentación y demostración

- [ ] **Guion de fallos ensayable** (cada uno con su comando y resultado esperado): (1) matar una instancia del backend y ver que el servicio sigue; (2) caer la primaria y promover la réplica; (3) pico de carga con k6 y ver escalar/saturar en Grafana; (4) restaurar un respaldo.
- [ ] **VM encendida** antes de la sustentación: hoy un script la desasigna a las 23:00 y no hay encendido automático.
- [ ] **Crédito Azure:** el APF2 proyectaba ~67 USD hasta el 13-dic con una sola VM. Cada VM adicional hay que cotizarla contra el saldo real (**no verificado**).
- [ ] Plan B si falla la nube en vivo: mismo stack en `docker compose` local + capturas/video de respaldo.
- [ ] Presentación y reparto de preguntas por integrante (el criterio evalúa "dominio técnico absoluto").

### Entregables formales

- [ ] **Informe PDF** reestructurado en Fase 1 / 2 / 3 (el APF2 está organizado por capítulos de Integrador II, V a X, y no se puede entregar tal cual). Reutilizar tablas y figuras, **reescribir el texto** con enfoque cloud para no duplicar el informe de otro curso.
- [ ] **Repositorio nuevo y público** (GitHub/GitLab). El de ClickClak apunta a `MiguelCGonzales94/ClickClak` por SSH y no sé si es público; para este curso conviene un repo separado.
- [ ] **IaC real.** Hoy hay Compose y scripts `sh`, pero la VM/red se creó a mano en el portal. Añadir Bicep, Terraform o un script `az` que cree el grupo de recursos, VNet, subredes, NSG y VM(s) de forma reproducible.
- [ ] Marcar como **hecho en otro curso** lo que se reutiliza (código base, seguridad web, replicación) para no confundirlo con el aporte nuevo de este curso.

---

## 4. Lo que ya se puede reutilizar

| Activo | Dónde | Sirve para |
|---|---|---|
| Stack prod en Compose con healthchecks | `infra/docker-compose.prod.yml` | Criterio 2 (base) |
| Nginx con TLS, HSTS y rate limiting | `infra/nginx/plantillas/` | Criterio 3 y 4 (patrones, seguridad) |
| Réplica PostgreSQL por streaming y scripts de verificación | `infra/postgres/replicacion/`, `infra/scripts/verificar-replicacion.sh` | Criterio 4 (punto de partida) |
| Prueba de humo 52/52 | `infra/scripts/verificar-despliegue.sh` | Criterio 2 y 5 |
| CI con GitHub Actions por componente | `.github/workflows/` | Criterio 2 (pipeline) |
| Plan de capacidad, escenarios P1–P4, costos Azure | APF2 caps. 7.2 y 10 | Criterios 1 y 3 |
| Línea base de recursos medida | APF2 tabla 38 | Criterio 1 |

---

## 5. Decisión de arquitectura

> **Decidido el 2026-11-22: camino B (2 VM).** El diseño detallado está en [`ARQUITECTURA_OBJETIVO.md`](ARQUITECTURA_OBJETIVO.md). Se conservan abajo las dos opciones evaluadas.

La rúbrica pide subredes públicas/privadas y tolerancia a fallos reales, y con **una sola VM** ninguna de las dos es auténtica. Dos caminos:

**A — Una VM, todo en Compose.** Dos redes Docker (`publica` / `privada` con `internal: true`), 2 réplicas del backend tras Nginx, monitoreo completo, backups a Blob. Barato y simple; la "subred privada" sería lógica, no de Azure, y la réplica seguiría en la misma máquina.

**B — Dos VM (recomendada).** `vm-app` (la actual) en subred pública con proxy, backend ×2 y monitoreo; `vm-db` pequeña en subred privada **sin IP pública**, con la réplica y los respaldos. Da VNet/NSG reales, elimina el límite "misma VM", y permite una demo de caída y promoción creíble. Costo extra: una VM pequeña encendida solo para pruebas y sustentación; **hay que validarlo contra el crédito restante**.

Kubernetes queda como extra opcional en ambos casos.

---

## 6. Plan de trabajo propuesto (orden por impacto en la rúbrica)

| Fase | Trabajo | Criterio |
|---|---|---|
| 0 | Confirmar fecha de la Semana 18, crédito Azure restante y camino A/B | todos |
| 1 | Crear repo público, mover IaC base, optimizar Dockerfiles, redes y límites | 2 |
| 2 | Prometheus + Grafana + exporters + tablero; añadir `micrometer-registry-prometheus` | 3 |
| 3 | Externalizar estado en memoria del backend; 2 instancias + `upstream` en Nginx | 4, 3 |
| 4 | k6: ejecutar P1–P4, documentar escalado y punto de quiebre | 3 |
| 5 | VNet/subredes/NSG por IaC; segunda VM y réplica remota (si camino B) | 3, 4 |
| 6 | Backups a Blob, restauración medida, DRP y mapeo de patrones | 4 |
| 7 | Diagramas físico y lógico; informe PDF por fases | 1, entregable 1 |
| 8 | Guion de fallos, ensayo y plan B | 5 |

Las fases 1–3 desbloquean todo lo demás y no dependen de la decisión A/B.
