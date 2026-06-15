#!/bin/bash
# Vygeneruje self-signed TLS certifikat pro Prometheus Remote Write endpoint.
# Spust na serveru po naklonovani repozitare.
#
# Pouziti:
#   ./gen-certs.sh <hostname> [<ip>]
#
# Priklady:
#   ./gen-certs.sh skyline.example.com
#   ./gen-certs.sh skyline.example.com 10.0.0.42
#
# Vystup:
#   certs/prometheus.crt  — nahrat na Check Point kolektoru jako CA cert
#   certs/prometheus.key  — zustava na serveru (nesdilet)

set -euo pipefail

HOSTNAME="${1:?Chybi hostname. Pouziti: $0 <hostname> [<ip>]}"
IP="${2:-}"

SAN="DNS:${HOSTNAME}"
[[ -n "$IP" ]] && SAN="${SAN},IP:${IP}"

mkdir -p certs

openssl req -x509 -newkey rsa:4096 \
    -keyout certs/prometheus.key \
    -out  certs/prometheus.crt \
    -days 3650 -nodes \
    -subj "/CN=${HOSTNAME}" \
    -addext "subjectAltName=${SAN}"

chmod 600 certs/prometheus.key

echo ""
echo "Certifikat vygenerovan:"
echo "  certs/prometheus.crt  (SAN: ${SAN})"
echo "  certs/prometheus.key"
echo ""
echo "Na Check Point kolektoru nastav jako CA cert: certs/prometheus.crt"
