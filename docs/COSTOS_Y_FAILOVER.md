# ClickClak Cloud — Costos, replicación de datos y failover

Fecha: 2026-11-22 · Estado: **análisis**, nada creado en Azure todavía.

## 1. Costos validados (Chile Central, USD)

Fuente: API pública de precios de Azure (`prices.azure.com`, consultada el 2026-11-22) y el selector de tamaños del portal. Son **precios de lista**; la cifra final aparece en Cost Management.

| Recurso | Precio | Mensual 24/7 | Se cobra apagada |
|---|---|---|---|
| VM `B2als_v2` (2 vCPU, 4 GiB) | 0,0526 /h | 38,40 | No (desasignada) |
| VM `B2ats_v2` (2 vCPU, 1 GiB) | — (portal) | 9,64 | No |
| Disco Standard SSD E6 (64 GiB, LRS) | 6,72 /mes | 6,72 | **Sí** |
| IP pública Basic estática (la actual) | 0,0036 /h | 2,63 | **Sí** |
| IP pública Standard estática | 0,005 /h | 3,65 | **Sí** |
| Load Balancer Standard (hasta 5 reglas) | 0,025 /h | 18,25 | Mientras exista |
| Load Balancer: datos procesados | 0,005 /GB | despreciable | — |
| Traffic Manager: punto de conexión Azure | 0,36 /mes c/u | ~0,72 (2) | — |
| Traffic Manager: consultas DNS | 0,54 /millón | despreciable | — |
| Blob Hot LRS (respaldos) | ~0,024–0,026 /GB·mes | centavos | — |
| Snapshot de disco | por GB usado; HDD LRS 0,07 /GB·mes como cota | < 4,5 si se conserva | Sí |

Comprobaciones: 0,0526 × 730 h = 38,40 (coincide con el portal); la IP actual a 2,63 coincide con los USD 2,64 de noviembre.

**No verificado:** el precio de Azure Database for PostgreSQL (servicio administrado) en Chile Central; la consulta no devolvió resultados.

### Escenarios (crédito disponible: USD 79; noviembre ya consume 9,01)

Fijo con todo apagado = discos + IPs. El Load Balancer se **elimina** al apagar (se recrea con IaC) para no pagarlo parado.

| Escenario | Fijo apagado /mes | Costo por hora encendido | 120 h de pruebas | 7 días 24/7 | Mes completo 24/7 |
|---|---|---|---|---|---|
| Hoy (1 VM) | 9,35 | 0,0526 | ~15,7 | ~18,2 | ~47,8 |
| **A. 2 nodos idénticos + LB Standard** | 19,72 | 0,1352 | **~35,9** | ~42,4 | ~118 |
| **B. A + VM de base dedicada (B2ats_v2, 1 GiB)** | 26,44 | 0,1484 | **~44,3** | ~51,3 | ~135 |
| A con Traffic Manager en vez de LB (suma ~0,72 fijo) | 19,72 | 0,1052 | ~33,1 | ~38,1 | ~97 |

Supuestos: 2 discos de 64 GiB, IP de la VM 1 Basic y de la VM 2 Standard, sin tráfico saliente de pago.

Lectura: **ninguna opción aguanta 24/7** con USD 79; con encendido solo para pruebas y sustentación, A cuesta unos USD 36–42 por mes de uso intensivo y B unos USD 44–51. Hay que **apagar y eliminar el LB** al terminar cada sesión, y vigilar la alerta de presupuesto.

## 2. Cómo se replica la base de datos

```
Backend ──escribe──► PRIMARIA (timeline 1)
                         │  WAL por streaming (asíncrono)
                         ▼
                     RÉPLICA (hot standby, solo lectura)
```

- La primaria escribe cada cambio en el **WAL**; la réplica lo recibe por una conexión de replicación y lo reproduce. La réplica es una copia física, siempre un poco detrás.
- Con replicación **asíncrona** (la actual), una transacción se confirma en la primaria sin esperar a la réplica. Si la primaria se pierde de golpe, lo último puede no haber llegado: **RPO > 0**.
- La **ranura de replicación** hace que la primaria guarde el WAL que la réplica aún no leyó. Si la réplica está caída, el WAL se acumula hasta el tope `max_slot_wal_keep_size = 2 GiB`; pasado ese límite la ranura se invalida y la réplica debe reconstruirse.

## 3. ¿Qué pasa si la réplica asume y la primaria vuelve?

Secuencia:

1. La primaria **P** tiene datos hasta el punto X; la réplica **R** va un poco atrás (X − δ).
2. P se apaga. Se **promueve** R: abre una **nueva línea de tiempo (timeline 2)** y empieza a aceptar escrituras.
3. P se enciende. Cree que sigue siendo la primaria en la timeline 1.

Consecuencias:

| Situación | Qué ocurre |
|---|---|
| Datos de P entre X − δ y X (nunca llegaron a R) | Existen solo en P. Si P se reincorpora tal cual, se **descartan**; si importan, hay que rescatarlos antes |
| Datos escritos en R tras la promoción | Existen solo en R (la fuente de verdad ahora) |
| ¿Se puede "reconectar" P a R directamente? | **No.** Las historias divergieron; PostgreSQL lo rechaza por incompatibilidad de timeline |
| Si P y R reciben escrituras a la vez | **Split-brain:** dos verdades irreconciliables. Es el peor caso |

**Riesgo concreto en este proyecto:** el compose usa `restart: unless-stopped`, y desplegar de nuevo "levantaría la primaria anterior". Al encender la VM 1 su PostgreSQL arrancaría como primaria. Hay que **cercar** (fencing) el nodo viejo antes de encenderlo.

### Procedimiento recomendado tras un failover

1. **Cercar P:** mantenerla apagada o con PostgreSQL detenido y fuera del balanceador. Nada debe escribir en ella.
2. (Opcional) **Rescatar** lo no replicado de P si importa: revisar su WAL final o comparar tablas con R.
3. **Reincorporar P como réplica de R**, con una de dos vías:
   - `pg_rewind`: la rebobina hasta el punto de divergencia y la deja seguir a R. Exige `wal_log_hints = on` o checksums de datos **configurados antes** del fallo.
   - Reconstrucción completa con `pg_basebackup` (lo que ya hace `entrada-replica.sh`): más lento, siempre funciona.
4. Ahora los **roles quedaron intercambiados**: R es la primaria y P la réplica. **No se hace fail-back automático**; se vuelve al diseño original, si se quiere, con un *switchover* planificado.
5. Verificar con el script de réplica y la prueba de humo.

### Buenas prácticas para este caso

- **Un solo escritor** y **fencing** explícito antes de cualquier promoción.
- Activar `wal_log_hints` (o `data_checksums`) **desde ahora**, para poder usar `pg_rewind`.
- Replicación síncrona (`synchronous_commit` con una réplica síncrona) da **RPO 0**, pero bloquea las escrituras si la réplica cae; con 2 nodos es un compromiso a declarar. Alternativa: dejar asíncrona y documentar el RPO medido.
- Herramientas de failover automático (Patroni con etcd, repmgr con testigo, pg_auto_failover con nodo monitor) necesitan un **tercer** componente de quórum. Con 2 nodos la promoción debe ser **guionizada y ensayada**, no automática.
- Monitorear retraso y desconexión de la réplica (alerta) y **respaldos externos** a Blob: la réplica copia también un `DELETE` equivocado, no es un respaldo.

## 4. Opción de "una base dedicada a la que apuntan ambos nodos"

| | Base en un nodo (primaria en nodo 1, standby en nodo 2) | **Base dedicada** (`vm-db`) a la que apuntan nodo 1 y nodo 2 |
|---|---|---|
| Fuente de verdad | Una (la primaria) | Una (`vm-db`) |
| Nodos de aplicación | No son idénticos: el nodo 1 aloja la primaria | **Idénticos y sin estado** |
| Seguridad | Base accesible desde la red de los nodos | Base en **subred privada**, sin IP pública, NSG que solo admite los nodos |
| Punto único de falla | Se cubre con el standby | `vm-db` lo es, **salvo que se le añada standby** |
| Costo | Menor | +~USD 8–12 por mes de uso (Escenario B) |

La base dedicada sola **no resuelve** la tolerancia a fallos; resuelve la consistencia y la seguridad. Combinada con un standby (en el nodo 2) da el mejor resultado: aplicación activa-activa, datos con un único escritor y recuperación ante la pérdida de `vm-db`.

## 5. OWASP Top 10 (2021) aplicado al servidor de datos

Se usa la edición 2021.

| Riesgo | Control para la base y su servidor |
|---|---|
| **A01 Control de acceso** | Rol de ejecución sin superusuario ni DDL; rol de migración (Flyway) aparte; rol de replicación solo `REPLICATION`; `pg_hba` por CIDR; NSG: 5432 solo desde los nodos |
| **A02 Fallas criptográficas** | TLS entre aplicación → BD y primaria → réplica (al iniciar el proyecto no iba cifrado: se corrige aquí); SCRAM-SHA-256; discos y Blob cifrados en reposo; respaldos cifrados |
| **A03 Inyección** | Consultas parametrizadas (JPA); el rol de ejecución no puede usar `COPY PROGRAM`; sin SQL dinámico |
| **A04 Diseño inseguro** | Modelo de amenazas del servidor de datos; un solo escritor con fencing; RPO/RTO definidos y medidos |
| **A05 Configuración incorrecta** | Sin IP ni puerto público para la BD; `listen_addresses` restringido; revisar el permiso `CONNECT` a PUBLIC (hallazgo de la revisión inicial, por verificar); NSG de denegación por defecto; contenedor no root |
| **A06 Componentes vulnerables** | Imagen `postgis` fijada por versión y digest; escaneo con Trivy en el CI; plan de actualización |
| **A07 Fallas de autenticación** | Contraseñas generadas y rotadas, sin credenciales por defecto; SSH solo con llave y `fail2ban`; acceso a `vm-db` por salto desde un nodo |
| **A08 Integridad de software y datos** | Imágenes versionadas desde registro; `data_checksums`; `pg_verifybackup` en cada respaldo; scripts de despliegue bajo control de versiones |
| **A09 Registro y monitoreo** | `log_connections`, `log_disconnections`, fallos de autenticación; alertas de retraso de réplica y de accesos fallidos en Grafana |
| **A10 SSRF** | La BD sin salida a Internet arbitraria; extensiones como `dblink`/`postgres_fdw` deshabilitadas; validación de URLs en la aplicación |

## 6. Pendientes de verificar antes de crear nada

- Cuota de vCPU en Chile Central (la tabla del portal no cargó).
- Zona de disponibilidad de `vm-clickclak` y si el snapshot puede crear la VM 2 en otra zona.
- Que el estado del backend en memoria se externalice antes de balancear (ver `ARQUITECTURA_OBJETIVO.md`).
- Precio y disponibilidad del PostgreSQL administrado en Chile Central, para citarlo como alternativa PaaS en la Fase 1.
