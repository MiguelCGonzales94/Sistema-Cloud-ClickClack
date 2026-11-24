# 1. Fase 1: análisis, virtualización y almacenamiento

## 1.1 Descripción del sistema base

**Objetivo de negocio.** Antes de ClickClak, el control de asistencia se hacía con una hoja de cálculo mensual: cada colaborador la completaba por su cuenta, la enviaba y Recursos Humanos consolidaba los archivos a mano. Ese instrumento es autodeclarado: no produce evidencia verificable de dónde y cuándo se marcó. ClickClak lo reemplaza con **marcaciones desde el dispositivo del colaborador, validadas por ubicación**, con gestión de incidencias (tardanzas, ausencias, permisos) y un panel para supervisores y Recursos Humanos. La organización no dispone de cifras de plantilla ni de volúmenes, así que la demanda se estima con escenarios (sección 1.2).

**Arquitectura inicial.** El *back-end* es una API REST pura sobre Spring Boot, sin vistas del lado del servidor, organizada en capas: controladores (reciben la petición HTTP), servicios (reglas de negocio), repositorios (acceso a datos) y entidades. Dos clientes React consumen esa API: una **aplicación de campo (PWA)** con cola local sin conexión, y un **panel administrativo**. Todo se desplegó en el curso anterior en **una sola máquina virtual** con Docker Compose.

@tabla Componentes del sistema y su tecnología (versión de este proyecto)
| Componente | Tecnología | Función |
|---|---|---|
| Back-end (API REST) | Java 21, Spring Boot 3.5.14, Spring Data JPA, Spring Security, Flyway, Hibernate Spatial | Reglas de negocio, validación espacial, autenticación y autorización, auditoría y persistencia |
| Base de datos | PostgreSQL 16 con PostGIS 3.4 | Almacenamiento transaccional y cálculo de distancias geográficas |
| Aplicación de campo (PWA) | React, TypeScript, Vite, Tailwind CSS, Workbox, Dexie.js (IndexedDB), WebAuthn | Marcación del personal de campo con cola local sin conexión |
| Panel administrativo | React, TypeScript, Vite, Tailwind CSS | Gestión de usuarios, sedes, turnos, asignaciones e incidencias |
| Proxy | Nginx | Cifrado en tránsito, cabeceras de seguridad, límites de peticiones y enrutamiento |

> **Punto de partida y qué cambió.** En el curso anterior el backend estaba en Spring Boot 3.3.4 y guardaba cuatro tipos de estado en la memoria del proceso (tokens revocados, intentos fallidos de acceso, tokens de recuperación de clave y desafíos de WebAuthn). Eso impide ejecutar dos instancias coherentes. Es la primera brecha que este proyecto cerró (capítulo 4).

## 1.2 Análisis de requerimientos cloud

### Cómputo, memoria y disco: línea base medida

Los valores siguientes se midieron en el despliegue de una sola VM del curso anterior (Standard_B2als_v2, 2 vCPU y 4 GiB), sin carga de usuarios reales.

@tabla Consumo del sistema en una sola VM (línea base, 3 de octubre de 2026, informe APF2)
| Elemento | Valor medido |
|---|---|
| Back-end | 296,4 MiB de memoria |
| PostgreSQL primaria | 40,9 MiB |
| PostgreSQL réplica local | 20,0 MiB |
| Proxy y dos frontends | ≈ 11,2 MiB en total |
| Sistema completo | 1,2 GiB usados de 3,8 GiB (swap: 80 KiB de 2 GiB) |
| Imágenes | Backend 409 MB; cada frontend 74 MB |
| Disco | 14 % de 61 GB |

**Lectura.** La memoria alcanza con holgura para una instancia de la aplicación más su base, y es el motivo por el que la VM de 4 GiB se mantuvo en lugar de la de 8 GiB (el doble de costo). El recurso que resultó **limitante bajo carga** no fue la memoria sino la **CPU** (capítulo 3).

### Demanda esperada

Se usaron tres escenarios con supuestos declarados: 4 marcaciones por colaborador al día (ingreso, inicio y fin de refrigerio, salida), 312 días de trabajo al año, el 60 % de los ingresos concentrado en 15 minutos y 0,5 KB por marcación con índices. **Los valores deben validarse con la organización.**

@tabla Proyección de demanda y almacenamiento por escenario
| Concepto | Piloto (50) | Operación (200) | Escala (500) |
|---|---|---|---|
| Marcaciones por día | 200 | 800 | 2 000 |
| Pico de ingresos (por minuto) | 2 | 8 | 20 |
| Pico en solicitudes por segundo | 0,03 | 0,13 | 0,33 |
| Filas de marcación por año | 62 400 | 249 600 | 624 000 |
| Almacenamiento anual estimado | 31 MB | 125 MB | 312 MB |

Aun en el escenario de escala el pico de **0,33 solicitudes por segundo** es muy inferior al límite de 20 por segundo que aplica el proxy, y el almacenamiento anual de datos es de unos 312 MB. La capacidad de cómputo y de disco no es el problema de este sistema: **el problema a resolver es la disponibilidad**, es decir, que el servicio siga funcionando cuando algo falla.

### Tráfico de red estimado

> **Estas cifras son estimaciones propias con supuestos declarados; el tráfico real no se midió.** Los supuestos son: la mezcla de operaciones de la prueba de carga (25 % escrituras, así que el escenario de escala implica unas 8 000 solicitudes diarias), 2 KB de media por intercambio (petición y respuesta, con cabeceras) y 0,5 KB por marcación en la base.

@tabla Tráfico de red estimado, escenario de escala (500 colaboradores)
| Flujo | Estimación | Cómo se obtuvo |
|---|---|---|
| Usuarios → aplicación (API) | ≈ 16 MB al día, ≈ 0,5 GB al mes | 8 000 solicitudes × 2 KB |
| Descarga de la aplicación (PWA) | Una vez por dispositivo, luego en caché | Tamaño del paquete **no medido** |
| Replicación primaria → standby | Del orden de unos pocos MB al día | Escrituras de 0,5 KB por marcación más sobrecarga del registro de transacciones; **no medido** |
| Respaldos → Azure Blob | ≈ 1,5 MB al día | 24 respaldos de ≈ 65 KB (**medido**) |
| Monitoreo (testigo → nodos) | Probablemente el flujo mayor, interno | Recolección cada 10 s de 13 objetivos; **no medido** |

Según la tarifa de Azure no se cobra el tráfico dentro de una misma red virtual y el volumen saliente a Internet es pequeño; **no se verificó en Cost Management**. La conclusión que importa: **el ancho de banda no limita el diseño**; lo hacen la CPU y la disponibilidad.

### Requerimientos de disponibilidad derivados

De la guía del proyecto y del análisis anterior se fijaron los requerimientos que guían el diseño. Son objetivos de diseño, no un acuerdo de nivel de servicio firmado con una organización.

@tabla Requerimientos de disponibilidad y cómo se cubren
| # | Requerimiento | Cubierto por |
|---|---|---|
| RC1 | El servicio sigue respondiendo si cae un servidor o un backend | Dos nodos activos tras un balanceador con sondeo de salud |
| RC2 | La caída de la base de datos primaria se recupera sin perder escrituras confirmadas | Réplica en streaming y promoción guionizada con *fencing* |
| RC3 | Un error humano (borrado accidental) es recuperable | Respaldos externos con restauración probada |
| RC4 | Dos instancias del backend son coherentes entre sí | Estado compartido en PostgreSQL, sin memoria local |
| RC5 | Se puede observar la salud del sistema, también durante una falla | Monitoreo fuera de los nodos de aplicación |
| RC6 | El tráfico entre componentes no viaja en claro | TLS interno verificado |

## 1.3 Estrategia de virtualización y almacenamiento

### Modelo de despliegue: IaaS, PaaS o híbrido

> **Límite de esta comparación.** No pude verificar la disponibilidad ni el precio de **Azure Database for PostgreSQL (servicio administrado)** ni de plataformas de aplicación administradas en **Chile Central**: la consulta de precios no devolvió resultados. Por eso la columna PaaS es cualitativa y no se afirma su costo.

@tabla Comparación de modelos de despliegue
| Criterio | IaaS (VM + contenedores) | PaaS (servicios administrados) | Híbrido (app en VM, base administrada) |
|---|---|---|---|
| Control de replicación y failover | **Total**: scripts propios, se demuestran y miden | El proveedor lo gestiona; poco que mostrar | Solo para la base, administrada |
| Soporte de PostGIS y versión exacta | Imagen elegida por el equipo (PostGIS 3.4) | No verificado en esta suscripción | Idem |
| Costo con USD 79 de crédito | Calculado con precios de lista (capítulo 6) | **No verificado** | **No verificado** |
| Esfuerzo de operación | Alto: parches, respaldos, seguridad del sistema operativo | Bajo | Medio |
| Portabilidad | Alta: los contenedores corren en cualquier nube | Menor: atado a servicios concretos | Media |
| Encaje con lo que evalúa el curso | **Alto**: balanceo, replicación, DRP y monitoreo propios | Bajo: se delega justo lo que se debe demostrar | Medio |

**Decisión: IaaS con contenedores.** Las razones, en orden de peso: (1) el curso evalúa precisamente replicación, tolerancia a fallos y recuperación ante desastres, que en un servicio administrado quedarían ocultas tras el proveedor; (2) el sistema ya estaba empaquetado con Docker Compose, sin cambios de código; (3) el control sobre PostGIS y sus versiones; (4) la portabilidad. **El costo de esta decisión** es asumir la operación: parches, respaldos y seguridad del sistema operativo son responsabilidad del equipo (modelo de responsabilidad compartida), y el failover es guionizado, no automático (capítulo 4). Un servicio administrado ofrecería alta disponibilidad con menos esfuerzo; si el sistema pasara a producción real, sería la primera alternativa a evaluar.

### Tipo de almacenamiento

@tabla Opciones de almacenamiento evaluadas
| Necesidad | Opción elegida | Por qué | Alternativa descartada |
|---|---|---|---|
| Marcaciones, usuarios, incidencias, ubicaciones | **PostgreSQL 16 con PostGIS** (SQL) | Transacciones ACID, restricciones de integridad (por ejemplo la unicidad del identificador de cliente que da idempotencia) y consultas de distancia geográfica | Bases NoSQL en la nube (Cosmos DB, Datastore): sin la validación espacial ni las restricciones relacionales que el modelo ya usa. Cloud Spanner pertenece a otra plataforma |
| Respaldos de la base | **Azure Blob Storage** (contenedor privado, nivel Hot) | Almacenamiento de objetos barato, cifrado en reposo, ciclo de vida para la retención de 14 días y acceso por identidad administrada | Discos adicionales o Azure Files: más caros y sin ciclo de vida nativo |
| Sistema operativo y datos de cada VM | Disco Standard SSD de 64 GiB (LRS) | Suficiente: la base ocupa unos 20 MB y el sistema el 14 % del disco | Discos Premium: costo sin beneficio para esta carga |

### Decisión de topología: tres servidores

Se compararon cuatro topologías. La elegida es la **opción C**: dos nodos idénticos con la aplicación y la base replicada, más un tercer servidor *testigo*.

@tabla Topologías comparadas
| | A. 2 servidores | B. 2 de aplicación + 1 de base | **C. 2 nodos + testigo (elegida)** | D. 2 de aplicación + base primaria y réplica |
|---|---|---|---|---|
| Servidores | 2 | 3 | 3 | 4 |
| Tolerancia a fallos de datos | Réplica en el otro nodo | **Punto único de falla** | Réplica en el otro nodo | Réplica dedicada |
| Monitoreo sobrevive a la caída de un nodo | No | Parcial | **Sí** | Parcial |
| Nodos idénticos y reemplazables | No exactamente | Sí | **Sí** | Sí |
| Costo, 120 h de pruebas (USD, lista) | ≈ 35,9 | ≈ 49,0 | ≈ 49,0 | ≈ 62,0 |

Una base dedicada sola (B) no da tolerancia a fallos: solo mueve el punto único de falla. El testigo se eligió porque el monitoreo debe vivir **fuera del dominio de falla** de lo que vigila: si Prometheus y Grafana corrieran en un nodo y este cayera, la demostración quedaría a ciegas justo cuando se provoca la falla.

> **Qué es y qué no es el testigo.** El tercer servidor aloja el monitoreo, los respaldos y la generación de carga. **No es todavía un votante de quórum**: la promoción de la base ante una caída es manual y guionizada, no automática. Con dos nodos de base y un testigo sin base de datos no hay mayoría para decidir solo; un gestor como Patroni con etcd o pg_auto_failover lo automatizaría y es la mejora natural (sección 4.6).
