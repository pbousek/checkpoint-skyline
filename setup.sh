#!/bin/bash
# Generates config files from .env and certs.
# Run on the server after git clone / git pull, before docker compose up.
#
# What it generates:
#   prometheus/web.yml  -- TLS + basic auth config
#   caddy/Caddyfile     -- TLS mode based on CADDY_TLS_MODE
#   certs/grafana.*     -- self-signed cert for Grafana (if CADDY_TLS_MODE=custom)
#   payload.json        -- Check Point collector config

set -euo pipefail

if [[ ! -f .env ]]; then
    echo "ERROR: .env not found. Copy .env.example to .env and fill in values."
    exit 1
fi

set -a; source .env; set +a

: "${PROMETHEUS_SERVER:?Set PROMETHEUS_SERVER in .env}"
: "${PROMETHEUS_AUTH_USER:?Set PROMETHEUS_AUTH_USER in .env}"
: "${PROMETHEUS_AUTH_PASSWORD:?Set PROMETHEUS_AUTH_PASSWORD in .env}"
: "${GRAFANA_DOMAIN:?Set GRAFANA_DOMAIN in .env}"

CADDY_TLS_MODE="${CADDY_TLS_MODE:-internal}"
CERT_FILE="certs/prometheus.crt"

if [[ ! -f "$CERT_FILE" ]]; then
    echo "ERROR: $CERT_FILE not found. Run gen-certs.sh first."
    exit 1
fi

# --- prometheus/web.yml ---

echo "Generating bcrypt hash for Prometheus basic auth..."
if python3 -c "import bcrypt" 2>/dev/null; then
    HASH=$(BCRYPT_PW="${PROMETHEUS_AUTH_PASSWORD}" python3 -c "
import bcrypt, os
pw = os.environ['BCRYPT_PW']
print(bcrypt.hashpw(pw.encode(), bcrypt.gensalt(12)).decode())
")
else
    echo "(python3-bcrypt not found, using Docker -- this may take a moment)"
    HASH=$(docker run --rm -e PW="${PROMETHEUS_AUTH_PASSWORD}" httpd:2 \
        sh -c 'htpasswd -bnBC 12 "" "$PW"' | tr -d ':\n' | sed 's/\$2y/\$2b/')
fi

cat > prometheus/web.yml <<EOF
tls_server_config:
  cert_file: /etc/prometheus/certs/prometheus.crt
  key_file:  /etc/prometheus/certs/prometheus.key

  # mTLS -- overeni klienta (Check Point kolektoru). Odkomentovat pokud CP vyzaduje mTLS:
  # client_ca_file:    /etc/prometheus/certs/ca.crt
  # client_auth_type:  RequireAndVerifyClientCert

basic_auth_users:
  ${PROMETHEUS_AUTH_USER}: ${HASH}
EOF

echo "Generated prometheus/web.yml"

# --- caddy/Caddyfile ---

# For custom mode: generate Grafana cert if missing
if [[ "$CADDY_TLS_MODE" == "custom" && ! -f "certs/grafana.crt" ]]; then
    echo "Generating Grafana TLS cert (self-signed)..."
    openssl req -x509 -newkey rsa:4096 \
        -keyout certs/grafana.key \
        -out certs/grafana.crt \
        -days 3650 -nodes \
        -subj "/CN=${GRAFANA_DOMAIN}" \
        -addext "subjectAltName=DNS:${GRAFANA_DOMAIN}"
    chmod 644 certs/grafana.crt certs/grafana.key
    echo "Generated certs/grafana.crt -- add to browser/OS trust store to avoid warnings"
fi

case "$CADDY_TLS_MODE" in
  letsencrypt)
    cat > caddy/Caddyfile <<EOF
${GRAFANA_DOMAIN} {
    reverse_proxy grafana:3000
}
EOF
    ;;
  internal)
    cat > caddy/Caddyfile <<EOF
${GRAFANA_DOMAIN} {
    tls internal
    reverse_proxy grafana:3000
}
EOF
    ;;
  custom)
    cat > caddy/Caddyfile <<EOF
${GRAFANA_DOMAIN} {
    tls /etc/caddy/certs/grafana.crt /etc/caddy/certs/grafana.key
    reverse_proxy grafana:3000
}
EOF
    ;;
  *)
    echo "ERROR: Unknown CADDY_TLS_MODE=${CADDY_TLS_MODE}. Use: letsencrypt, internal, custom"
    exit 1
    ;;
esac

echo "Generated caddy/Caddyfile (mode: ${CADDY_TLS_MODE})"

# --- payload.json ---

CERT=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' "$CERT_FILE")

cat > payload.json <<EOF
{
    "enabled": true,
    "export-targets": {
        "add": [
            {
                "client-auth": {
                    "basic": {
                        "username": "${PROMETHEUS_AUTH_USER}",
                        "password": "${PROMETHEUS_AUTH_PASSWORD}"
                    }
                },
                "enabled": true,
                "server-auth": {
                    "ca-public-key": {
                        "type": "PEM-X509",
                        "value": "${CERT}"
                    }
                },
                "type": "prometheus-remote-write",
                "url": "https://${PROMETHEUS_SERVER}:9090/api/v1/write"
            }
        ]
    }
}
EOF

echo "Generated payload.json"
echo ""
echo "Next steps:"
echo "  docker compose up -d      # first run"
echo "  docker compose restart    # if already running"
echo ""
echo "Apply on Check Point gateway:"
echo "  sklnctl export --set \"\$(cat payload.json)\""
