#!/bin/sh
# Punto de entrada del contenedor de la réplica de Postgres (streaming replication).
#
# Primera vez, con el volumen vacío: copia la primaria con pg_basebackup. La opción -R deja el
# archivo standby.signal y la conexión a la primaria en postgresql.auto.conf, de modo que al
# arrancar Postgres entra solo en modo réplica (hot standby: acepta lecturas, rechaza escrituras).
# Siguientes veces: el volumen ya tiene datos y arranca directo, retomando la replicación donde
# se quedó gracias a la ranura `replica_slot` de la primaria.
#
# Si la primaria todavía no está lista (rol aún no creado, arranque en curso) reintenta, porque
# Compose solo espera a que la primaria esté sana, no a que desplegar.sh la haya preparado.
#
# Los argumentos que recibe (las opciones -c del compose) se pasan tal cual a Postgres.
set -eu

DATOS="${PGDATA:-/var/lib/postgresql/data}"
: "${REPLICA_PASSWORD:?Falta REPLICA_PASSWORD}"
# Por defecto la primaria es el servicio `postgres` de este mismo compose y la ranura es
# `replica_slot`. Un nodo remoto (infra/nodos/nodo2.yml) las sobrescribe.
PRIMARIA_HOST="${PRIMARY_HOST:-postgres}"
# Con la CA interna montada (nodos), la copia y la replicación exigen TLS con verificación completa.
if [ -f /certs/ca.crt ]; then SSL_MODO="verify-full"; SSL_RAIZ="/certs/ca.crt"; else SSL_MODO="prefer"; SSL_RAIZ=""; fi
RANURA="${REPLICA_SLOT:-replica_slot}"

if [ ! -s "$DATOS/PG_VERSION" ]; then
    echo "réplica: volumen vacío, copiando la primaria"
    mkdir -p "$DATOS"
    chown postgres:postgres "$DATOS"
    chmod 700 "$DATOS"

    intentos=0
    until PGPASSWORD="$REPLICA_PASSWORD" PGSSLMODE="$SSL_MODO" PGSSLROOTCERT="$SSL_RAIZ" gosu postgres pg_basebackup \
            -h "$PRIMARIA_HOST" -U replicador -D "$DATOS" -X stream -S "$RANURA" -R -c fast; do
        intentos=$((intentos + 1))
        if [ "$intentos" -ge 40 ]; then
            echo "réplica: no se pudo copiar la primaria tras $intentos intentos" >&2
            exit 1
        fi
        echo "réplica: la primaria aún no admite la copia (intento $intentos de 40); reintentando en 3 s"
        # Una copia a medias deja el directorio sin vaciar y haría fallar el siguiente intento.
        find "$DATOS" -mindepth 1 -delete
        sleep 3
    done
    echo "réplica: copia inicial terminada"
    if [ -f /certs/ca.crt ]; then
        # La última definición gana en postgresql.auto.conf: se fija la conexión de streaming con TLS verificado.
        gosu postgres sh -c "cat >> $DATOS/postgresql.auto.conf" <<EOF
primary_conninfo = 'host=$PRIMARIA_HOST port=5432 user=replicador password=$REPLICA_PASSWORD sslmode=verify-full sslrootcert=/certs/ca.crt'
EOF
    fi
fi

exec docker-entrypoint.sh postgres "$@"
