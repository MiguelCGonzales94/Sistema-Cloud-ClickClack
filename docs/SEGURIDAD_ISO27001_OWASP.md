# ClickClak Cloud — Seguridad: ISO/IEC 27001:2022 y OWASP Top 10

Fecha: 2026-11-22 · Estado: **diseño y plan de evidencias** (nada implementado todavía en esta fase).
Topología base: 3 servidores — nodo 1 y nodo 2 idénticos (aplicación y base replicada) y un testigo (quórum, observabilidad y respaldos). Ver `DECISION_TOPOLOGIA.md`.

## 1. Alcance y límites de lo que se afirma

- **Qué es:** un proyecto académico que **adopta y alinea** sus controles con ISO/IEC 27001:2022 y OWASP Top 10. **No es una certificación**, ni existe auditoría externa. En el informe se debe decir "alineado con", nunca "cumple" ni "certificado".
- **Alcance del SGSI aplicado:** la plataforma ClickClak Cloud en Azure (3 VM, red virtual, balanceador, almacenamiento de respaldos), su código, su pipeline de entrega y los datos que procesa.
- **Fuera de alcance:** las instalaciones físicas y la infraestructura base de Azure (responsabilidad compartida: el proveedor gestiona el centro de datos; el equipo gestiona lo que despliega sobre él). Se declara así en la Declaración de Aplicabilidad.
- **Edición de OWASP:** se mantiene la **2021** por consistencia con el APF2. *Por verificar:* si procede adoptar una edición más reciente.
- **Datos personales:** el sistema trata asistencia y **ubicación** de personas. En Perú aplica la Ley N.º 29733 de Protección de Datos Personales. *Por verificar con la docente o asesoría legal:* obligaciones concretas (consentimiento, registro del banco de datos, versión vigente del reglamento). No se asume cumplimiento.

## 2. Activos y clasificación (A.5.9, A.5.12)

| Activo | Clasificación | Dónde vive | Riesgo principal |
|---|---|---|---|
| Marcaciones y ubicaciones | Confidencial (datos personales) | PostgreSQL (nodos 1 y 2), respaldos en Blob | Acceso indebido, pérdida, divulgación |
| Credenciales y claves públicas WebAuthn | Confidencial | PostgreSQL | Robo, enumeración, fuerza bruta |
| Secretos (JWT, BD, replicación) | Secreto | `.env` de cada nodo | Fuga, reutilización |
| Clave privada TLS y claves SSH | Secreto | Nodos | Copia indebida |
| Respaldos | Confidencial | Azure Blob | Exposición, restauración no probada |
| Código e imágenes | Interno | GitHub, registro de imágenes | Manipulación de la cadena de suministro |
| Bitácoras y métricas | Interno | Nodos y testigo | Pérdida, manipulación |

## 3. Riesgos que introduce la arquitectura de 3 servidores

| ID | Riesgo | Control principal | Estado |
|---|---|---|---|
| R1 | Copiar certificado, `JWT_SECRET` y `.env` entre nodos amplía la superficie de secretos | Secretos por nodo con permisos 600; rotación documentada; plan para llevar secretos a Azure Key Vault (*por evaluar costo*) | Nuevo |
| R2 | Split-brain en la base de datos | Un solo escritor, fencing, quórum con el testigo, `targetServerType=primary` | Nuevo |
| R3 | Tráfico de replicación y aplicación → BD sin cifrar (riesgo aceptado en el APF2) | TLS interno obligatorio y SCRAM | **Implementado** (TLS 1.3 `verify-full`; `pg_hba` rechaza lo no cifrado; ver `ENDURECIMIENTO_F5.md`) |
| R4 | Panel de Grafana/Prometheus expuesto | Sin IP pública; acceso por túnel SSH o NSG restringido a IP del equipo | Nuevo |
| R5 | Respaldos con credenciales de almacenamiento en un servidor | Identidad administrada de la VM con permiso mínimo sobre un contenedor Blob | **Implementado** (sin claves ni SAS en las VM) |
| R6 | Acceso SSH abierto a cualquier IP (riesgo del APF2) | NSG: 22 solo desde la IP del equipo; llave sin contraseña; `fail2ban` | **Implementado** (solo la IP del equipo; los demás integrantes deben añadir la suya) |
| R7 | Estado en memoria del backend impide varias instancias (y revocar tokens de forma consistente) | Mover tokens revocados, intentos fallidos y desafíos WebAuthn a PostgreSQL | Nuevo |
| R8 | Restauración nunca probada | Prueba periódica de restauración con RTO/RPO medidos | **Implementado** (prueba semanal en cron; medida: 9,4 s) |
| R9 | Cadena de suministro: imágenes y dependencias | Imágenes fijadas por versión y digest, Trivy y análisis de dependencias en el CI | **Parcial**: Trivy en CI en cada cambio y semanalmente (backend 51→4 aceptados con caducidad, frontends y proxy 0); falta fijar por digest las imágenes base de los Dockerfile |
| R10 | Bitácoras sin alertas de seguridad (A09 parcial en el APF2) | Alertmanager en el testigo: 401/429 repetidos, cuentas bloqueadas, accesos fallidos a la BD | Nuevo |

## 4. Declaración de aplicabilidad resumida (ISO/IEC 27001:2022, Anexo A)

Estados: **Existente** (ya evidenciado en el APF2), **Nuevo** (a implementar aquí), **Azure** (responsabilidad del proveedor), **N/A**. Etapas: E1 a E5 según `DECISION_TOPOLOGIA.md` §6.

### A.5 Controles organizacionales

| Control | Aplicación en el proyecto | Evidencia prevista | Estado |
|---|---|---|---|
| 5.1 Políticas de seguridad | Política breve de seguridad y de uso de secretos del proyecto | `docs/seguridad/politica.md` | Nuevo (E1) |
| 5.2 Roles y responsabilidades | Scrum Master / PO / desarrolladores con responsabilidades de seguridad por componente | Matriz RACI en el informe | Existente (APF2 8.2.5) + Nuevo |
| 5.3 Separación de funciones | Nadie revisa lo que él mismo registra (C13); revisión por pares de PR | C13, regla de PR | Existente |
| 5.8 Seguridad en la gestión de proyectos | Riesgos de seguridad en el backlog y revisión por sprint | Tablero Jira | Existente |
| 5.9 Inventario de activos | Tabla de §2 más inventario de recursos Azure por etiquetas (`curso=servicios-cloud`) | Exportación de recursos | Nuevo (E1) |
| 5.12 Clasificación de la información | Clasificación de §2 | Este documento | Nuevo |
| 5.15–5.18 Control de acceso, identidad, autenticación, derechos | Roles por operación (C12), WebAuthn, bcrypt, bloqueo (C8–C11); alta y baja de accesos Azure por RBAC | Pruebas de roles; revisión de RBAC | Existente + Nuevo |
| 5.19–5.22 Proveedores | Microsoft Azure y GitHub como proveedores; revisión de sus certificaciones y términos | Anexo del informe con enlaces a sus informes de cumplimiento | Nuevo |
| 5.23 Seguridad de servicios en la nube | Modelo de responsabilidad compartida, NSG, identidades administradas, cifrado, región permitida | §5 de `ARQUITECTURA_OBJETIVO.md` | Nuevo (E1) |
| 5.24–5.27 Gestión de incidentes | Procedimiento de incidentes (detección → clasificación → respuesta → lección aprendida), apoyado en alertas y en el ensayo de fallas | `docs/seguridad/incidentes.md`; registro de incidentes de las pruebas de falla | Nuevo (E3–E4) |
| 5.29–5.30 Continuidad y preparación TIC | Plan de recuperación (DRP): réplica, promoción, respaldos, RTO/RPO medidos | DRP del informe; resultados de E4 | Nuevo (E4) |
| 5.31 / 5.34 Requisitos legales y privacidad | Ley N.º 29733: minimización, finalidad y acceso a ubicación (*por verificar*) | Nota legal en el informe | Pendiente |
| 5.37 Procedimientos operativos documentados | Scripts versionados: despliegue, promoción, restauración, rotación de secretos | `infra/scripts/` | Existente + Nuevo |

### A.6 y A.7 Personas y físicos

| Control | Aplicación | Estado |
|---|---|---|
| 6.3 Concienciación | Charla breve de seguridad del equipo y de uso de secretos antes de la sustentación | Nuevo |
| 6.7 Trabajo remoto | Acceso solo por llave SSH y desde IP autorizada | Nuevo (R6) |
| 7.1–7.14 Seguridad física | Centro de datos de Azure; no se gestiona en el proyecto | Azure |

### A.8 Controles tecnológicos

| Control | Aplicación | Evidencia prevista | Estado |
|---|---|---|---|
| 8.1 Dispositivos de usuario | WebAuthn delega la biometría al dispositivo; no se almacenan datos biométricos | APF2 6.3.1 | Existente |
| 8.2 Privilegios de acceso | Rol de BD de ejecución sin superusuario ni DDL; rol de migración separado; RBAC Azure con mínimo privilegio | Scripts de roles; asignaciones RBAC | Existente + Nuevo (E1) |
| 8.3 Restricción de acceso a la información | Mínimo privilegio en listados (C12); `pg_hba` por CIDR | Pruebas por rol | Existente + Nuevo |
| 8.4 Acceso al código fuente | Rama principal protegida, revisión por pares | Configuración del repo | Existente |
| 8.5 Autenticación segura | WebAuthn, bcrypt, bloqueo; segundo factor para administradores (pendiente del APF2) | C8–C11 | Existente + Pendiente |
| 8.6 Gestión de capacidad | Plan de capacidad y pruebas de carga P1–P4 con 1 y 2 instancias | Resultados k6 | Existente (plan) + Nuevo (E2) |
| 8.7 Protección contra malware | Imágenes oficiales, escaneo Trivy en el CI, sin ejecución de software no versionado | Informe de Trivy | Nuevo (E1) |
| 8.8 Vulnerabilidades técnicas | Análisis de dependencias (react-router migrado; backend analizado) y escaneo continuo | CLICKCLACK-68/69; Trivy (`ENDURECIMIENTO_F5.md`) | Existente + **Implementado** (Spring Boot 3.5.14; escaneo aún manual) |
| 8.9 Gestión de configuración | Infraestructura como código (Bicep) y compose versionados; línea base de configuración | Repositorio | Nuevo (E1) |
| 8.10 Eliminación de información | Retención de bitácoras y respaldos con caducidad; borrado de los datos de prueba al cerrar | Política de retención | Nuevo (E4) |
| 8.12 Prevención de fuga de datos | Sin datos reales en pruebas; respaldos en contenedor privado, sin acceso público | Configuración Blob | Nuevo (E4) |
| 8.13 Respaldo de la información | Respaldos horarios a Blob con restauración probada | `docs/evidencias/respaldo-y-restauracion/` | **Implementado** (2026-11-23) |
| 8.14 Redundancia de las instalaciones de procesamiento | 2 nodos activos, balanceador con sondeo, réplica con promoción | Prueba de falla en vivo | Nuevo (E1–E4) |
| 8.15 Registro | Bitácora de auditoría (C18), registros de Nginx, conexiones y fallos de autenticación de PostgreSQL | Capturas de registros | Existente + Nuevo |
| 8.16 Actividades de monitoreo | Prometheus, Grafana, Alertmanager y sonda externa en el testigo | Tablero y alertas | Nuevo (E3) |
| 8.17 Sincronización de relojes | NTP/chrony en las 3 VM (importa para WAL, JWT y registros) | `chronyc tracking` | Nuevo (E1) |
| 8.20 Seguridad de redes | NSG por subred, solo el balanceador y los nodos reciben tráfico público necesario | Reglas NSG | Existente (C7) + Nuevo |
| 8.21 Seguridad de servicios de red | Balanceador Estándar con sondeo; TLS 1.2/1.3 | Configuración LB | Nuevo (E1) |
| 8.22 Segregación de redes | Subredes y redes Docker `publica`/`privada` (interna) | Diagrama y configuración | Nuevo (E1) |
| 8.23 Filtrado web | Salida a Internet restringida desde los nodos de datos | NSG de salida | Nuevo (E1) |
| 8.24 Criptografía | TLS externo e interno, SCRAM, discos y Blob cifrados, respaldos cifrados; gestión y rotación de claves | C1, C4, C22 + TLS interno `verify-full` | **Implementado** (falta renovación automática de certificados) |
| 8.25 Ciclo de vida de desarrollo seguro | CI, revisión por pares, pruebas, etiquetas de versión | APF2 cap. IX | Existente |
| 8.26 Requisitos de seguridad de las aplicaciones | Controles C1–C22 como requisitos verificables | APF2 6.3.3 | Existente |
| 8.27 Arquitectura segura | Capas, mínima superficie, un solo escritor, quórum | Diagramas lógico y físico | Existente + Nuevo |
| 8.28 Codificación segura | Consultas parametrizadas, validación de entradas (C14), errores uniformes (C15) | Pruebas | Existente |
| 8.29 Pruebas de seguridad | Prueba de humo de 52 comprobaciones, pruebas de roles, escaneo de imágenes; **prueba ofensiva básica** (pendiente del APF2) | Resultados | Existente + Nuevo (E5) |
| 8.31 Separación de entornos | Desarrollo local, pruebas y producción diferenciados; sin cuenta de desarrollo en producción (C20) | Configuración | Existente |
| 8.32 Gestión de cambios | Proceso del APF2 8.2 (tipos, riesgo, reversión); cambios de infraestructura vía IaC y PR | Registro de cambios | Existente |
| 8.33 Información de prueba | Datos sintéticos en pruebas | Scripts de carga | Existente |
| 8.34 Protección durante pruebas de auditoría | Pruebas de carga y de falla solo en la ventana acordada | Plan de pruebas | Nuevo |

## 5. OWASP Top 10 (2021) frente a la arquitectura de 3 servidores

La columna "APF2" es el estado declarado en el informe de Integrador II; "Aquí" es lo que añade este proyecto.

| Categoría | APF2 | Aquí (controles nuevos o reforzados) | Etapa |
|---|---|---|---|
| **A01 Control de acceso roto** | Implementado (C12, C13, C7) | Matriz automática de roles por endpoint (pendiente del APF2); roles de BD con mínimo privilegio; NSG que limita 5432 y 22 | E1–E2 |
| **A02 Fallos criptográficos** | Parcial (sin TLS interno) → **Implementado aquí** | **TLS entre aplicación → BD y primaria → réplica**; SCRAM; respaldos cifrados; secretos por nodo con rotación documentada | E1, E4 |
| **A03 Inyección** | Implementado | Mantener parámetros nombrados; el rol de ejecución no puede usar `COPY PROGRAM`; sin extensiones como `dblink` | E1 |
| **A04 Diseño inseguro** | Parcial (sin modelo de amenazas) | **Modelo de amenazas** del sistema de 3 servidores (R1–R10); fencing y quórum; RPO/RTO definidos y medidos | E1, E4 |
| **A05 Configuración incorrecta** | Implementado | Sin IP ni puerto público para la BD y el testigo; NSG de denegación por defecto; contenedores no root con `HEALTHCHECK`; base de configuración en IaC; `pg_hba` por CIDR | E1 |
| **A06 Componentes vulnerables** | Parcial → atendido (CLICKCLACK-68/69) | Trivy y análisis de dependencias en cada PR; imágenes fijadas por versión y digest; plan de actualización | E1 |
| **A07 Fallos de autenticación** | Parcial | Segundo factor para supervisores y RR. HH. (pendiente); contraseñas de BD generadas y rotadas; SSH solo con llave; credenciales de respaldo por identidad administrada | E2, E4 |
| **A08 Integridad de software y datos** | Parcial (sin firma de imágenes) | Imágenes versionadas desde GHCR; verificación de firma o digest; `data_checksums`; `pg_verifybackup` en cada respaldo; IaC revisada por PR | E1, E4 |
| **A09 Registro y monitoreo** | Parcial (sin alertas) | **Alertmanager en el testigo**: 401/429 repetidos, cuentas bloqueadas, retraso o corte de réplica, accesos fallidos a la BD; `log_connections`/`log_disconnections` | E3 |
| **A10 SSRF** | No aplica | Sigue sin aplicar: la sonda externa consulta solo URL fijas propias; no hay peticiones a destinos indicados por el usuario | — |

## 6. Plan de evidencias para el informe y la sustentación

| Etapa | Evidencia a capturar | Sirve para |
|---|---|---|
| E1 | Reglas NSG por subred; TLS interno activo; escaneo Trivy sin críticos; `chronyc`; etiquetas de recursos; roles de BD | ISO 8.2, 8.9, 8.17, 8.20–8.24; OWASP A02, A05, A06 |
| E2 | Matriz de roles ejecutada en 2 instancias; pruebas k6; login consistente entre nodos | ISO 8.6, 8.29; OWASP A01, A07 |
| E3 | Tablero de Grafana y alertas de seguridad disparadas en vivo | ISO 8.15, 8.16; OWASP A09 |
| E4 | Respaldo cifrado a Blob, restauración medida, DRP, fencing, promoción | ISO 5.29, 5.30, 8.13, 8.14; OWASP A02, A08 |
| E5 | Prueba ofensiva básica y su informe; revisión interna del SoA (auditoría interna simulada) | ISO 8.29, cláusula 9.2 |

**Auditoría interna simulada:** antes de la sustentación, revisar este documento contra las evidencias reales y marcar cada control como *Implementado*, *Parcial* o *No implementado*. Lo no evidenciado no se declara.

## 7. Riesgos abiertos que se declaran

- Sin certificación ni auditoría externa; sin prueba de penetración independiente hasta E5.
- Segundo factor para administradores y tráfico interno cifrado siguen pendientes hasta implementarlos.
- Gestión de secretos con Azure Key Vault evaluada pero no decidida (costo).
- Cumplimiento de la Ley N.º 29733 sin validar legalmente.
- Los nodos de aplicación y base comparten host; se mitiga con red interna, `pg_hba`, TLS y NSG.
