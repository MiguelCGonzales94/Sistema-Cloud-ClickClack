#!/bin/sh
# PRUEBA DE RESTAURACIÓN: baja un respaldo de Azure Blob, verifica su integridad, lo restaura en una base
# DESCARTABLE (un contenedor aislado, sin puertos publicados) y la compara con la base en producción.
# Mide cuánto tarda (esa es la parte del RTO de un desastre que se recupera desde respaldo).
#     sh ~/respaldos/restaurar.sh            # el respaldo más reciente
#     sh ~/respaldos/restaurar.sh 2026/11/23/clickclak-20261123T120000Z.dump
#
# NO toca la base de producción: solo la lee (rol `respaldo`, solo lectura) para comparar conteos.
# Un respaldo que nunca se ha restaurado no es un respaldo: esta prueba debe repetirse periódicamente.
set -eu

DIR="${DIR:-$HOME/respaldos}"
# shellcheck disable=SC1091
. "$DIR/respaldos.env"
: "${CUENTA:?Falta CUENTA en respaldos.env}"
CONTENEDOR="respaldos"
IMAGEN="postgis/postgis:16-3.4"
VERSION_API="2022-11-02"
BASE="https://$CUENTA.blob.core.windows.net/$CONTENEDOR"
TMP="$DIR/tmp"; mkdir -p "$TMP"
CONT="restauracion-prueba"

TOKEN=$(curl -fsS -H "Metadata:true" \
    "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F" \
    | jq -r .access_token)
api() { curl -fsS -H "Authorization: Bearer $TOKEN" -H "x-ms-version: $VERSION_API" "$@"; }

BLOB="${1:-}"
if [ -z "$BLOB" ]; then
    # Los nombres llevan la fecha (AAAA/MM/DD/clickclak-AAAAMMDDThhmmssZ.dump): entre los que cumplen ESE patrón (un
    # archivo ajeno no se elige aunque ordene después), el último en orden alfabético es el más reciente.
    BLOB=$(api "$BASE?restype=container&comp=list&prefix=20" \
        | grep -o '<Name>[^<]*/clickclak-[0-9]\{8\}T[0-9]\{6\}Z\.dump</Name>' | sed 's/<[^>]*>//g' | sort | tail -1)
fi
[ -n "$BLOB" ] || { echo "No hay respaldos en el contenedor." >&2; exit 1; }
echo "Respaldo: $BLOB"

t0=$(date +%s.%N)
api -o "$TMP/restaurar.dump" "$BASE/$BLOB"
api -o "$TMP/restaurar.dump.sha256" "$BASE/$BLOB.sha256"
ESPERADA=$(cut -d' ' -f1 "$TMP/restaurar.dump.sha256")
OBTENIDA=$(sha256sum "$TMP/restaurar.dump" | cut -d' ' -f1)
[ "$ESPERADA" = "$OBTENIDA" ] || { echo "INTEGRIDAD: la huella SHA-256 NO coincide. Respaldo corrupto." >&2; exit 1; }
t1=$(date +%s.%N)
echo "Integridad verificada (SHA-256 coincide). Descarga: $(echo "$t1 - $t0" | bc) s, $(wc -c < "$TMP/restaurar.dump") bytes."

docker rm -f "$CONT" > /dev/null 2>&1 || true
trap 'docker rm -f "$CONT" > /dev/null 2>&1 || true' EXIT   # no dejar el contenedor descartable si algo falla
docker run -d --name "$CONT" -e POSTGRES_PASSWORD=descartable "$IMAGEN" > /dev/null
# Por TCP (127.0.0.1): durante su inicialización la imagen levanta un servidor temporal solo por socket y
# lo apaga; por socket pg_isready lo daría por listo demasiado pronto.
for i in $(seq 1 60); do docker exec "$CONT" pg_isready -h 127.0.0.1 -U postgres > /dev/null 2>&1 && break; sleep 1; done
# Base VACÍA (template0): la imagen postgis ya instala sus extensiones en la base por defecto y el
# respaldo las crea de nuevo (CREATE SCHEMA tiger ... ya existe). Restaurar en una base limpia es lo correcto.
docker exec "$CONT" psql -U postgres -qc "CREATE DATABASE clickclak_restaurada TEMPLATE template0"
docker cp "$TMP/restaurar.dump" "$CONT:/tmp/restaurar.dump"
t2=$(date +%s.%N)
docker exec "$CONT" pg_restore -U postgres -d clickclak_restaurada --no-owner --no-acl --exit-on-error /tmp/restaurar.dump
t3=$(date +%s.%N)
echo "Restauración terminada en $(echo "$t3 - $t2" | bc) s."

CONTEOS="SELECT table_name || '=' || (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' AND table_name NOT IN ('token_revocado','intento_fallido','token_recuperacion','desafio_webauthn') ORDER BY 1"
docker exec "$CONT" psql -U postgres -d clickclak_restaurada -tAc "$CONTEOS" > "$TMP/conteos_restaurada.txt"
docker run --rm -e PGPASSWORD="$(cat "$DIR/secretos/respaldo_clave")" -v "$DIR/ca.crt":/ca/ca.crt:ro "$IMAGEN" \
    psql "host=10.0.0.4,10.0.0.5 port=5432 dbname=clickclak user=respaldo target_session_attrs=prefer-standby connect_timeout=3 sslmode=verify-full sslrootcert=/ca/ca.crt" \
    -tAc "$CONTEOS" > "$TMP/conteos_produccion.txt"
TABLAS=$(wc -l < "$TMP/conteos_restaurada.txt")
if diff -q "$TMP/conteos_restaurada.txt" "$TMP/conteos_produccion.txt" > /dev/null; then
    COMPARACION="IGUALES"
else
    COMPARACION="DIFERENTES"; diff "$TMP/conteos_restaurada.txt" "$TMP/conteos_produccion.txt" || true
fi
POSTGIS=$(docker exec "$CONT" psql -U postgres -d clickclak_restaurada -tAc "SELECT extversion FROM pg_extension WHERE extname='postgis'" | tr -d ' ')
echo "Tablas comparadas: $TABLAS | conteos restaurada vs producción: $COMPARACION | PostGIS: ${POSTGIS:-no}"

rm -f "$TMP/restaurar.dump" "$TMP/restaurar.dump.sha256"
printf '{"blob":"%s","descarga_s":%s,"restauracion_s":%s,"total_s":%s,"tablas":%s,"conteos":"%s","postgis":"%s"}\n' \
    "$BLOB" "$(echo "$t1 - $t0" | bc)" "$(echo "$t3 - $t2" | bc)" "$(echo "$t3 - $t0" | bc)" "$TABLAS" "$COMPARACION" "${POSTGIS:-}" \
    | tee "$DIR/ultima-restauracion.json"
