#!/bin/sh
# Balanceador de carga de ClickClak en Azure (infraestructura como código con Azure CLI).
# Es idempotente: se puede volver a ejecutar sin duplicar nada.
#
#   sh infra/azure/balanceador.sh crear          crea la IP, el balanceador, el sondeo, las reglas y suma los nodos
#   sh infra/azure/balanceador.sh salida-y-ssh   regla de salida a Internet y SSH por NAT (puertos 2201/2202)
#   sh infra/azure/balanceador.sh agregar-testigo  suma el testigo al grupo de salida y le da SSH (2203)
#   sh infra/azure/balanceador.sh quitar-ip NIC CONFIG IP   retira y borra la IP pública de un nodo
#   sh infra/azure/balanceador.sh mover-dns      pasa el nombre DNS público del nodo 1 al balanceador
#   sh infra/azure/balanceador.sh eliminar       borra el balanceador y su IP (el balanceador cobra mientras exista)
#
# Diseño (ver docs/DECISION_TOPOLOGIA.md):
#   - Azure Load Balancer Estándar, capa 4: el TLS lo termina el Nginx de cada nodo, con el mismo
#     certificado del mismo dominio, así que el balanceador no descifra nada.
#   - Sondeo HTTPS a /salud (Nginx -> /actuator/health del backend): un nodo cuyo backend cae sale
#     del reparto en ~10 s (intervalo 5 s x 2 fallos), aunque su Nginx siga vivo.
#   - Un nodo recibe tráfico solo mientras su backend responde; el estado del backend es compartido
#     (PostgreSQL), así que cualquier nodo atiende cualquier petición.
set -eu

# Git Bash en Windows convierte los argumentos que empiezan con "/" en rutas de Windows (/salud se
# volvía C:/Program Files/Git/salud y el sondeo del balanceador apuntaba a una ruta inexistente: el
# balanceador probaba el frontend en vez del backend). Esta variable lo impide.
export MSYS_NO_PATHCONV=1

RG="${RG:-rg-clickclak}"
UBICACION="${UBICACION:-chilecentral}"
LB="${LB:-lb-clickclak}"
IP="${IP:-lb-clickclak-ip}"
FRONTEND="fe-clickclak"
POOL="be-nodos"
SONDA="sonda-salud"
DNS_ETIQUETA="${DNS_ETIQUETA:-clickclak-utp}"
ETIQUETAS="curso=servicios-cloud proyecto=clickclak"
# NIC y configuración de IP de cada nodo (nombres de los recursos que creó Azure).
NODOS="vm-clickclakVMNic:ipconfigvm-clickclak vm-clickclak-2VMNic:ipconfigvm-clickclak-2"
VIEJA_IP="${VIEJA_IP:-vm-clickclakPublicIP}"

crear() {
    echo "== IP pública del balanceador"
    az network public-ip create -g "$RG" -n "$IP" --location "$UBICACION" \
        --sku Standard --allocation-method Static --tags $ETIQUETAS -o none

    echo "== Balanceador Estándar"
    az network lb create -g "$RG" -n "$LB" --location "$UBICACION" --sku Standard \
        --public-ip-address "$IP" --frontend-ip-name "$FRONTEND" --backend-pool-name "$POOL" \
        --tags $ETIQUETAS -o none

    echo "== Sondeo de salud (HTTPS /salud)"
    az network lb probe create -g "$RG" --lb-name "$LB" -n "$SONDA" \
        --protocol Https --port 443 --path /salud --interval 5 --probe-threshold 2 -o none

    for puerto in 80 443 8443; do
        echo "== Regla TCP $puerto"
        az network lb rule create -g "$RG" --lb-name "$LB" -n "regla-$puerto" \
            --protocol Tcp --frontend-port "$puerto" --backend-port "$puerto" \
            --frontend-ip-name "$FRONTEND" --backend-pool-name "$POOL" --probe-name "$SONDA" \
            --idle-timeout 4 -o none
    done

    for par in $NODOS; do
        nic="${par%%:*}"
        config="${par##*:}"
        echo "== Nodo en el grupo de back-end: $nic"
        az network nic ip-config address-pool add -g "$RG" --nic-name "$nic" --ip-config-name "$config" \
            --lb-name "$LB" --address-pool "$POOL" -o none
    done
    echo "IP del balanceador: $(az network public-ip show -g "$RG" -n "$IP" --query ipAddress -o tsv)"
}

# Red privada: los nodos pierden su IP pública y el balanceador pasa a ser el ÚNICO punto público.
#   - Salida a Internet (apt, imágenes Docker, geocodificación) por una regla de salida del balanceador.
#   - Acceso SSH por reglas NAT del balanceador: puerto 2201 -> nodo 1, 2202 -> nodo 2, 2203 -> testigo.
# Motivo: la suscripción de estudiante tiene un tope de 3 IP públicas, y además es el diseño
# recomendado (OWASP A05; ISO 27001 8.20-8.22): menos superficie expuesta.
POOL_SALIDA="be-salida"

salida_y_ssh() {
    echo "== Grupo de salida y regla de salida"
    az network lb address-pool create -g "$RG" --lb-name "$LB" -n "$POOL_SALIDA" -o none
    # Con una regla de salida explícita, las reglas de entrada no deben hacer SNAT.
    for puerto in 80 443 8443; do
        az network lb rule update -g "$RG" --lb-name "$LB" -n "regla-$puerto" --disable-outbound-snat true -o none
    done
    az network lb outbound-rule create -g "$RG" --lb-name "$LB" -n salida \
        --frontend-ip-configs "$FRONTEND" --address-pool "$POOL_SALIDA" \
        --protocol All --outbound-ports 8000 --idle-timeout 15 -o none

    puerto_ssh=2201
    for par in $NODOS; do
        nic="${par%%:*}"; config="${par##*:}"
        echo "== $nic: grupo de salida y SSH por el puerto $puerto_ssh"
        az network nic ip-config address-pool add -g "$RG" --nic-name "$nic" --ip-config-name "$config" \
            --lb-name "$LB" --address-pool "$POOL_SALIDA" -o none
        az network lb inbound-nat-rule create -g "$RG" --lb-name "$LB" -n "ssh-$puerto_ssh" \
            --protocol Tcp --frontend-port "$puerto_ssh" --backend-port 22 --frontend-ip-name "$FRONTEND" -o none
        az network nic ip-config inbound-nat-rule add -g "$RG" --nic-name "$nic" --ip-config-name "$config" \
            --lb-name "$LB" --inbound-nat-rule "ssh-$puerto_ssh" -o none
        puerto_ssh=$((puerto_ssh + 1))
    done
}

# Añade el testigo (tercer servidor) al grupo de salida y le da su puerto SSH (2203).
agregar_testigo() {
    nic="${NIC_TESTIGO:-vm-clickclak-3VMNic}"; config="${CONFIG_TESTIGO:-ipconfig1}"
    az network nic ip-config address-pool add -g "$RG" --nic-name "$nic" --ip-config-name "$config" \
        --lb-name "$LB" --address-pool "$POOL_SALIDA" -o none
    az network lb inbound-nat-rule create -g "$RG" --lb-name "$LB" -n "ssh-2203" \
        --protocol Tcp --frontend-port 2203 --backend-port 22 --frontend-ip-name "$FRONTEND" -o none
    az network nic ip-config inbound-nat-rule add -g "$RG" --nic-name "$nic" --ip-config-name "$config" \
        --lb-name "$LB" --inbound-nat-rule "ssh-2203" -o none
}

# Quita la IP pública de una NIC y la elimina. Solo después de comprobar SSH y salida por el balanceador.
quitar_ip() {
    nic="$1"; config="$2"; ip="$3"
    az network nic ip-config update -g "$RG" --nic-name "$nic" -n "$config" --remove publicIpAddress -o none
    az network public-ip delete -g "$RG" -n "$ip" -o none
}

mover_dns() {
    echo "== El nombre $DNS_ETIQUETA pasa de $VIEJA_IP al balanceador"
    az network public-ip update -g "$RG" -n "$VIEJA_IP" --dns-name "" -o none
    az network public-ip update -g "$RG" -n "$IP" --dns-name "$DNS_ETIQUETA" -o none
    az network public-ip show -g "$RG" -n "$IP" --query dnsSettings.fqdn -o tsv
}

eliminar() {
    echo "== Eliminando balanceador e IP (el cobro se detiene)"
    az network lb delete -g "$RG" -n "$LB" -o none || true
    az network public-ip delete -g "$RG" -n "$IP" -o none || true
}

case "${1:-}" in
    crear) crear ;;
    salida-y-ssh) salida_y_ssh ;;
    agregar-testigo) agregar_testigo ;;
    quitar-ip) shift; quitar_ip "$@" ;;
    mover-dns) mover_dns ;;
    eliminar) eliminar ;;
    *) echo "Uso: sh $0 {crear|salida-y-ssh|agregar-testigo|quitar-ip NIC CONFIG IP|mover-dns|eliminar}" >&2; exit 2 ;;
esac
