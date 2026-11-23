#!/bin/sh
# Crea el TESTIGO (tercer servidor) sin IP pública. Idempotente en lo posible.
#
#   sh infra/azure/testigo.sh crear     NSG, NIC, VM y SSH por NAT (puerto 2203 del balanceador)
#   sh infra/azure/testigo.sh eliminar  borra VM, NIC, disco y NAT (el testigo cobra mientras exista; apagarlo basta para pausar el cómputo)
#
# Por qué sin IP pública: la suscripción de estudiante tiene un tope de 3 IP públicas y el diseño
# deja al balanceador como único punto público. La NIC se crea YA dentro del grupo de salida del
# balanceador para que cloud-init tenga Internet desde el primer arranque (instala Docker).
set -eu

RG="${RG:-rg-clickclak}"
UBICACION="${UBICACION:-chilecentral}"
LB="${LB:-lb-clickclak}"
VM="vm-clickclak-3"
NIC="${VM}VMNic"
NSG="${VM}-nsg"
IP_PRIVADA="${IP_PRIVADA:-10.0.0.6}"
LLAVE_PUBLICA="${LLAVE_PUBLICA:-$HOME/.ssh/clickclak_azure.pub}"
RUTA="$(cd "$(dirname "$0")" && pwd)"
ETIQUETAS="curso=servicios-cloud proyecto=clickclak rol=testigo"

crear() {
    echo "== NSG del testigo: sin entradas desde Internet; SSH solo desde la VNet"
    az network nsg create -g "$RG" -n "$NSG" --location "$UBICACION" --tags $ETIQUETAS -o none
    az network nsg rule create -g "$RG" --nsg-name "$NSG" -n ssh-desde-vnet --priority 1000 \
        --direction Inbound --access Allow --protocol Tcp --source-address-prefixes 10.0.0.0/24 \
        --destination-port-ranges 22 -o none

    echo "== NIC con IP privada fija y dentro del grupo de salida del balanceador"
    az network nic create -g "$RG" -n "$NIC" --location "$UBICACION" \
        --vnet-name vm-clickclakVNET --subnet vm-clickclakSubnet --private-ip-address "$IP_PRIVADA" \
        --network-security-group "$NSG" --lb-name "$LB" --lb-address-pools be-salida --tags $ETIQUETAS -o none

    echo "== VM (Ubuntu 24.04, B2als_v2, 32 GiB) con cloud-init"
    az vm create -g "$RG" -n "$VM" --location "$UBICACION" \
        --image Canonical:ubuntu-24_04-lts:server:latest --size Standard_B2als_v2 \
        --os-disk-size-gb 32 --storage-sku StandardSSD_LRS --security-type Standard \
        --admin-username azureuser --ssh-key-values "$LLAVE_PUBLICA" --authentication-type ssh \
        --nics "$NIC" --custom-data "$RUTA/cloud-init-testigo.yaml" --tags $ETIQUETAS -o none

    echo "== SSH por NAT: puerto 2203 del balanceador"
    az network lb inbound-nat-rule create -g "$RG" --lb-name "$LB" -n ssh-2203 --protocol Tcp \
        --frontend-port 2203 --backend-port 22 --frontend-ip-name fe-clickclak -o none
    az network nic ip-config inbound-nat-rule add -g "$RG" --nic-name "$NIC" --ip-config-name ipconfig1 \
        --lb-name "$LB" --inbound-nat-rule ssh-2203 -o none
}

eliminar() {
    az vm delete -g "$RG" -n "$VM" --yes -o none || true
    az network nic delete -g "$RG" -n "$NIC" -o none || true
    az network lb inbound-nat-rule delete -g "$RG" --lb-name "$LB" -n ssh-2203 -o none || true
    az disk list -g "$RG" --query "[?starts_with(name, '${VM}_')].name" -o tsv | while read -r d; do
        az disk delete -g "$RG" -n "$d" --yes -o none || true
    done
}

case "${1:-}" in
    crear) crear ;;
    eliminar) eliminar ;;
    *) echo "Uso: sh $0 {crear|eliminar}" >&2; exit 2 ;;
esac
