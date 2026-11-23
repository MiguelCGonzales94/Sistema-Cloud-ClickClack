#!/bin/sh
# Escritor continuo para MEDIR el failover. Se ejecuta DENTRO del contenedor de PostgreSQL de un nodo
# (usa su contraseña de entorno): inserta ids consecutivos y anota cada intento con su hora.
# El id solo avanza cuando la escritura se confirma, así los ids confirmados son 1..N sin huecos.
#
#   - RTO de escritura = hora del primer "ok" tras la caída − hora del último "ok" antes de ella.
#   - RPO = ids confirmados al cliente que NO existen en la nueva primaria (replicación asíncrona).
#
# La conexión lleva los dos nodos (libpq): `target_session_attrs=read-write` descarta a la standby,
# así que el escritor sigue a la primaria igual que lo hace el backend con JDBC.
# Para detenerlo:  touch /tmp/parar-escritor
CONEXION="host=10.0.0.4,10.0.0.5 port=5432 dbname=clickclak user=clickclak password=$POSTGRES_PASSWORD target_session_attrs=read-write connect_timeout=2"
rm -f /tmp/parar-escritor /tmp/escritor.log
psql "$CONEXION" -qtAc "CREATE TABLE IF NOT EXISTS _prueba_failover (id bigint PRIMARY KEY, t timestamptz DEFAULT now()); TRUNCATE _prueba_failover" > /dev/null
i=0
while [ ! -f /tmp/parar-escritor ]; do
    n=$((i + 1))
    if psql "$CONEXION" -qtAc "INSERT INTO _prueba_failover (id) VALUES ($n) ON CONFLICT DO NOTHING" > /dev/null 2>&1; then
        i=$n
        echo "$(date +%s.%N) $n ok" >> /tmp/escritor.log
    else
        echo "$(date +%s.%N) $n err" >> /tmp/escritor.log
    fi
    sleep 0.1
done
