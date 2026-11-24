# 5. Seguridad: ISO/IEC 27001:2022 y OWASP Top 10

## 5.1 Alcance y lo que se afirma

> **Este proyecto adopta y alinea sus controles con ISO/IEC 27001:2022 y OWASP Top 10 (edición 2021). No está certificado ni auditado por un tercero.** Cuando el informe dice "implementado" significa que existe y se comprobó; no significa "cumple la norma". La edición 2021 de OWASP se mantiene por consistencia con el curso anterior; no se verificó si procede una más reciente.

**Alcance.** La plataforma ClickClak en Azure: los tres servidores, la red virtual, el balanceador, el almacenamiento de respaldos, el código, el flujo de integración continua y los datos que trata. Quedan fuera las instalaciones físicas y la infraestructura base de Azure (responsabilidad compartida: el proveedor gestiona el centro de datos; el equipo, lo que despliega encima).

**Datos personales.** El sistema trata asistencia y **ubicación** de personas. En Perú aplica la Ley 29733 de Protección de Datos Personales. **No se verificó con asesoría legal** qué obligaciones concretas corresponden (consentimiento, registro del banco de datos) y no se asume cumplimiento.

@tabla Activos principales
| Activo | Clasificación | Dónde vive | Riesgo principal |
|---|---|---|---|
| Marcaciones y ubicaciones | Confidencial (datos personales) | PostgreSQL de los nodos; respaldos en Blob | Acceso indebido, pérdida, divulgación |
| Credenciales y claves públicas WebAuthn | Confidencial | PostgreSQL | Robo, enumeración, fuerza bruta |
| Secretos (JWT, base de datos, replicación) | Secreto | `.env` de cada nodo | Fuga, reutilización |
| Claves TLS y SSH | Secreto | Nodos y testigo | Copia indebida |
| Respaldos | Confidencial | Azure Blob | Exposición; restauración no probada |
| Código e imágenes | Interno | GitHub (repositorio público) | Manipulación de la cadena de suministro |

## 5.2 Riesgos de la arquitectura de tres servidores

La tabla muestra el estado **real**, no el planificado.

@tabla Riesgos de la arquitectura y su estado
| ID | Riesgo | Control | Estado |
|---|---|---|---|
| R1 | Copiar certificado y secretos entre nodos amplía la superficie de secretos | Secretos con permisos 600, generados al azar en cada nodo; sin Key Vault | **Parcial** |
| R2 | *Split-brain* en la base de datos | Un solo escritor, *fencing*, `targetServerType=primary`, alertas `SinPrimaria` y `DosPrimarias` | **Parcial** (sin quórum automático) |
| R3 | Tráfico de replicación y de aplicación a base de datos sin cifrar | TLS 1.3 con verificación completa; `pg_hba` rechaza lo no cifrado | **Implementado** |
| R4 | Paneles de monitoreo expuestos | Sin IP pública; acceso por túnel SSH | **Implementado** |
| R5 | Respaldos con credenciales de almacenamiento en un servidor | Identidad administrada con permiso mínimo sobre un contenedor | **Implementado** |
| R6 | SSH abierto a cualquier IP | NSG: puerto 22 solo desde la IP del equipo; autenticación solo por llave | **Implementado** (los demás integrantes deben añadir su IP) |
| R7 | Estado en memoria del backend impide revocar tokens de forma consistente | Estado en PostgreSQL | **Implementado** |
| R8 | Restauración nunca probada | Restauración semanal y medida | **Implementado** (9,4–9,5 s) |
| R9 | Cadena de suministro: imágenes y dependencias | Trivy en integración continua; actualización de dependencias | **Parcial** (no se fijan por digest las imágenes base) |
| R10 | Bitácoras sin alertas de seguridad | Alertas sobre 401 y 429 repetidos | **Parcial** (logs no centralizados) |

## 5.3 Cifrado interno (OWASP A02, ISO 8.24)

El curso anterior dejó el tráfico entre la aplicación y la base como riesgo aceptado. Aquí se corrigió.

**Diseño.** Una autoridad certificadora privada (RSA 3072, 3 años) y un certificado de servidor por nodo (RSA 2048, 1 año) con la **IP del nodo en el nombre alternativo**. La clave de la autoridad vive **solo en el testigo**, nunca en los nodos ni en el repositorio. Se aplicó **de forma gradual** para no romper el clúster en marcha: primero TLS opcional, luego los backends con `sslmode=verify-full`, y solo al final la imposición (`pg_hba` con `hostssl` y una regla que **rechaza** lo no cifrado en la red entre nodos).

@tabla Verificación del cifrado interno (evidencia: `docs/evidencias/failover-4-con-tls-cae-nodo2/`)
| Prueba | Resultado |
|---|---|
| Conexiones de los backends a la primaria | TLS 1.3, `TLS_AES_256_GCM_SHA384` |
| Conexión de replicación | `streaming`, cifrada, TLS 1.3, retraso 0 |
| Cliente **sin TLS** desde el testigo | **Rechazado** por `pg_hba.conf` ("no encryption") |
| `verify-full` con un nombre que no está en el certificado | **Rechazado** (el nombre no coincide) |
| `verify-full` correcto | Conectado, TLS 1.3 |
| **Failover completo con TLS exigido** | `pg_rewind` correcto; RPO 0; RTO 35,4 s |
| Respaldo y restauración con `verify-full` | Correctos |

**Límites.** Los certificados caducan en 1 año y la autoridad en 3; **no hay renovación automática**. La clave privada de cada servidor está en disco, sin HSM ni Key Vault. Los exportadores y el socket Unix hablan dentro del mismo nodo sin TLS: es tráfico que no sale de la máquina.

## 5.4 Vulnerabilidades de componentes (OWASP A06, ISO 8.8)

Se escanean con **Trivy** el código (dependencias de Maven y npm, y secretos) y las **cuatro imágenes** del proyecto, en **cada cambio, en cada *pull request* y cada lunes**, con integración continua (`.github/workflows/seguridad.yml`). El escaneo falla ante cualquier hallazgo HIGH o CRITICAL que no esté aceptado por escrito.

@tabla Vulnerabilidades HIGH y CRITICAL por imagen
| Imagen | Antes | Ahora | Qué se hizo |
|---|---|---|---|
| Backend | 51 (11 críticas) | **4** (2 críticas) | Spring Boot 3.3.4 a 3.5.14; parches de Tomcat, Jackson, Spring Framework, PostgreSQL JDBC y Micrometer; Spring Data y Guava fijados. Las 329 pruebas siguen en verde |
| Frontends | 68 (3 críticas) | **0** | `apk upgrade` sobre la imagen sin privilegios |
| Proxy | 70 (3 críticas) | **0** | Imagen construida con su propio Dockerfile y `apk upgrade` |
| PostGIS (imagen ajena) | 391 (29 críticas) | **sin cambios** | **Riesgo aceptado**: 238 sin corrección disponible; no está expuesta a Internet |

**Los 4 hallazgos del backend se aceptan por escrito** en `.trivyignore.yaml`, cada uno con su motivo y una **fecha de caducidad** (2026-12-31): al vencer, vuelven a fallar el escaneo y obligan a revisarlos. Son dos críticos de `spring-webmvc` (la corrección solo existe en Spring Framework 7, un salto de versión mayor) y dos de `httpcore5` (dependencias transitivas de la librería WebAuthn). Los motivos se comprobaron buscando en el código: no hay vistas XSLT, SSE ni WebFlux, y el cliente HTTP propio del proyecto es el del JDK. **Es una búsqueda, no un análisis de alcance completo.**

> **Decisión sobre la herramienta.** En marzo de 2026 se comprometieron casi todas las etiquetas de la acción `aquasecurity/trivy-action` y se publicó un binario malicioso de Trivy (v0.69.4) ([aviso oficial](https://github.com/aquasecurity/trivy/security/advisories/GHSA-69fq-xp46-6x23)). Por eso el CI no usa esa acción: ejecuta la **imagen oficial de Trivy 0.57.1 fijada por su digest**, que no puede ser reemplazada moviendo una etiqueta. Es una lección práctica de la cadena de suministro (A08) aplicada a la propia herramienta de seguridad.

## 5.5 OWASP Top 10 (2021) aplicado

@tabla Correspondencia con OWASP Top 10 y estado real
| Riesgo | Estado | Controles |
|---|---|---|
| **A01 Control de acceso** | Parcial | Roles y autorización en Spring Security; rol de respaldo de solo lectura; rol del exportador solo con `pg_monitor`; `pg_hba` por CIDR. **Pendiente:** el rol con el que corre la aplicación todavía es el propietario (puede ejecutar DDL) y falta la matriz automática de roles por endpoint |
| **A02 Fallas criptográficas** | Implementado | TLS 1.3 verificado, SCRAM-SHA-256, tokens guardados como huella SHA-256 (sección 5.3) |
| **A03 Inyección** | Heredado | Consultas parametrizadas con JPA (del curso anterior; no se volvió a auditar) |
| **A04 Diseño inseguro** | Parcial | Un solo escritor con *fencing*; RTO y RPO medidos. **Falta** un modelo de amenazas formal |
| **A05 Configuración incorrecta** | Implementado | Sin IP pública en nodos ni testigo; SSH restringido; contenedores sin privilegios con capacidades descartadas; límites de recursos; PostgreSQL no se abre a Internet |
| **A06 Componentes vulnerables** | Implementado | Trivy en CI y semanal; excepciones con caducidad (sección 5.4) |
| **A07 Fallos de autenticación** | Parcial | SSH solo con llave; secretos aleatorios; límite de intentos compartido entre nodos. **Pendiente:** segundo factor para supervisores y Recursos Humanos |
| **A08 Integridad de software y datos** | Parcial | Huella SHA-256 de cada respaldo (se rechaza uno manipulado); Trivy fijado por digest. **Faltan:** firma de imágenes y fijar por digest las imágenes base |
| **A09 Registro y monitoreo** | Parcial | 17 alertas, incluidas las de autenticaciones fallidas y peticiones bloqueadas. **Los logs no están centralizados** |
| **A10 SSRF** | No aplica | La aplicación no hace peticiones a destinos indicados por el usuario |

## 5.6 ISO/IEC 27001:2022: controles del Anexo A seleccionados

@tabla Controles del Anexo A y su estado
| Control | Aplicación | Estado |
|---|---|---|
| 5.30 Preparación de las TIC para la continuidad | Failover, respaldos y DRP con tiempos medidos | **Implementado** |
| 8.8 Gestión de vulnerabilidades técnicas | Trivy en CI y semanal; actualización de dependencias | **Implementado** |
| 8.13 Respaldo de la información | Cada hora a Blob, restauración medida | **Implementado** |
| 8.14 Redundancia de las instalaciones | Dos nodos activos, balanceador con sondeo, réplica con promoción | **Implementado** |
| 8.16 Actividades de monitoreo | Prometheus, Grafana y Alertmanager en el testigo | **Implementado** |
| 8.20 a 8.22 Seguridad y segregación de redes | Balanceador como único punto público, SSH restringido | **Parcial** (una sola subred) |
| 8.24 Uso de criptografía | TLS interno verificado | **Implementado** |
| 8.5 Autenticación segura | Llave en SSH, límite de intentos | **Parcial** (sin segundo factor) |
| 8.15 Registro | Registros por nodo; alertas | **Parcial** (sin centralizar) |
| 8.9 Gestión de la configuración | Compose y scripts versionados | **Parcial** (red y nodos sin script) |
| 5.1 Políticas de seguridad | — | **No hecho** (no hay documento de política) |

> **Qué falta para hablar de un SGSI.** Un sistema de gestión real exige además política, roles formalmente asignados, evaluación de riesgos periódica y auditoría interna. Aquí hay un registro de riesgos y controles técnicos con evidencia, **no un SGSI completo**.

## 5.7 Pendientes de seguridad, declarados

- **Segundo factor** para supervisores y Recursos Humanos (queda como riesgo aceptado).
- **Rol de base de datos de ejecución sin permisos de DDL** (hoy la aplicación entra como propietario).
- **Prueba ofensiva básica** independiente (autenticación, autorización, cabeceras, límites).
- **Renovación de certificados internos** y gestión de secretos con Key Vault.
- **Política de seguridad** y modelo de amenazas formal.
- **Matriz automática de roles por endpoint.**
