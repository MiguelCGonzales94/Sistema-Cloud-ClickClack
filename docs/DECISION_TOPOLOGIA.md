# ClickClak Cloud — Decisión de topología: ¿2 servidores, 3 con base dedicada, o 3 con testigo?

Fecha: 2026-11-22 · Estado: **DECIDIDO — opción C (3 servidores: nodo 1, nodo 2 y testigo)**, construida por etapas empezando por los dos nodos. Seguridad: ISO/IEC 27001:2022 y OWASP Top 10 (ver `SEGURIDAD_ISO27001_OWASP.md`). Complementa `ARQUITECTURA_OBJETIVO.md` y `COSTOS_Y_FAILOVER.md`.

## 1. Criterios de decisión

1. **Rúbrica** (criterios 3, 4 y 5): balanceo, replicación, redundancia, DRP, monitoreo en vivo y tolerancia a fallos demostrada.
2. **Costo**: crédito disponible USD 79; los servidores solo se encienden para pruebas y sustentación.
3. **Correctitud de datos**: un solo escritor, sin split-brain.
4. **Operabilidad**: cuánto trabajo y cuántas piezas nuevas hay que dominar para la sustentación.

## 2. Qué dicen las prácticas (resumen de fuentes)

- **Con 2 nodos no hay quórum.** Un nodo no puede distinguir "el otro cayó" de "perdí la red con el otro"; por eso los sistemas de alta disponibilidad piden un **tercer voto**. Ese testigo **no necesita ser una réplica completa de datos**; sirve para desempatar. (EDB; Packt; Canonical con su "watcher" ligero sin PostgreSQL propio.)
- **El fencing no es opcional**: aun con consenso (Patroni), hay que garantizar que el nodo viejo no siga escribiendo. (EDB.)
- **La aplicación debe seguir a la primaria sola.** El driver JDBC de PostgreSQL acepta varios hosts con `targetServerType=primary` y prueba en orden hasta hallar la primaria; es mejor listar los hosts que usar un nombre DNS con varias IP. El estado se cachea 10 s por defecto (`hostRecheckSeconds`). Esto evita añadir HAProxy o un balanceador de base de datos.
- **El monitoreo debe vivir fuera del dominio de falla de lo que vigila**; si Prometheus y Grafana caen junto con el servidor, la sustentación queda "a ciegas" justo cuando se provoca la falla. Dos procesos en la misma máquina no son dos dominios de falla.

*Límite:* la búsqueda no devolvió la documentación oficial de Patroni ni de pg_auto_failover; los detalles de su configuración deben confirmarse en sus sitios oficiales antes de implementarlos.

## 3. Opciones comparadas

| | **A. 2 servidores** | **B. 2 app + 1 BD dedicada** | **C. 2 nodos + 1 testigo/observabilidad** (recomendada) | **D. 2 app + BD primaria + BD réplica** |
|---|---|---|---|---|
| Servidores | 2 | 3 | 3 | 4 |
| Datos | Primaria en nodo 1, réplica en nodo 2 | Una BD: **punto único de falla** salvo que se añada standby | Primaria y réplica en los nodos 1 y 2 | Primaria y réplica en servidores propios |
| Failover | Manual guionizado; riesgo de split-brain sin quórum | Manual (o ninguno) | **Automático con quórum** (nodo 1, nodo 2 y testigo) o manual guionizado | Como C si se añade testigo |
| Monitoreo sobrevive a la caída de un nodo | No (corre en un nodo) | Parcial | **Sí** (corre en el testigo) | Parcial |
| Seguridad por capas (OWASP A01/A05) | Base comparte host con la app | **Mejor**: BD en subred privada | Base comparte host con la app (se mitiga con red interna y `pg_hba`) | **Mejor** |
| Nodos idénticos | No exactamente | Sí | **Sí** | Sí |
| Costo, 120 h de pruebas (USD)* | ~35,9 | ~49,0 | **~49,0** | ~62,0 |
| Complejidad | Baja | Media | Media-alta | Alta |
| Encaje con la rúbrica | Cumple lo mínimo | Débil en resiliencia de datos | **Cubre balanceo, replicación, quórum, monitoreo y DRP** | Cubre, con costo alto |

\* Con tamaños B2als_v2 (4 GiB), discos de 64 GiB, balanceador estándar eliminado al apagar y precios de lista (ver `COSTOS_Y_FAILOVER.md`). El testigo con una B2ats_v2 (1 GiB) bajaría C a ~44,3.

## 4. Recomendación

**Tres servidores, pero el tercero no es una base de datos: es testigo de quórum + observabilidad + respaldos (opción C).** Se construye de forma incremental, empezando por los dos primeros.

Razones:

1. **Resuelve el problema real de 2 nodos** (quórum) con un voto barato, sin triplicar datos.
2. **Una base dedicada sola (B) no da tolerancia a fallos**: simplemente mueve el punto único de falla. Si después se le añade standby, equivale a D, que cuesta ~USD 13 más sin aportar más a la rúbrica.
3. **El monitoreo sobrevive a la falla provocada** en la demostración: se ve la caída y la recuperación en Grafana en tiempo real.
4. **Los nodos 1 y 2 son idénticos y reemplazables**, que es lo que se pidió (replicar el servidor 1).
5. El respaldo a Blob se origina fuera de los nodos de aplicación.

Costo de aceptar C frente a B: la base comparte host con la aplicación. Se declara en el informe y se mitiga: red Docker `privada` interna, `pg_hba` por CIDR, TLS, SCRAM, sin IP ni puerto público para la BD.

**Cuándo bastarían solo 2 servidores (opción A):** si el tiempo no alcanza. Es una versión válida y defendible (balanceador, replicación, promoción manual guionizada, DRP con respaldos), pero sin failover automático seguro y con el monitoreo en un nodo. El diseño admite añadir el testigo después sin rehacer nada.

## 4.1 Estado real del tercer servidor (actualizado 2026-11-23)

El testigo (`vm-clickclak-3`, `10.0.0.6`) **ya está creado y operativo** (fase F3). Hoy cumple estas funciones:

| Función | Estado |
|---|---|
| Observabilidad fuera de los nodos (Prometheus, Alertmanager, Grafana, sondas externas) | **Hecho** |
| Respaldos a Azure Blob y pruebas de restauración | **Hecho** |
| Generador de carga (k6) dentro de la VNet | **Hecho** |
| **Votante de quórum para un failover automático** (etcd/Patroni o monitor de pg_auto_failover) | **No implementado**: la promoción sigue siendo manual y guionizada (ver `DRP_Y_FAILOVER.md`). Es la etapa opcional de la F5; se recorta primero si falta tiempo |

Por eso el testigo es hoy un servidor de *observabilidad, respaldos y pruebas*, no un tercer miembro de decisión del clúster. Qué cambia si se implementa el quórum: el failover pasaría de ~30–36 s con una persona a unos segundos sin ella, con riesgo de split-brain controlado por consenso.

## 5. Stack recomendado

| Capa | Tecnología | Nota |
|---|---|---|
| Entrada | Azure Load Balancer Standard (L4) + sondeo de salud | TLS termina en Nginx de cada nodo; certificado del mismo dominio en ambos |
| Proxy y estáticos | Nginx (ya existe) con `limit_req`, HSTS | |
| Aplicación | Spring Boot 3 / Java 21, 2 instancias activas | Estado en memoria (tokens, intentos, WebAuthn) pasa a PostgreSQL; mismo `JWT_SECRET` en ambos |
| Frontends | React + Vite en Nginx (ya existen) | Usuario no root, `HEALTHCHECK` |
| Datos | PostgreSQL 16 + PostGIS, primaria + réplica | `wal_log_hints = on` para `pg_rewind`; `data_checksums` |
| Conexión | JDBC multi-host: `jdbc:postgresql://nodo1:5432,nodo2:5432/clickclak?targetServerType=primary` | Sin proxy de base de datos adicional |
| Failover | **Fase 1:** promoción manual guionizada (los scripts ya existen). **Fase 2:** Patroni + etcd (3 miembros: nodo 1, nodo 2, testigo) o pg_auto_failover (monitor en el testigo) | Elegir tras confirmar documentación oficial y tiempo disponible |
| Observabilidad (testigo) | Prometheus, Alertmanager, Grafana, `blackbox_exporter` externo; en nodos: node-exporter, cAdvisor, postgres_exporter | Logs: Loki opcional |
| Respaldos | `pg_dump`/WAL a Azure Blob, restauración medida (RTO/RPO) | Desde el testigo |
| Imágenes y CI | GitHub Actions → GHCR, etiquetas versionadas; Trivy en el CI | OWASP A06/A08 |
| IaC | Bicep (grupo, VNet, subredes, NSG, VM, LB) + scripts de aprovisionamiento | Entregable del curso |
| Carga | k6: escenarios P1–P4 con 1 y 2 instancias | Evidencia de elasticidad |

## 6. Plan por etapas

| Etapa | Contenido | Resultado demostrable |
|---|---|---|
| 1 | Snapshot de la VM 1 → VM 2; réplica entre nodos; JDBC multi-host; Load Balancer | Caída de un backend sin corte |
| 2 | Estado del backend a PostgreSQL; pruebas k6 | Escalado a 2 instancias medido |
| 3 | Testigo: Prometheus/Grafana/blackbox/Alertmanager | Tablero en vivo durante las fallas |
| 4 | Promoción guionizada + respaldos a Blob + DRP medido | Failover de datos con RTO/RPO |
| 5 | Patroni/pg_auto_failover (si hay tiempo) | Failover automático sin split-brain |

## 7. Riesgos

- **Tiempo:** la fecha de la Semana 18 no está confirmada; define si se llega a las etapas 4 y 5.
- **Memoria:** etcd y Prometheus/Grafana en el testigo; si se usa B2ats_v2 (1 GiB) hay que acotar retención y panel.
- **Zonas:** la VM 1 no tiene zona; repartir en zonas exige recrearla desde un snapshot.
- **Complejidad de Patroni** con PostGIS en contenedores: validar una imagen que incluya ambos.
