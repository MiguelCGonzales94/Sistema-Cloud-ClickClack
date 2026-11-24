# CAPÍTULO I: FUNDAMENTOS DEL PROYECTO Y SOLUCIÓN PROPUESTA

## 1.1 Análisis del contexto empresarial

### 1.1.1 Reseña de la empresa

Indra Perú es la subsidiaria local de Indra Sistemas, una multinacional española de tecnología, consultoría y defensa. En el país opera como socio tecnológico de empresas de telecomunicaciones, banca, minería, energía y del sector público, con un equipo de ingenieros de sistemas, consultores funcionales y técnicos de soporte.

Este proyecto se concibe como una propuesta de mejora interna de carácter académico y profesional, desarrollada por estudiantes de la Universidad Tecnológica del Perú (UTP). No es un producto comercial para distribución externa, y la información se trata con criterio de confidencialidad.

### 1.1.2 Análisis del entorno empresarial

El modelo de prestación de servicios de TI ha migrado hacia esquemas deslocalizados, híbridos y remotos: consultores y técnicos ya no operan desde oficinas permanentes, sino en las dependencias de varios clientes o en ruta. Esa deslocalización plantea tres desafíos:

@tabla Desafíos del personal deslocalizado
| Dimensión | Desafío |
|---|---|
| Regulación laboral | La legislación peruana exige un registro estricto, auditable y veraz de las horas laboradas, la asistencia y la puntualidad |
| Dispersión geográfica | El personal técnico opera en zonas con conectividad celular inestable o nula, lo que invalida los controles basados en conexión continua |
| Costos operativos | Sin visibilidad en tiempo real de la ubicación y la disponibilidad del personal, se asignan mal las rutas y se atienden tarde las incidencias críticas |

### 1.1.3 Diagnóstico empresarial

Existen sistemas corporativos consolidados para el registro de horas del personal administrativo de oficina, pero el **personal móvil de campo carece de una herramienta adaptada a su realidad**. El reporte de asistencia y la justificación de incidencias (retrasos por tráfico, problemas de acceso en la sede del cliente, fallas de equipo) se hacen de forma semi-manual o por canales informales: mensajería instantánea, correos y llamadas. Ese esquema introduce tres vulnerabilidades:

- **Falta de trazabilidad.** Recursos Humanos y los supervisores no pueden auditar con certeza la puntualidad ni la ubicación real del colaborador en el momento de marcar.
- **Inconsistencia en la nómina.** La reconciliación manual al final de cada mes genera retrasos y un sobrecosto que el diagnóstico original estimó en **15 %**; esta cifra es una estimación de ese diagnóstico y **no se verificó en este proyecto**.
- **Sobrecarga administrativa.** Recursos Humanos invierte horas auditando mensajes y correos dispersos para procesar las incidencias.

## 1.2 Diagnóstico del problema y oportunidad de innovación

### 1.2.1 Definición del problema

El problema central se define formalmente como:

> **«Ineficiencia operativa y vulnerabilidad de control debido a la falta de un sistema centralizado, seguro e interactivo para el registro de asistencia, puntualidad y gestión de incidencias laborales del personal deslocalizado de Indra Perú.»**

Se manifiesta en tres dimensiones críticas:

- **Vulnerabilidad a fraudes de geolocalización (*GPS spoofing*).** Aplicaciones maliciosas alteran las coordenadas del teléfono del técnico para simular una puntualidad física ficticia en las dependencias del cliente.
- **Imposibilidad de registro sin conexión.** La inestabilidad de la red celular (centros de datos subterráneos, naves industriales lejanas) impide cargar a tiempo las marcas y bloquea la marcación.
- **Falta de un flujo estandarizado de auditoría de incidencias.** No existe un proceso centralizado para reportar, evaluar y aprobar incidencias con flujos de aprobación claros y estados definidos.

### 1.2.2 Trazabilidad del problema: causas y consecuencias

@tabla Matriz de trazabilidad del problema
| Causa raíz | Consecuencia o impacto operativo |
|---|---|
| Registro de coordenadas móviles básicas, sin validación de firmas ni de autenticidad | Fraude sistemático por *GPS spoofing*, marcajes falsos y suplantación de puntualidad |
| Dependencia absoluta de una conexión continua a Internet para marcar | Bloqueo operativo total en zonas sin señal, sótanos o zonas rurales |
| Flujo informal de justificaciones (mensajería, capturas, llamadas) | Sobrecostos de nómina por ineficiencias de control y saturación de la carga administrativa de Recursos Humanos |
| Ausencia de una autenticación robusta y adaptada a la movilidad | Suplantación de identidad entre técnicos para simular asistencias grupales fraudulentas |

### 1.2.3 De la solución de negocio al riesgo de disponibilidad

La respuesta a ese problema es **ClickClak**, un sistema de control de asistencia y gestión de incidencias (sección 1.4.1). Pero una solución que centraliza el registro de la asistencia **pasa a ser crítica**: si el servicio no responde, el personal no puede marcar o lo hace sin constancia inmediata, y si pierde datos, se pierde la evidencia de la asistencia. La aplicación tolera los cortes de conexión del usuario con su cola local, pero **no puede tolerar la caída de sus propios servidores sin que nadie lo note ni pueda recuperarlos**.

Al iniciar este proyecto (22 de noviembre de 2026) se revisaron el código y la infraestructura de la solución, que corría en **una sola máquina virtual de Azure** con Docker Compose. La revisión encontró lo siguiente:

@tabla Hallazgos técnicos de la situación inicial y su consecuencia
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

**Problema técnico central.** La solución tiene **puntos únicos de falla**, no es observable y no es recuperable: su disponibilidad y la integridad de sus datos dependen de una sola máquina y de la atención manual. Eso la deja expuesta justamente a lo que debía evitar: no poder registrar la asistencia cuando se necesita.

**Pregunta que guía este proyecto.** ¿Cómo lograr que ClickClak siga disponible y sus datos protegidos ante la falla de un componente, de un servidor o de un error humano, con las restricciones de una cuenta de estudiante?

### 1.2.4 Restricciones del entorno

@tabla Restricciones que condicionan el diseño
| Restricción | Efecto en el diseño |
|---|---|
| Crédito de **USD 79** (Azure for Students, vigente hasta el 2 de octubre de 2027) | Los servidores se encienden solo para pruebas y sustentación; se descartan topologías costosas |
| Cuota de **3 direcciones IP públicas** | Obliga a dejar una sola IP pública y a administrar los servidores por detrás del balanceador |
| Política de la suscripción que restringe las regiones | Se usa **Chile Central** |
| Plazo de las semanas 17 y 18 del curso | Se prioriza lo que se puede **medir** y demostrar; el resto se declara como trabajo futuro |
| Máquinas de la serie B (CPU en ráfaga) y 4 GiB de memoria | Los límites de memoria por contenedor son estrictos y el rendimiento sostenido es una incógnita |

## 1.3 Formulación de objetivos

### 1.3.1 Objetivos de la solución de negocio

**Objetivo general.** Diseñar un sistema web y móvil integrado (ClickClak) de control de asistencia, puntualidad y gestión de incidencias que optimice la trazabilidad de la jornada del personal deslocalizado de Indra Perú.

**Objetivos específicos.**

- Garantizar la veracidad de la identidad del personal con biometría delegada al sistema operativo del teléfono, mediante el estándar WebAuthn.
- Mitigar el riesgo de *GPS spoofing* con validaciones de geolocalización contextualizadas en el backend, sobre una base de datos espacial (PostgreSQL con PostGIS).
- Asegurar la continuidad del registro en cualquier entorno con una arquitectura *offline-first* (PWA con Workbox y Dexie.js sobre IndexedDB) que encole las marcas y las sincronice al recuperar la conexión.
- Sistematizar de forma auditable el ciclo de vida de las incidencias con un panel administrativo (Spring Boot y React) y un flujo formal: Registrada, En revisión, Aprobada o Rechazada, Cerrada.

### 1.3.2 Objetivos de este proyecto: la solución en la nube

**Objetivo general.** Diseñar, desplegar y verificar en Azure una arquitectura **altamente disponible, resiliente y escalable** para ClickClak, que elimine sus puntos únicos de falla y que se pueda observar, recuperar y reproducir.

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

## 1.4 Solución propuesta

### 1.4.1 La solución de negocio: ClickClak

ClickClak consta de dos componentes integrados por una API REST desarrollada en Spring Boot:

- **Aplicación móvil de campo (PWA).** Instalable en Android; autentica con WebAuthn; captura la ubicación de la marcación; permite marcar sin conexión, guardando las marcas en una cola local (IndexedDB con Dexie.js) que se reenvía al reconectar.
- **Panel administrativo web (SPA).** Hecho con React, Vite y Tailwind CSS para supervisores y Recursos Humanos: gestión de usuarios, sedes, turnos y asignaciones, y un módulo de incidencias con evidencias, comentarios y estados definidos.

@tabla Causas del problema de negocio y capacidad de ClickClak que las atiende
| Causa raíz | Capacidad de ClickClak | Qué se comprobó en este proyecto |
|---|---|---|
| Coordenadas sin validación | Validación contextual en el backend: se compara la distancia de la marcación con el radio de la sede, descontando la precisión reportada del GPS | Existe en el código. **No se volvió a validar su eficacia ante *GPS spoofing***, y el diseño original menciona además una heurística de velocidad que **no se encontró** en el código revisado |
| Dependencia de la conexión | Cola local en IndexedDB y reenvío al reconectar, con identificador de cliente que evita duplicados | Existe en el código; la idempotencia se verificó bajo carga (capítulo IV). **La cola local no está cifrada**, a diferencia de lo que describe el diseño original |
| Flujo informal de justificaciones | Incidencias con estados Registrada, En revisión, Aprobada, Rechazada y Cerrada | Los estados existen en el código; el flujo funcional no se volvió a probar aquí |
| Autenticación débil | WebAuthn con biometría delegada al dispositivo y registro de dispositivos autorizados | Existe en el código; no se volvió a auditar |

> **Alcance de este proyecto respecto de la solución de negocio.** Este proyecto **no desarrolla** esas funciones ni demuestra su eficacia funcional: toma el sistema como solución y se ocupa de que esté **disponible, recuperable y observable**. La tabla anterior dice con honestidad qué se comprobó y qué no.

### 1.4.2 La solución de infraestructura: arquitectura de tres servidores

La solución cambia la unidad de despliegue: de **un servidor** a **tres**, repartidos así:

- **Dos nodos idénticos** que ejecutan la aplicación y una copia de la base de datos (una primaria y una *standby* que recibe sus cambios por *streaming*). Ambos atienden tráfico.
- **Un servidor testigo**, fuera de los nodos, que aloja el monitoreo, los respaldos y la generación de carga. Su ubicación aparte es deliberada: el monitoreo debe seguir vivo cuando un nodo cae.
- **Un balanceador de carga** como única entrada pública, con sondeo de salud que retira al nodo que falla.

### 1.4.3 De la problemática técnica a la solución

@tabla Hallazgos técnicos y solución con su resultado medido
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

### 1.4.4 Alcance y limitaciones

**Alcance.** Dos nodos de aplicación con balanceador, base de datos replicada con recuperación guionizada, un servidor de monitoreo y respaldos, cifrado interno, pruebas de carga y de falla, y el repositorio con integración continua.

**Limitaciones heredadas del diseño del sistema** (no se alteraron en este proyecto):

- La PWA se optimiza solo para **Android**; el motor de WebAuthn varía en los navegadores de iOS.
- **No hay aplicación nativa** (APK o AAB): se distribuye como PWA.
- Los navegadores no exponen si la ubicación simulada está activa, de modo que el riesgo de *GPS spoofing* **solo se mitiga con validación en el servidor**.
- La validación es un **motor de reglas determinista**, sin inteligencia artificial.
- Los datos se exportan en formatos planos (CSV o Excel); **no hay integración** con los sistemas de planillas de la empresa.

**Una limitación original que este proyecto supera.** El diseño del sistema preveía operar en una máquina virtual básica de capa gratuita y declaraba que su desempeño se limitaría ante **más de 50 usuarios concurrentes**. La arquitectura de este proyecto se midió con **200 usuarios simultáneos y 0 % de errores** (capítulo IV); esa medición se hizo con base pequeña y duraciones cortas, y sus límites se declaran allí.

**Fuera del alcance de este proyecto:** el *failover* automático con quórum, el escalado automático, la recuperación en otra región, Kubernetes y la certificación formal en ISO/IEC 27001.

### 1.4.5 Criterios de logro

Antes de las pruebas se fijó un criterio de aceptación de capacidad: **p95 inferior a 2 segundos y menos de 1 % de errores**. Para la recuperación no se fijó una meta numérica previa: se midieron el tiempo de recuperación (RTO) y las escrituras perdidas (RPO) y se informan tal cual, junto con sus límites.

> **Cómo leer las afirmaciones.** Este informe distingue lo **medido** (con evidencia en el repositorio), lo **diseñado pero no verificado** y lo **no implementado**. Cuando algo no se pudo comprobar, se dice. Los precios son de lista; la cifra final figura en Cost Management de Azure.

## 1.5 Estado del arte

La solución se apoya en estándares y prácticas ampliamente documentados:

- **Aplicaciones web progresivas e IndexedDB.** Los *service workers* (con la biblioteca Workbox) permiten que una aplicación web funcione sin conexión y se instale en el teléfono, y IndexedDB (a través de Dexie.js) da una base de datos local para encolar las marcas.
- **WebAuthn.** Estándar del W3C y de la FIDO Alliance que autentica con criptografía de clave pública; la biometría se queda en el dispositivo y no viaja a los servidores. **No se verificó con asesoría legal** su alcance frente a la Ley 29733 de Protección de Datos Personales.
- **PostGIS.** Extensión espacial de PostgreSQL que calcula distancias y relaciones geográficas en el servidor.
- **Prácticas de nube adoptadas en este proyecto:** contenedores y orquestación declarativa, replicación en *streaming* con promoción controlada (*fencing*), respaldos externos con restauración probada, observabilidad con métricas y alertas, y seguridad alineada con ISO/IEC 27001 y OWASP.
