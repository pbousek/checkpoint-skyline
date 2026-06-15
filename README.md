# Skyline -- Prometheus + Grafana pro Check Point Skyline

Standalone Docker Compose stack pro prijem metrik z Check Point Skyline pres
**Prometheus Remote Write** (HTTPS + basic auth) a jejich vizualizaci v Grafane.

Vychazi z: **https://support.checkpoint.com/results/sk/sk178566**

## Komponenty

| Komponenta | Popis |
|---|---|
| [Prometheus](https://prometheus.io/docs/introduction/overview/) | Prijima metriky z Check Point via Remote Write, uklada do TSDB |
| [Grafana](https://grafana.com/docs/grafana/latest/) | Vizualizace metrik, dashboardy nacitane automaticky ze slozky `dashboards/` |
| [Caddy](https://caddyserver.com/docs/) | Reverse proxy pred Grafanou, zajistuje HTTPS |

## Architektura

```
Check Point zarizeni
  \-- OpenTelemetry Collector
        \-- Prometheus Remote Write (HTTPS + basic auth)
              \-- Prometheus :9090
                    \-- Grafana :3000  <-- Caddy :443
```

## Pozadavky

- Docker + Docker Compose plugin
- 2 vCPU, 2 GB RAM
- Port `9090` dostupny z Check Point site
- Port `443` dostupny pro administratory (Grafana)

## Rychly start

### 1. Konfigurace

```bash
cp .env.example .env
```

Uprav `.env` -- minimalne tyto hodnoty:

```
GRAFANA_DOMAIN=promtest.example.com   # DNS nebo IP serveru
GRAFANA_ADMIN_PASSWORD=silne-heslo

CADDY_TLS_MODE=internal               # viz sekce TLS nize

PROMETHEUS_SERVER=10.0.0.42           # IP/hostname tohoto serveru
PROMETHEUS_AUTH_USER=skyline
PROMETHEUS_AUTH_PASSWORD=silne-heslo
```

### 2. Certifikat pro Prometheus

```bash
./gen-certs.sh <hostname-nebo-IP>
# priklad:
./gen-certs.sh promtest.example.com 10.0.0.42
```

Vygeneruje `certs/prometheus.crt` a `certs/prometheus.key`.

### 3. Generovani konfigurace

```bash
./setup.sh
```

Vygeneruje:
- `prometheus/web.yml` -- TLS + basic auth (bcrypt hash hesla)
- `caddy/Caddyfile` -- TLS mod dle `CADDY_TLS_MODE`
- `certs/grafana.*` -- self-signed cert pro Grafanu (jen pro `CADDY_TLS_MODE=custom`)
- `payload.json` -- konfigurace pro Check Point kolektor

### 4. Spusteni

```bash
docker compose up -d
docker compose logs -f
```

### 5. Check Point kolektor

Na Check Point gateway spust:

```bash
sklnctl export --set "$(cat payload.json)"
```

`payload.json` obsahuje endpoint, certifikat i credentials -- vygeneroval ho `setup.sh`.

---

## TLS pro Grafanu (Caddy)

Nastavuje se pres `CADDY_TLS_MODE` v `.env`, `setup.sh` vygeneruje Caddyfile.

| Mode | Popis | Kdy pouzit |
|---|---|---|
| `letsencrypt` | Caddy ziska certifikat automaticky od Let's Encrypt | Verejny server s DNS zaznamem a porty 80+443 z internetu |
| `internal` | Caddy vygeneruje vlastni CA | Interni sit bez verejne IP; prohlizec bude hlasit neduveryhodny cert |
| `custom` | `setup.sh` vygeneruje self-signed cert do `certs/grafana.*` | Interni sit; cert pridas do trust store a prohlizec nebude hlasit chybu |

Pro `custom` mode: po spusteni `setup.sh` najdes `certs/grafana.crt` --
ten naimportujes do trust store svych pocitacu/prohlizecu.

---

## Dashboardy

Oficialni Check Point dashboardy ke stazeni v sekci **Downloads**:
**https://support.checkpoint.com/results/sk/sk178566**

JSON soubory vloz do `dashboards/`. Grafana je automaticky nacte a kazdych 30 sekund
kontroluje zmeny. Podslozky se zobrazi jako slozky v Grafane.

---

## Aktualizace

```bash
git pull origin master
./setup.sh                  # obnovi konfiguraci
docker compose pull
docker compose up -d
```

---

## Struktura

```
skyline/
+-- docker-compose.yml
+-- .env                    # konfigurace (neni v gitu)
+-- .env.example            # sablona
+-- gen-certs.sh            # generuje certs/prometheus.*
+-- setup.sh                # generuje web.yml, Caddyfile, payload.json
+-- payload.json            # konfigurace pro CP kolektor (neni v gitu)
+-- certs/                  # certifikaty (neni v gitu)
|   +-- prometheus.crt/key
|   \-- grafana.crt/key     # jen pro CADDY_TLS_MODE=custom
+-- prometheus/
|   +-- prometheus.yml
|   \-- web.yml             # generuje setup.sh
+-- caddy/
|   \-- Caddyfile           # generuje setup.sh
+-- grafana/provisioning/
+-- dashboards/             # JSON dashboardy
\-- alertmanager/           # zatim vypnuto
```
