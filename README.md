# Skyline — Prometheus + Grafana pro Check Point Skyline

Standalone Docker Compose stack pro prijem metrik z Check Point Skyline pres
**Prometheus Remote Write** (HTTPS/mTLS) a jejich vizualizaci v Grafane.

Vychazi z: **https://support.checkpoint.com/results/sk/sk178566**
(SK clanek venovany nasazeni Skyline, sekce Downloads obsahuje oficialni Grafana dashboardy)

## Komponenty

| Komponenta | Dokumentace | Popis |
|---|---|---|
| [Prometheus](https://prometheus.io/docs/introduction/overview/) | [Remote Write](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#remote_write) · [TLS](https://prometheus.io/docs/prometheus/latest/configuration/https/) | Prijima metriky z Check Point via Remote Write, uklada do TSDB |
| [Grafana](https://grafana.com/docs/grafana/latest/) | [Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/) | Vizualizace metrik, dashboardy nacitane automaticky ze slozky |
| [Caddy](https://caddyserver.com/docs/) | [Reverse proxy](https://caddyserver.com/docs/quick-starts/reverse-proxy) | Reverse proxy s automatickym TLS (Let's Encrypt) pred Grafanou |
| [Alertmanager](https://prometheus.io/docs/alerting/latest/alertmanager/) | [Config](https://prometheus.io/docs/alerting/latest/configuration/) | Sprava alertu — v compose zatim vypnuty, pripraven k pouziti |

## Architektura

```
Check Point zarizeni
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
├── certs/                        # TLS certifikaty (nejsou v gitu)
│   ├── prometheus.crt            # certifikat serveru
│   └── prometheus.key            # privatni klic
├── prometheus/
│   ├── prometheus.yml            # Prometheus config
│   └── web.yml                   # TLS / mTLS konfigurace
├── grafana/provisioning/
│   ├── datasources/prometheus.yml
│   └── dashboards/provider.yml   # sleduje ./dashboards/ kazdych 30 s
├── dashboards/                   # JSON soubory dashboardu
└── alertmanager/
    └── alertmanager.yml          # sablona (v compose zatim vypnuty)
```

## Pozadavky

**Hardware** (doporucene minimum):
- 2 vCPU, 2 GB RAM
- Disk: zavisi na poctu metrik a delce retence — Prometheus uvadi postup vypoctu
  v [dokumentaci ke storage](https://prometheus.io/docs/prometheus/latest/storage/#operational-aspects).
  Jako orientacni hodnota: Check Point gateway exportuje cca **1 400 metrik**, pocet se lisi
  podle typu zarizeni, poctu bezicich blade a konfiguraci. Vysledna velikost dat na disku
  zavisi take na poctu monitorovanych GW a zvolene retenci.

**Sit:**
- Port `9090` pristupny z Check Point site (Prometheus remote write), idealne omezit firewallem jen na IP kolektoru
- Port `80` a `443` pro Caddy — viz nize

**Software:**
- Docker + Docker Compose plugin

**Poznamka k sitovemu umisteni a TLS:**
Stack nevyzaduje verejnou IP. Caddy podporuje tri rezimy TLS:
- **Let's Encrypt** — automaticky certifikat, vyzaduje verejnou IP a DNS zaznam (porty 80+443 z internetu)
- **`tls internal`** — Caddy si vytvori vlastni lokalni CA a podepise certifikat sam; vhodne pro interni nasazeni bez verejne IP (prohlizec bude certifikat povazovat za neduveryhodny, dokud nepridas CA do trust store)
- **Vlastni certifikat** — predas cert a klic, napr. vydany interni PKI

## 1. Certifikat

Prometheus musi bezet pres HTTPS — Check Point kolektor odmita plain HTTP.

### Self-signed (pro testovani nebo interni pouziti)

```bash
openssl req -x509 -newkey rsa:4096 \
  -keyout certs/prometheus.key \
  -out certs/prometheus.crt \
  -days 3650 -nodes \
  -subj "/CN=prometheus" \
  -addext "subjectAltName=IP:<IP tohoto serveru>,DNS:<hostname>"
```

Soubor `certs/prometheus.crt` pak predas Check Point kolektoru jako **CA certifikat**
(pole `tls_ca_cert` v konfiguraci kolektoru).

### Vydany certifikat (Let's Encrypt, interni CA)

Staci zkopirovat:
```bash
cp /cesta/k/fullchain.pem certs/prometheus.crt
cp /cesta/k/privkey.pem   certs/prometheus.key
```

### mTLS (overeni Check Point kolektoru)

Pokud Check Point kolektor posila klientsky certifikat, odkomentuj v `prometheus/web.yml`:
```yaml
client_ca_file:   /etc/prometheus/certs/ca.crt
client_auth_type: RequireAndVerifyClientCert
```
a vloz CA certifikat do `certs/ca.crt`.

## 2. Konfigurace (.env)

Zkopiruj a uprav `.env`:
```bash
# Grafana heslo
GRAFANA_ADMIN_PASSWORD=silne-heslo

# Verejna URL Grafany (pro spravne odkazy)
GRAFANA_ROOT_URL=https://monitoring.example.com:3000

# Retention Promethea
PROMETHEUS_RETENTION=90d
PROMETHEUS_RETENTION_SIZE=10GB
```

## 3. Spusteni

```bash
docker compose up -d
docker compose logs -f   # sledovat logy
```

## 4. Check Point kolektor — remote write endpoint

Na strane Check Point OpenTelemetry Collectoru nastavis:

| Parametr | Hodnota |
|---|---|
| Endpoint | `https://<IP/hostname tohoto serveru>:9090/api/v1/write` |
| TLS CA cert | obsah `certs/prometheus.crt` |
| Autentizace | zadna (nebo mTLS dle konfigurace vyse) |

## 5. Grafana dashboardy

Oficialni Check Point dashboardy ke stazeni v sekci **Downloads**:
**https://support.checkpoint.com/results/sk/sk178566**

JSON soubory dashboardu vloz do slozky `dashboards/`. Grafana je automaticky
importuje a kazdych 30 sekund kontroluje zmeny — pri aktualizaci souboru se
dashboard reimportuje bez restartu.

Podadresy v `dashboards/` se zobrazi jako slozky v Grafane
(`foldersFromFilesStructure: true`).

```
dashboards/
├── checkpoint/
│   ├── firewall-overview.json
│   └── vpn-tunnels.json
└── system/
    └── hardware.json
```

## 6. Alertmanager (pro budouci pouziti)

Alertmanager je v `docker-compose.yml` zakomentovany. Az bude potreba:

1. Uprav `alertmanager/alertmanager.yml` (SMTP, prijemci atd.)
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
# Priklad pro nftables / iptables — upravit dle prostredi
# Port 9090 jen z Check Point site
ufw allow from <CP_subnet> to any port 9090
# Port 3000 jen pro administratory
ufw allow from <admin_subnet> to any port 3000
```
