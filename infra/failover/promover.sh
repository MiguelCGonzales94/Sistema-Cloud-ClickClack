#!/bin/sh
# Promueve la STANDBY local a primaria. Se ejecuta EN el nodo que va a pasar a primaria:
#     sh failover/promover.sh <IP_PRIVADA_DEL_NODO_VIEJO> [RANURA_PARA_EL_NODO_VIEJO]
#     p. ej. en el nodo 2:  sh failover/promover.sh 10.0.0.4 nodo1_slot
#
# ANTES hay que haber aislado (fencing) al nodo viejo: ver failover/aislar.sh. Promover con el nodo
# viejo todavía escribiendo crea dos primarias (split-brain): esta es la comprobación que importa.
#
# Qué hace:
#   1. Verifica que este nodo es standby (si ya es primaria, se detiene sin tocar nada).
#   2. Promueve (pg_promote) y espera a que acepte escrituras. Abre una nueva línea de tiempo.
#   3. Fuerza un CHECKPOINT: pg_rewind lo exige antes de poder reincorporar al nodo viejo.
#   4. Deja lista la replicación hacia el nodo viejo (ranura y regla de pg_hba) para reincorporarlo.
#
# Los backends de AMBOS nodos llevan los dos hosts en la URL JDBC con targetServerType=primary,
# así que encuentran a la nueva primaria solos: no hay que tocar la aplicación.
set -eu

IP_VIEJA="${1:?Falta la IP privada del nodo viejo (p. ej. 10.0.0.4)}"
RANURA="${2:-nodo1_slot}"
PG="${PG_CONTENEDOR:-clickclak-postgres-1}"

q() { sudo docker exec "$PG" psql -U clickclak -d clickclak -tAc "$1"; }

if [ "$(q 'SELECT pg_is_in_recovery()')" != "t" ]; then
    echo "Este nodo NO es una standby (pg_is_in_recovery = f): no hay nada que promover." >&2
    exit 1
fi

echo "$(date -u +%T.%N) promoviendo..."
q "SELECT pg_promote(wait => true, wait_seconds => 30)" > /dev/null
echo "$(date -u +%T.%N) promovida; escritura permitida: $([ "$(q 'SELECT pg_is_in_recovery()')" = f ] && echo sí || echo no)"

q "CHECKPOINT" > /dev/null
sudo docker exec -u postgres -e SLOTS_EXTRA="$RANURA" -e REPLICA_CIDR="$IP_VIEJA/32" \
    "$PG" sh /replicacion/preparar-primaria.sh

echo "Nueva primaria lista. Línea de tiempo: $(q 'SELECT timeline_id FROM pg_control_checkpoint()')."
echo "Siguiente paso, en el nodo viejo: sh failover/reincorporar.sh <IP de esta primaria> <ranura>"
