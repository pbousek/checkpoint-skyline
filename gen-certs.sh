#!/bin/bash
# Vygeneruje self-signed TLS certifikát pro Prometheus Remote Write endpoint.
# Spusť na serveru po naklonování repozitáře.
#
# Použití:
#   ./gen-certs.sh <hostname> [<ip>]
#
# Příklady:
#   ./gen-certs.sh skyline.example.com
#   ./gen-certs.sh skyline.example.com 10.0.0.42
#
# Výstup:
#   certs/prometheus.crt  — nahrát na Check Point kolektoru jako CA cert
#   certs/prometheus.key  — zůstává na serveru (nesdílet)

set -euo pipefail

HOSTNAME="${1:?Chybí hostname. Použití: $0 <hostname> [<ip>]}"
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
echo "Certifikát vygenerován:"
echo "  certs/prometheus.crt  (SAN: ${SAN})"
echo "  certs/prometheus.key"
echo ""
echo "Na Check Point kolektoru nastav jako CA cert: certs/prometheus.crt"
