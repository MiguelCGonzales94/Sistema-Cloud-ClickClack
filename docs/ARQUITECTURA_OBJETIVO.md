# ClickClak Cloud — Arquitectura objetivo (2 VM)

Estado: **propuesta de diseño**, decidida la dirección (2 VM) el 2026-11-22. Los valores marcados *(por verificar)* no se han comprobado en Azure.

## 1. Idea central

Separar la **capa de aplicación** (sin estado, recuperable por IaC) de la **capa de datos** (con estado, protegida por réplica y respaldos), cada una en su propia subred.

```
Internet
   │ 80/443/8443
┌──▼───────────────── VNet vnet-clickclak 10.10.0.0/16 ──────────────────────┐
│  snet-publica 10.10.1.0/24  (NSG nsg-publica)                              │
│  ┌──────────────── vm-app (IP pública) ─────────────────┐                  │
│  │ nginx (LB, TLS) ─► backend-1, backend-2              │                  │
│  │ frontend-admin, frontend-campo                       │                  │
│  │ prometheus, grafana, cadvisor, node-exporter         │                  │
│  │ postgres-standby (réplica en caliente)               │                  │
│  └───────────────────────┬──────────────────────────────┘                  │
│                          │ 5432 (solo desde snet-publica)                  │
│  snet-privada 10.10.2.0/24  (NSG nsg-privada, sin IP pública)              │
│  ┌──────────────── vm-db ───────────────────────────────┐                  │
│  │ postgres PRIMARIA (PostGIS)                          │                  │
│  │ node-exporter, postgres-exporter                     │                  │
│  │ respaldo programado ─────────► Azure Blob (endpoint) │                  │
│  └──────────────────────────────────────────────────────┘                  │
└────────────────────────────────────────────────────────────────────────────┘
```

## 2. Reparto de componentes

| VM | Subred | Corre | Rol de resiliencia |
|---|---|---|---|
| `vm-app` (actual, Standard_B2als_v2) | `snet-publica` | Nginx, backend ×2, frontends, Prometheus, Grafana, cAdvisor, node-exporter, **réplica** PostgreSQL | Capa sin estado: si cae, se recrea con IaC. Aloja el standby que se promueve si cae `vm-db` |
| `vm-db` (nueva, tamaño pequeño, p. ej. B1ms, *por verificar*) | `snet-privada` | PostgreSQL **primaria**, exporters, tarea de respaldo | Capa de datos aislada, sin IP pública |

Por qué la primaria va en la subred privada y la réplica en la pública: así la base principal nunca queda expuesta, y la réplica queda junto a la aplicación para poder promoverla si se pierde `vm-db`. Contrapartida a declarar en el informe: si cae `vm-app` **y** hay que recuperar datos, se restaura desde la primaria o desde Blob.

## 3. Red y seguridad

| Elemento | Valor |
|---|---|
| Región | Chile Central (la más cercana a Perú entre las 5 permitidas por la universidad) |
| VNet | `vnet-clickclak` 10.10.0.0/16 |
| Subredes | `snet-publica` 10.10.1.0/24 · `snet-privada` 10.10.2.0/24 |

**NSG de `snet-publica`**

| Prioridad | Entrada | Origen | Acción |
|---|---|---|---|
| 100 | 80, 443, 8443 | Internet | Permitir |
| 110 | 22 | IP del equipo (solo) | Permitir |
| 4096 | Todo lo demás | — | Denegar |

**NSG de `snet-privada`**

| Prioridad | Entrada | Origen | Acción |
|---|---|---|---|
| 100 | 5432 | `snet-publica` | Permitir |
| 110 | 22 | `snet-publica` (salto desde `vm-app`) | Permitir |
| 120 | 9100, 9187 (exporters) | `snet-publica` | Permitir |
| 4096 | Todo lo demás | — | Denegar |

Dentro de `vm-app`, Docker usa dos redes: `publica` (Nginx) y `privada` con `internal: true` (backend, base, exporters). Solo Nginx publica puertos.

## 4. Decisiones de diseño

1. **Estado en memoria del backend → PostgreSQL**, no Redis. Tokens revocados, intentos fallidos y desafíos WebAuthn pasan a tablas con expiración. Evita otro servicio y su consumo de RAM; es lo que hace posible el balanceo con 2 instancias.
2. **Balanceo con Nginx `upstream`** (round-robin con comprobación pasiva y `max_fails`), apoyado en `/actuator/health`. Es suficiente para demostrar tolerancia a fallos; Azure Load Balancer/Application Gateway se menciona como alternativa PaaS en la justificación.
3. **Monitoreo con Prometheus + Grafana** en `vm-app`, scrapeando los exporters de ambas VM por la red privada. Alertas mínimas: retraso/desconexión de la réplica, CPU, memoria, disco, p95, 5xx.
4. **Respaldos a Azure Blob** con *service endpoint* de Storage en `snet-privada`, de modo que no haga falta salida a Internet.
5. **IaC:** Bicep o script `az` para grupo de recursos, VNet, subredes, NSG, IPs y VMs; scripts de aprovisionamiento por VM.

## 5. Riesgos y puntos a verificar

| Riesgo | Detalle | Acción |
|---|---|---|
| **Salida a Internet de `vm-db`** | Sin IP pública, Azure puede no darle acceso de salida predeterminado en subredes nuevas *(por verificar)*; `vm-db` necesita bajar paquetes e imágenes Docker | Aprovisionarla con IP pública temporal o preparar las imágenes desde `vm-app` (`docker save`/`load`); evitar NAT Gateway por costo |
| **Crédito Azure** | Cada VM adicional consume crédito de los USD 79 disponibles | Consultar saldo real, cotizar `vm-db` y encender ambas solo para pruebas y sustentación |
| **Migración de la primaria** | Hoy la primaria está en `vm-app` | Los datos son de prueba: recrear la base en `vm-db` y reconstruir el standby |
| **Apagado nocturno** | El script desasigna `vm-app` a las 23:00 | Extenderlo a `vm-db` y añadir encendido ordenado (primero la base) |
| **Latencia entre VM** | Misma región, no debería afectar el criterio de aceptación (p95 < 2 s) | Medirla en las pruebas de carga |

## 5.1 Validación en el portal de Azure (2026-11-22, solo lectura)

Revisado con la cuenta UTP sobre la suscripción **Azure for Students** (rol Propietario, estado Activo). No se creó ni modificó ningún recurso.

| Punto | Resultado |
|---|---|
| Crédito | **USD 79 de USD 100 disponibles**; vence el **02/10/2027** (314 días). El informe asumía que se agotaba hacia el 13-dic |
| Gasto de noviembre | USD 9,01 a la fecha; previsión USD 12,19 (disco 4,98 · IP pública 2,64 · VM 1,39) |
| VM actual | `vm-clickclak`, Chile Central, B2als_v2, **detenida (desasignada)**, IP 57.156.70.235, grupo `rg-clickclak` |
| Red existente | VNet `vm-clickclakVNET` ya creada; se puede añadir una subred privada en lugar de crear otra VNet |
| Tamaños en Chile Central | Serie B v2 disponible: B2ats_v2 y B2ts_v2 (1 GiB; USD 9,64 y 10,66/mes), **B2als_v2 y B2ls_v2 (4 GiB; USD 38,40 y 42,49/mes)**, B2as_v2 (8 GiB; USD 76,65/mes) |
| Tamaño no disponible | `Standard_D2s_v3`: "NotAvailableForSubscription" en Chile Central. No usarlo |
| B2als_v2 en el asistente | Sin error de disponibilidad al seleccionarlo |
| VM sin IP pública | El asistente permite "IP pública: Ninguno" |

**No verificado:** la tabla de cuotas de vCPU no cargó en el portal (varios intentos), así que el límite regional de vCPU y la salida a Internet de una VM sin IP pública siguen pendientes. Se comprobarán al crear la VM o con `az vm list-usage --location chilecentral`.

**Costo estimado de `vm-db` (precios de lista, 24/7):** B2als_v2 38,40; con encendido ~12 h/día, ~19 más disco (~5) y sin IP pública (se ahorran ~2,6). Cabe en los USD 79 si ambas VM se apagan fuera de pruebas.

## 5.2 Validación de creación con la cuenta estudiante (2026-11-22, sin crear nada)

Probado en el asistente del portal con la cuenta UTP. Se usó "Revisar y crear" (solo valida); **no se pulsó "Crear"** y no existe ningún recurso nuevo.

| Prueba | Resultado |
|---|---|
| VM 2 `vm-clickclak-2`, `B2als_v2`, Chile Central, Zona 1, grupo `rg-clickclak`, clave SSH nueva | **Validación superada**: sin errores, botón "Crear" habilitado, 0,0526 USD/h con "se aplican créditos de suscripción". Esto cubre también la cuota de vCPU regional |
| Políticas de la suscripción | Solo una asignada: *Allowed resource deployment regions* (limita regiones, no tipos de recurso) |
| Load Balancer: SKU Estándar, tipo Pública, nivel Regional, Chile Central | El asistente lo acepta (nombre válido); el SKU Basic ya no se ofrece |
| Zonas de disponibilidad | Existen en Chile Central (Zona 1 seleccionable) |
| `vm-clickclak` (VM 1) | **Sin zona de disponibilidad ni conjunto de disponibilidad**; subred `vm-clickclakSubnet`, IP privada 10.0.0.4; etiqueta `proyecto=clickclak` y una etiqueta `curso` heredada del clonado (pendiente de actualizar) |

**Pendiente:** la validación completa del Load Balancer (requiere IP de front-end, grupo de back-end con la VM 2 y reglas); se hará al construirlo.

**Consecuencias para el diseño**

- La VM 1 no está en una zona y no se puede mover a una: para repartir los nodos en zonas distintas habría que recrearla desde un snapshot de su propio disco (Zona 1) y crear la VM 2 en la Zona 2. Si no, ambas quedan sin zona (solo redundancia por máquina).
- La VNet existente usa 10.0.0.0/16 (la VM 1 tiene 10.0.0.4), no el 10.10.0.0/16 propuesto arriba: las subredes nuevas deben salir de ese rango.
- La etiqueta `curso` heredada del clonado debe actualizarse a `servicios-cloud` en los recursos para identificar los costos de este proyecto.

## 5.3 Estado real: Etapa 1, paso 1 ejecutado (2026-11-22)

Creado con Azure CLI en `rg-clickclak` (Chile Central). La VM 1 se mantuvo **desasignada** durante la copia.

| Recurso | Detalle |
|---|---|
| Snapshot `snap-vm-clickclak-20261122` | Incremental, Standard_LRS, copia del disco de la VM 1 (consistente: VM apagada) |
| Disco `vm-clickclak-2_osdisk` | Standard SSD LRS, generación 2, creado desde el snapshot |
| VM `vm-clickclak-2` | B2als_v2, regional (sin zona, igual que la VM 1), seguridad Estándar, **encendida** |
| Red | Misma VNet y subred que la VM 1; IP privada `10.0.0.5`; NSG compartido `vm-clickclakNSG` (22, 80, 443, 8443) |
| IP pública `vm-clickclak-2-ip` | Standard estática `57.156.57.95`; DNS `clickclak-utp-2.chilecentral.cloudapp.azure.com` |
| Etiquetas | `curso=servicios-cloud`, `proyecto=clickclak`, `rol=nodo-2` |
| Acceso | SSH como `azureuser` con la misma llave de la VM 1 |

**Verificado en la VM 2:** 6 contenedores sanos (proxy, 2 frontends, backend, PostgreSQL primaria y réplica); campo 200, API sin token 401 y panel (8443) 200. Nombre de host corregido a `vm-clickclak-2`.

**Es una copia fiel y por eso aún no es un nodo del clúster:**

- Su base es una **primaria independiente** (con su propia réplica local); no recibe datos de la VM 1. Hay que reconfigurarla como réplica de la VM 1 (siguiente paso).
- Comparte secretos y `JWT_SECRET` con la VM 1 (necesario para el balanceo; ver riesgo R1 en `SEGURIDAD_ISO27001_OWASP.md`).
- El certificado es el del dominio de la VM 1; con el nombre `clickclak-utp-2…` el navegador mostrará advertencia hasta que haya un dominio común detrás del balanceador.
- **No tiene identidad administrada**: el apagado de las 23:00 (heredado) falla sin efecto. La VM 2 no puede apagar a la VM 1 porque el script usa el nombre de la propia VM. Para el autoapagado habría que asignarle identidad y el rol sobre sí misma.
- **No encender la VM 1 y la VM 2 a la vez antes de definir quién es la primaria**: ambas arrancarían como primarias.

**Corrección de costos:** la IP pública de la VM 1 es **Standard** (no Basic), unos USD 3,65/mes; el fijo apagado real de la VM 1 es ~USD 10,4 en lugar de 9,35. Con la VM 2 el fijo apagado es ~USD 20,8 (2 discos + 2 IP).

**Costo en curso:** la VM 2 encendida cuesta USD 0,0526/h (~USD 1,26/día). Para apagarla: `az vm deallocate -g rg-clickclak -n vm-clickclak-2`.

## 5.4 Etapa 1, paso 2: replicación nodo 1 → nodo 2 conectada (2026-11-22)

La VM 2 dejó de ser una primaria independiente: ahora es **standby** de la VM 1. Esto reemplaza la advertencia de la sección 5.3 sobre "dos primarias" mientras cada nodo mantenga su rol.

**Cambios en el repositorio (retrocompatibles; sin los archivos de nodo todo se comporta como antes):**

| Archivo | Cambio |
|---|---|
| `infra/postgres/replicacion/preparar-primaria.sh` | Variables opcionales `SLOTS_EXTRA` y `REPLICA_CIDR`: crea ranuras adicionales y reglas `pg_hba` para réplicas remotas, con validación de formato |
| `infra/postgres/replicacion/entrada-replica.sh` | Variables opcionales `PRIMARY_HOST` y `REPLICA_SLOT` (por defecto `postgres` y `replica_slot`) |
| `infra/scripts/desplegar.sh` | Si existe `docker-compose.nodo.yml`, lo suma al compose |
| `infra/nodos/nodo1.yml` | Nodo 1: publica PostgreSQL solo en `10.0.0.4:5432`, ranura `nodo2_slot`, autoriza solo a `10.0.0.5/32` |
| `infra/nodos/nodo2.yml` | Nodo 2: `postgres` pasa a standby (copia con `pg_basebackup`), desactiva la réplica local y apunta el backend a `jdbc:postgresql://10.0.0.4:5432,10.0.0.5:5432/clickclak?targetServerType=primary` |

En cada VM el archivo del rol se copia como `infra/docker-compose.nodo.yml`; los scripts originales quedaron respaldados en `~/respaldo-infra-20261122`.

**Verificación realizada:**

| Comprobación | Resultado |
|---|---|
| VM 2 `pg_is_in_recovery()` | `t` |
| `pg_stat_wal_receiver` en la VM 2 | `streaming` desde 10.0.0.4, ranura `nodo2_slot` |
| `pg_stat_replication` en la VM 1 | `10.0.0.5` en `streaming`, asíncrona, retraso 0 bytes |
| Escritura en la standby | Rechazada: "cannot execute CREATE TABLE in a read-only transaction" |
| Propagación | Tabla de 1000 filas creada en la primaria visible en la standby; borrado también propagado (tabla de prueba eliminada) |
| Backend de la VM 2 | Sano; 10 conexiones a la primaria remota vía JDBC multi-host |
| VM 2 por su IP pública | Campo 200, API sin token 401 |
| Exposición del 5432 | Solo en `10.0.0.4` (IP privada); el NSG no lo abre a Internet |

**Límites y pendientes de este paso:**

- **Sin TLS en la replicación ni en la conexión aplicación → BD** (hoy autentica con SCRAM por la red privada de Azure). Es el control A02 de OWASP / ISO 8.24 que `SEGURIDAD_ISO27001_OWASP.md` marca como obligatorio: pendiente.
- **Las ranuras están llenas (2 de 2):** `replica_slot` (réplica local de la VM 1, que ya no aporta en el diseño final) y `nodo2_slot`. Retirar la réplica local de la VM 1 libera una ranura.
- **Failover no probado:** falta ensayar la promoción de la VM 2, el *fencing* de la VM 1 y la reincorporación (`pg_rewind`). Hoy la VM 1 sigue siendo el único escritor.
- Si la VM 1 está apagada, el backend de la VM 2 **no tiene primaria** a la que conectarse (esperado hasta que exista promoción).
- El resto de la copia sigue idéntico a la VM 1 (secretos compartidos, certificado del dominio de la VM 1).
- `wal_log_hints` aún sin activar: sin él no se podrá usar `pg_rewind` para reincorporar la primaria vieja.

**Costo en curso:** con las dos VM encendidas, USD 0,1052/h (~USD 2,52/día). Apagar: `az vm deallocate -g rg-clickclak -n vm-clickclak-2` y `-n vm-clickclak`.

## 5.5 Estado real (2026-11-23): 3 servidores, balanceador y monitoreo en marcha

```
Internet ─► lb-clickclak (IP 68.211.146.181, clickclak-utp.chilecentral.cloudapp.azure.com)  ← ÚNICA IP pública
              │  443/8443/80 (sondeo HTTPS /salud cada 5 s, 2 fallos)        SSH por NAT: 2201 / 2202 / 2203
              ├─► vm-clickclak   10.0.0.4  nodo1  proxy, backend, frontends, PostgreSQL PRIMARIA, exportadores
              ├─► vm-clickclak-2 10.0.0.5  nodo2  proxy, backend, frontends, PostgreSQL STANDBY,  exportadores
              └─   vm-clickclak-3 10.0.0.6  testigo  Prometheus, Alertmanager, Grafana, blackbox, node-exporter
              (salida a Internet de los tres: regla de salida del balanceador)
```

| Recurso | Detalle |
|---|---|
| Acceso SSH | `ssh -i ~/.ssh/clickclak_azure -p 2201\|2202\|2203 azureuser@68.211.146.181` (nodo1, nodo2, testigo) |
| IP públicas | **Una** (el balanceador). La suscripción de estudiante tiene un tope de **3 IP públicas**; por eso los nodos y el testigo no tienen la suya |
| Cabecera de prueba | `X-Nodo: nodo1\|nodo2` en cada respuesta, para ver el reparto y qué nodo queda si el otro cae |
| Grafana | `10.0.0.6:3000` solo desde la VNet: `ssh -p 2203 -L 3000:10.0.0.6:3000 azureuser@68.211.146.181` y abrir `http://localhost:3000` (usuario `admin`; la clave está en `~/monitoreo/secretos/grafana_clave` del testigo) |
| Prometheus / Alertmanager | `10.0.0.6:9090` / `10.0.0.6:9093` (mismo túnel) |
| IaC | `infra/azure/balanceador.sh` (balanceador, salida, NAT, IP), `infra/azure/testigo.sh` y `cloud-init-testigo.yaml` (testigo), `infra/nodos/*.yml` (rol de cada nodo), `infra/monitoreo/` (pila de observabilidad) |
| Métricas | `/actuator/prometheus` solo con HTTP Basic (usuario `prometheus`); el proxy no enruta `/actuator`; rol de BD `monitoreo` solo con `pg_monitor` |

**Lo que aprendimos al construirlo (útil para el informe)**

- **Cuota de 3 IP públicas** en Azure for Students: obligó al diseño de red privada (balanceador como único punto público + regla de salida + NAT de SSH), que además mejora la seguridad (OWASP A05; ISO 27001 8.20–8.22).
- Una NIC con IP pública propia **no puede** pertenecer a un grupo con regla de salida: el orden correcto es NAT de SSH → comprobar → quitar la IP → sumar al grupo de salida.
- El NAT del balanceador **conserva la IP de origen**, así que el NSG del testigo debe permitir el SSH desde la IP del equipo, no solo desde la VNet.
- Registrar el fallo de login en una transacción de solo lectura que se revierte **anularía el límite de fuerza bruta**: los almacenes escriben con `REQUIRES_NEW`.
- Una variable de entorno `…PERCENTILES_HISTOGRAM…` se interpreta como otra propiedad y tumba el arranque; la forma correcta es `…PERCENTILESHISTOGRAM…`. Durante esa caída el sitio siguió respondiendo desde el otro nodo.

**Riesgos abiertos de este estado:** las VM son B-series (CPU ráfaga; vigilar créditos con las pruebas de carga); el SSH del NSG de los nodos sigue abierto a `*` (solo llave y `fail2ban`); la standby y el testigo comparten secretos con la VM 1 (R1); TLS interno aún pendiente.

## 6. Qué demuestra cada criterio

| Criterio | Evidencia que produce este diseño |
|---|---|
| 2 | Compose con redes `publica`/`privada`, límites de recursos, imágenes versionadas |
| 3 | VNet, subredes y NSG reales; tablero Grafana en vivo; k6 con 1→2 instancias y punto de quiebre |
| 4 | Balanceo con caída de un backend sin corte; caída de `vm-db` con promoción del standby; restauración desde Blob con RTO/RPO medidos |
| 5 | Tres escenarios de falla guionizados, ejecutables en vivo con el tablero abierto |
