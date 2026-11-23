# Proxy inverso con los paquetes del sistema al día (OWASP A06). Antes se usaba la imagen nginx:1.27-alpine tal
# cual; construirla aquí permite aplicar `apk upgrade` y que el escaneo de Trivy no marque bibliotecas ya corregidas.
# La configuración (plantillas, certificados) sigue montándose desde el host: no cambia nada más.
FROM nginx:1.27-alpine
RUN apk upgrade --no-cache
