# Skyline — Prometheus + Grafana pro Check Point Skyline

Standalone Docker Compose stack pro příjem metrik z Check Point Skyline přes
**Prometheus Remote Write** (HTTPS/mTLS) a jejich vizualizaci v Grafaně.

Vychází z: **https://support.checkpoint.com/results/sk/sk178566**
(SK článek věnovaný nasazení Skyline, sekce Downloads obsahuje oficiální Grafana dashboardy)

## Komponenty

| Komponenta | Dokumentace | Popis |
|---|---|---|
| [Prometheus](https://prometheus.io/docs/introduction/overview/) | [Remote Write](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#remote_write) · [TLS](https://prometheus.io/docs/prometheus/latest/configuration/https/) | Přijímá metriky z Check Point via Remote Write, ukládá do TSDB |
| [Grafana](https://grafana.com/docs/grafana/latest/) | [Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/) | Vizualizace metrik, dashboardy načítané automaticky ze složky |
| [Caddy](https://caddyserver.com/docs/) | [Reverse proxy](https://caddyserver.com/docs/quick-starts/reverse-proxy) | Reverse proxy s automatickým TLS (Let's Encrypt) před Grafanou |
| [Alertmanager](https://prometheus.io/docs/alerting/latest/alertmanager/) | [Config](https://prometheus.io/docs/alerting/latest/configuration/) | Správa alertů — v compose zatím vypnutý, připraven k použití |

## Architektura

```
Check Point zařízení
  └── OpenTelemetry Agent (CPView → metriky)
        └── OpenTelemetry Collector
              └── Prometheus Remote Write (HTTPS)
                    └── [tento server] Prometheus :9090
                              └── Grafana :3000
```

## Struktura

```
skyline/
├── docker-compose.yml
├── .env                          # konfigurace (porty, verze, hesla)
├── certs/                        # TLS certifikáty (nejsou v gitu)
│   ├── prometheus.crt            # certifikát serveru
│   └── prometheus.key            # privátní klíč
├── prometheus/
│   ├── prometheus.yml            # Prometheus config
│   └── web.yml                   # TLS / mTLS konfigurace
├── grafana/provisioning/
│   ├── datasources/prometheus.yml
│   └── dashboards/provider.yml   # sleduje ./dashboards/ každých 30 s
├── dashboards/                   # JSON soubory dashboardů
└── alertmanager/
    └── alertmanager.yml          # šablona (v compose zatím vypnutý)
```

## Požadavky

- Docker + Docker Compose plugin
- Otevřený port 9090 (Prometheus remote write) dovnitř z Check Point sítě
- Otevřený port 3000 (Grafana) pro uživatele

## 1. Certifikát

Prometheus musí běžet přes HTTPS — Check Point kolektor odmítá plain HTTP.

### Self-signed (pro testování nebo interní použití)

```bash
openssl req -x509 -newkey rsa:4096 \
  -keyout certs/prometheus.key \
  -out certs/prometheus.crt \
  -days 3650 -nodes \
  -subj "/CN=prometheus" \
  -addext "subjectAltName=IP:<IP tohoto serveru>,DNS:<hostname>"
```

Soubor `certs/prometheus.crt` pak předáš Check Point kolektoru jako **CA certifikát**
(pole `tls_ca_cert` v konfiguraci kolektoru).

### Vydaný certifikát (Let's Encrypt, interní CA)

Stačí zkopírovat:
```bash
cp /cesta/k/fullchain.pem certs/prometheus.crt
cp /cesta/k/privkey.pem   certs/prometheus.key
```

### mTLS (ověření Check Point kolektoru)

Pokud Check Point kolektor posílá klientský certifikát, odkomentuj v `prometheus/web.yml`:
```yaml
client_ca_file:   /etc/prometheus/certs/ca.crt
client_auth_type: RequireAndVerifyClientCert
```
a vlož CA certifikát do `certs/ca.crt`.

## 2. Konfigurace (.env)

Zkopíruj a uprav `.env`:
```bash
# Grafana heslo
GRAFANA_ADMIN_PASSWORD=silne-heslo

# Veřejná URL Grafany (pro správné odkazy)
GRAFANA_ROOT_URL=https://monitoring.example.com:3000

# Retention Promethea
PROMETHEUS_RETENTION=90d
PROMETHEUS_RETENTION_SIZE=10GB
```

## 3. Spuštění

```bash
docker compose up -d
docker compose logs -f   # sledovat logy
```

## 4. Check Point kolektor — remote write endpoint

Na straně Check Point OpenTelemetry Collectoru nastavíš:

| Parametr | Hodnota |
|---|---|
| Endpoint | `https://<IP/hostname tohoto serveru>:9090/api/v1/write` |
| TLS CA cert | obsah `certs/prometheus.crt` |
| Autentizace | žádná (nebo mTLS dle konfigurace výše) |

## 5. Grafana dashboardy

Oficiální Check Point dashboardy ke stažení v sekci **Downloads**:
**https://support.checkpoint.com/results/sk/sk178566**

JSON soubory dashboardů vlož do složky `dashboards/`. Grafana je automaticky
importuje a každých 30 sekund kontroluje změny — při aktualizaci souboru se
dashboard reimportuje bez restartu.

Podadresy v `dashboards/` se zobrazí jako složky v Grafaně
(`foldersFromFilesStructure: true`).

```
dashboards/
├── checkpoint/
│   ├── firewall-overview.json
│   └── vpn-tunnels.json
└── system/
    └── hardware.json
```

## 6. Alertmanager (pro budoucí použití)

Alertmanager je v `docker-compose.yml` zakomentovaný. Až bude potřeba:

1. Uprav `alertmanager/alertmanager.yml` (SMTP, příjemci atd.)
2. Odkomentuj sekci `alertmanager` v `docker-compose.yml` (i volume `alertmanager_data`)
3. Odkomentuj sekci `alerting` v `prometheus/prometheus.yml`
4. `docker compose up -d`

## Restart / aktualizace

```bash
# Aktualizace images
docker compose pull
docker compose up -d

# Reload Prometheus konfigurace bez restartu
curl -X POST http://localhost:9090/-/reload
```

## Firewall

```bash
# Příklad pro nftables / iptables — upravit dle prostředí
# Port 9090 jen z Check Point sítě
ufw allow from <CP_subnet> to any port 9090
# Port 3000 jen pro administrátory
ufw allow from <admin_subnet> to any port 3000
```
