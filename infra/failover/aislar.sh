#!/bin/sh
# FENCING del nodo viejo: impide que su PostgreSQL vuelva a arrancar como primaria.
# Se ejecuta EN el nodo al que se le quita el rol de primaria, y siempre ANTES de promover al otro.
#
# Por qué es obligatorio: el compose usa `restart: unless-stopped`, así que al reiniciar la VM (o si el
# contenedor se cae) Docker volvería a levantar su PostgreSQL como PRIMARIA, con una historia distinta a
# la de la nueva primaria: dos primarias escribiendo a la vez (split-brain), con datos irreconciliables.
#
#     sh failover/aislar.sh
set -eu
PG="${PG_CONTENEDOR:-clickclak-postgres-1}"

# 1. Sin reinicio automático: que Docker no lo vuelva a levantar.
sudo docker update --restart=no "$PG" > /dev/null
# 2. Detenido (si ya está caído no hace nada).
sudo docker stop -t 5 "$PG" > /dev/null 2>&1 || true
estado=$(sudo docker inspect -f '{{.State.Status}}' "$PG")
echo "PostgreSQL de $(hostname) aislado: contenedor $estado, reinicio automático desactivado."
[ "$estado" = "running" ] && { echo "NO se pudo detener: no promover al otro nodo." >&2; exit 1; }
exit 0
