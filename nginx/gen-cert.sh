#!/usr/bin/env bash
set -euo pipefail

# Script sinh certificate SSL tự ký cho Nginx Reverse Proxy
# Chạy trong WSL2: ./nginx/gen-cert.sh [LAN_IP]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/certs"
mkdir -p "${CERTS_DIR}"

CRT_FILE="${CERTS_DIR}/server.crt"
KEY_FILE="${CERTS_DIR}/server.key"

# SAN default: localhost and 127.0.0.1
SAN="DNS:localhost,IP:127.0.0.1"

# Tùy chọn: nhận IP LAN vào SAN
if [ -n "${1:-}" ]; then
    echo "[INFO] Thêm IP LAN vào SAN: $1"
    SAN="${SAN},IP:$1"
fi

echo "[INFO] Đang tạo chứng chỉ SSL tự ký (RSA 2048, 365 ngày, SAN: ${SAN})..."

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "${KEY_FILE}" \
    -out "${CRT_FILE}" \
    -subj "/C=VN/ST=ThaiNguyen/L=ThaiNguyen/O=DTC245180061/OU=AssetManagement/CN=localhost" \
    -addext "subjectAltName=${SAN}" \
    -addext "basicConstraints=CA:FALSE" \
    -addext "keyUsage=digitalSignature,keyEncipherment" \
    -addext "extendedKeyUsage=serverAuth"

chmod 644 "${CRT_FILE}"
chmod 644 "${KEY_FILE}"

echo "[SUCCESS] Chứng chỉ đã được tạo thành công:"
echo "  - Certificate: ${CRT_FILE}"
echo "  - Private Key: ${KEY_FILE}"

openssl x509 -noout -subject -dates -ext subjectAltName -in "${CRT_FILE}"
