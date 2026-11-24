# Resumen ejecutivo

## Qué se hizo

ClickClak es un sistema de control de asistencia y gestión de incidencias con marcación georreferenciada y trabajo sin conexión, desarrollado por el equipo en el curso Integrador II. Allí quedó desplegado en **una sola máquina virtual** de Azure. En este curso se tomó ese sistema como base y se lo convirtió en una arquitectura **con dos nodos activos, un balanceador, una base de datos replicada con recuperación ante fallos, monitoreo en tiempo real, respaldos externos y cifrado interno**, todo medido con pruebas reales y reproducible desde el repositorio.

La arquitectura final usa **tres servidores** en Chile Central: dos nodos idénticos que ejecutan la aplicación y una base PostgreSQL (uno como primaria y otro como standby) y un tercer servidor, el *testigo*, que aloja el monitoreo, los respaldos y la generación de carga. Un balanceador de carga Estándar es el único punto con IP pública.

## Resultados medidos

@tabla Resultados principales del proyecto (todos con evidencia en el repositorio)
| Aspecto | Resultado | Dónde se detalla |
|---|---|---|
| Caída de la primaria de PostgreSQL (3 ensayos reales) | RTO de escritura **30,0 · 36,4 · 35,8 s**; RPO **0** (178/178, 205/205 y 214/214 escrituras confirmadas halladas en la nueva primaria) | Capítulo 4 |
| Reincorporación del nodo caído | `pg_rewind` en **12 s**, o reconstrucción completa en ≈ 10 s | Capítulo 4 |
| Caída de un backend | El balanceador lo retira en **~11 s**; **97,4 %** de sondas exitosas durante la prueba | Capítulo 4 |
| Capacidad bajo carga (k6) | p95 de **7–14 ms** hasta 50 usuarios; **0 % de errores** con 200 usuarios (~400 peticiones/s) | Capítulo 3 |
| Escalado de 1 a 2 instancias bajo estrés | p95 de 41,8 a **11,4 ms (−73 %)**; la cola del pool de conexiones pasó de 46 a 0 | Capítulo 3 |
| Respaldos | Cada hora a Azure Blob con identidad administrada; restauración verificada en **9,4 s** con conteos iguales | Capítulo 4 |
| Cifrado interno | TLS 1.3 con verificación completa entre aplicación y base y en la replicación; lo no cifrado se rechaza | Capítulo 5 |
| Vulnerabilidades HIGH/CRITICAL (Trivy) | Backend 51 → **4** (aceptados con motivo y caducidad); frontends 68 → **0**; proxy 70 → **0** | Capítulo 5 |
| Pruebas automáticas del backend | **329** en verde; integración continua en cada cambio | Capítulos 3 y 5 |
| Costo de operación | ≈ USD 0,19 por hora con todo encendido (precios de lista); el crédito de USD 79 obliga a encender solo para pruebas | Capítulo 6 |

## Alcance y reutilización

> **Qué viene del curso anterior y qué es nuevo.** Del Integrador II proviene el **sistema base**: el código del backend y de los dos frontends y su modelo de datos (informe APF2). Es nuevo en este curso todo lo que convierte ese sistema en una arquitectura cloud: la contenedorización optimizada, el diseño de dos nodos con balanceador, el backend sin estado compartido, la replicación y el failover, los respaldos, el monitoreo, el cifrado interno, las pruebas de carga, el escaneo de vulnerabilidades en integración continua y la infraestructura como código. Este informe **no reproduce** el APF2: lo cita solo para describir el punto de partida.

## Cómo está organizado este documento

El informe sigue las tres fases de la guía del proyecto y añade capítulos transversales:

@tabla Estructura del informe y su relación con la guía y la rúbrica
| Capítulo | Contenido | Criterio de la rúbrica |
|---|---|---|
| 1. Fase 1 | Sistema base, requerimientos cloud, estrategia de virtualización y almacenamiento | Criterio 1 |
| 2. Fase 2 | Contenedorización, orquestación y topología de red | Criterio 2 y 3 |
| 3. Monitoreo y escalabilidad | Métricas, alertas, pruebas de carga y política de escalabilidad | Criterio 3 |
| 4. Fase 3 | Patrones de diseño, tolerancia a fallos, DRP y diagramas | Criterio 4 |
| 5. Seguridad | ISO/IEC 27001:2022 y OWASP Top 10 | Transversal |
| 6. Costos, límites y lecciones | Costos reales y lo que no se logró | Transversal |
| 7. Matriz de la rúbrica | Evidencia por criterio | Todos |

> **Cómo leer las afirmaciones.** Este informe distingue lo **medido** (con evidencia en `docs/evidencias/`), lo **diseñado pero no verificado** y lo **no implementado**. Cuando algo no se pudo comprobar, se dice. Los precios son de lista y la cifra final figura en Cost Management de Azure.
