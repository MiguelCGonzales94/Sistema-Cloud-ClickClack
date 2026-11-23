# ClickClak Cloud — Plan de cierre (de F5 a la sustentación)

Fecha: 2026-11-23 (lunes, Semana 17) · Complementa `PLAN_DE_TRABAJO.md` (que sigue siendo la referencia de las fases F0–F8).
Estado: **propuesta para aprobar**. Las duraciones son **estimaciones mías en horas-persona**, no compromisos. La **fecha exacta de la Semana 18 no la tengo**: el calendario se cuenta en días hacia la sustentación (D-7 … D0) hasta que se confirme.

## 1. Qué queda realmente (contrastado con la carpeta, 2026-11-23)

| Pendiente | Fase original | Estado verificado hoy |
|---|---|---|
| Repositorio git y público | F0.2–0.3 | **No existe**: la carpeta no es un repositorio. Hay `.gitignore`, `.gitattributes` y 4 workflows en `.github/workflows/` **heredados de ClickClak, sin revisar para este proyecto** |
| Diagramas físico y lógico | F6.4 | Carpeta `docs/diagramas/` creada, **sin diagramas** |
| Informe PDF por 3 fases | F6.1–6.3, 6.5–6.7 | Carpeta `docs/informe/` creada, **sin informe**. La base técnica ya está en `docs/` |
| Mapeo patrones cloud → código | F4.9 | No hecho |
| Política de escalabilidad + elasticidad | F2.6 | Hay medición 1→2 instancias (`PRUEBAS_DE_CARGA.md`); **falta la política escrita** con disparadores. No hay autoescalado |
| Matriz de roles por endpoint | F2.4 | No hecha |
| IaC reproducible | F1.4 | Hay scripts `az` para balanceador, testigo y respaldos. **Los nodos 1 y 2, la VNet y los NSG se crearon a mano / por clonado**; no hay script ni Bicep. El plan original decía Bicep |
| Imágenes en registro, CI con pruebas y Trivy | F1.3, F5.1 | No hecho |
| Segundo factor, rol de BD sin DDL, prueba ofensiva | F5.2, 5.4, 5.7 | Pendientes (ver `ENDURECIMIENTO_F5.md` §7) |
| Auditoría interna del SoA | F5.8 | No hecha |
| Alerta de presupuesto, etiquetas, saldo de crédito | F0.6 | **No verificado**: no he comprobado el saldo restante |
| Nota de reutilización (qué viene de Integrador II) | F0.7 | Parcial (sección "Origen" del README) |
| Guion, ensayos, plan B, diapositivas | F7 | No hecho |
| Cierre y apagado | F8 | No hecho |

## 2. Bloques de trabajo

Cada bloque tiene una **puerta** (qué debe ser verdad para darlo por cerrado). "Nube" indica si necesita los servidores encendidos.

### Bloque A — Repositorio público y CI (≈5 h) · sin nube

| # | Tarea | Resultado |
|---|---|---|
| A1 | `git init`, revisar que **no entra nada sensible**: `infra/azure/.cuenta-respaldos`, claves/CA, `.env`, secretos del testigo, `*.dump`, evidencias con IP o claves | Lista de exclusiones y escaneo de secretos (p. ej. `gitleaks`) limpio |
| A2 | Primer commit y creación del repo **público** (plataforma por decidir) | URL |
| A3 | Revisar los 4 workflows heredados: adaptarlos a este repo (rutas, nombres de imagen, secretos) o retirarlos | CI que compila y corre las 329 pruebas |
| A4 | Añadir **Trivy** (imágenes y dependencias) al CI | Cierra el pendiente de F5 |
| A5 | Publicar imágenes versionadas en GHCR (solo si la plataforma es GitHub) | Registro |
| A6 | Protección de `main` + PR | Reglas |
| A7 | README raíz de **reproducción desde cero** (prerrequisitos, orden de despliegue, cómo ver el tablero) + licencia | Entregable 2 |

**Avance (2026-11-23):** A1 y A2 **hechos**: repo público <https://github.com/MiguelCGonzales94/Sistema-Cloud-ClickClack>, 8 commits en español sin atribución a herramientas, correo `noreply` de GitHub. En A1 se quitaron los tokens JWT de las evidencias de k6 y se excluyó `.cuenta-respaldos`; búsqueda manual de secretos limpia (no se usó `gitleaks`: no está instalado). A3 **parcial**: los 4 workflows heredados corrieron en verde sobre el primer commit (incluye las 329 pruebas), pero siguen sin adaptarse (comentarios apuntan a `Docs/tecnica/pipeline-ci.md`, que no existe aquí). **A3 y A4 hechos** (rama `ci/trivy`): comentarios de los 4 workflows adaptados y nuevo `seguridad.yml` con Trivy (código y las 4 imágenes) que falla con HIGH/CRITICAL. Trivy va desde su imagen oficial 0.57.1 fijada por digest, no con `trivy-action` (comprometida en marzo de 2026). La primera ejecución encontró 7 hallazgos en el backend; se cerraron 3 (`spring-data` y `guava`, 329 pruebas en verde) y se aceptaron 4 en `.trivyignore.yaml` con motivo y caducidad 2026-12-31. Siguen **pendientes** A5 a A7.

**Puerta:** repo público sin secretos; CI en verde; README seguible por un tercero.
**Corte posible:** A5 y A6.

### Bloque B — Brechas técnicas cortas (≈10 h) · B1–B3 sin nube, B4 con nube parcial

| # | Tarea | Resultado |
|---|---|---|
| B1 | **Tabla patrón → archivo/commit** (Health Endpoint Monitoring `/salud`, Throttling rate limit, Gateway Routing balanceador+proxy, Idempotent Consumer marcaciones, Retry JDBC multi-host, Queue-Based Load Leveling si aplica, Circuit Breaker si hay tiempo). Solo se declara un patrón si el código lo respalda | `docs/PATRONES_CLOUD.md` |
| B2 | **Política de escalabilidad**: disparadores (CPU, p95, conexiones) tomados de Prometheus, pasos horizontal/vertical, y **qué no hace** (sin autoescalado; manual). Reutiliza la prueba 1→2 instancias como evidencia de elasticidad | `docs/ESCALABILIDAD.md` |
| B3 | **Matriz de roles por endpoint** con pruebas automáticas (OWASP A01) | Tests + tabla |
| B4 | **IaC de lo que falta**: script `az` para VNet, subred, NSG y las dos VM de nodo (decisión: scripts `az` coherentes con los existentes, **no** reescribir a Bicep) y verificación en seco del orden de despliegue | `infra/azure/nodos.sh` + README |
| B5 | Verificar **saldo de crédito**, alerta de presupuesto y etiquetas `curso=servicios-cloud` | Saldo anotado en el plan |

**Puerta:** cada patrón citado tiene archivo; política de escalabilidad escrita; B4 probado al menos en modo lectura.
**Corte posible:** Circuit Breaker, B3 (se declara como pendiente).

### Bloque C — Diagramas (≈6 h) · sin nube

| # | Diagrama | Contenido |
|---|---|---|
| C1 | **Físico (Azure)** | Región Chile Central, VNet/subred, NSG, balanceador y su única IP pública, los 3 servidores con rol, Blob de respaldos, flujo de tráfico y de replicación |
| C2 | **Lógico** | Contenedores por nodo, redes `web`/`datos`, Prometheus/Grafana en el testigo, replicación y respaldos |
| C3 | **Secuencia de failover** | Caída de la primaria → fencing → promoción → reincorporación, con los tiempos medidos |
| C4 | **Red y puertos** | Quién habla con quién y por dónde (TLS interno) |

**Avance (2026-11-23):** los 4 diagramas están hechos en `docs/diagramas/` (fuente `.drawio` editable y `.png` exportado): `01-fisico-azure`, `02-logico-contenedores`, `03-secuencia-failover` y `04-red-y-puertos`. Se contrastaron con `ARQUITECTURA_OBJETIVO.md`, `DRP_Y_FAILOVER.md` y los archivos de `infra/` (puertos de exportadores, redes Docker y rol de cada nodo). Los íconos de Azure no se usaron: son figuras genéricas.

Formato: draw.io (editable) + PNG exportado en `docs/diagramas/`. **Puerta:** los 4 diagramas coinciden con el estado real (IPs, puertos y roles de `ARQUITECTURA_OBJETIVO.md` §5).

### Bloque D — Informe técnico PDF por fases (≈16 h) · sin nube

Se **reescribe con enfoque cloud**; no se copia el APF2 (riesgo académico ya identificado).

| # | Capítulo | Se apoya en |
|---|---|---|
| D1 | **Fase 1 — Análisis y arquitectura base**: sistema, requerimientos cloud, **tráfico de red estimado**, **IaaS vs PaaS vs híbrido** (incluye validar si PostgreSQL administrado existe y a qué precio en Chile Central; hasta validarlo se dice "no verificado"), tipo de almacenamiento y Blob | `ANALISIS_BRECHAS`, `ARQUITECTURA_OBJETIVO`, `COSTOS_Y_FAILOVER`, `DECISION_TOPOLOGIA` |
| D2 | **Fase 2 — Contenedores, orquestación, infraestructura y monitoreo**: Dockerfiles antes/después, redes, límites, NSG, Prometheus/Grafana, escalabilidad | `docker-compose.prod.yml`, `PRUEBAS_DE_CARGA`, B2 |
| D3 | **Fase 3 — Resiliencia y patrones**: balanceador, replicación, failover con RTO/RPO, backups, DRP, patrones | `DRP_Y_FAILOVER`, `evidencias/`, B1 |
| D4 | **Seguridad** (transversal): ISO 27001 (SoA honesto) y OWASP | `SEGURIDAD_ISO27001_OWASP`, `ENDURECIMIENTO_F5` |
| D5 | **Costos reales, limitaciones y lecciones** (RPO>0 posible, promoción manual, sin autoescalado, riesgo aceptado de `postgis`) | todos |
| D6 | **Matriz criterio de la rúbrica → evidencia** y revisión cruzada | Guía y rúbrica |

Herramienta: redactar en Markdown/Word y exportar a PDF (formato por decidir). **Puerta:** cada afirmación tiene su evidencia o está marcada como no verificada; revisión de otro integrante contra la rúbrica, criterio por criterio.

### Bloque E — Evidencias con la nube encendida (≈4 h) · **necesita nube**

| # | Tarea |
|---|---|
| E1 | Capturas del portal de Azure (3 VM, balanceador, NSG, almacenamiento) y de Grafana con carga y con una caída |
| E2 | Ejecutar de nuevo la prueba de humo y guardar la salida |
| E3 | Cualquier captura que falte tras escribir el informe |

Se hace **en una sola ventana** para no tener los servidores encendidos más de lo necesario.

### Bloque F — Sustentación (≈10 h) · **necesita nube**

| # | Tarea | Resultado |
|---|---|---|
| F1 | **Guion** con tiempos y reparto por integrante (duración de la sustentación: **no la conozco**) | Guion |
| F2 | **Tres guiones de falla** cronometrados: caída de un backend, caída de la primaria, restauración de un respaldo | Hoja de ejecución |
| F3 | **Dos ensayos completos**, el último con preguntas cruzadas | Registro y tiempos |
| F4 | **Plan B**: el mismo stack con `docker compose` local y video grabado de la demo | Paquete de respaldo |
| F5 | **Checklist del día**: encender en orden (primero la base), saldo, certificado, ventana de acceso, IP del equipo en el NSG de **cada** integrante | Lista |
| F6 | Diapositivas y banco de preguntas (por qué IaaS, por qué 3 nodos, split-brain, RTO/RPO, costos, seguridad) | Presentación |

**Puerta:** un ensayo completo sin intervención fuera de guion.

### Bloque G — Cierre (≈2 h)

Congelar y etiquetar la versión; entregar el informe en la fecha; tras la nota, apagar y **eliminar** recursos (el balanceador se recrea con `balanceador.sh`); verificar la factura; retrospectiva.

## 3. Dependencias y orden

```
A1─A2─A3─A4 ──────────────────────────────┐
B1,B2,B3 ─► C1─C4 ─► D1─D5 ─► D6 ─► E ─► F ─► G
B4,B5 ───────────────────────────┘
```

- **A y B corren en paralelo**; C necesita el estado real (ya está en `ARQUITECTURA_OBJETIVO.md`).
- D1 puede empezar hoy; D2 y D3 esperan B1/B2.
- **E y F son los únicos que exigen servidores encendidos.**

## 4. Calendario propuesto

Se cuenta desde hoy (lunes 23, Semana 17); la sustentación cae en la Semana 18. Si resulta ser antes del lunes 30, los bloques se recortan según §6.

| Día | Trabajo | Nube |
|---|---|---|
| Lun 23 (hoy) | A1–A2 (con tu visto bueno), B1, empezar C1 | encendida (ya lo está) |
| Mar 24 | A3–A4, B2, B5, C1–C4 | apagable |
| Mié 25 | B3, B4, D1 | apagable |
| Jue 26 | D2, D3 | apagable |
| Vie 27 | D4, D5, D6 (revisión cruzada) | **encender para E** |
| Sáb 28 | E, F1–F2 (guiones de falla) | encendida |
| Dom 29 | F3 (dos ensayos), F4 (plan B), F6 | encendida |
| Semana 18 | Checklist F5 y sustentación; luego G | encendida hasta la sustentación |

**Presupuesto:** con los 3 servidores y el balanceador encendidos cuestan ~USD 0,19/h (~4,5 al día); apagados, ~USD 27,5/mes fijos. Si se apagan lun noche→vie, se ahorran ~USD 18 frente a dejarlos prendidos 4 días. **El saldo real aún no lo he verificado (B5)**; hasta tenerlo, esta cifra es referencia de lista.

## 5. Responsables (sugerencia, a ajustar por el equipo)

| Bloque | Sugerido |
|---|---|
| A, B4, E, F2 (infraestructura) | Cuadros (con apoyo del SM) |
| B3, B1 (backend y patrones) | Tapia |
| C, D, B2 (informe y diagramas) | Cieza |
| F1, F3, F5, F6, G (guion, ensayos, cierre) | Villanueva |

Todos deben poder explicar todas las capas en la sustentación: el reparto es solo de ejecución. En el plan cada integrante necesita además **acceso SSH** (su IP en el NSG) para poder ensayar.

## 6. Qué se recorta primero (en este orden)

1. Circuit Breaker y Queue-Based Load Leveling (B1).
2. A5 (GHCR) y A6 (protección de `main`).
3. B3 (matriz de roles automática): se documenta como pendiente.
4. Segundo factor, rol de BD sin DDL y prueba ofensiva (F5): se declaran **riesgo aceptado** en el SoA.
5. B4 en forma de script: queda como procedimiento documentado.

**No se recorta:** repo público sin secretos, diagramas, informe, evidencias del failover real, ensayo y plan B.

## 7. Riesgos de este tramo

| Riesgo | Efecto | Mitigación |
|---|---|---|
| Publicar un secreto en el repo público | Compromiso de claves | A1 con escaneo antes del primer push; rotar si algo se cuela |
| Fecha de sustentación más cercana de lo supuesto | Menos días de informe | Recortes de §6; confirmar la fecha hoy |
| Crédito menor al esperado | Demo caída | B5 antes de encender para E |
| Informe parecido al APF2 | Observación académica | Reescribir por fases y citar la reutilización |
| Un integrante sin acceso SSH el día de la demo | No puede mostrar | IP de cada uno en el NSG antes de F3 |
| Cambio de IP del equipo | Pérdida de SSH | `az network nsg rule update` (no requiere SSH) |

## 8. Decisiones que necesito de ti

1. **Plataforma del repo** (GitHub o GitLab) y **cuenta** (personal o del equipo), y autorización para publicarlo.
2. **Fecha exacta y duración** de la sustentación.
3. **Formato del informe**: Word → PDF o Markdown → PDF; si la guía pide una plantilla o extensión.
4. ¿Apagar los servidores entre bloques (martes a jueves) o dejarlos encendidos?
