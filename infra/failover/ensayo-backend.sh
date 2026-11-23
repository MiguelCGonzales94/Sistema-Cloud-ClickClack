#!/bin/bash
# GUION DE FALLA n.º 1: caída de un backend (la base de datos sigue sana). Se ejecuta desde TU máquina:
#     bash infra/failover/ensayo-backend.sh            # tumba el backend del nodo 1 (por defecto)
#     NODO=2 bash infra/failover/ensayo-backend.sh     # o el del nodo 2
#
# Qué demuestra: el sondeo de salud del balanceador (/salud, cada 5 s, 2 fallos) saca al nodo caído del
# reparto y el servicio sigue respondiendo desde el otro; al volver el backend, el nodo se reincorpora solo.
# Mide cuántas peticiones fallan y cuánto tarda el balanceador en reaccionar.
set -u
LB="${LB:-68.211.146.181}"
LLAVE="${LLAVE:-$HOME/.ssh/clickclak_azure}"
URL="${URL:-https://clickclak-utp.chilecentral.cloudapp.azure.com/salud}"
SALIDA="${SALIDA:-$(pwd)/ensayo-backend-resultado}"
NODO="${NODO:-1}"
PUERTO=$((2200 + NODO))
mkdir -p "$SALIDA"; rm -f "$SALIDA/parar" "$SALIDA/sonda.log"
ssh_n() { ssh -i "$LLAVE" -p "$PUERTO" -o BatchMode=yes -o ConnectTimeout=15 azureuser@"$LB" "$@"; }
marca() { printf '[%s] %s\n' "$(date +%T)" "$*"; }

marca "Sonda pública a ~5 peticiones/s durante todo el ensayo (código y nodo que responde)"
( while [ ! -f "$SALIDA/parar" ]; do
      t=$(date +%s.%N)
      r=$(curl -s -m 3 -D - -o /dev/null "$URL" 2>/dev/null | tr -d '\r' | awk '/^HTTP/{c=$2} /^[Xx]-[Nn]odo/{n=$2} END{print (c==""?"000":c), (n==""?"-":n)}')
      echo "$t $r"; sleep 0.15
  done ) > "$SALIDA/sonda.log" 2>/dev/null &
SONDA=$!
sleep 12
marca "== CAÍDA: se detiene el backend del nodo $NODO"
T0=$(ssh_n 'sudo docker update --restart=no clickclak-backend-1 >/dev/null; t=$(date +%s.%N); sudo docker stop -t 1 clickclak-backend-1 >/dev/null; echo $t' | tr -d '\r')
sleep 30
marca "== RECUPERACIÓN: se vuelve a arrancar el backend del nodo $NODO"
T1=$(ssh_n 'sudo docker update --restart=unless-stopped clickclak-backend-1 >/dev/null; t=$(date +%s.%N); sudo docker start clickclak-backend-1 >/dev/null; echo $t' | tr -d '\r')
sleep 45
touch "$SALIDA/parar"; sleep 1; kill $SONDA 2>/dev/null

python -I - "$SALIDA" "$T0" "$T1" "$NODO" <<'PY'
import sys, json, pathlib
d = pathlib.Path(sys.argv[1]); T0, T1 = float(sys.argv[2]), float(sys.argv[3]); nodo = f"nodo{sys.argv[4]}"
son = [(float(a), b, c) for a, b, c in (l.split() for l in (d/"sonda.log").read_text().splitlines() if len(l.split()) == 3)]
fallos = [(t, c) for t, c, _ in son if c != "200"]
caida = [(t, n) for t, c, n in son if T0 <= t < T1]
# último 200 servido por el nodo caído tras T0 = momento en que el balanceador lo saca del reparto
del_caido = [t for t, c, n in son if n == nodo and T0 <= t < T1]   # última petición que el balanceador aún le envió
sacado = (max(del_caido) - T0) if del_caido else 0.0
despues = [(t, n) for t, c, n in son if t > T1 and c == "200"]
vuelve = [t for t, n in despues if n == nodo]
r = {
  "nodo_caido": nodo, "sondas_totales": len(son), "sondas_no_200": len(fallos),
  "porcentaje_exito": round(100 * (len(son) - len(fallos)) / len(son), 2),
  "el_balanceador_dejo_de_usar_al_nodo_tras_s": round(sacado, 1),
  "peticiones_fallidas_durante_la_caida": sum(1 for t, c in fallos if T0 <= t < T1),
  "nodos_que_respondieron_durante_la_caida": {n: sum(1 for _, x in caida if x == n) for n in sorted({x for _, x in caida})},
  "el_nodo_vuelve_al_reparto_tras_s": round(min(vuelve) - T1, 1) if vuelve else None,
}
(d/"resultado.json").write_text(json.dumps(r, indent=2, ensure_ascii=False))
for k, v in r.items(): print(f"  {k}: {v}")
PY
marca "Archivos en $SALIDA"
