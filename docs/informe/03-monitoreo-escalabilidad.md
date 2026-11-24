# 3. Monitoreo, métricas y escalabilidad

## 3.1 Monitoreo y métricas

El monitoreo vive en el **servidor testigo**, fuera de los dos nodos de aplicación. Esa separación es deliberada: si el monitoreo estuviera en un nodo y este cayera, la falla provocada en la demostración dejaría al equipo sin ver nada justo cuando más importa.

@tabla Pila de monitoreo
| Pieza | Dónde corre | Qué aporta |
|---|---|---|
| Prometheus 2.53 | Testigo | Recolecta cada 10 s los 13 objetivos y evalúa las alertas |
| Alertmanager | Testigo | Gestiona las alertas disparadas |
| Grafana 11.2 | Testigo | Tablero de 21 paneles, generado por un script versionado (`generar_tablero.py`) |
| `blackbox_exporter` | Testigo | Sonda **desde fuera** la URL pública y cada nodo (disponibilidad y vencimiento del certificado) |
| `node-exporter` 1.8.2 | Cada servidor | CPU, memoria, disco y red de la VM |
| `cAdvisor` 0.49.1 | Nodos | CPU y memoria por contenedor |
| `postgres_exporter` 0.15.0 | Nodos | Estado de PostgreSQL, rol (primaria o réplica), retraso de la replicación y conexiones |
| Micrometer en el backend | Nodos | Latencia de las peticiones HTTP (histograma para el percentil 95), errores por estado y pool de conexiones |

**Acceso y seguridad del monitoreo.** Grafana, Prometheus y Alertmanager solo escuchan en la IP privada del testigo; se abren por un túnel SSH. Las métricas del backend (`/actuator/prometheus`) exigen autenticación HTTP Basic y el proxy no enruta `/actuator`. El rol de base de datos que usa el exportador solo tiene el permiso `pg_monitor`.

**Cobertura de lo que pide la guía.** CPU, memoria y almacenamiento se miden en cada servidor y por contenedor. **Los registros (logs) no están centralizados**: se consultan con `docker logs` y en los registros de Nginx en cada nodo. Se evaluó añadir Loki y se recortó por falta de tiempo; es una limitación declarada.

### Alertas

Hay **17 reglas** de alerta. Se agrupan por lo que protegen:

@tabla Reglas de alerta de Prometheus (umbral y duración que deben mantenerse)
| Grupo | Alerta | Se dispara cuando |
|---|---|---|
| Disponibilidad | `NodoCaido` | El exportador de un servidor no responde durante 30 s |
| | `BackendCaido` | El backend de un nodo no responde durante 20 s |
| | `ServicioPublicoCaido` | La sonda externa a la URL pública falla durante 30 s |
| | `NodoFueraDelReparto` | La sonda a un nodo falla durante 20 s |
| | `CertificadoPorVencer` | El certificado vence en menos de 14 días |
| Recursos | `CpuAlta` | CPU mayor al 85 % durante 5 min |
| | `MemoriaAlta` | Memoria usada mayor al 85 % durante 5 min |
| | `DiscoLleno` | Disco usado por encima del umbral durante 5 min |
| | `LatenciaP95Alta` | El percentil 95 supera 1 s durante 5 min |
| | `ErroresServidorAltos` | Más de 0,2 errores 5xx por segundo durante 3 min |
| Base de datos | `PostgresCaido` | `pg_up` es 0 durante 20 s |
| | `ReplicaDesconectada` | La réplica tiene más de 30 s de retraso durante 1 min |
| | `SinPrimaria` | Ningún nodo es primaria durante 30 s |
| | `DosPrimarias` | Más de un nodo es primaria durante 10 s (**detector de *split-brain***) |
| | `ConexionesBdAltas` | Más de 35 conexiones activas durante 3 min |
| Seguridad | `PicoDeAutenticacionesFallidas` | Más de 20 respuestas 401 en 5 min |
| | `PeticionesBloqueadasPorLimite` | Más de 10 respuestas 429 en 5 min |

La alerta `PostgresCaido` fue la que definió el tiempo de detección en los ensayos de failover (capítulo 4): su duración de 20 s más el ciclo de recolección explican que la detección sea el 85–90 % del tiempo de recuperación.

## 3.2 Pruebas de carga

Se midió con **k6** desde un contenedor en el testigo, dentro de la red virtual. La operación simulada es la de un colaborador autenticado: 45 % consulta de su sesión, 15 % sus incidencias, 15 % sus asignaciones y **25 % marcaciones (escritura con validación espacial e idempotencia)**. Cada petición verifica el token contra la lista de revocados guardada **en PostgreSQL**, de modo que la prueba ejercita el diseño sin estado. Se probaron **una instancia** (solo el backend de un nodo) y **dos** (ambos nodos). El criterio de aceptación es p95 inferior a 2 s y menos de 1 % de errores.

@tabla Resultados de las pruebas de carga (evidencia en `docs/evidencias/pruebas-de-carga/`)
| Prueba | Instancias | Peticiones | Req/s | **p95** | Errores | Usuarios | CPU máx. |
|---|---|---|---|---|---|---|---|
| P1 nominal | 1 | 1 781 | 9,8 | **9,3 ms** | 0 % | 10 | 9,6 % |
| P1 nominal | 2 | 1 801 | 9,9 | **13,8 ms** | 0 % | 10 | 14,5 % |
| P2 pico | 1 | 9 828 | 49,0 | **7,2 ms** | 0 % | 50 | 19,4 % |
| P2 pico | 2 | 9 860 | 49,1 | **9,6 ms** | 0 % | 50 | 17,4 % |
| P3 ráfaga con repetidos | 2 | 1 981 | 33,0 | **8,3 ms** | 0 % | 60 | 9,0 % |
| **P4 estrés** | **1** | 99 083 | 404 | **41,8 ms** | 0 % | 200 | **95,9 %** |
| **P4 estrés** | **2** | 102 262 | 417 | **11,4 ms** | 0 % | 200 | 81,0 % |

**Lectura de los resultados**

1. **El criterio se cumple con un margen enorme.** Hasta 50 usuarios simultáneos el p95 es de 7 a 14 ms frente al límite de 2 s. La demanda proyectada para 500 colaboradores es de 0,33 solicitudes por segundo; la capacidad medida es del orden de mil veces mayor.
2. **No se llegó a un punto de quiebre por errores**: con 200 usuarios (~400 req/s) hubo 0 % de errores. Lo que sí se encontró es **dónde se satura una instancia**: la CPU del nodo llegó al 96 % y el pool de conexiones (10 por backend) se agotó, con **46 peticiones esperando conexión**.
3. **Pasar de una a dos instancias lo resolvió**: el p95 bajó de 41,8 a 11,4 ms (**−73 %**), la cola del pool desapareció (46 a 0) y la CPU bajó al 81 %. El rendimiento total casi no cambió (404 a 417 req/s) porque el cliente es de modelo cerrado: lo que se gana es **latencia y holgura**, no más peticiones por segundo con esta generación de carga.
4. **Idempotencia bajo carga (P3).** Se enviaron 2 000 marcaciones sobre un conjunto de 500 identificadores, repartidas entre las dos instancias: 0 % de errores y **486 filas en la base, una por identificador distinto**. Las repeticiones se absorbieron sin duplicar ni perder datos.
5. **La sesión vale en ambas instancias**: el inicio de sesión se hizo en una y el token se usó en las dos.
6. **Límite de peticiones (P5).** 80 peticiones por segundo desde una sola IP durante 20 s: 723 de 1 601 respondieron 429 (45 %) sin degradar el servicio. Como el límite es **por nodo**, con dos nodos el límite efectivo por IP se **duplica**; un límite compartido exigiría un almacén común.

> **Cómo se declara el método.** Las duraciones fueron más cortas que las del plan original por el crédito y el tiempo disponibles (3 minutos en lugar de 10 en P1). Las pruebas se hicieron **contra los backends directamente** (puerto 8080 privado) y no contra el Nginx público, porque el proxy limita a 20 peticiones por segundo por IP y desde una sola IP se habría medido ese límite en lugar de la capacidad. Un primer intento de P3 se **descartó** por un error de método propio (cada usuario virtual generaba su propio conjunto "aleatorio" de identificadores) y se repitió con identificadores deterministas; ambos se conservan en el repositorio.

## 3.3 Escalabilidad y elasticidad

@tabla Política de escalabilidad: qué se hizo y qué no
| Dimensión | Estrategia | Evidencia o estado |
|---|---|---|
| **Horizontal** | Añadir instancias del backend tras el balanceador. Es posible porque el backend no guarda estado en memoria | **Demostrado**: de 1 a 2 instancias el p95 bajo estrés bajó un 73 % y desapareció la cola del pool. Agregar un tercer nodo se haría clonando una VM, como se hizo con el nodo 2 |
| **Vertical** | Cambiar la VM por una con más vCPU, ya que la CPU es el recurso limitante | **No probado**: se identificó el recurso, no se ensayó una VM mayor |
| **Automática** | Escalado por reglas sobre métricas (por ejemplo con conjuntos de escalado de máquinas virtuales de Azure) | **No implementada**: añadir o quitar nodos es manual; los nodos son VM fijas |
| **Planificada** | Encender o dimensionar según la hora: el 60 % de los ingresos se concentra en 15 minutos | **Propuesta**; hoy solo se enciende y apaga manualmente para ahorrar crédito |

**Disparadores propuestos para escalar:** CPU sostenida por encima del 70 % durante 5 minutos, p95 por encima de 1 s, o peticiones esperando conexión en el pool. Las métricas existen en Prometheus. **La alerta de CPU implementada salta al 85 %**, es decir, más tarde que el umbral de escalado propuesto; ninguno de los dos dispara una acción automática.

**Cuellos de botella identificados.** (1) La **CPU** del nodo: con 2 vCPU, una instancia se acerca al 96 % bajo 200 usuarios. (2) El **pool de conexiones** de 10 por backend. (3) El nodo con la primaria de PostgreSQL también aloja un backend, así que ambos compiten por la misma CPU; separar la base en un servidor propio es la mejora natural.

**Reparto de carga.** El balanceador reparte por una función de dispersión sobre los datos de la conexión, no por "turnos"; la cabecera `X-Nodo` permitió verificar que el tráfico llega a ambos nodos y que, si uno cae, el otro absorbe todo.

> **Lo que no se puede afirmar.** Las máquinas son de la **serie B** (CPU con créditos). Con la CPU al 96 % durante unos minutos no se observó degradación, pero **no se pudo leer la métrica de créditos de CPU** de Azure, así que no está descartado que una carga larga agote los créditos y limite el rendimiento. Tampoco se probó con una base grande: las pruebas usaron decenas de miles de filas, que se eliminaron después.
