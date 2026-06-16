#!/bin/bash
# Generates a self-signed TLS certificate for the Prometheus Remote Write endpoint.
# Run on the server after cloning the repository.
#
# Usage:
#   ./gen-certs.sh <hostname> [<ip>]
#
# Examples:
#   ./gen-certs.sh skyline.example.com
#   ./gen-certs.sh skyline.example.com 10.0.0.42
#
# Output:
#   certs/prometheus.crt  -- upload to Check Point collector as CA cert
#   certs/prometheus.key  -- stays on the server, do not share

set -euo pipefail

HOSTNAME="${1:?Missing hostname. Usage: $0 <hostname> [<ip>]}"
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

chmod 644 certs/prometheus.key

echo ""
echo "Certificate generated:"
echo "  certs/prometheus.crt  (SAN: ${SAN})"
echo "  certs/prometheus.key"
echo ""
echo "Upload certs/prometheus.crt to the Check Point collector as CA cert."
