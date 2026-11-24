# 6. Costos, limitaciones y lecciones aprendidas

## 6.1 Costos

El proyecto corre sobre el crédito de **Azure for Students (USD 79 disponibles)**, que vence el 2 de octubre de 2027, en la región Chile Central. Los precios son **de lista**, tomados de la API pública de precios de Azure el 22 de noviembre de 2026; la cifra final aparece en Cost Management.

@tabla Precios de los recursos (USD, lista)
| Recurso | Precio | Se cobra apagado |
|---|---|---|
| VM `B2als_v2` (2 vCPU, 4 GiB) | 0,0526 por hora (38,40 al mes encendida 24/7) | No (desasignada) |
| Disco Standard SSD de 64 GiB | 6,72 al mes | **Sí** |
| IP pública Standard estática | 0,005 por hora (3,65 al mes) | **Sí** |
| Balanceador Estándar (hasta 5 reglas) | 0,025 por hora | Mientras exista |
| Blob Hot LRS (respaldos) | ≈ 0,024–0,026 por GB al mes | Centavos |

**Costo de la configuración final.** Con los tres servidores y el balanceador encendidos: 3 × 0,0526 + 0,025 + 0,005 ≈ **USD 0,19 por hora**, unos USD 4,5 por día, **sin contar los discos**. Con todo apagado quedan los tres discos (≈ USD 20 al mes) y las IP públicas que se conserven. El balanceador se **elimina** al apagar y se recrea con su script.

@tabla Costo estimado de 120 horas de pruebas según la topología (precios de lista)
| Topología | Costo (USD) |
|---|---|
| A. 2 servidores | ≈ 35,9 |
| **C. 2 nodos + testigo (elegida)** | **≈ 49,0** |
| D. 2 de aplicación + base primaria y réplica | ≈ 62,0 |

**Lectura.** Ninguna opción aguanta 24 horas al día con el crédito de USD 79 (un mes 24/7 costaría unos USD 135 en la opción elegida): la operación exige **encender solo para pruebas y sustentación**. El peso de los discos y las IP, que se cobran apagados, justifica además liberar lo que no se use.

> **No verificado.** El saldo de crédito realmente consumido a la fecha no se comprobó en Cost Management, y la alerta de presupuesto no se verificó. Tampoco se verificó el precio de PostgreSQL administrado en Chile Central, por lo que la comparación con un servicio administrado es cualitativa (sección 1.3).

## 6.2 Limitaciones consolidadas

@tabla Lo que no se logró o no se pudo comprobar
| Área | Limitación |
|---|---|
| Resiliencia | Replicación asíncrona (RPO mayor que cero posible); promoción manual sin quórum; el testigo no vota |
| Escalabilidad | Sin escalado automático; no se probó una VM más grande |
| Datos | Respaldos lógicos cada hora, sin recuperación a un instante exacto |
| Infraestructura como código | La red virtual, el NSG y los nodos de aplicación se crearon a mano o por clonado; no hay script |
| Red | Una sola subred; sin zonas de disponibilidad; una sola región |
| Seguridad | Sin segundo factor; la aplicación entra a la base como propietario; sin prueba ofensiva; certificados internos sin renovación automática; sin política de seguridad formal |
| Observabilidad | Logs sin centralizar |
| Rendimiento | Créditos de CPU de las VM de la serie B no medidos; pruebas más cortas que las planeadas y con base pequeña |
| Tráfico de red | Estimado, no medido |

## 6.3 Lecciones aprendidas

Varias lecciones salieron de **errores propios** que se detectaron y se corrigieron; se documentan porque son lo más útil para quien reproduzca el proyecto.

1. **Una limitación de la cuenta se convirtió en una mejora de seguridad.** La cuota de 3 IP públicas obligó a dejar una sola, la del balanceador. Una NIC con IP pública propia no puede unirse a un grupo con regla de salida: el orden correcto es crear el NAT de SSH, comprobar, quitar la IP y recién entonces sumarla al grupo de salida.
2. **El sondeo del balanceador apuntaba al lugar equivocado.** Git Bash en Windows convirtió `/salud` en una ruta de Windows (`C:/Program Files/Git/salud`) y el balanceador sondeaba el frontend en lugar del backend. Dos frontends llevaron media hora detenidos sin que nada lo avisara. Se corrigió con `MSYS_NO_PATHCONV=1`.
3. **Los finales de línea importan.** Editar scripts con Python en Windows los dejó en CRLF y `sh` falló en la VM. `tar` desde Windows perdió el bit de ejecución de un script y el proxy no arrancó. Los scripts deben guardarse con LF.
4. **Registrar un fallo dentro de una transacción que se revierte lo anula.** Por eso los almacenes de estado escriben con `REQUIRES_NEW` (sección 4.2).
5. **Un nombre de variable de entorno mal escrito tumbó el arranque.** `…PERCENTILES_HISTOGRAM…` se interpretó como otra propiedad; la forma correcta es `…PERCENTILESHISTOGRAM…`. Durante esa caída el sitio siguió respondiendo desde el otro nodo, lo que de paso probó la redundancia.
6. **Medir mal también cuenta.** El primer ensayo de failover informó un RTO de 0 s, y el primer intento de la prueba P3 no generaba identificadores repetidos entre instancias. Ambos se detectaron, se descartaron y se repitieron con el método corregido; el intento descartado se conserva en el repositorio.
7. **Verificar que un cambio se aplicó.** Un script de parche con un error de sintaxis no aplicó ningún cambio y las comprobaciones posteriores eran de archivos sin tocar; se detectó porque un contador de líneas daba cero.
8. **Los números sin cero inicial no son JSON.** Los scripts de respaldo emitían `.09` (la salida de `bc`), que un lector de JSON rechaza; se detectó al intentar leer la evidencia y se corrigió en los scripts.
9. **El límite de peticiones por nodo se duplica con dos nodos.** Un efecto no obvio del escalado horizontal que hay que declarar.
10. **La cadena de suministro alcanza a la propia herramienta de seguridad.** La acción de Trivy fue comprometida en 2026; el CI usa la imagen fijada por digest (sección 5.4).
