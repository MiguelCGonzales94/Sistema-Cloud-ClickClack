#!/bin/bash
# ENSAYO CRONOMETRADO DE FAILOVER (guion de falla n.º 2 de la sustentación). Se ejecuta desde TU máquina:
#     bash infra/failover/ensayo-failover.sh
#
# Provoca la caída ABRUPTA de la primaria (docker kill, sin apagado limpio), la detecta con la alerta
# PostgresCaido de Prometheus, la aísla (fencing), promueve a la standby, mide RTO y RPO con un escritor
# continuo y una sonda pública, y reincorpora al nodo viejo como standby (pg_rewind). Deja los roles
# intercambiados (nodo 2 = primaria, nodo 1 = standby).
#
# MODO=n1-cae (por defecto) provoca la caída del nodo 1; MODO=n2-cae la del nodo 2 (sentido inverso).
# Requisitos: SSH por el balanceador (puertos 2201 nodo 1, 2202 nodo 2, 2203 testigo) y los roles
# actuales nodo 1 = primaria, nodo 2 = standby (ver el estado antes de empezar).
set -u
LB="${LB:-68.211.146.181}"
LLAVE="${LLAVE:-$HOME/.ssh/clickclak_azure}"
URL="${URL:-https://clickclak-utp.chilecentral.cloudapp.azure.com/salud}"
SALIDA="${SALIDA:-$(pwd)/failover-resultado}"
mkdir -p "$SALIDA"

# El nodo que cae es la primaria actual (VIEJO); el que se promueve es la standby (NUEVO).
MODO="${MODO:-n1-cae}"
if [ "$MODO" = "n1-cae" ]; then
    VIEJO=n1; NUEVO=n2; IP_VIEJA=10.0.0.4; IP_NUEVA=10.0.0.5; SLOT_VIEJO=nodo1_slot
    ROL_STANDBY_VIEJO=nodos/nodo1-standby.yml; ROL_PRIMARIA_NUEVO=nodos/nodo2-primaria.yml
else
    VIEJO=n2; NUEVO=n1; IP_VIEJA=10.0.0.5; IP_NUEVA=10.0.0.4; SLOT_VIEJO=nodo2_slot
    ROL_STANDBY_VIEJO=nodos/nodo2.yml; ROL_PRIMARIA_NUEVO=nodos/nodo1.yml
fi

n1() { ssh -i "$LLAVE" -p 2201 -o BatchMode=yes -o ConnectTimeout=15 azureuser@"$LB" "$@"; }
n2() { ssh -i "$LLAVE" -p 2202 -o BatchMode=yes -o ConnectTimeout=15 azureuser@"$LB" "$@"; }
nt() { ssh -i "$LLAVE" -p 2203 -o BatchMode=yes -o ConnectTimeout=15 azureuser@"$LB" "$@"; }
psql_n() { # $1 = nodo (n1|n2), $2 = consulta
    $1 "sudo docker exec clickclak-postgres-1 psql -U clickclak -d clickclak -tAc \"$2\"" 2>/dev/null | tr -d '\r\n '
}
marca() { printf '[%s] %s\n' "$(date +%T)" "$*"; }

marca "== 0. Precondiciones"
[ "$(psql_n $VIEJO 'select pg_is_in_recovery()')" = "f" ] || { marca "El nodo que debe caer ($VIEJO) no es la primaria. Abortado."; exit 1; }
[ "$(psql_n $NUEVO 'select pg_is_in_recovery()')" = "t" ] || { marca "El nodo a promover ($NUEVO) no es standby. Abortado."; exit 1; }
marca "primaria = $VIEJO, standby = $NUEVO, retraso: $(psql_n $VIEJO "select coalesce(max(pg_wal_lsn_diff(pg_current_wal_lsn(),replay_lsn)),-1) from pg_stat_replication") bytes"
# pg_rewind lee wal_log_hints del ARCHIVO DE CONTROL, que solo se actualiza con un checkpoint: sin esto
# (lección del primer ensayo) pg_rewind falla aunque SHOW wal_log_hints diga on.
psql_n $VIEJO "checkpoint" > /dev/null
$VIEJO "sudo docker exec -u postgres clickclak-postgres-1 pg_controldata /var/lib/postgresql/data | grep -q 'wal_log_hints setting: *on'"     && marca "archivo de control: wal_log_hints = on (pg_rewind disponible)"     || { marca "wal_log_hints no figura en el archivo de control. Abortado."; exit 1; }

marca "== 1. Escritor continuo (dentro del PostgreSQL del nodo 2) y sonda pública (desde aquí)"
$NUEVO 'sudo docker cp ~/clickclak/infra/failover/escritor.sh clickclak-postgres-1:/tmp/escritor.sh && sudo docker exec -d clickclak-postgres-1 sh /tmp/escritor.sh'
( while [ ! -f "$SALIDA/parar-sonda" ]; do
      t=$(date +%s.%N)
      r=$(curl -s -m 2 -D - -o /dev/null "$URL" 2>/dev/null | tr -d '\r' | awk '/^HTTP/{c=$2} /^[Xx]-[Nn]odo/{n=$2} END{print (c==""?"000":c), (n==""?"-":n)}')
      echo "$t $r"
      sleep 0.2
  done ) > "$SALIDA/sonda.log" 2>/dev/null &
SONDA_PID=$!
rm -f "$SALIDA/parar-sonda"
sleep 15
marca "base: $(wc -l < "$SALIDA/sonda.log") sondas, $($NUEVO 'wc -l < /tmp/escritor.log 2>/dev/null; true' 2>/dev/null) escrituras en el log del escritor"

marca "== 2. CAÍDA ABRUPTA de la primaria ($VIEJO): sin reinicio automático y docker kill"
T0=$($VIEJO 'sudo docker update --restart=no clickclak-postgres-1 >/dev/null; t=$(date +%s.%N); sudo docker kill clickclak-postgres-1 >/dev/null; echo $t' | tr -d '\r')
marca "T0 = $T0 (primaria caída)"

marca "== 3. Detección: esperamos la alerta PostgresCaido de Prometheus (for: 20 s)"
DET=""
for i in $(seq 1 60); do
    estado=$(nt "curl -s http://10.0.0.6:9090/api/v1/alerts | jq -r '[.data.alerts[] | select(.labels.alertname==\"PostgresCaido\") | .state] | first // \"-\"'" | tr -d '\r\n')
    if [ "$estado" = "firing" ]; then DET=$(date +%s.%N); marca "alerta PostgresCaido EN DISPARO"; break; fi
    sleep 1
done
[ -z "$DET" ] && { DET=$(date +%s.%N); marca "la alerta no llegó a disparar en 60 s; se continúa igualmente"; }

marca "== 4. Aislamiento (fencing) del nodo viejo y promoción de la standby"
$VIEJO 'sh ~/clickclak/infra/failover/aislar.sh'
TP0=$(date +%s.%N)
$NUEVO "cd ~/clickclak/infra && sh failover/promover.sh $IP_VIEJA $SLOT_VIEJO"
TP1=$(date +%s.%N)

marca "== 5. Esperar a que el servicio público se estabilice (5 sondas seguidas en 200)"
for i in $(seq 1 90); do
    ult=$(tail -5 "$SALIDA/sonda.log" | awk '{print $2}' | sort -u | tr '\n' ' ')
    [ "$ult" = "200 " ] && break
    sleep 1
done
sleep 5
$NUEVO 'sudo docker exec clickclak-postgres-1 touch /tmp/parar-escritor'
touch "$SALIDA/parar-sonda"; sleep 1; kill $SONDA_PID 2>/dev/null
sleep 2
$NUEVO 'sudo docker exec clickclak-postgres-1 cat /tmp/escritor.log' | tr -d '\r' > "$SALIDA/escritor.log"
MAX_OK=$(awk '$3=="ok"{m=$2} END{print m+0}' "$SALIDA/escritor.log")
PRESENTES=$(psql_n $NUEVO "select count(*) from _prueba_failover where id <= $MAX_OK")
NUEVA_TL=$(psql_n $NUEVO "select timeline_id from pg_control_checkpoint()")

marca "== 6. Reincorporar el nodo viejo como standby (pg_rewind) y cambiar los roles"
TR0=$(date +%s.%N)
$VIEJO "cd ~/clickclak/infra && sh failover/reincorporar.sh $IP_NUEVA $SLOT_VIEJO $ROL_STANDBY_VIEJO" | tee "$SALIDA/reincorporar.log"
TR1=$(date +%s.%N)
$NUEVO "cd ~/clickclak/infra && cp $ROL_PRIMARIA_NUEVO docker-compose.nodo.yml"
sleep 5
marca "$VIEJO en recuperación: $(psql_n $VIEJO 'select pg_is_in_recovery()') | $NUEVO en recuperación: $(psql_n $NUEVO 'select pg_is_in_recovery()')"
REPL=$(psql_n $NUEVO "select client_addr||'/'||state||'/lag='||coalesce(pg_wal_lsn_diff(pg_current_wal_lsn(),replay_lsn),-1) from pg_stat_replication limit 1")
marca "replicación nodo 2 -> nodo 1: $REPL"
$NUEVO 'sudo docker exec clickclak-postgres-1 psql -U clickclak -d clickclak -qc "DROP TABLE IF EXISTS _prueba_failover"' > /dev/null

marca "== 7. Resultados"
python -I - "$SALIDA" "$T0" "$DET" "$TP0" "$TP1" "$TR0" "$TR1" "$MAX_OK" "$PRESENTES" "$NUEVA_TL" "$REPL" <<'PY'
import sys, json, pathlib
d = pathlib.Path(sys.argv[1]); T0, DET, TP0, TP1, TR0, TR1 = map(float, sys.argv[2:8])
max_ok, presentes, tl, repl = int(sys.argv[8]), int(sys.argv[9] or 0), sys.argv[10], sys.argv[11]
esc = [l.split() for l in (d/"escritor.log").read_text().splitlines() if l.strip()]
ok = [(float(t), int(i)) for t, i, e in esc if e == "ok"]
# RTO de escritura = mayor hueco entre dos escrituras confirmadas consecutivas (el escritor sigue
# escribiendo unos instantes después de T0, hasta que la caída surte efecto, así que "la primera tras T0" no sirve).
marcas = sorted(t for t, _ in ok)
huecos = [(marcas[i+1] - marcas[i], marcas[i], marcas[i+1]) for i in range(len(marcas) - 1)]
hueco = max(huecos) if huecos else None
ultimo_antes = hueco[1] if hueco else None
primero_despues = hueco[2] if hueco else None
errores = sum(1 for _, _, e in esc if e == "err")
son = [l.split() for l in (d/"sonda.log").read_text().splitlines() if len(l.split()) >= 2]
caidas = [(float(t), c) for t, c, *_ in son if c != "200"]
ventana = None
if caidas:
    ini = min(t for t, _ in caidas if t >= T0 - 1) if any(t >= T0 - 1 for t, _ in caidas) else None
    fin = max(t for t, _ in caidas)
    ventana = (ini, fin)
nodos_tras = {}
for t, c, *n in son:
    if float(t) > TP1 + 5: nodos_tras[n[0] if n else "-"] = nodos_tras.get(n[0] if n else "-", 0) + 1
r = {
  "deteccion_s": round(DET - T0, 1),
  "promocion_s": round(TP1 - TP0, 1),
  "rto_desde_caida_s (T0 -> primera escritura)": round(primero_despues - T0, 1) if primero_despues else None,
  "rto_escritura_s (ultima ok -> primera ok)": round(primero_despues - ultimo_antes, 1) if (primero_despues and ultimo_antes) else None,
  "ventana_publica_no_200_s": round(ventana[1] - ventana[0], 1) if ventana and ventana[0] else 0,
  "sondas_totales": len(son), "sondas_no_200": len(caidas),
  "escrituras_confirmadas": max_ok, "escrituras_presentes_en_nueva_primaria": presentes,
  "rpo_escrituras_perdidas": max_ok - presentes, "intentos_con_error_durante_la_caida": errores,
  "nueva_linea_de_tiempo": tl, "reincorporacion_s": round(TR1 - TR0, 1), "replicacion_final": repl,
  "nodos_que_atienden_tras_el_failover": nodos_tras,
}
(d/"resultado.json").write_text(json.dumps(r, indent=2, ensure_ascii=False))
for k, v in r.items(): print(f"  {k}: {v}")
PY
marca "Archivos en $SALIDA (escritor.log, sonda.log, reincorporar.log, resultado.json)"
