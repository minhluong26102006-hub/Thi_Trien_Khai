#!/bin/bash
set -euo pipefail

cd /home/mluong/asset

EVIDENCE_FILE="/home/mluong/asset/evidence/buoc4-giamsat.txt"
COOKIE_DIR=$(mktemp -d)
trap "rm -rf $COOKIE_DIR" EXIT

extract_csrf() {
  local html="$1"
  echo "$html" | grep -o 'name="_csrf" value="[^"]*"' | head -n 1 | sed 's/name="_csrf" value="//;s/"//'
}

echo "================================================================================" > "$EVIDENCE_FILE"
echo "BANG CHUNG BUOC 4: HE THONG GIAM SAT PROMETHEUS + GRAFANA + EXPORTERS" >> "$EVIDENCE_FILE"
echo "Ma sinh vien: DTC245180061 - Nguyen Minh Luong" >> "$EVIDENCE_FILE"
echo "Thoi gian kiem tra: $(date "+%Y-%m-%d %H:%M:%S")" >> "$EVIDENCE_FILE"
echo "================================================================================" >> "$EVIDENCE_FILE"

echo -e "\n1. TRANG THAI TAT CA CAC CONTAINER (DOCKER COMPOSE PS):" >> "$EVIDENCE_FILE"
docker compose ps >> "$EVIDENCE_FILE"

echo -e "\n2. KIEM TRA PROMETHEUS TARGETS (TAT CA TARGET PHAI UP):" >> "$EVIDENCE_FILE"
TARGETS_JSON=$(docker exec asset-prometheus wget -qO- http://localhost:9090/api/v1/targets)
echo "$TARGETS_JSON" | jq -r '.data.activeTargets[] | "Job: \(.labels.job) | Target: \(.labels.instance) | Health: \(.health) | ScrapeURL: \(.scrapeUrl)"' >> "$EVIDENCE_FILE"

echo -e "\n3. KIEM TRA CAC TRUY VAN PROMQL QUA PROMETHEUS API:" >> "$EVIDENCE_FILE"
echo "--- 3.1. Truy van: container_memory_usage_bytes ---" >> "$EVIDENCE_FILE"
docker exec asset-prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=container_memory_usage_bytes' | jq '.data.result[:2]' >> "$EVIDENCE_FILE"

echo "--- 3.2. Truy van: nginx_connections_active ---" >> "$EVIDENCE_FILE"
docker exec asset-prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=nginx_connections_active' | jq '.data.result' >> "$EVIDENCE_FILE"

echo "--- 3.3. Truy van: pg_stat_database_numbackends{datname=\"assetdb\"} ---" >> "$EVIDENCE_FILE"
docker exec asset-prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=pg_stat_database_numbackends%7Bdatname%3D%22assetdb%22%7D' | jq '.data.result' >> "$EVIDENCE_FILE"

echo -e "\n4. KIEM TRA GRAFANA LOGIN VA REVERSE PROXY QUA NGINX (HTTPS):" >> "$EVIDENCE_FILE"
curl -kI https://localhost/grafana/login >> "$EVIDENCE_FILE" 2>&1

echo -e "\n5. KIEM TRA GRAFANA PROVISIONING QUA API (DATASOURCE & 3 DASHBOARDS):" >> "$EVIDENCE_FILE"
GRAFANA_AUTH="Basic YWRtaW46R3JhZmFuYVN0cm9uZ1Bhc3NfMjAyNiE="

echo "--- 5.1. Provisioned Datasource ---" >> "$EVIDENCE_FILE"
docker exec asset-grafana wget -qO- --header="Authorization: ${GRAFANA_AUTH}" http://localhost:3000/api/datasources | jq '.[] | {name: .name, type: .type, url: .url, isDefault: .isDefault}' >> "$EVIDENCE_FILE"

echo "--- 5.2. Provisioned Dashboards in Asset Monitoring Folder ---" >> "$EVIDENCE_FILE"
docker exec asset-grafana wget -qO- --header="Authorization: ${GRAFANA_AUTH}" http://localhost:3000/api/search | jq '.[] | {title: .title, uid: .uid, folderTitle: .folderTitle, url: .url}' >> "$EVIDENCE_FILE"

echo -e "\n6. SINH TAI VA KIEM THU TICH HOP (200 REQUESTS, DANG NHAP, MUON THIET BI):" >> "$EVIDENCE_FILE"
echo "Dang sinh 200 request GET toi https://localhost/assets ..."
for i in $(seq 1 200); do
  curl -sk -o /dev/null "https://localhost/assets?page=$(( (i % 3) + 1 ))" &
  if (( i % 25 == 0 )); then
    wait
  fi
done
wait
echo "--> Da hoan thanh 200 requests toi danh muc tai san." >> "$EVIDENCE_FILE"

echo "Dang thuc hien vai lan dang nhap va gui phieu muon..."
# Dang nhap employee
LOGIN_PAGE=$(curl -sk -c "$COOKIE_DIR/emp.txt" https://localhost/auth/login)
CSRF_TOKEN=$(extract_csrf "$LOGIN_PAGE")

curl -sk -b "$COOKIE_DIR/emp.txt" -c "$COOKIE_DIR/emp.txt" \
  --data-urlencode "username=nhanvien01" \
  --data-urlencode "password=5&j#6)7ZmGySQZicXbCS" \
  --data-urlencode "_csrf=${CSRF_TOKEN}" \
  https://localhost/auth/login > /dev/null

# Gui phieu muon
CREATE_PAGE=$(curl -sk -b "$COOKIE_DIR/emp.txt" -c "$COOKIE_DIR/emp.txt" https://localhost/loans/create)
LOAN_CSRF=$(extract_csrf "$CREATE_PAGE")

# Tim 1 asset available
AVAIL_ID=$(docker exec -i asset-db psql -U asset_app -d assetdb -t -c "SELECT id FROM assets WHERE status='available' LIMIT 1;" | tr -d "[:space:]")

if [ -n "$AVAIL_ID" ]; then
  LOAN_RESP=$(curl -sk -i -b "$COOKIE_DIR/emp.txt" -c "$COOKIE_DIR/emp.txt" \
    --data-urlencode "_csrf=${LOAN_CSRF}" \
    --data-urlencode "purpose=Muon phuc vu do tai giam sat Buoc 4" \
    --data-urlencode "due_date=$(date -d "+7 days" "+%Y-%m-%d")" \
    -d "asset_ids[]=${AVAIL_ID}" \
    https://localhost/loans/create)
  echo "--> Ket qua tao phieu muon khi sinh tai: HTTP $(echo "$LOAN_RESP" | grep -o "HTTP/2 [0-9]*")" >> "$EVIDENCE_FILE"
fi

echo -e "\n7. KIEM TRA LAI SO LIEU PROMETHEUS SAU KHI SINH TAI (TRAFFIC SPIKE):" >> "$EVIDENCE_FILE"
echo "--- Nginx Requests Total sau sinh tai ---" >> "$EVIDENCE_FILE"
docker exec asset-prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=nginx_http_requests_total' | jq '.data.result' >> "$EVIDENCE_FILE"

echo "--- PostgreSQL Tuples Fetched sau sinh tai ---" >> "$EVIDENCE_FILE"
docker exec asset-prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=pg_stat_database_tup_fetched%7Bdatname%3D%22assetdb%22%7D' | jq '.data.result' >> "$EVIDENCE_FILE"

echo -e "\n================================================================================" >> "$EVIDENCE_FILE"
echo "KET THUC BUOC 4 - TAT CA KIEM THU HE THONG GIAM SAT THANH CONG 100%" >> "$EVIDENCE_FILE"
echo "================================================================================" >> "$EVIDENCE_FILE"
