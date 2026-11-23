# ClickClak Cloud — Failover y plan de recuperación ante desastres (DRP)

Fecha de los ensayos: 2026-11-23 · Entorno: 2 nodos + testigo en Azure (Chile Central) · Evidencia: `docs/evidencias/`

## 1. Escenarios cubiertos

| # | Escenario | Qué se provoca | Guion | Resultado |
|---|---|---|---|---|
| 1 | Cae un backend | `docker stop` del backend de un nodo | `infra/failover/ensayo-backend.sh` | El balanceador lo saca del reparto; el servicio sigue |
| 2 | Cae la primaria de PostgreSQL | `docker kill` (caída abrupta) con escritura continua | `infra/failover/ensayo-failover.sh` | Promoción de la standby, **RPO 0**, RTO ≈ 30–36 s |
| 3 | Reincorporación del nodo caído | Reconstruir o rebobinar al nodo viejo como standby | `infra/failover/reincorporar.sh` | `pg_rewind` en 12 s |
| 4 | Pérdida de datos o error humano | `DROP TABLE` accidental; restauración desde Azure Blob | `infra/respaldos/respaldar.sh` y `restaurar.sh` | La réplica **copia el borrado**; el respaldo **recupera** los datos (1000 filas) |

## 2. Resultados medidos

### Escenario 2 — caída de la primaria (3 ensayos, con un escritor confirmando ~10 inserciones por segundo)

| Ensayo | Cae | Detección | Promoción | **RTO de escritura** | Servicio público ≠ 200 | **RPO** | Reincorporación |
|---|---|---|---|---|---|---|---|
| 1 | nodo 1 | 26,8 s | 2,6 s | **30,0 s** | 13 de 64 sondas | **0** (178 de 178) | 9,7 s, reconstrucción |
| 2 | nodo 2 | 33,9 s | 2,2 s | **36,4 s** | 18 de 72 sondas | **0** (205 de 205) | 9,7 s, reconstrucción |
| 3 | nodo 1 | 32,7 s | 2,7 s | **35,8 s** | 18 de 71 sondas | **0** (214 de 214) | 12,3 s, **`pg_rewind`** |

- **RTO** = mayor hueco entre dos escrituras confirmadas consecutivas (desde la última antes de la caída hasta la primera tras la promoción).
- **Detección** = tiempo hasta que la alerta `PostgresCaido` de Prometheus entra en disparo (`for: 20 s` más el ciclo de recolección y evaluación). **Es el 85–90 % del RTO**; la promoción en sí tarda ~2,5 s.
- **RPO 0 en los tres ensayos**: todas las escrituras confirmadas al cliente existían en la nueva primaria. Con replicación **asíncrona** esto **no está garantizado**: una caída justo entre la confirmación y el envío del WAL puede perder las últimas transacciones. Las pruebas muestran retraso 0 en reposo y con carga ligera; no son una garantía.
- Cada ensayo cambió el rol de los nodos. Estado final: **nodo 2 = primaria** (línea de tiempo 4), nodo 1 = standby, retraso 0.

### Escenario 1 — caída de un backend (nodo 1)

| Métrica | Valor |
|---|---|
| Sondas públicas totales | 191 |
| Sondas distintas de 200 | 5 (**97,4 % de éxito**) |
| Peticiones fallidas | ~4, todas en los ~10 s previos a que el balanceador reaccionara |
| El balanceador dejó de usar al nodo | ~11 s (sondeo cada 5 s, 2 fallos) |
| Durante la caída respondió | `nodo2` (todo el tráfico restante) |
| El nodo vuelve al reparto | 17,3 s después de arrancar su backend |

### Escenario 4 — respaldos y restauración (Azure Blob)

| Métrica | Valor |
|---|---|
| Frecuencia | cada hora (cron en el testigo) + prueba de restauración semanal |
| Tamaño del respaldo | ~65 KB comprimido (la base pesa ~20 MB; casi todo es el catálogo de PostGIS) |
| Duración del respaldo | 1,4 s en total (1,3 s de volcado + 0,1 s de subida) |
| Restauración (descarga + `pg_restore`) | 0,1 s + 1,8 s; **9,4 s con el arranque de la base descartable** |
| Verificación | SHA-256 (se rechaza un respaldo manipulado: probado) y conteos de 14 tablas **iguales** a producción; PostGIS 3.4.3 |
| Retención | 14 días (política de ciclo de vida de la cuenta) |
| **RPO por respaldo** | hasta 1 h (intervalo del cron); no sustituye a la replicación para fallos de infraestructura |
| **RTO por respaldo** | ~10 s con esta base pequeña, más el tiempo humano de decidir y apuntar la aplicación |

**Prueba del error humano** (`docs/evidencias/respaldo-y-restauracion/escenario-borrado-accidental.txt`): se creó una tabla de 1000 filas, se respaldó, y se ejecutó `DROP TABLE` en la primaria. **La standby también la perdió** (la réplica copió el error: no es un respaldo). La restauración desde Blob devolvió la tabla con sus 1000 filas.

**Diseño y seguridad** (OWASP A02/A05/A07/A08; ISO 27001 8.13, 8.24, 5.17):
- Cuenta privada: TLS 1.2 mínimo, solo HTTPS, sin acceso público a blobs, cifrado en reposo de Azure.
- El testigo sube y lee con su **identidad administrada** y el rol *Storage Blob Data Contributor* limitado a **un solo contenedor**: no hay claves de almacenamiento ni SAS en ninguna VM.
- `pg_dump` usa el rol `respaldo` de **solo lectura** (`pg_read_all_data`) y lee de la **standby** (`prefer-standby`), sin cargar a la primaria.
- La restauración se prueba en un contenedor aislado, sin puertos publicados; nunca sobre producción.
- Infraestructura como código: `infra/azure/respaldos.sh`; scripts en `infra/respaldos/`.

## 3. Procedimiento de recuperación de la base de datos

1. **Detectar:** alerta `PostgresCaido` (o `SinPrimaria`) en Alertmanager / tablero de Grafana.
2. **Aislar al nodo viejo (fencing):** `sh failover/aislar.sh` en el nodo caído. Desactiva el reinicio automático y detiene el contenedor. **Obligatorio antes de promover**: si el nodo viejo vuelve a arrancar como primaria hay dos primarias con historias distintas (split-brain). El script se niega a continuar si no logra detenerlo.
3. **Promover:** `sh failover/promover.sh <IP del nodo viejo> <ranura>` en el nodo standby. Se niega si el nodo no es standby. Hace `pg_promote`, un `CHECKPOINT` (lo exige `pg_rewind`) y deja lista la replicación hacia el nodo viejo.
4. **La aplicación sigue sola:** los dos backends llevan ambos hosts en la URL JDBC con `targetServerType=primary`; no se toca nada.
5. **Reincorporar:** `sh failover/reincorporar.sh <IP de la nueva primaria> <ranura> <rol>` en el nodo viejo. Intenta `pg_rewind` y, si falla, reconstruye con `pg_basebackup`.
6. **Verificar:** `pg_stat_replication` en la primaria (estado `streaming`, retraso 0), `/salud` en 200 en ambos nodos y alertas en calma.
7. **No hay fail-back automático:** los roles quedan intercambiados. Volver al diseño original es un *switchover* planificado, no una urgencia.

## 4. Lecciones aprendidas (útiles para el informe y las preguntas)

1. **`pg_rewind` depende del archivo de control, no del parámetro.** Activar `wal_log_hints = on` y reiniciar no basta: el valor lo lee `pg_rewind` del archivo de control, que solo se actualiza en un **checkpoint**. Tras activarlo hay que ejecutar `CHECKPOINT` y comprobar con `pg_controldata`. El ensayo lo hace como precondición.
2. **La recuperación tras una caída abrupta también puede deshacerlo.** El script completaba la recuperación con `postgres --single`, que arranca **sin** el `-c wal_log_hints=on` del contenedor y reescribe el archivo de control con el valor por defecto (`off`). Corregido con `--single -c wal_log_hints=on`. Los dos primeros ensayos cayeron al camino de reserva (reconstrucción) por este motivo.
3. **El fencing no es opcional.** El compose usa `restart: unless-stopped`; sin `docker update --restart=no`, el nodo caído volvería a levantar su PostgreSQL como primaria.
4. **El tiempo lo domina la detección, no la promoción.** Promover tarda ~2,5 s; detectar con una alerta `for: 20 s` tarda ~27–34 s. Bajar el `for` a 10 s recortaría el RTO a costa de más falsas alarmas.
5. **Con un solo nodo de base de datos caído, el servicio público se cae.** El sondeo `/salud` del balanceador incluye el estado de la base (actuator `db`); sin primaria, los dos nodos fallan el sondeo y el balanceador deja de entregar tráfico nuevo hasta la promoción. Es un RTO real y se declara.
6. **Errores propios que el ensayo destapó** (todos corregidos y versionados; los dos últimos, de los respaldos):
   - El sondeo del balanceador apuntaba a `C:/Program Files/Git/salud`: **Git Bash en Windows convirtió `/salud` en una ruta de Windows**. El balanceador probaba el frontend, no el backend. Se corrigió con `MSYS_NO_PATHCONV=1`.
   - Los frontends del nodo 1 llevaban 30 minutos en estado `Created` sin que nada lo avisara, y el nodo salía del reparto: el sondeo equivocado lo ocultaba y el tablero lo mostró.
   - Editar scripts con Python en Windows (`write_text`) los dejó en **CRLF** y `sh` en la VM falló (`Illegal option -`). Los scripts deben guardarse siempre con LF.
   - `tar` desde Windows perdió el bit de ejecución de `10-seleccionar-certificado.envsh` y el proxy no arrancó; `desplegar.sh` lo reafirma, pero un despliegue manual lo evita.
   - La restauración chocó con la imagen `postgis`: su inicialización ya crea las extensiones (`tiger`) y el respaldo las recrea. Se restaura en una base **vacía** (`template0`).
   - `pg_isready` por socket da por listo un servidor temporal de inicialización que se apaga enseguida; se comprueba por **TCP**.
   - La selección del "último respaldo" elegía cualquier `.dump` que ordenara después alfabéticamente; ahora exige el patrón de nombre de los respaldos reales.
7. **Medir mal también cuenta:** la primera versión del ensayo midió un RTO de 0 s (tomaba la primera escritura posterior a la caída, no el hueco) y la del balanceador contaba respuestas posteriores a la recuperación. Se corrigieron y los resultados se recalcularon a partir de los registros originales.

## 5. Limitaciones que se declaran

- **Replicación asíncrona:** RPO > 0 posible ante una caída justo en el instante de confirmar.
- **Promoción manual guionizada**, no automática: con dos nodos y un testigo sin base de datos no hay quórum para decidir solo. Un gestor (Patroni con etcd o pg_auto_failover) lo automatizaría y es la mejora natural.
- **Respaldos lógicos cada hora:** RPO por respaldo de hasta 1 h; no hay archivado continuo de WAL, así que no permiten recuperar a un instante exacto (PITR). Son un respaldo **lógico** (`pg_dump`): restaurarlo recrea la base, no la reincorpora al clúster. No hay alerta de "respaldo atrasado" todavía.
- La clave del rol `respaldo` está en el testigo (`~/respaldos/secretos`, permisos 600); la subida a Blob no usa claves, la lectura de la base sí.
- Los ensayos usaron carga ligera (~10 escrituras/s) y base pequeña (~110 MB); con bases mayores `pg_rewind` y la reconstrucción tardan más.
- Las VM son de la serie B (CPU en ráfaga): bajo carga sostenida los créditos de CPU pueden limitar el rendimiento.

## 6. Cómo repetirlo en la sustentación

```bash
bash infra/failover/ensayo-backend.sh              # guion 1: cae un backend (~1,5 min)
bash infra/failover/ensayo-failover.sh             # guion 2: cae la primaria (~3 min); MODO=n2-cae si la primaria es el nodo 2
```

Antes de empezar: ambos nodos sanos, `pg_stat_replication` en `streaming`, y el tablero de Grafana abierto (túnel SSH al testigo) para mostrar la caída y la recuperación en vivo.
