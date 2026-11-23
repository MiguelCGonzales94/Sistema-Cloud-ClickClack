# ClickClak Cloud — Endurecimiento de seguridad (F5): TLS interno, vulnerabilidades y acceso

Fecha: 2026-11-23 · Marco: OWASP Top 10 (2021) e ISO/IEC 27001:2022 · Complementa `SEGURIDAD_ISO27001_OWASP.md`

## 1. Resumen

| Control | Antes | Ahora | OWASP / ISO |
|---|---|---|---|
| Tráfico aplicación → base de datos | Sin cifrar (SCRAM por red privada) | **TLS 1.3 con `verify-full`** (cadena e IP del certificado) | A02 · 8.24 |
| Replicación primaria → standby | Sin cifrar | **TLS 1.3 verificado**; `pg_hba` **rechaza** lo que llegue sin cifrar por la red entre nodos | A02 · 8.24 |
| Vulnerabilidades HIGH/CRITICAL de las imágenes | Backend 51, frontends 68, proxy 70 | Backend **7**, frontends **0**, proxy **0** | A06 · 8.8 |
| SSH a los nodos | Abierto a cualquier IP (solo llave) | Restringido a la IP del equipo (NSG) | A05 · 6.7 |
| Prueba de humo del despliegue | 52 comprobaciones, replicación local | **66–69 comprobaciones**, replicación entre nodos y TLS | 8.29 |

## 2. TLS interno (A02 / ISO 8.24)

**Diseño.** CA privada propia (RSA 3072, 3 años) y un certificado de servidor por nodo (RSA 2048, 1 año) con la **IP del nodo en el SAN** (`10.0.0.4` y `10.0.0.5`). La clave de la CA vive **solo en el testigo** (`~/pki`, permisos 600), nunca en los nodos ni en el repositorio. Cada nodo recibe `ca.crt`, `server.crt` y `server.key` en `/etc/clickclak/tls-bd` (la clave como `root:999`, modo 640, que PostgreSQL acepta).

**Aplicación gradual** (para no romper el clúster en marcha):
1. **TLS opcional** en ambos PostgreSQL (`ssl=on`, TLS ≥ 1.2); los clientes antiguos siguen conectando.
2. **Backends con `sslmode=verify-full`** y la CA montada (reinicio en rotación, sin cortar el servicio).
3. **Replicación con `verify-full`** (`primary_conninfo` de la standby) y, **solo entonces**, la imposición: `hostssl` para la replicación y `hostnossl … 10.0.0.0/24 reject` **al principio** de `pg_hba.conf`.

**Verificación.**

| Prueba | Resultado |
|---|---|
| Conexiones de los backends a la primaria (`pg_stat_ssl`) | TLSv1.3, `TLS_AES_256_GCM_SHA384` |
| Conexión de replicación (`pg_stat_replication` + `pg_stat_ssl`) | `streaming`, `ssl = t`, TLSv1.3, retraso 0 |
| Cliente sin TLS desde el testigo (`sslmode=disable`) | **Rechazado:** `pg_hba.conf rejects connection … no encryption` |
| Cliente con `verify-full` y la CA | Conectado, TLSv1.3 |
| `verify-full` con un nombre que no está en el certificado | **Rechazado:** `server certificate … does not match host name` |
| **Failover completo con TLS exigido** (cae la primaria; `docs/evidencias/failover-4-con-tls-cae-nodo2/`) | `pg_rewind` con TLS terminó bien (119 de 185 MB), **RPO 0**, RTO 35,4 s, roles restituidos, replicación `streaming` cifrada |
| Respaldo y restauración con `verify-full` | Correctos (restauración 1,7 s, conteos iguales) |

**Lo que NO se cifra, y por qué:** el exportador de PostgreSQL y el socket Unix se conectan **dentro del mismo nodo** (red de Docker / socket); la regla de rechazo solo cubre la red entre nodos. Es tráfico que no sale de la máquina.

**Operación y límites.**
- Los certificados caducan en 1 año y la CA en 3: hay que renovarlos antes (el CA y su clave están en el testigo). No hay renovación automática.
- Una standby reconstruida con `pg_basebackup` (`entrada-replica.sh`) y una reincorporada con `pg_rewind` (`reincorporar.sh`) ya escriben su conexión con `verify-full`.
- La clave privada del servidor está en disco en cada nodo (sin HSM ni Key Vault).

## 3. Vulnerabilidades de componentes (A06 / ISO 8.8)

Escaneo con **Trivy 0.57** de las imágenes en los nodos (solo HIGH y CRITICAL).

| Imagen | Antes | Después | Qué se hizo |
|---|---|---|---|
| `clickclak-backend` | 51 (11 críticas) | **7** (2 críticas) | Spring Boot **3.3.4 → 3.5.14** y parches de Tomcat (10.1.30→10.1.59), Jackson (2.17.2→2.21.7), Spring Framework (6.1.13→6.2.19), JDBC de PostgreSQL (42.7.4→42.7.12) y Micrometer |
| `clickclak-frontend-admin` / `campo` | 68 (3 críticas) | **0** | `apk upgrade` sobre la imagen `nginx-unprivileged` (se vuelve al usuario 101) |
| Proxy (`nginx:1.27-alpine`) | 70 (3 críticas) | **0** | Imagen construida con su propio `Dockerfile` y `apk upgrade` |
| `postgis/postgis:16-3.4` | 391 (29 críticas) | **sin cambios** | **Riesgo aceptado** (ver abajo) |

**Cómo se hizo:** la actualización de Spring Boot es un salto de dos versiones menores y se hizo con red de seguridad: copia del `pom`, **329 pruebas** como criterio de aceptación (todas en verde, sin cambiar código), despliegue en rotación y rescaneo. Los parches se fijan como propiedades del `pom`.

**Lo que queda (y por qué):**
- **Backend, 7 hallazgos:** `spring-webmvc` (2 críticas, corrección solo en Spring Framework 7, salto de versión mayor); `guava`, `httpcore5` (dependencias transitivas de la librería WebAuthn, sin corrección compatible en su línea) y `spring-data-commons` (corrección de parche disponible, no aplicada).
- **`postgis`: 238 de 391 sin corrección disponible** (base Debian); el contenedor **no está expuesto a Internet** (solo red privada), exige **TLS** y SCRAM, y se acota con NSG y `pg_hba`. Se declara como riesgo aceptado; la mitigación de fondo es migrar a una versión más nueva de la imagen y reescanear.
- El escaneo es **manual**: aún no está integrado en un pipeline de CI que lo ejecute en cada cambio (no existe repositorio remoto todavía).

## 4. Acceso SSH (A05 / ISO 6.7)

El NSG de los nodos pasó de `22 ← *` a `22 ← IP del equipo`; el testigo ya tenía su regla propia. El SSH entra por las reglas NAT del balanceador (puertos 2201 a 2203). **Límite:** si cambia la IP del equipo, el acceso se pierde hasta actualizar la regla (`az network nsg rule update`, que no necesita SSH); los demás integrantes deben añadir su IP.

## 5. Prueba de humo del despliegue (ISO 8.29)

El script `infra/scripts/verificar-despliegue.sh` ahora reconoce el diseño de dos nodos y llama a `verificar-replicacion-nodos.sh`, que comprueba según el rol del nodo: primaria o standby, `streaming`, **conexión de replicación cifrada**, retraso, ranura activa, rol de respaldo de solo lectura, regla de rechazo sin cifrar, `ssl = on` y `wal_log_hints = on`.

| Nodo | Aciertos | Fallos |
|---|---|---|
| Nodo 1 (primaria) | 69 | 0 |
| Nodo 2 (standby) | 66 | 0 |

## 6. Errores míos durante la F5 (corregidos)

- Un script de parche con un error de sintaxis **no aplicó ningún cambio** y mis comprobaciones posteriores "OK" eran de archivos sin tocar; se detectó al revisar que el contador de `ssl=on` era cero y se rehízo.
- Mi primera prueba negativa de `verify-full` usaba la misma IP en los dos parámetros, así que *debía* conectar; se rehízo con un nombre ajeno al certificado.
- Los sondeos con `pgrep -f` se emparejaban con su propia línea de comandos; se pasó a un archivo marcador de fin.
- La prueba de humo ejecutada dos veces seguidas dio fallos falsos por el **límite de peticiones del proxy** (el propio control de seguridad); se espera a que se libere el cupo.
- El rol de primaria no desactivaba la réplica local heredada y `desplegar.sh` la arrancó; ambos roles la desactivan ahora.

## 7. Qué sigue pendiente de la F5

- **Segundo factor** para supervisores y RR. HH. (pendiente del APF2; se declarará como riesgo aceptado si no hay tiempo).
- **Rol de base de datos de ejecución sin DDL** (hoy la aplicación entra como propietario).
- **Escaneo en CI** y **prueba ofensiva básica** independiente.
- Renovación de certificados internos y gestión de secretos con Key Vault.
