# ClickClak Cloud — Pruebas de carga y escalabilidad (k6)

Fecha: 2026-11-23 · Herramienta: k6 0.54 (contenedor en el testigo, dentro de la VNet) · Evidencia: `docs/evidencias/pruebas-de-carga/` · Guiones: `infra/carga/`

## 1. Qué se midió y cómo

- **Operación real de un colaborador** autenticado: 45 % `GET /api/auth/yo`, 15 % `GET /api/incidencias/mias`, 15 % `GET /api/asignaciones/mias` y **25 % `POST /api/marcaciones`** (escritura con validación espacial e idempotencia). Cada petición verifica el JWT y consulta la lista de tokens revocados **en PostgreSQL**, así que ejercita el diseño sin estado.
- **Dos configuraciones:** *1 instancia* (solo el backend del nodo 2) y *2 instancias* (los dos nodos). Cada usuario virtual se fija a un backend (`VU mod n`), como lo haría el reparto del balanceador.
- **Un único inicio de sesión** por prueba, hecho en la **primera** instancia; el token se usa luego contra la segunda: comprueba que la sesión vale en cualquier nodo (secreto JWT común y revocados compartidos).
- **Criterio de aceptación** fijado antes de las pruebas: p95 < 2 s y menos de 1 % de errores.
- **Instantánea de Prometheus** de cada prueba: CPU y memoria máximas por nodo, p95 medido por el backend, conexiones del pool Hikari y de PostgreSQL.

### Decisiones de método (declaradas)

| Parámetro | Decisión | Motivo |
|---|---|---|
| Duración de P1 | 3 min | Crédito y tiempo de la semana |
| Forma de P2 | rampa de 2 min y 1 min sostenido hasta 50 usuarios | Ídem |
| Destino de la carga | **Contra los backends (puerto 8080 privado)** | El proxy limita a 20 peticiones/s por IP (control de seguridad): desde una sola IP se mediría ese límite y no la capacidad. El límite se prueba aparte (P5) |
| Modelo de llegada | **Cerrado** (N usuarios con 0,2–1,5 s de pausa) | Más simple; ver limitación 3 |

## 2. Resultados

| Prueba | Instancias | Peticiones | Req/s | Media | **p95** | Máx. | Errores | Usuarios | CPU máx. | Memoria máx. |
|---|---|---|---|---|---|---|---|---|---|---|
| P1 nominal | 1 | 1 781 | 9,8 | 4,7 ms | **9,3 ms** | 138 ms | 0 % | 10 | 9,6 % | 33 % |
| P1 nominal | 2 | 1 801 | 9,9 | 7,4 ms | **13,8 ms** | 1 150 ms¹ | 0 % | 10 | 14,5 % | 33 % |
| P2 pico | 1 | 9 828 | 49,0 | 3,5 ms | **7,2 ms** | 79 ms | 0 % | 50 | 19,4 % | 33 % |
| P2 pico | 2 | 9 860 | 49,1 | 4,6 ms | **9,6 ms** | 196 ms | 0 % | 50 | 17,4 % | 33 % |
| P3 ráfaga + repetidos | 2 | 1 981 | 33,0 | 4,2 ms | **8,3 ms** | 81 ms | 0 % | 60 | 9,0 % | 36 % |
| **P4 estrés** | **1** | 99 083 | 404 | 11,8 ms | **41,8 ms** | 873 ms | 0 % | 200 | **95,9 %** | 34 % |
| **P4 estrés** | **2** | 102 262 | 417 | 5,2 ms | **11,4 ms** | 85 ms | 0 % | 200 | 81,0 % | 36 % |

¹ Un único valor atípico al abrir la primera conexión a la segunda instancia; el p95 no se ve afectado.

### P3 — ráfaga con identificadores repetidos (idempotencia)
2 000 marcaciones en 60 s sobre un conjunto de 500 `uuidCliente`, repartidas entre las dos instancias. **1 981 peticiones, 0 % de errores; en la base 486 filas = 486 identificadores distintos**: las otras ~1 495 repeticiones se absorbieron sin duplicar ni perder (de 2 000 sorteos sobre 500 se esperan unos 491 distintos).

### P4 — estrés (hasta 200 usuarios, ~400 peticiones/s)

| | 1 instancia | 2 instancias |
|---|---|---|
| p95 | 41,8 ms | **11,4 ms (−73 %)** |
| CPU máxima | **95,9 %** | 81,0 % |
| Conexiones activas del pool (máx. 10 por backend) | 10 (agotado) | 5 |
| **Peticiones esperando conexión** | **46** | **0** |
| Errores | 0 % | 0 % |

### P5 — límite de peticiones del proxy (por la URL pública y el balanceador)
80 peticiones/s durante 20 s desde una sola IP: **1 601 peticiones, 723 respondieron 429** (45 %); el resto 401 (sin token, esperado). El servicio no se degradó (p95 2 ms).

## 3. Lectura de los resultados

1. **El criterio se cumple con un margen enorme.** Hasta 50 usuarios concurrentes (~49 peticiones/s) el p95 es de 7–14 ms frente al límite de 2 s, sin errores. La demanda proyectada para 500 colaboradores era de **0,33 peticiones/s** (escenario de escala del informe): la capacidad medida es ~1 200 veces mayor.
2. **No se llegó a un punto de quiebre por errores:** con 200 usuarios (~400 req/s) hubo 0 % de errores. Lo que sí se encontró es **dónde se satura**: con una instancia, la CPU del nodo llegó al **96 %** (2 vCPU) y el **pool de conexiones de 10 se agotó con 46 peticiones en cola**.
3. **Escalar de 1 a 2 instancias lo resolvió:** el p95 bajó de 41,8 a 11,4 ms (−73 %), la cola del pool desapareció y la CPU bajó a 81 %. El **rendimiento total casi no cambió** (404 → 417 req/s) porque el cliente es de modelo cerrado (usuarios con pausa): lo que se gana es **latencia y holgura**, no más peticiones por segundo con esta generación de carga.
4. **Cuello de botella identificado:** CPU del nodo y tamaño del pool Hikari. El nodo 2 además aloja la **primaria de PostgreSQL**, así que backend y base compiten por la misma CPU; mover la base a un servidor propio (opción B de `DECISION_TOPOLOGIA.md`) es la mejora natural.
5. **La sesión es válida en ambas instancias** (se inició en una y se usó en las dos): demuestra que el estado compartido en PostgreSQL funciona bajo carga.
6. **Idempotencia bajo carga y entre instancias:** sin duplicados ni pérdidas.
7. **El límite del proxy es por nodo.** Se dejaron pasar unas 878 de 1 601 peticiones, que coincide con 2 nodos × (20/s × 20 s + ráfaga de 40) = 880: con dos nodos el límite efectivo por IP **se duplica**. Es un efecto a declarar; un límite compartido exigiría un almacén común.

## 4. Elasticidad y política de escalabilidad

| Dimensión | Lo hecho | Lo no hecho |
|---|---|---|
| Horizontal | Se demostró que **añadir una instancia** reduce el p95 un 73 % bajo estrés y elimina la cola del pool; el backend es sin estado | **No hay autoescalado**: añadir o quitar nodos es manual (los nodos son VM fijas). Azure Virtual Machine Scale Sets lo automatizaría |
| Vertical | Se identificó la CPU como recurso limitante (B2als_v2, 2 vCPU) | No se probó una VM mayor |
| Disparadores propuestos | CPU > 70 % sostenido 5 min, p95 > 1 s, cola del pool > 0 (alertas de Prometheus ya definidas en `alertas.yml`) | No están conectados a ninguna acción automática |
| Costo | Dos nodos: ~USD 0,105/h; una instancia adicional es el escalón de costo | — |

## 5. Limitaciones que se declaran

1. **Duraciones reducidas** (3 min en P1; 3,3 min en P2; 4,5 min en P4) frente a las del plan; no se observó degradación en el tiempo (fugas, agotamiento de créditos).
2. **CPU en ráfaga:** las VM son de la serie B; con CPU al 96 % durante unos minutos no se vio degradación, pero **no pude leer la métrica de créditos de CPU** de Azure, así que el riesgo de limitación por créditos agotados en cargas largas **no está descartado**.
3. **Modelo cerrado de carga:** no se midió cuántas peticiones por segundo aguanta el sistema antes de rechazar (para eso haría falta un modelo de llegada abierto).
4. **Los backends se probaron directamente**, sin el Nginx público ni el TLS; esa ruta solo se ejercitó en P5. La latencia de usuarios reales incluye la red de Internet, que aquí no existe (cliente dentro de la VNet).
5. **Base pequeña** (decenas de miles de filas tras las pruebas; se limpiaron después): con más datos las consultas serán más lentas.
6. **Primer intento de P3 descartado** por un error de método mío (cada usuario virtual de k6 generaba su propio conjunto "aleatorio" de identificadores, así que no había repetidos entre instancias). Se conserva en `p3-intento-1-descartado/` y se repitió con identificadores deterministas.
7. Datos de prueba: se creó un usuario `COLABORADOR` temporal con un dispositivo y **58 933 marcaciones**; todo se eliminó al terminar (la base volvió a 23 marcaciones) y se borraron la clave y el hash del testigo.

## 6. Cómo repetirlo

```bash
# en el testigo (requiere un usuario de prueba con dispositivo; ver docs/evidencias para el procedimiento)
sh ~/carga/ejecutar.sh p2-pico 2-instancias "http://10.0.0.4:8080,http://10.0.0.5:8080"
```
