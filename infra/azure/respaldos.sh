#!/bin/sh
# Almacenamiento de respaldos en Azure (infraestructura como código con Azure CLI). Idempotente.
#
# (ejecutar desde la raíz del repositorio)
#   sh infra/azure/respaldos.sh crear      cuenta de almacenamiento privada, contenedor, retención e identidad
#   sh infra/azure/respaldos.sh eliminar   borra la cuenta (y TODOS los respaldos)
#
# Diseño de seguridad (OWASP A02/A05/A07; ISO 27001 8.13, 8.24, 5.17):
#   - Cuenta con TLS 1.2 mínimo, solo HTTPS y SIN acceso público a blobs; cifrado en reposo por defecto de Azure.
#   - El testigo sube y lee con su IDENTIDAD ADMINISTRADA y el rol "Storage Blob Data Contributor" limitado a
#     ESTE contenedor: no hay claves de almacenamiento ni SAS guardados en ninguna VM.
#   - Una política de ciclo de vida borra los respaldos con más de 14 días.
set -eu
export MSYS_NO_PATHCONV=1   # Git Bash en Windows convertiría los ámbitos "/subscriptions/..." en rutas de Windows

RG="${RG:-rg-clickclak}"
UBICACION="${UBICACION:-chilecentral}"
CONTENEDOR="respaldos"
VM_TESTIGO="${VM_TESTIGO:-vm-clickclak-3}"
ARCHIVO_CUENTA="$(cd "$(dirname "$0")" && pwd)/.cuenta-respaldos"
ETIQUETAS="curso=servicios-cloud proyecto=clickclak rol=respaldos"

crear() {
    if [ -s "$ARCHIVO_CUENTA" ]; then CUENTA=$(cat "$ARCHIVO_CUENTA"); else
        CUENTA="stclickclak$(openssl rand -hex 3)"
        az storage account check-name -n "$CUENTA" --query nameAvailable -o tsv | grep -q true || { echo "nombre no disponible: $CUENTA" >&2; exit 1; }
        echo "$CUENTA" > "$ARCHIVO_CUENTA"
    fi
    echo "== Cuenta de almacenamiento $CUENTA"
    az storage account create -g "$RG" -n "$CUENTA" -l "$UBICACION" --sku Standard_LRS --kind StorageV2 \
        --min-tls-version TLS1_2 --allow-blob-public-access false --https-only true --tags $ETIQUETAS -o none

    echo "== Contenedor privado $CONTENEDOR"
    az storage container create --account-name "$CUENTA" -n "$CONTENEDOR" --public-access off --auth-mode key -o none

    echo "== Retención: se borran los respaldos de más de 14 días"
    # La ruta es relativa a la raíz del repositorio (az en Windows no entiende rutas /tmp de Git Bash).
    az storage account management-policy create -g "$RG" --account-name "$CUENTA" --policy "@infra/azure/politica-retencion.json" -o none

    echo "== Identidad administrada del testigo y permiso mínimo sobre el contenedor"
    PRINCIPAL=$(az vm identity assign -g "$RG" -n "$VM_TESTIGO" --query systemAssignedIdentity -o tsv)
    ALCANCE=$(az storage account show -g "$RG" -n "$CUENTA" --query id -o tsv)/blobServices/default/containers/$CONTENEDOR
    az role assignment create --assignee-object-id "$PRINCIPAL" --assignee-principal-type ServicePrincipal \
        --role "Storage Blob Data Contributor" --scope "$ALCANCE" -o none
    echo "Listo. Cuenta: $CUENTA, contenedor: $CONTENEDOR"
}

eliminar() {
    CUENTA=$(cat "$ARCHIVO_CUENTA")
    az storage account delete -g "$RG" -n "$CUENTA" --yes
}

case "${1:-}" in
    crear) crear ;;
    eliminar) eliminar ;;
    *) echo "Uso: sh $0 {crear|eliminar}" >&2; exit 2 ;;
esac
