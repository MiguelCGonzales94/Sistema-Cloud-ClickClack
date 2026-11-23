#!/bin/sh
# Verificación de la replicación ENTRE NODOS (diseño de dos nodos). Se ejecuta EN cualquiera de los dos, desde infra/:
#     sh scripts/verificar-replicacion-nodos.sh
# Detecta si el nodo es la primaria o la standby y comprueba lo que corresponde. Solo lee (no escribe en la base).
# Termina con código distinto de 0 si algo falla. Sustituye a verificar-replicacion.sh, que prueba la réplica LOCAL
# de la instalación de una sola VM.
PG="${PG_CONTENEDOR:-clickclak-postgres-1}"
FALLOS=0
q() { sudo docker exec "$PG" psql -U clickclak -d clickclak -tAc "$1" 2>&1 | tr -d '\r\n '; }
comprobar() { # $1 = descripción, $2 = esperado, $3 = obtenido
    if [ "$2" = "$3" ]; then printf 'OK     %-62s %s\n' "$1" "$3"; else printf 'FALLA  %-62s esperado %s, obtenido %s\n' "$1" "$2" "$3"; FALLOS=$((FALLOS + 1)); fi
}

if [ "$(q 'SELECT pg_is_in_recovery()')" = "f" ]; then
    comprobar "este nodo es la primaria (no está en recuperación)" f f
    comprobar "hay una réplica conectada en streaming" streaming "$(q "SELECT state FROM pg_stat_replication LIMIT 1")"
    comprobar "la conexión de replicación va cifrada (TLS)" t "$(q "SELECT s.ssl FROM pg_stat_replication r JOIN pg_stat_ssl s USING (pid) LIMIT 1")"
    ATRASO=$(q "SELECT COALESCE(max(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)), -1)::bigint FROM pg_stat_replication")
    comprobar "retraso de la réplica dentro de 1 MiB" t "$([ "${ATRASO:--1}" -ge 0 ] && [ "${ATRASO:--1}" -le 1048576 ] && echo t || echo f)"
    comprobar "la ranura de replicación de la otra réplica está activa" t "$(q "SELECT bool_or(active) FROM pg_replication_slots WHERE slot_type = 'physical'")"
    comprobar "el rol de respaldo es de solo lectura (no superusuario)" f "$(q "SELECT rolsuper FROM pg_roles WHERE rolname = 'respaldo'")"
    comprobar "la regla pg_hba rechaza el tráfico sin cifrar entre nodos" t "$(sudo docker exec "$PG" sh -c 'grep -q "^hostnossl all all 10.0.0.0/24 reject" "$(psql -U clickclak -d clickclak -tAc "show hba_file")" && echo t || echo f')"
else
    comprobar "este nodo es la standby (en recuperación)" t t
    comprobar "el receptor de WAL está en streaming" streaming "$(q "SELECT status FROM pg_stat_wal_receiver")"
    comprobar "la standby rechaza escrituras" rechazada "$(sudo docker exec "$PG" psql -U clickclak -d clickclak -qc 'CREATE TABLE _verificacion_standby (i int)' 2>&1 | grep -q 'read-only transaction' && echo rechazada || echo aceptada)"
    comprobar "la standby tiene PostGIS" postgis "$(q "SELECT extname FROM pg_extension WHERE extname = 'postgis'")"
fi
comprobar "TLS habilitado en el servidor de base de datos" on "$(q 'SHOW ssl')"
comprobar "wal_log_hints activado (permite pg_rewind)" on "$(q 'SHOW wal_log_hints')"

[ "$FALLOS" -eq 0 ] || exit 1
