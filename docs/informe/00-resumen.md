# Resumen

**Problema.** ClickClak, un sistema de control de asistencia y gestión de incidencias para personal de campo, corría en una sola máquina virtual con la aplicación, la base de datos y su réplica juntas, sin balanceador, sin monitoreo, sin respaldos y con estado guardado en la memoria del servidor. Su disponibilidad y sus datos dependían de una sola máquina.

**Solución.** Se diseñó, desplegó y verificó en Azure (Chile Central) una arquitectura de **tres servidores**: dos nodos idénticos que ejecutan la aplicación y una base PostgreSQL replicada (una primaria y una *standby*), y un servidor testigo con el monitoreo, los respaldos y la generación de carga. Un balanceador de carga es la única entrada pública. El backend pasó a ser **sin estado compartido**, el tráfico interno se cifra con TLS 1.3 verificado, y todo se orquesta con contenedores, se prueba con integración continua y se reproduce desde un repositorio público.

**Resultados.**

@tabla Resultados principales (todos con evidencia en el repositorio)
| Aspecto | Resultado | Capítulo |
|---|---|---|
| Caída de la primaria de PostgreSQL (4 ensayos reales) | RTO de escritura **30,0 · 36,4 · 35,8 · 35,4 s**; RPO **0** | V |
| Reincorporación del nodo caído | `pg_rewind` en **12 s**, o reconstrucción completa en ≈ 10 s | V |
| Caída de un backend | El balanceador lo retira en **≈ 11 s**; **97,4 %** de sondas correctas | V |
| Capacidad bajo carga (k6) | p95 de **7–14 ms** hasta 50 usuarios; **0 % de errores** con 200 usuarios (≈ 400 peticiones/s) | IV |
| Escalado de 1 a 2 instancias bajo estrés | p95 de 41,8 a **11,4 ms (−73 %)** | IV |
| Respaldos | Cada hora a Azure Blob; restauración verificada en **9,4–9,5 s** | V |
| Cifrado interno | TLS 1.3 con verificación completa; lo no cifrado se rechaza | VI |
| Vulnerabilidades HIGH/CRITICAL | Backend 51 → **4** (aceptados con caducidad); frontends 68 → **0**; proxy 70 → **0** | VI |
| Pruebas automáticas del backend | **329** en verde, con integración continua en cada cambio | III y VII |
| Costo de operación | ≈ USD 0,19 por hora con todo encendido (precios de lista) | VII |

**Límites.** La replicación es asíncrona (un RPO mayor que cero es posible), la promoción de la base es guionizada y no automática, no hay escalado automático, la red y los nodos de aplicación no tienen todavía script de infraestructura como código, y faltan un segundo factor de autenticación y una prueba ofensiva independiente. El detalle está en los capítulos V a VII.

**Palabras clave:** alta disponibilidad, resiliencia, contenedores, Azure, PostgreSQL, replicación, recuperación ante desastres, monitoreo, OWASP, ISO/IEC 27001.
