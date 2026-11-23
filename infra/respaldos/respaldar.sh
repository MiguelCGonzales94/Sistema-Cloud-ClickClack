#!/bin/sh
# Respaldo lógico de PostgreSQL a Azure Blob. Se ejecuta EN EL TESTIGO (fuera de los nodos de aplicación):
#     sh ~/respaldos/respaldar.sh
#
# Cómo lo hace (y por qué):
#   - pg_dump con el rol `respaldo` (SOLO LECTURA, pg_read_all_data): un respaldo comprometido no sirve
#     para alterar datos. La contraseña vive en ~/respaldos/secretos/respaldo_clave (permisos 600).
#   - Se conecta con target_session_attrs=prefer-standby: lee de la STANDBY y no carga a la primaria (si
#     no hay standby, usa la primaria). Los dos hosts van en la cadena, así sirve tras un failover.
#   - Formato -Fc (comprimido y restaurable por partes) y SIN propietarios ni privilegios, para poder
#     restaurar en cualquier servidor.
#   - Sube a Azure Blob con la IDENTIDAD ADMINISTRADA del testigo (token de IMDS): no hay claves de
#     almacenamiento ni SAS guardados. Contenedor privado; Azure cifra en reposo.
#   - Guarda junto al respaldo su huella SHA-256 para verificar la integridad al restaurar (OWASP A08).
#   - La retención (14 días) la aplica una política de ciclo de vida de la cuenta, no este script.
set -eu

DIR="${DIR:-$HOME/respaldos}"
# shellcheck disable=SC1091
. "$DIR/respaldos.env"                      # define CUENTA (cuenta de almacenamiento)
: "${CUENTA:?Falta CUENTA en respaldos.env}"
CONTENEDOR="respaldos"
IMAGEN="postgis/postgis:16-3.4"
VERSION_API="2022-11-02"

TS=$(date -u +%Y%m%dT%H%M%SZ)
BLOB="$(date -u +%Y/%m/%d)/clickclak-$TS.dump"
TMP="$DIR/tmp"; mkdir -p "$TMP"
ARCHIVO="$TMP/clickclak-$TS.dump"

t_ini=$(date +%s.%N)
echo "$(date -u +%FT%TZ) respaldando (preferencia: standby)..."
docker run --rm --user "$(id -u):$(id -g)" -e PGPASSWORD="$(cat "$DIR/secretos/respaldo_clave")" \
    -v "$TMP":/salida -v "$DIR/ca.crt":/ca/ca.crt:ro "$IMAGEN" \
    pg_dump "host=10.0.0.4,10.0.0.5 port=5432 dbname=clickclak user=respaldo target_session_attrs=prefer-standby connect_timeout=3 sslmode=verify-full sslrootcert=/ca/ca.crt" \
        -Fc --no-owner --no-acl -f "/salida/clickclak-$TS.dump"
t_dump=$(date +%s.%N)

( cd "$TMP" && sha256sum "clickclak-$TS.dump" > "clickclak-$TS.dump.sha256" )
TAM=$(wc -c < "$ARCHIVO")

TOKEN=$(curl -fsS -H "Metadata:true" \
    "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F" \
    | jq -r .access_token)
subir() { # $1 = archivo local, $2 = nombre del blob
    codigo=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
        -H "Authorization: Bearer $TOKEN" -H "x-ms-version: $VERSION_API" -H "x-ms-blob-type: BlockBlob" \
        -H "Content-Type: application/octet-stream" --data-binary "@$1" \
        "https://$CUENTA.blob.core.windows.net/$CONTENEDOR/$2")
    [ "$codigo" = "201" ] || { echo "Subida fallida de $2: HTTP $codigo" >&2; exit 1; }
}
subir "$ARCHIVO" "$BLOB"
subir "$ARCHIVO.sha256" "$BLOB.sha256"
t_fin=$(date +%s.%N)

rm -f "$ARCHIVO" "$ARCHIVO.sha256"
printf '{"blob":"%s/%s","bytes":%s,"dump_s":%s,"subida_s":%s,"total_s":%s,"fecha":"%s"}\n' \
    "$CONTENEDOR" "$BLOB" "$TAM" \
    "$(echo "$t_dump - $t_ini" | bc)" "$(echo "$t_fin - $t_dump" | bc)" "$(echo "$t_fin - $t_ini" | bc)" "$TS" \
    | tee -a "$DIR/respaldos.log"
