# CAPÍTULO VIII: CONCLUSIONES Y TRABAJO FUTURO

## 8.1 Conclusiones

El problema central era que ClickClak dependía de una sola máquina y de la atención manual. La arquitectura de tres servidores desplegada en Azure elimina esos puntos únicos de falla y lo demuestra con mediciones, no con diseño:

1. **Se eliminó la dependencia de un solo servidor** (OE5). Con dos nodos activos tras un balanceador, la caída de un backend se absorbe en unos 11 segundos con el 97,4 % de las sondas correctas. La caída abrupta de la base primaria se recupera en 30 a 36 segundos sin pérdida de escrituras confirmadas en cuatro ensayos reales, con aislamiento del nodo caído para evitar el *split-brain* y reincorporación con `pg_rewind`.
2. **Los datos tienen una segunda línea de defensa** (OE5). La réplica no protege de un borrado accidental (la probamos: copia el error), pero el respaldo horario a Azure Blob sí: se restauró una tabla perdida y una base completa en menos de 10 segundos, con integridad comprobada por huella SHA-256.
3. **El sistema es observable** (OE4). Veintiuna visualizaciones y diecisiete alertas, incluidas las que detectan la ausencia o el exceso de primarias, viven fuera de los nodos y siguen funcionando cuando uno cae.
4. **La capacidad está medida y supera con holgura la demanda proyectada** (OE1, OE4). Con 200 usuarios simultáneos no hubo errores; el recurso que limita es la CPU, y añadir una segunda instancia redujo la latencia p95 un 73 %.
5. **La seguridad mejoró de forma verificable** (OE6). El tráfico interno va cifrado con TLS 1.3 y el que no lo está se rechaza; las vulnerabilidades altas y críticas de las imágenes bajaron de 51, 68 y 70 a 4, 0 y 0, y un escaneo en integración continua impide que vuelvan sin que alguien las acepte por escrito.
6. **El entorno es reproducible en gran parte** (OE7): imágenes en dos etapas, orquestación versionada, scripts de despliegue, falla y respaldo, y un repositorio público con integración continua. **No del todo**: la red virtual y los nodos de aplicación se crearon a mano.

La decisión de usar máquinas virtuales con contenedores (IaaS) en lugar de servicios administrados permitió **construir y medir** la replicación, el *failover* y los respaldos, que es lo que evalúa el proyecto; el costo fue asumir su operación. En un entorno de producción un servicio administrado de base de datos sería la primera alternativa a evaluar.

## 8.2 Limitaciones principales

- La replicación es **asíncrona**: un RPO mayor que cero es posible; las pruebas dieron cero con carga ligera, lo que no es una garantía.
- La promoción de la base es **manual y guionizada**; el testigo no vota, así que no hay quórum para decidir solo.
- **No hay escalado automático** ni se probó el escalado vertical.
- Falta un **segundo factor** de autenticación, un rol de base de datos de ejecución sin permisos de DDL y una **prueba ofensiva** independiente.
- Los registros no están centralizados y los créditos de CPU de las máquinas de la serie B no se pudieron medir.

## 8.3 Trabajo futuro

@tabla Mejoras recomendadas, en orden de impacto
| Mejora | Qué resuelve |
|---|---|
| *Failover* automático con quórum (Patroni con etcd, o pg_auto_failover) haciendo votante al testigo | Recuperación sin intervención y menor tiempo de detección |
| Archivado continuo del WAL a Blob | Recuperación a un instante exacto (PITR) |
| Servidor propio para la base de datos | Evita que aplicación y base compitan por la CPU |
| Infraestructura como código completa (red, NSG y nodos) | Reproducir el entorno desde cero |
| Escalado automático con conjuntos de escalado de máquinas virtuales | Elasticidad sin intervención |
| Nodos en zonas de disponibilidad distintas y réplica en otra región | Tolerar la caída de un centro de datos o de una región |
| Registro centralizado (por ejemplo Loki), segundo factor, rol de ejecución sin DDL y prueba ofensiva | Observabilidad y seguridad |
| Publicación de imágenes en un registro y despliegue continuo | Despliegues repetibles y trazables |
