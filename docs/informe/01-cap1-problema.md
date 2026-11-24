# CAPÍTULO I: PLANTEAMIENTO DEL PROBLEMA Y SOLUCIÓN PROPUESTA

## 1.1 Contexto

ClickClak es un sistema de control de asistencia y gestión de incidencias para personal de campo. El colaborador registra su ingreso, su refrigerio y su salida desde el teléfono, incluso sin conexión; el sistema valida cada marcación contra una ubicación autorizada y la guarda como evidencia. Supervisores y Recursos Humanos consultan y administran la información desde un panel web.

Un sistema así es **crítico durante la jornada**: si no responde, el personal no puede marcar o lo hace sin que quede constancia inmediata; si pierde datos, se pierde la evidencia de la asistencia. La aplicación tolera cortes breves de conexión del usuario (cola local), pero **no puede tolerar la caída de sus propios servidores sin que nadie lo note ni pueda recuperarlos**.

## 1.2 Situación inicial y problemática

Al iniciar el proyecto (22 de noviembre de 2026) se revisaron el código y la infraestructura del sistema, que corría en **una sola máquina virtual de Azure** con Docker Compose. La revisión encontró lo siguiente:

@tabla Hallazgos de la situación inicial y su consecuencia
| # | Hallazgo | Consecuencia |
|---|---|---|
| H1 | Aplicación, base de datos y su réplica corren en la **misma máquina** | Una falla de la VM o de su disco deja fuera el servicio **y** los datos; la réplica no protege de nada |
| H2 | Un solo contenedor de backend detrás del proxy, sin balanceador | No hay redundancia de la aplicación: mantenimiento o falla equivale a caída |
| H3 | El backend guarda **cuatro tipos de estado en la memoria** de su proceso (tokens revocados, intentos fallidos, recuperación de clave, desafíos WebAuthn) | No se pueden ejecutar dos instancias coherentes: un cierre de sesión o un bloqueo por fuerza bruta valdría solo en una de ellas |
| H4 | **Sin monitoreo**: no se publican métricas ni hay tableros ni alertas | Las fallas se descubren cuando los usuarios reclaman; no hay datos para dimensionar |
| H5 | **Sin respaldos** automáticos ni restauración probada | Un borrado accidental se replica y es irrecuperable |
| H6 | Tráfico hacia la base de datos **sin cifrar**; acceso SSH abierto a cualquier IP | Exposición innecesaria de datos personales y de la administración |
| H7 | Imágenes sin optimizar (cada cambio de código vuelve a descargar dependencias), frontends ejecutándose como administrador, sin límites de recursos, sin comprobaciones de salud en los frontends | Construcciones lentas, mayor superficie de ataque y un contenedor descontrolado puede agotar la máquina |
| H8 | **Sin pruebas de carga**, sin política de escalabilidad, sin topología de red diseñada y con la infraestructura creada a mano | Se desconoce la capacidad real y el entorno no es reproducible |

**Problema central.** El sistema tiene **puntos únicos de falla**, no es observable y no es recuperable: su disponibilidad y la integridad de sus datos dependen de una sola máquina y de la atención manual.

**Pregunta que guía el proyecto.** ¿Cómo lograr que ClickClak siga disponible y sus datos protegidos ante la falla de un componente, de un servidor o de un error humano, con las restricciones de una cuenta de estudiante?

## 1.3 Restricciones del entorno

@tabla Restricciones que condicionan el diseño
| Restricción | Efecto en el diseño |
|---|---|
| Crédito de **USD 79** (Azure for Students, vigente hasta el 2 de octubre de 2027) | Los servidores se encienden solo para pruebas y sustentación; se descartan topologías costosas |
| Cuota de **3 direcciones IP públicas** | Obliga a dejar una sola IP pública y a administrar los servidores por detrás del balanceador |
| Política de la suscripción que restringe las regiones | Se usa **Chile Central** |
| Plazo de las semanas 17 y 18 del curso | Se prioriza lo que se puede **medir** y demostrar; el resto se declara como trabajo futuro |
| Máquinas de la serie B (CPU en ráfaga) y 4 GiB de memoria | Los límites de memoria por contenedor son estrictos y el rendimiento sostenido es una incógnita |

## 1.4 Objetivos y alcance

**Objetivo general.** Diseñar, desplegar y verificar en Azure una arquitectura **altamente disponible, resiliente y escalable** para ClickClak, que elimine sus puntos únicos de falla y que se pueda observar, recuperar y reproducir.

**Objetivos específicos.**

@tabla Objetivos específicos, hallazgos que atienden y fase de la guía
| # | Objetivo | Atiende | Fase |
|---|---|---|---|
| OE1 | Analizar el sistema, estimar sus requerimientos cloud y justificar el modelo de despliegue y el almacenamiento | H8 | 1 |
| OE2 | Contenedorizar con imágenes optimizadas y orquestar el entorno con redes y límites | H7 | 2 |
| OE3 | Diseñar la topología de red y la seguridad cloud | H6, H8 | 2 |
| OE4 | Implementar monitoreo en tiempo real, medir la capacidad con pruebas de carga y definir la política de escalabilidad | H4, H8 | 2 |
| OE5 | Eliminar los puntos únicos de falla: balanceo, estado compartido, replicación con *failover* y respaldos con plan de recuperación medido | H1, H2, H3, H5 | 3 |
| OE6 | Alinear la seguridad con ISO/IEC 27001:2022 y OWASP Top 10 | H6 | Transversal |
| OE7 | Entregar un repositorio público reproducible con integración continua | H8 | Transversal |

**Alcance.** Incluye dos nodos de aplicación con balanceador, base de datos replicada con recuperación guionizada, un servidor de monitoreo y respaldos, cifrado interno, pruebas de carga y de falla y el repositorio con integración continua. **Queda fuera:** el *failover* automático con quórum, el escalado automático, la recuperación en otra región, Kubernetes y la certificación formal en ISO/IEC 27001.

## 1.5 Solución propuesta

La solución cambia la unidad de despliegue: de **un servidor** a **tres**, repartidos así:

- **Dos nodos idénticos** que ejecutan la aplicación y una copia de la base de datos (una primaria y una *standby* que recibe sus cambios por *streaming*). Ambos atienden tráfico.
- **Un servidor testigo**, fuera de los nodos, que aloja el monitoreo, los respaldos y la generación de carga. Su ubicación aparte es deliberada: el monitoreo debe seguir vivo cuando un nodo cae.
- **Un balanceador de carga** como única entrada pública, con sondeo de salud que retira al nodo que falla.

Cada hallazgo de la situación inicial tiene su respuesta, con evidencia medida:

@tabla De la problemática a la solución
| # | Solución | Capítulo | Resultado medido |
|---|---|---|---|
| H1 | Base replicada **entre dos servidores**; *fencing* y promoción guionizada; reincorporación con `pg_rewind` | V | Caída de la primaria: RTO **30–36 s**, RPO **0** en 4 ensayos |
| H2 | Dos nodos activos tras un balanceador con sondeo `/salud` | V | Caída de un backend: se retira en ≈ **11 s**; **97,4 %** de sondas correctas |
| H3 | El estado se mueve a PostgreSQL; el backend queda **sin estado** | V | **329** pruebas automáticas; sesión válida en ambos nodos |
| H4 | Prometheus, Grafana y Alertmanager en el testigo; sondas externas | IV | **17** alertas y tablero de **21** paneles |
| H5 | Respaldos horarios a Azure Blob con identidad administrada y restauración semanal | V | Restauración en **9,4–9,5 s**, 14 tablas con conteos iguales |
| H6 | TLS 1.3 con verificación completa; SSH restringido; una sola IP pública | III y VI | Sin TLS: **rechazado**; SSH solo desde la IP del equipo |
| H7 | Dockerfiles en dos etapas sin privilegios, con comprobaciones de salud y límites | III | Backend 51 → **4** y frontends y proxy 68/70 → **0** vulnerabilidades HIGH/CRITICAL |
| H8 | Pruebas de carga con k6, política de escalabilidad, diagramas y scripts versionados | II y IV | p95 de **7–14 ms** hasta 50 usuarios; **0 %** de errores con 200 usuarios |

**Criterios de logro.** Antes de las pruebas se fijó un criterio de aceptación de capacidad: **p95 inferior a 2 segundos y menos de 1 % de errores**. Para la recuperación no se fijó una meta numérica previa: se midieron el tiempo de recuperación (RTO) y las escrituras perdidas (RPO) y se informan tal cual, junto con sus límites.

> **Cómo leer las afirmaciones.** Este informe distingue lo **medido** (con evidencia en el repositorio), lo **diseñado pero no verificado** y lo **no implementado**. Cuando algo no se pudo comprobar, se dice. Los precios son de lista; la cifra final figura en Cost Management de Azure.
