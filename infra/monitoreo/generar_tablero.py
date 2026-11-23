"""Genera el tablero de Grafana (grafana/dashboards/clickclak.json).

Se genera con código para que el JSON salga siempre bien formado y los paneles sean fáciles de
cambiar. Uso:  python infra/monitoreo/generar_tablero.py
"""
import json
import pathlib

DS = {"type": "prometheus", "uid": "prometheus"}
paneles = []
_id = [0]


def _base(titulo, x, y, w, h, tipo):
    _id[0] += 1
    return {"id": _id[0], "type": tipo, "title": titulo, "datasource": DS,
            "gridPos": {"x": x, "y": y, "w": w, "h": h}}


def serie(titulo, exprs, x, y, w=8, h=7, unidad="short", minimo=None, maximo=None):
    p = _base(titulo, x, y, w, h, "timeseries")
    p["targets"] = [{"refId": chr(65 + i), "expr": e, "legendFormat": leyenda, "datasource": DS}
                    for i, (e, leyenda) in enumerate(exprs)]
    p["fieldConfig"] = {"defaults": {"unit": unidad,
                                     **({"min": minimo} if minimo is not None else {}),
                                     **({"max": maximo} if maximo is not None else {}),
                                     "custom": {"lineWidth": 2, "fillOpacity": 10}}, "overrides": []}
    p["options"] = {"legend": {"displayMode": "list", "placement": "bottom"}, "tooltip": {"mode": "multi"}}
    return p


def estado(titulo, expr, leyenda, x, y, w=4, h=4):
    """Panel 'stat' verde/rojo: 1 = arriba, 0 = caído."""
    p = _base(titulo, x, y, w, h, "stat")
    p["targets"] = [{"refId": "A", "expr": expr, "legendFormat": leyenda, "datasource": DS}]
    p["fieldConfig"] = {"defaults": {
        "mappings": [{"type": "value", "options": {"0": {"text": "CAÍDO", "color": "red"},
                                                   "1": {"text": "ARRIBA", "color": "green"}}}],
        "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
        "color": {"mode": "thresholds"}}, "overrides": []}
    p["options"] = {"colorMode": "background", "graphMode": "none", "textMode": "value_and_name"}
    return p


def alertas(x, y, w, h):
    p = _base("Alertas activas", x, y, w, h, "alertlist")
    p.pop("datasource")
    p["options"] = {"alertInstanceLabelFilter": "", "groupMode": "default", "maxItems": 20,
                    "sortOrder": 1, "stateFilter": {"firing": True, "pending": True, "noData": False,
                                                    "normal": False, "error": True}, "viewMode": "list"}
    return p


# Fila 1: estado de un vistazo
y = 0
paneles.append(estado("Servicio público", 'probe_success{job="sonda-publica"}', "URL pública", 0, y))
paneles.append(estado("Nodo 1 en el balanceador", 'probe_success{job="sonda-nodos",nodo="nodo1"}', "nodo1 /salud", 4, y))
paneles.append(estado("Nodo 2 en el balanceador", 'probe_success{job="sonda-nodos",nodo="nodo2"}', "nodo2 /salud", 8, y))
paneles.append(estado("Backend nodo 1", 'up{job="backend",nodo="nodo1"}', "backend nodo1", 12, y))
paneles.append(estado("Backend nodo 2", 'up{job="backend",nodo="nodo2"}', "backend nodo2", 16, y))
paneles.append(estado("PostgreSQL nodo 1", 'pg_up{nodo="nodo1"}', "pg nodo1", 20, y))
y += 4
paneles.append(estado("PostgreSQL nodo 2", 'pg_up{nodo="nodo2"}', "pg nodo2", 0, y))
paneles.append(estado("Primaria de PostgreSQL: nodo 1", 'pg_replication_is_replica{nodo="nodo1"} == bool 0', "es primaria", 4, y))
paneles.append(estado("Primaria de PostgreSQL: nodo 2", 'pg_replication_is_replica{nodo="nodo2"} == bool 0', "es primaria", 8, y))
paneles.append(alertas(12, y, 12, 4))
y += 4

# Fila 2: tráfico y latencia del servicio
paneles.append(serie("Peticiones por segundo (por nodo)",
                     [('sum by (nodo) (rate(http_server_requests_seconds_count{job="backend"}[1m]))', "{{nodo}}")],
                     0, y, unidad="reqps"))
paneles.append(serie("Latencia p95 (s) — límite RNF03: 2 s",
                     [('histogram_quantile(0.95, sum by (le, nodo) (rate(http_server_requests_seconds_bucket{job="backend"}[1m])))', "p95 {{nodo}}")],
                     8, y, unidad="s"))
paneles.append(serie("Errores 5xx y 401 por segundo",
                     [('sum by (nodo) (rate(http_server_requests_seconds_count{job="backend",status=~"5.."}[1m]))', "5xx {{nodo}}"),
                      ('sum by (nodo) (rate(http_server_requests_seconds_count{job="backend",status="401"}[1m]))', "401 {{nodo}}")],
                     16, y, unidad="reqps"))
y += 7

# Fila 3: capacidad de las VM
paneles.append(serie("CPU (%)", [('100 - avg by (nodo) (rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100', "{{nodo}}")],
                     0, y, unidad="percent", minimo=0, maximo=100))
paneles.append(serie("Memoria usada (%)",
                     [('(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100', "{{nodo}}")],
                     8, y, unidad="percent", minimo=0, maximo=100))
paneles.append(serie("Disco usado (%)",
                     [('(1 - node_filesystem_avail_bytes{mountpoint="/",fstype!="rootfs"} / node_filesystem_size_bytes{mountpoint="/",fstype!="rootfs"}) * 100', "{{nodo}}")],
                     16, y, unidad="percent", minimo=0, maximo=100))
y += 7

# Fila 4: base de datos y réplica
paneles.append(serie("Retraso de la réplica (s)", [('pg_replication_lag_seconds', "{{nodo}}")], 0, y, unidad="s"))
paneles.append(serie("Conexiones a PostgreSQL (máx. 50)", [('sum by (nodo) (pg_stat_activity_count)', "{{nodo}}")], 8, y))
paneles.append(serie("Memoria por contenedor (MiB)",
                     [('container_memory_working_set_bytes{job="contenedores",name=~"clickclak.*"} / 1024 / 1024', "{{nodo}} {{name}}")],
                     16, y, unidad="mbytes"))
y += 7

# Fila 5: disponibilidad vista desde fuera
paneles.append(serie("Latencia de la sonda externa (s)",
                     [('probe_duration_seconds{job="sonda-publica"}', "URL pública"),
                      ('probe_duration_seconds{job="sonda-nodos"}', "{{nodo}}")], 0, y, w=12, unidad="s"))
paneles.append(serie("Días hasta el vencimiento del certificado",
                     [('(probe_ssl_earliest_cert_expiry{job="sonda-publica"} - time()) / 86400', "certificado")],
                     12, y, w=12, unidad="d"))

tablero = {
    "uid": "clickclak",
    "title": "ClickClak — Disponibilidad, capacidad y replicación",
    "tags": ["clickclak", "cloud"],
    "timezone": "browser",
    "refresh": "5s",
    "schemaVersion": 39,
    "time": {"from": "now-15m", "to": "now"},
    "panels": paneles,
}

salida = pathlib.Path(__file__).parent / "grafana" / "dashboards" / "clickclak.json"
salida.parent.mkdir(parents=True, exist_ok=True)
salida.write_text(json.dumps(tablero, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"{len(paneles)} paneles -> {salida}")
