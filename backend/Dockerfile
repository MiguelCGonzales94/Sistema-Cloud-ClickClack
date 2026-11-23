# Imagen del backend en dos etapas: compilar con JDK y ejecutar solo con JRE.
#
# Optimización de construcción (criterio de contenedorización): el repositorio local de Maven se
# conserva entre construcciones con una caché de BuildKit (no forma parte de la imagen). Cambiar solo
# el código fuente ya no vuelve a descargar las dependencias, y la imagen final no arrastra ni el JDK
# ni los artefactos de compilación.
FROM eclipse-temurin:21-jdk-alpine AS build

WORKDIR /app

COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN chmod +x mvnw

COPY src/ src/
RUN --mount=type=cache,target=/root/.m2 ./mvnw -q -B -DskipTests package

FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

# curl solo para el HEALTHCHECK. El proceso corre sin privilegios (usuario clickclak).
RUN apk add --no-cache curl \
    && addgroup -S clickclak \
    && adduser -S clickclak -G clickclak

COPY --from=build /app/target/backend-0.1.0-SNAPSHOT.jar app.jar

USER clickclak
EXPOSE 8080

# Misma comprobación que usan Compose y el sondeo del balanceador: /actuator/health.
HEALTHCHECK --interval=10s --timeout=5s --start-period=40s --retries=18 \
    CMD curl -fsS http://localhost:8080/actuator/health >/dev/null || exit 1

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
