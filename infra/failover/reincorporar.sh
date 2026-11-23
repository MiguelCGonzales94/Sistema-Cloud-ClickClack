#!/bin/sh
# Reincorpora al nodo VIEJO como standby de la NUEVA primaria. Se ejecuta EN el nodo viejo, desde infra/:
#     sh failover/reincorporar.sh <IP_NUEVA_PRIMARIA> <RANURA_DE_ESTE_NODO> <ARCHIVO_DE_ROL>
#     p. ej.  sh failover/reincorporar.sh 10.0.0.5 nodo1_slot nodos/nodo1-standby.yml
#
# La historia del nodo viejo divergió de la de la nueva primaria (dos líneas de tiempo), así que NO
# puede simplemente "volver a conectarse". Dos caminos:
#   A) pg_rewind (preferido): rebobina solo lo que difiere hasta el punto de divergencia. Exige
#      wal_log_hints = on en el momento de la falla (ya activo) y un CHECKPOINT en la nueva primaria.
#      Descarta lo que el nodo viejo escribió y nunca llegó a replicarse (el RPO de la replicación asíncrona).
#   B) Reconstrucción completa con pg_basebackup (siempre funciona; la base es pequeña).
#
# Es seguro repetirlo. Pide que el contenedor de PostgreSQL de este nodo ya esté detenido (aislar.sh).
set -eu

NUEVA_IP="${1:?Falta la IP privada de la nueva primaria}"
RANURA="${2:?Falta el nombre de la ranura de este nodo en la nueva primaria}"
ROL="${3:?Falta el archivo de rol del nodo (p. ej. nodos/nodo1-standby.yml)}"
PG="${PG_CONTENEDOR:-clickclak-postgres-1}"
VOLUMEN="${VOLUMEN_BD:-clickclak_postgres_data}"
IMAGEN="postgis/postgis:16-3.4"
COMPOSE="sudo docker compose -f docker-compose.prod.yml -f docker-compose.nodo.yml --env-file .env"

# shellcheck disable=SC1091
. ./.env
[ "$(sudo docker inspect -f '{{.State.Running}}' "$PG" 2>/dev/null || echo false)" = "false" ] || {
    echo "El PostgreSQL de este nodo sigue en marcha: ejecutar antes failover/aislar.sh" >&2; exit 1; }

reconstruir() {
    echo "== Camino B: reconstrucción completa (pg_basebackup desde $NUEVA_IP)"
    sudo docker rm -f "$PG" > /dev/null 2>&1 || true
    sudo docker volume rm "$VOLUMEN" > /dev/null
}

rebobinar() {
    echo "== Camino A: pg_rewind contra $NUEVA_IP"
    # 1) Termina la recuperación tras una caída abrupta: pg_rewind exige un apagado limpio. Se arranca en
    #    modo monousuario CON wal_log_hints=on: sin ese parámetro, al terminar la recuperación PostgreSQL
    #    reescribe el archivo de control con el valor por defecto (off) y pg_rewind se niega a continuar
    #    (lección de los dos primeros ensayos).
    # 2) Rebobina hasta el punto de divergencia con la nueva línea de tiempo.
    # 3) Lo deja como standby de la nueva primaria con el rol `replicador` (no el superusuario).
    sudo docker run --rm -v "$VOLUMEN":/var/lib/postgresql/data -v /etc/clickclak/tls-bd:/certs:ro \
        -e NUEVA="$NUEVA_IP" -e DBP="$DB_PASSWORD" -e RP="$REPLICA_PASSWORD" -e RANURA="$RANURA" \
        --entrypoint sh "$IMAGEN" -c '
            set -e
            D=/var/lib/postgresql/data
            gosu postgres postgres --single -c wal_log_hints=on -D "$D" postgres < /dev/null > /dev/null 2>&1 || true
            gosu postgres env PGPASSWORD="$DBP" pg_rewind --target-pgdata="$D" \
                --source-server="host=$NUEVA port=5432 user=clickclak dbname=postgres sslmode=verify-full sslrootcert=/certs/ca.crt" --progress
            gosu postgres touch "$D/standby.signal"
            gosu postgres sh -c "cat >> $D/postgresql.auto.conf" <<EOF
primary_conninfo = '"'"'host=$NUEVA port=5432 user=replicador password=$RP sslmode=verify-full sslrootcert=/certs/ca.crt'"'"'
primary_slot_name = '"'"'$RANURA'"'"'
EOF
        '
}

if rebobinar; then
    echo "pg_rewind terminó bien."
else
    echo "pg_rewind falló: se usa la reconstrucción completa." >&2
    reconstruir
fi

echo "== Cambiando el rol de este nodo a standby ($ROL) y arrancando"
cp "$ROL" docker-compose.nodo.yml
$COMPOSE up -d --no-deps postgres
for i in $(seq 1 30); do
    [ "$(sudo docker inspect -f '{{.State.Health.Status}}' "$PG" 2>/dev/null)" = "healthy" ] && break
    sleep 2
done
echo "En recuperación (debe ser t): $(sudo docker exec "$PG" psql -U clickclak -d clickclak -tAc 'SELECT pg_is_in_recovery()')"
