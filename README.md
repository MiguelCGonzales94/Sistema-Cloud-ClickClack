# ClickClak Cloud

Proyecto final del curso **Servicios Cloud (100000S91T)**, UTP, sección 43639. Migración, contenedorización y despliegue en la nube de **ClickClak**, el sistema de control de asistencia y gestión de incidencias desarrollado para el curso Integrador II.

## Origen del código

Copia del código commiteado de `ClickClak/main` (commit `ebcc625`), sin `node_modules`, `target` ni documentación del otro curso. El repositorio original no se modifica.

## Estructura

| Carpeta | Contenido |
|---|---|
| `backend/` | API REST (Spring Boot 3, Java 21, PostgreSQL/PostGIS) |
| `frontend-admin/` | Panel administrativo (React + Vite) |
| `frontend-campo/` | PWA de marcación (React + Vite) |
| `infra/` | Docker Compose, Nginx, replicación PostgreSQL, scripts de despliegue |
| `.github/` | CI por componente |
| `docs/referencia/` | Guía y rúbrica del curso |
| `docs/informe/` | Informe técnico (Fase 1, 2 y 3) |
| `docs/diagramas/` | Arquitectura física y lógica |
| `docs/evidencias/` | Capturas, salidas de pruebas, resultados de carga |

## Estado

Decisión tomada: **3 servidores** (nodo 1, nodo 2 y un testigo de quórum/observabilidad/respaldos), con seguridad alineada a ISO/IEC 27001:2022 y OWASP Top 10. Ya está desplegado en Azure (Chile Central): balanceador, 2 nodos con replicación PostgreSQL, testigo con monitoreo, respaldos en Blob y TLS interno. Los servidores se apagan fuera de las ventanas de prueba, así que la URL pública puede no responder.

| Documento | Contenido |
|---|---|
| [`docs/PLAN_DE_TRABAJO.md`](docs/PLAN_DE_TRABAJO.md) | **Plan por fases F0–F8 hasta el cierre** |
| [`docs/informe/`](docs/informe/) | Fuentes del **informe técnico** en Markdown y el generador de DOCX y PDF |
| [`docs/diagramas/`](docs/diagramas/) | Diagramas físico, lógico, de failover y de red (`.drawio` y `.png`) |
| [`docs/PLAN_DE_CIERRE.md`](docs/PLAN_DE_CIERRE.md) | **Plan de cierre**: lo que queda desde F5 hasta la sustentación, por bloques y días |
| [`docs/ANALISIS_BRECHAS.md`](docs/ANALISIS_BRECHAS.md) | Qué falta frente a la rúbrica |
| [`docs/DECISION_TOPOLOGIA.md`](docs/DECISION_TOPOLOGIA.md) | Por qué 3 servidores, stack y etapas |
| [`docs/ARQUITECTURA_OBJETIVO.md`](docs/ARQUITECTURA_OBJETIVO.md) | Red, NSG y validaciones en Azure |
| [`docs/COSTOS_Y_FAILOVER.md`](docs/COSTOS_Y_FAILOVER.md) | Costos, replicación y failover |
| [`docs/SEGURIDAD_ISO27001_OWASP.md`](docs/SEGURIDAD_ISO27001_OWASP.md) | Controles ISO 27001 y OWASP Top 10 |

## Repositorio

Público en GitHub: <https://github.com/MiguelCGonzales94/Sistema-Cloud-ClickClack>. La rama `main` es la versión de trabajo.

## Convención de commits

Los mensajes se escriben **en español**, en presente y describiendo qué cambia y por qué (por ejemplo: `Agrega el guion de failover con aislamiento de la primaria`). Un commit por cambio coherente; nunca se versionan secretos ni claves.
