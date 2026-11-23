FROM node:20-alpine AS build

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# Nginx sin privilegios (usuario 101, puerto 8080): si el contenedor se compromete, el proceso no es
# root (OWASP A05; ISO 27001 8.2). Por eso escucha en 8080 y no en 80.
FROM nginxinc/nginx-unprivileged:1.27-alpine

# Paquetes del sistema al día (OWASP A06): la imagen base trae bibliotecas (openssl, expat, libpng...) con
# vulnerabilidades ya corregidas en el repositorio de Alpine. Se vuelve al usuario sin privilegios después.
USER root
RUN apk upgrade --no-cache
USER 101

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=5 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1
