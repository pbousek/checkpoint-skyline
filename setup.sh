#!/bin/bash
# Generates prometheus/web.yml (TLS + basic auth) and payload.json for Check Point.
# Run on the server after git clone / git pull, before docker compose up.
#
# Usage:
#   ./setup.sh
#
# Requires .env with: PROMETHEUS_SERVER, PROMETHEUS_AUTH_USER, PROMETHEUS_AUTH_PASSWORD
# Certs must exist in certs/ (run gen-certs.sh first if not).

set -euo pipefail

if [[ ! -f .env ]]; then
    echo "ERROR: .env not found. Copy .env.example to .env and fill in values."
    exit 1
fi

set -a; source .env; set +a

: "${PROMETHEUS_SERVER:?Set PROMETHEUS_SERVER in .env}"
: "${PROMETHEUS_AUTH_USER:?Set PROMETHEUS_AUTH_USER in .env}"
: "${PROMETHEUS_AUTH_PASSWORD:?Set PROMETHEUS_AUTH_PASSWORD in .env}"

CERT_FILE="certs/prometheus.crt"

if [[ ! -f "$CERT_FILE" ]]; then
    echo "ERROR: $CERT_FILE not found. Run gen-certs.sh first."
    exit 1
fi

# Generate bcrypt hash -- try Python bcrypt, fall back to Docker
echo "Generating bcrypt hash..."
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

# Write prometheus/web.yml
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

echo "Updated prometheus/web.yml"

# Generate payload.json
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
echo "  docker compose restart prometheus"
echo ""
echo "Apply on Check Point gateway:"
echo "  sklnctl export --set \"\$(cat payload.json)\""
