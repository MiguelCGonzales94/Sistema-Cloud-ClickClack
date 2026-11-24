# ANEXOS

## Anexo A. Matriz de cumplimiento de la guía y la rúbrica

Para cada criterio se indica dónde está la evidencia, lo que respalda el nivel más alto y **lo que un evaluador podría objetar**. No se asigna una nota: la decide quien evalúa.

@tabla Criterios de la rúbrica y evidencia
| Criterio | Evidencia | Lo que respalda un nivel alto | Lo que se podría objetar |
|---|---|---|---|
| **1. Análisis y arquitectura base** (Unidad 1) | Capítulos I y II; problemática, consumo medido, demanda, tráfico, modelos de despliegue y almacenamiento | Problemática y situación inicial documentadas; sistema descrito con su consumo medido; justificación IaaS frente a PaaS y de PostgreSQL, Blob y discos; topologías comparadas con costos | La opción PaaS se compara de forma cualitativa (no se verificó su precio ni disponibilidad en la región); el tráfico de red es una estimación con supuestos, no una medición |
| **2. Contenedorización y orquestación** (Unidad 2) | Capítulo III; Dockerfiles; `docker-compose.prod.yml` y `infra/nodos/`; prueba de humo 69/0 y 66/0 | Imágenes en dos etapas, sin privilegios, con comprobación de salud y límites; entorno orquestado con Compose, dos redes y dependencias de salud, sin errores | Se usa Compose y no Kubernetes (decisión razonada, pero distinta de lo que sugiere la guía); las imágenes de los frontends y del proxy pesan unos 21 MB más que su base por la capa de actualización de seguridad |
| **3. Infraestructura, monitoreo y escalabilidad** (Unidad 2) | Capítulos III y IV; diagramas físico y de red; 17 alertas y tablero de 21 paneles; pruebas de carga P1 a P5 | Red virtual con balanceador, NSG y una sola IP pública; métricas con alertas; escalabilidad **demostrada** de 1 a 2 instancias (p95 −73 %) y política escrita | **No hay escalado automático** ni se probó el escalado vertical; los logs no están centralizados; la red y los nodos no tienen script de infraestructura como código; no se midieron los créditos de CPU |
| **4. Resiliencia y patrones de diseño** (Unidad 3) | Capítulo V; patrones con su archivo; failover (3 ensayos más uno con TLS); respaldos; DRP | Failover real con RTO de 30–36 s y RPO 0 medidos, *fencing*, reincorporación con `pg_rewind`, respaldos con restauración verificada, patrones con evidencia | El failover es **manual**, la replicación es asíncrona y el testigo no vota; faltan Circuit Breaker y cola del lado servidor; sin zonas de disponibilidad ni segunda región |
| **5. Sustentación y demostración** (semanas 17–18) | Tres guiones de falla en `infra/failover/` y `infra/respaldos/`; tablero de Grafana | El sistema corre en la nube y las tres fallas están ensayadas y cronometradas | **Pendiente de realizar:** el ensayo completo y el plan B de la sustentación se preparan después de este informe |

## Anexo B. Qué demuestra la sustentación en vivo

Se ejecutarán tres fallas con el tablero de Grafana abierto, para ver la caída y la recuperación en tiempo real:

1. **Cae un backend** (`ensayo-backend.sh`): el balanceador lo retira en ≈ 11 s y el otro nodo absorbe el tráfico.
2. **Cae la primaria de PostgreSQL** (`ensayo-failover.sh`): aislamiento, promoción, reconexión automática de los backends y reincorporación del nodo caído.
3. **Pérdida de datos** (`respaldar.sh` y `restaurar.sh`): se borra una tabla en la primaria, se comprueba que la réplica también la perdió y se recupera desde Azure Blob.

Antes de empezar: ambos nodos sanos, la replicación en `streaming` y los servidores encendidos en orden, **primero el que aloja la primaria**.

## Anexo C. Estructura del repositorio

Repositorio público: <https://github.com/MiguelCGonzales94/Sistema-Cloud-ClickClack>

@tabla Carpetas del repositorio
| Carpeta | Contenido |
|---|---|
| `backend/` | API REST (Spring Boot, Java 21) y su Dockerfile |
| `frontend-admin/`, `frontend-campo/` | Los dos clientes React y sus Dockerfiles |
| `infra/docker-compose.prod.yml`, `infra/nodos/` | Orquestación y rol de cada nodo |
| `infra/nginx/` | Proxy: Dockerfile y plantillas de configuración |
| `infra/postgres/` | Scripts de la replicación (primaria y réplica) |
| `infra/failover/` | Aislamiento, promoción, reincorporación y ensayos de falla |
| `infra/respaldos/` | Respaldo y restauración a Azure Blob |
| `infra/monitoreo/` | Prometheus, Alertmanager, Grafana y sondas |
| `infra/azure/` | Scripts de `az` del balanceador, el testigo y los respaldos |
| `infra/carga/` | Guiones de las pruebas de carga con k6 |
| `infra/scripts/` | Despliegue y prueba de humo |
| `.github/workflows/` | Integración continua: pruebas, auditoría y Trivy |
| `docs/` | Documentación técnica, diagramas y evidencias |

## Anexo D. Evidencias

@tabla Evidencias y dónde están
| Evidencia | Ubicación |
|---|---|
| Pruebas de carga P1 a P5 (resultados y métricas de Prometheus) | `docs/evidencias/pruebas-de-carga/` |
| Caída de un backend | `docs/evidencias/caida-de-un-backend/` |
| Failover (4 ensayos) | `docs/evidencias/failover-1-cae-nodo1/` a `failover-4-con-tls-cae-nodo2/` |
| Respaldo y restauración | `docs/evidencias/respaldo-y-restauracion/` |
| Diagramas (editables y en imagen) | `docs/diagramas/` |
| Escaneos de Trivy y excepciones | `.github/workflows/seguridad.yml`, `.trivyignore.yaml` |

## Anexo E. Documentos de apoyo del repositorio

`docs/ARQUITECTURA_OBJETIVO.md` (diseño y validaciones en Azure), `docs/DECISION_TOPOLOGIA.md` (por qué tres servidores), `docs/COSTOS_Y_FAILOVER.md` (costos y semántica de la replicación), `docs/DRP_Y_FAILOVER.md` (ensayos y procedimiento), `docs/PRUEBAS_DE_CARGA.md`, `docs/ENDURECIMIENTO_F5.md` y `docs/SEGURIDAD_ISO27001_OWASP.md`.
