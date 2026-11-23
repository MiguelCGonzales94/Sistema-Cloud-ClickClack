#!/bin/sh
# Despliega (o actualiza) ClickClak en la VM. Se ejecuta EN la VM, desde la carpeta infra/:
#     sh scripts/desplegar.sh
# Es idempotente: volver a ejecutarlo reconstruye lo que cambió y no toca secretos ni datos.
set -eu
cd "$(dirname "$0")/.."

DOMINIO_POR_DEFECTO="clickclak-utp.chilecentral.cloudapp.azure.com"
COMPOSE="sudo docker compose -f docker-compose.prod.yml --env-file .env"
# Rol de este nodo (opcional): copiar infra/nodos/nodo1.yml o nodo2.yml como
# docker-compose.nodo.yml. Sin ese archivo el despliegue es el de una sola VM.
if [ -f docker-compose.nodo.yml ]; then
    COMPOSE="$COMPOSE -f docker-compose.nodo.yml"
fi

# 1. Secretos: se generan una sola vez y se quedan en la VM (el archivo está fuera de git).
if [ ! -f .env ]; then
    (
        umask 077
        {
            echo "DOMINIO=$DOMINIO_POR_DEFECTO"
            echo "DB_PASSWORD=$(openssl rand -hex 24)"
            echo "JWT_SECRET=$(openssl rand -base64 48 | tr -d '\n')"
        } > .env
    )
    echo "Creado infra/.env con secretos aleatorios (permisos 600)."
fi
# Despliegues anteriores a la réplica no tienen esta variable: se agrega sin tocar las demás.
if ! grep -q '^REPLICA_PASSWORD=' .env; then
    (umask 077; echo "REPLICA_PASSWORD=$(openssl rand -hex 24)" >> .env)
    echo "Agregada REPLICA_PASSWORD a infra/.env."
fi
# Clave de las métricas de Prometheus: debe ser LA MISMA en todos los nodos (el testigo usa una sola).
# En el nodo 2 se copia la del nodo 1 antes de desplegar; si no existe, se genera aquí.
if ! grep -q '^METRICAS_CLAVE=' .env; then
    (umask 077; echo "METRICAS_CLAVE=$(openssl rand -hex 24)" >> .env)
    echo "Agregada METRICAS_CLAVE a infra/.env."
fi
# Clave del rol de solo lectura de los respaldos. Misma en los dos nodos y en el testigo.
if ! grep -q '^RESPALDO_CLAVE=' .env; then
    (umask 077; echo "RESPALDO_CLAVE=$(openssl rand -hex 24)" >> .env)
    echo "Agregada RESPALDO_CLAVE a infra/.env."
fi
DOMINIO=$(sed -n 's/^DOMINIO=//p' .env)

# 2. Certificado autofirmado temporal, para que el proxy arranque por HTTPS desde el primer
#    despliegue. Se sustituye por el de Let's Encrypt cuando se emita (ver despliegue-azure.md).
sudo mkdir -p /etc/clickclak/tls-temporal /var/www/certbot
if [ ! -f /etc/clickclak/tls-temporal/fullchain.pem ]; then
    sudo openssl req -x509 -nodes -newkey rsa:2048 -days 90 \
        -subj "/CN=$DOMINIO" -addext "subjectAltName=DNS:$DOMINIO" \
        -keyout /etc/clickclak/tls-temporal/privkey.pem \
        -out /etc/clickclak/tls-temporal/fullchain.pem 2> /dev/null
    echo "Generado el certificado temporal para $DOMINIO."
fi

# 3. Construcción SECUENCIAL: compilar el backend y los dos frontends a la vez agotaría los
#    4 GiB de la VM. Los servicios sin Dockerfile propio no se construyen.
for servicio in backend frontend-admin frontend-campo proxy; do
    echo "== construyendo $servicio"
    $COMPOSE build "$servicio"
done

# 4. Arranque. Primero la primaria, que se prepara para la replicación antes de que arranque la
#    réplica (necesita el rol, la ranura y la regla de pg_hba). `--wait` espera a que esté sana.
$COMPOSE up -d --wait postgres
# Solo la primaria se prepara: la preparación escribe en la base (rol, ranuras, pg_hba) y una standby
# es de solo lectura, así que en el nodo 2 se omite (la standby hereda todo por replicación).
EN_RECUPERACION=$($COMPOSE exec -T postgres psql -U clickclak -d clickclak -tAc 'SELECT pg_is_in_recovery()' | tr -d '[:space:]')
if [ "$EN_RECUPERACION" = "f" ]; then
    $COMPOSE exec -T -u postgres postgres sh /replicacion/preparar-primaria.sh
else
    echo "Este nodo es una standby (pg_is_in_recovery=$EN_RECUPERACION): se omite preparar-primaria.sh."
fi

# El proxy ignora el selector de certificado si no es ejecutable (ver el propio archivo).
chmod +x nginx/10-seleccionar-certificado.envsh
$COMPOSE up -d
# El proxy lee su configuración de archivos montados: Compose no ve que cambiaron, así que no
# recrea el contenedor, y Nginx solo procesa las plantillas al arrancar. Sin esta línea, un
# despliegue que cambie la configuración dejaría corriendo el proxy anterior. Tarda un segundo.
$COMPOSE up -d --force-recreate --no-deps proxy
$COMPOSE ps
