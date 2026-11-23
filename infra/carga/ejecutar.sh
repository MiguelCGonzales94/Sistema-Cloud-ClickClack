#!/bin/sh
# Ejecuta un guion de k6 EN EL TESTIGO y guarda el resumen más una instantánea de Prometheus de esa prueba.
#     sh ~/carga/ejecutar.sh <p1-nominal|p2-pico|p3-rafaga|p4-estres|p5-limite-nginx> <etiqueta> "<URLs de los backends separadas por comas>"
#     p. ej.  sh ~/carga/ejecutar.sh p1-nominal 2-instancias "http://10.0.0.4:8080,http://10.0.0.5:8080"
# k6 corre en un contenedor (grafana/k6) con red del host, dentro de la VNet: llega a los backends por su IP privada.
set -eu
DIR="${DIR:-$HOME/carga}"
ESC="$1"; ETQ="$2"; OBJ="${3:-http://10.0.0.5:8080}"
IMAGEN="grafana/k6:0.54.0"
PROM="http://10.0.0.6:9090"
mkdir -p "$DIR/salida"
chmod 777 "$DIR/salida"   # k6 corre como un usuario sin privilegios (uid 12345) y debe poder escribir aquí
CLAVE=$(cat "$DIR/secretos/clave_prueba")

echo "== $ESC [$ETQ] contra: $OBJ"
INI=$(date +%s)
docker run --rm --network host -v "$DIR":/carga \
    -e OBJETIVOS="$OBJ" -e CLAVE="$CLAVE" -e USUARIO_ID="${USUARIO_ID:-14}" -e DISPOSITIVO_ID="${DISPOSITIVO_ID:-2}" \
    -e URL_PUBLICA="${URL_PUBLICA:-https://clickclak-utp.chilecentral.cloudapp.azure.com}" -e DURACION="${DURACION:-3m}" \
    "$IMAGEN" run --quiet --summary-export="/carga/salida/$ESC-$ETQ.json" "/carga/$ESC.js" > "$DIR/salida/$ESC-$ETQ.log" 2>&1 || true
FIN=$(date +%s)
D=$((FIN - INI + 10))

# Máximos observados por Prometheus durante la prueba (subconsultas cada 10 s).
q() { curl -s --data-urlencode "query=$1" "$PROM/api/v1/query" | jq -c '[.data.result[] | {(.metric.nodo // "total"): (.value[1] | tonumber | . * 100 | round / 100)}] | add // {}'; }
{
  echo "{"
  echo "\"prueba\":\"$ESC\",\"etiqueta\":\"$ETQ\",\"objetivos\":\"$OBJ\",\"duracion_s\":$((FIN - INI)),"
  echo "\"cpu_max_pct\":$(q "max_over_time((100 - avg by (nodo)(rate(node_cpu_seconds_total{mode=\"idle\"}[30s])) * 100)[${D}s:10s])"),"
  echo "\"memoria_max_pct\":$(q "max_over_time(((1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100)[${D}s:10s])"),"
  echo "\"p95_backend_max_s\":$(q "max_over_time(histogram_quantile(0.95, sum by (le, nodo)(rate(http_server_requests_seconds_bucket{job=\"backend\"}[30s])))[${D}s:10s])"),"
  echo "\"hikari_activas_max\":$(q "max_over_time(hikaricp_connections_active{job=\"backend\"}[${D}s])"),"
  echo "\"hikari_pendientes_max\":$(q "max_over_time(hikaricp_connections_pending{job=\"backend\"}[${D}s])"),"
  echo "\"conexiones_bd_max\":$(q "max_over_time((sum by (nodo)(pg_stat_activity_count))[${D}s:10s])")"
  echo "}"
} > "$DIR/salida/$ESC-$ETQ.prometheus.json"
echo "terminado: $DIR/salida/$ESC-$ETQ.json"
