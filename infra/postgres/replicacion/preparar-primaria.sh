#!/bin/sh
# Prepara la base primaria para que una réplica pueda conectarse. Se ejecuta DENTRO del
# contenedor de la primaria, como usuario postgres, en cada despliegue (lo invoca desplegar.sh):
#     docker compose exec -T -u postgres postgres sh /replicacion/preparar-primaria.sh
#
# Es idempotente y funciona sobre una base que ya tiene datos. No se hace con un script de
# /docker-entrypoint-initdb.d porque esos solo corren al inicializar un volumen vacío, y la
# primaria de producción ya existía cuando se agregó la réplica.
#
# Qué deja configurado:
#   - el rol `replicador`, solo con permiso de replicación, con la contraseña de REPLICA_PASSWORD.
#     La regla por defecto de la imagen (`host all all all`) le permitiría conectarse a la base de
#     la aplicación y ver los nombres de sus tablas, aunque no leer los datos; por eso se retira
#     CONNECT a PUBLIC. La replicación no lo necesita (usa el protocolo de replicación, que no
#     abre una base de datos) y la aplicación entra como propietario, que no depende de PUBLIC;
#   - la ranura física `replica_slot`: la primaria conserva el WAL que la réplica aún no leyó
#     (el tope lo pone max_slot_wal_keep_size en el compose, para que una réplica caída no
#     llene el disco);
#   - la regla de pg_hba que permite conexiones de replicación solo desde la misma subred de
#     Docker; la base nunca se publica fuera de esa red.
set -eu

: "${POSTGRES_USER:?}" "${POSTGRES_DB:?}" "${REPLICA_PASSWORD:?Falta REPLICA_PASSWORD}"

psql -v ON_ERROR_STOP=1 -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v clave="$REPLICA_PASSWORD" -v basedatos="$POSTGRES_DB" > /dev/null <<'SQL'
SELECT 'CREATE ROLE replicador WITH REPLICATION LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replicador') \gexec

-- Se reasigna siempre, así una rotación de REPLICA_PASSWORD se aplica en el siguiente despliegue.
ALTER ROLE replicador WITH REPLICATION LOGIN PASSWORD :'clave';

-- El rol replicador no debe poder entrar a la base de la aplicación (ver la cabecera).
REVOKE CONNECT ON DATABASE :"basedatos" FROM PUBLIC;

-- Sin \gexec: la función devuelve una fila, no texto SQL que ejecutar.
SELECT pg_create_physical_replication_slot('replica_slot')
WHERE NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = 'replica_slot');
SQL

# Rol de solo lectura para el monitoreo (postgres_exporter): pertenece a pg_monitor y nada más, así
# el exportador no usa al propietario de la base. Usa METRICAS_CLAVE como contraseña. Opcional: sin
# esa variable el rol no se crea. La standby lo hereda por replicación.
if [ -n "${METRICAS_CLAVE:-}" ]; then
    psql -v ON_ERROR_STOP=1 -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v clave="$METRICAS_CLAVE" -v basedatos="$POSTGRES_DB" > /dev/null <<'SQL'
SELECT 'CREATE ROLE monitoreo WITH LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'monitoreo') \gexec
ALTER ROLE monitoreo WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'clave';
GRANT pg_monitor TO monitoreo;
GRANT CONNECT ON DATABASE :"basedatos" TO monitoreo;
SQL
    echo "primaria: rol monitoreo (pg_monitor) listo"
fi

# Rol de SOLO LECTURA para los respaldos (pg_dump): pg_read_all_data y nada más. No puede escribir ni
# cambiar el esquema, así que un respaldo comprometido no sirve para alterar datos. Opcional: sin
# RESPALDO_CLAVE no se crea. La standby lo hereda por replicación.
if [ -n "${RESPALDO_CLAVE:-}" ]; then
    psql -v ON_ERROR_STOP=1 -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v clave="$RESPALDO_CLAVE" -v basedatos="$POSTGRES_DB" > /dev/null <<'SQL'
SELECT 'CREATE ROLE respaldo WITH LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'respaldo') \gexec
ALTER ROLE respaldo WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'clave';
GRANT pg_read_all_data TO respaldo;
GRANT CONNECT ON DATABASE :"basedatos" TO respaldo;
SQL
    echo "primaria: rol respaldo (pg_read_all_data) listo"
fi

# Réplicas remotas (otro nodo). Ambas variables son opcionales y valen lista separada por comas;
# sin ellas el script se comporta como antes. Las define infra/nodos/nodo1.yml.
#   SLOTS_EXTRA   una ranura física por réplica remota, p. ej. nodo2_slot
#   REPLICA_CIDR  direcciones autorizadas a replicar, p. ej. 10.0.0.5/32
for ranura in $(printf '%s' "${SLOTS_EXTRA:-}" | tr ',' ' '); do
    case "$ranura" in
        *[!a-z0-9_]*|'') echo "primaria: nombre de ranura no válido: $ranura" >&2; exit 1 ;;
    esac
    psql -tA -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
        "SELECT pg_create_physical_replication_slot('$ranura') WHERE NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = '$ranura')" > /dev/null
done

ARCHIVO_HBA=$(psql -tA -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SHOW hba_file")
REGLAS='host replication replicador samenet scram-sha-256'
for cidr in $(printf '%s' "${REPLICA_CIDR:-}" | tr ',' ' '); do
    case "$cidr" in
        *[!0-9./]*|'') echo "primaria: CIDR no válido: $cidr" >&2; exit 1 ;;
    esac
    REGLAS="$REGLAS
hostssl replication replicador $cidr scram-sha-256"
done
printf '%s\n' "$REGLAS" | while IFS= read -r regla; do
    if ! grep -qxF "$regla" "$ARCHIVO_HBA"; then
        echo "$regla" >> "$ARCHIVO_HBA"
        echo "primaria: regla agregada a pg_hba.conf: $regla"
    fi
done
# Con TLS disponible (hay certificado montado), TODO lo que llega por la red privada entre nodos debe ir
# cifrado: las reglas `hostnossl ... reject` van AL PRINCIPIO (pg_hba usa la primera que coincide). El
# tráfico local de los contenedores del propio nodo (red de Docker) no pasa por la red 10.0.0.0/24.
if [ -f /certs/server.crt ]; then
    for regla in 'hostnossl replication all 10.0.0.0/24 reject' 'hostnossl all all 10.0.0.0/24 reject'; do
        grep -qxF "$regla" "$ARCHIVO_HBA" || { sed -i "1i $regla" "$ARCHIVO_HBA"; echo "primaria: regla agregada al principio de pg_hba.conf: $regla"; }
    done
fi
psql -tA -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT pg_reload_conf()" > /dev/null

echo "primaria: rol replicador, ranuras y reglas de pg_hba listos"
