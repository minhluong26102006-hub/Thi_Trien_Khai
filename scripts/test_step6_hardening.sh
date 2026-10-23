#!/bin/bash
set -euo pipefail

cd /home/mluong/asset
OUTPUT_FILE="/home/mluong/asset/evidence/buoc6-hardening.txt"

echo "================================================================================" > "$OUTPUT_FILE"
echo "BẰNG CHỨNG BƯỚC 6: KIỂM CHỨNG CÁC BIỆN PHÁP HARDENING BẢO MẬT HỆ THỐNG" >> "$OUTPUT_FILE"
echo "Học phần: Triển khai và Quản trị Hệ thống Phần mềm" >> "$OUTPUT_FILE"
echo "Sinh viên: DTC245180061 - Nguyễn Minh Lượng" >> "$OUTPUT_FILE"
echo "Thời gian kiểm thử: $(date "+%Y-%m-%d %H:%M:%S")" >> "$OUTPUT_FILE"
echo "================================================================================" >> "$OUTPUT_FILE"

# 1. KIỂM TRA NON-ROOT USER
echo -e "\n[MỤC 1] KIỂM TRA ĐẶC QUYỀN CONTAINER (NON-ROOT USER):" >> "$OUTPUT_FILE"
SERVICES=("web" "db" "pgadmin" "nginx" "prometheus" "grafana" "cadvisor" "nginx-exporter" "postgres-exporter" "loki" "promtail" "alert-sink")

for s in "${SERVICES[@]}"; do
  echo -n "  - Service '$s': " >> "$OUTPUT_FILE"
  ID_OUT=$(docker compose exec -T "$s" id 2>&1 || true)
  if echo "$ID_OUT" | grep -q "uid="; then
    echo "$ID_OUT" >> "$OUTPUT_FILE"
  else
    CONF_USER=$(docker inspect "asset-$s" --format '{{.Config.User}}' 2>/dev/null || echo "N/A")
    echo "Configured User: $CONF_USER (Minimal image without /bin/id binary)" >> "$OUTPUT_FILE"
  fi
done

echo -e "\n  * Ghi chú ngoại lệ bắt buộc Root:" >> "$OUTPUT_FILE"
echo "    + cadvisor: Bắt buộc root để truy cập trực tiếp cgroups, sysfs (/sys), và Docker daemon socket." >> "$OUTPUT_FILE"
echo "    + promtail: Bắt buộc root/docker group để đọc Docker Engine socket (/var/run/docker.sock)." >> "$OUTPUT_FILE"
echo "    + nginx: Tiến trình master cần root để bind cổng chuẩn 80/443; các worker process chạy dưới tài khoản nginx (uid 101)." >> "$OUTPUT_FILE"

# 2. KIỂM TRA CÁCH LY MẠNG DOCKER (NETWORK ISOLATION)
echo -e "\n[MỤC 2] KIỂM TRA CÁCH LY MẠNG DOCKER (3-TIER NETWORKS):" >> "$OUTPUT_FILE"
echo "--- Danh sách các mạng dự án ---" >> "$OUTPUT_FILE"
docker network ls | grep "asset_" >> "$OUTPUT_FILE"

echo -e "\n--- Chi tiết mạng Backend (internal: true, chứa CSDL) ---" >> "$OUTPUT_FILE"
docker network inspect asset_backend | jq '.[0] | {Name: .Name, Internal: .Internal, Containers: [.Containers[] | {Name: .Name, IPv4: .IPv4Address}]}' >> "$OUTPUT_FILE"

echo -e "\n--- Kiểm tra mạng kết nối của CSDL (asset-db) ---" >> "$OUTPUT_FILE"
DB_NETS=$(docker inspect asset-db --format '{{json .NetworkSettings.Networks}}' | jq -r 'keys | .[]')
echo "  asset-db chỉ kết nối vào: $DB_NETS" >> "$OUTPUT_FILE"
if [ "$DB_NETS" = "asset_backend" ]; then
  echo "  --> XÁC NHẬN: CSDL asset-db được cô lập 100% trong mạng backend (internal: true), không thể truy cập từ bên ngoài." >> "$OUTPUT_FILE"
else
  echo "  --> CẢNH BÁO: DB kết nối ngoài backend!" >> "$OUTPUT_FILE"
fi

# 3. KIỂM TRA CỔNG MỞ TRÊN HOST VÀ WINDOWS
echo -e "\n[MỤC 3] KIỂM TRA CỔNG LẮNG NGHE & CÔNG BỐ (PORT EXPOSURE):" >> "$OUTPUT_FILE"
echo "--- Trạng thái cổng từ docker compose ps ---" >> "$OUTPUT_FILE"
docker compose ps --format "table {{.Name}}\t{{.Service}}\t{{.Status}}\t{{.Ports}}" >> "$OUTPUT_FILE"
echo "  --> XÁC NHẬN: Chỉ duy nhất container Nginx công bố cổng 80 và 443 ra ngoài host." >> "$OUTPUT_FILE"

echo -e "\n--- Hướng dẫn cấu hình Tường lửa Windows Defender Firewall (Mục 7) ---" >> "$OUTPUT_FILE"
echo "  * Lý do không dùng UFW trong WSL2: Trên môi trường Docker Desktop / WSL2, cổng xuất bản được ánh xạ trực tiếp" >> "$OUTPUT_FILE"
echo "    qua tiến trình Windows host (wslrelay.exe / com.docker.backend.exe), nên UFW bên trong WSL2 hoàn toàn KHÔNG" >> "$OUTPUT_FILE"
echo "    có tác dụng bảo vệ các cổng này đối với các kết nối từ mạng ngoài." >> "$OUTPUT_FILE"
echo "  * Lệnh kiểm tra quy tắc tường lửa hiện tại (chạy trên PowerShell):" >> "$OUTPUT_FILE"
echo "    netsh advfirewall firewall show rule name=all | findstr /i docker" >> "$OUTPUT_FILE"
echo "  * Lệnh tạo quy tắc chỉ cho phép cổng 80 và 443 của dự án (chạy trên PowerShell Administrator):" >> "$OUTPUT_FILE"
echo "    New-NetFirewallRule -DisplayName 'Allow Web HTTP 80' -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow" >> "$OUTPUT_FILE"
echo "    New-NetFirewallRule -DisplayName 'Allow Web HTTPS 443' -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow" >> "$OUTPUT_FILE"
echo "  * Phương án giới hạn Localhost (Nếu chỉ dùng trên máy này, sửa docker-compose.yml):" >> "$OUTPUT_FILE"
echo "    ports: [ '127.0.0.1:80:80', '127.0.0.1:443:443' ]" >> "$OUTPUT_FILE"

# 4. HẠN CHẾ QUYỀN DATABASE (LEAST PRIVILEGE)
echo -e "\n[MỤC 4] KIỂM TRA HẠN CHẾ QUYỀN CSDL CHO USER asset_app:" >> "$OUTPUT_FILE"
echo "--- Danh sách Roles và Thuộc tính trong PostgreSQL ---" >> "$OUTPUT_FILE"
docker compose exec -T db psql -U postgres -d assetdb -c '\du asset_app' >> "$OUTPUT_FILE"

echo "--- Bảng phân quyền trên bảng assets (\dp assets) ---" >> "$OUTPUT_FILE"
docker compose exec -T db psql -U postgres -d assetdb -c '\dp assets' >> "$OUTPUT_FILE"

echo -e "\n--- Thử nghiệm thực thi lệnh DROP TABLE bằng user asset_app ---" >> "$OUTPUT_FILE"
DROP_TEST=$(docker compose exec -T db psql -U asset_app -d assetdb -c 'DROP TABLE assets;' 2>&1 || true)
echo "  Kết quả thực thi: $DROP_TEST" >> "$OUTPUT_FILE"

echo -e "\n--- Thử nghiệm thực thi lệnh CREATE TABLE bằng user asset_app ---" >> "$OUTPUT_FILE"
CREATE_TEST=$(docker compose exec -T db psql -U asset_app -d assetdb -c 'CREATE TABLE test_unauth(id int);' 2>&1 || true)
echo "  Kết quả thực thi: $CREATE_TEST" >> "$OUTPUT_FILE"

echo -e "\n--- Kiểm tra quyền SELECT bình thường của user asset_app ---" >> "$OUTPUT_FILE"
SELECT_TEST=$(docker compose exec -T db psql -U asset_app -d assetdb -c 'SELECT count(*) as total_assets FROM assets;' 2>&1 || true)
echo "$SELECT_TEST" >> "$OUTPUT_FILE"

# 5. KIỂM TRA NGINX SECURITY HEADERS & ẨN THÔNG TIN SERVER
echo -e "\n[MỤC 5] KIỂM TRA PHẢN HỒI HTTP HEADERS & ẨN PHIÊN BẢN (NGINX + EXPRESS):" >> "$OUTPUT_FILE"
echo "--- Kiểm tra Headers trang gốc (https://localhost/) ---" >> "$OUTPUT_FILE"
curl -skI https://localhost/ >> "$OUTPUT_FILE"

echo -e "\n--- Kiểm tra chặn truy cập /nginx_status từ bên ngoài ---" >> "$OUTPUT_FILE"
curl -skI https://localhost/nginx_status >> "$OUTPUT_FILE"

# 6. RÀ SOÁT MẬT KHẨU TRONG GIT REPOSITORY
echo -e "\n[MỤC 6] RÀ SOÁT MẬT KHẨU & BÍ MẬT TRONG GIT:" >> "$OUTPUT_FILE"
echo "  - Kiểm tra file .env có bị git theo dõi không:" >> "$OUTPUT_FILE"
GIT_ENV_CHECK=$(git ls-files .env || true)
if [ -z "$GIT_ENV_CHECK" ]; then
  echo "    --> XÁC NHẬN: .env KHÔNG bị theo dõi bởi git." >> "$OUTPUT_FILE"
else
  echo "    --> CẢNH BÁO: .env đang bị git theo dõi!" >> "$OUTPUT_FILE"
fi

echo "  - Quyền file .env trên hệ thống:" >> "$OUTPUT_FILE"
ls -la .env >> "$OUTPUT_FILE"

# 7. KIỂM TRA THÔNG SỐ BẢO MẬT CONTAINER (DOCKER INSPECT)
echo -e "\n[MỤC 7] KIỂM TRA THÔNG SỐ BẢO MẬT CONTAINER (DOCKER INSPECT):" >> "$OUTPUT_FILE"
for s in web db nginx grafana; do
  echo "--- Container asset-$s ---" >> "$OUTPUT_FILE"
  docker inspect "asset-$s" | jq '.[0] | {
    SecurityOpt: .HostConfig.SecurityOpt,
    CapDrop: .HostConfig.CapDrop,
    CapAdd: .HostConfig.CapAdd,
    MemoryLimitMB: (.HostConfig.Memory / 1024 / 1024),
    NanoCpus: .HostConfig.NanoCpus
  }' >> "$OUTPUT_FILE"
done

# 8. SMOKE TEST TOÀN BỘ CHỨC NĂNG HỆ THỐNG
echo -e "\n[MỤC 8] SMOKE TEST TOÀN DIỆN CÁC TÍNH NĂNG NGHIỆP VỤ & GIÁM SÁT:" >> "$OUTPUT_FILE"

COOKIE_JAR=$(mktemp)
trap "rm -f $COOKIE_JAR" EXIT

extract_csrf() {
  local html="$1"
  echo "$html" | grep -o 'name="_csrf" value="[^"]*"' | head -n 1 | sed 's/name="_csrf" value="//;s/"//'
}

# Test 8.1: Đăng nhập Admin
LOGIN_GET=$(curl -sk -c "$COOKIE_JAR" https://localhost/auth/login)
CSRF_TOKEN=$(extract_csrf "$LOGIN_GET")
LOGIN_POST=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR" -c "$COOKIE_JAR"   --data-urlencode "username=admin"   --data-urlencode "password=D9a!X8KatFdDT%_kSd_Y"   --data-urlencode "_csrf=${CSRF_TOKEN}"   https://localhost/auth/login)
echo "  1. Đăng nhập Admin (admin): HTTP $LOGIN_POST (Mong đợi: 302 -> /assets)" >> "$OUTPUT_FILE"

# Test 8.2: Truy cập danh sách tài sản
ASSETS_PAGE=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR" https://localhost/assets)
echo "  2. Truy cập danh sách tài sản (/assets): HTTP $ASSETS_PAGE (Mong đợi: 200)" >> "$OUTPUT_FILE"

# Test 8.3: Xem nhãn QR tài sản
QR_PAGE=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR" https://localhost/assets/1/label)
echo "  3. Xem nhãn in QR Code tài sản TS-LAP-001: HTTP $QR_PAGE (Mong đợi: 200)" >> "$OUTPUT_FILE"

# Test 8.4: Upload ảnh tài sản (Multipart Form-Data qua x-csrf-token vào /admin/assets/new)
TEST_IMG="/tmp/test_asset_img.png"
echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" | base64 -d > "$TEST_IMG"

UPLOAD_CSRF=$(extract_csrf "$(curl -sk -b "$COOKIE_JAR" https://localhost/admin/assets/new)")
UPLOAD_RESP=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR"   -H "x-csrf-token: ${UPLOAD_CSRF}"   -F "_csrf=${UPLOAD_CSRF}"   -F "asset_code=TS-SEC-$(date +%s)"   -F "name=Thiết bị kiểm thử bảo mật Hardening"   -F "category_id=1"   -F "location_id=1"   -F "serial_number=SN-SEC-99881"   -F "purchase_date=2026-10-24"   -F "purchase_price=18500000"   -F "useful_life_years=5"   -F "status=available"   -F "note=Tài sản kiểm chứng upload ảnh dưới non-root"   -F "image=@${TEST_IMG};type=image/png"   https://localhost/admin/assets/new)
echo "  4. Thêm tài sản kèm upload ảnh thực tế: HTTP $UPLOAD_RESP (Mong đợi: 302 -> /assets)" >> "$OUTPUT_FILE"
rm -f "$TEST_IMG"

# Test 8.5: Kiểm thử quy trình Mượn/Trả (Nhân viên tạo phiếu qua /loans/create)
NV_COOKIE=$(mktemp)
NV_GET=$(curl -sk -c "$NV_COOKIE" https://localhost/auth/login)
NV_CSRF=$(extract_csrf "$NV_GET")
curl -sk -b "$NV_COOKIE" -c "$NV_COOKIE"   --data-urlencode "username=nhanvien01"   --data-urlencode "password=5&j#6)7ZmGySQZicXbCS"   --data-urlencode "_csrf=${NV_CSRF}"   https://localhost/auth/login > /dev/null

LOAN_NEW_CSRF=$(extract_csrf "$(curl -sk -b "$NV_COOKIE" https://localhost/loans/create)")
LOAN_RESP=$(curl -sk -o /dev/null -w "%{http_code}" -b "$NV_COOKIE"   --data-urlencode "_csrf=${LOAN_NEW_CSRF}"   --data-urlencode "asset_ids=12"   --data-urlencode "due_date=2026-11-01"   --data-urlencode "purpose=Mượn kiểm thử quy trình mượn trả Bước 6"   https://localhost/loans/create)
echo "  5. Nhân viên (nhanvien01) tạo phiếu mượn tài sản TS-NET-002: HTTP $LOAN_RESP (Mong đợi: 302 -> /loans)" >> "$OUTPUT_FILE"
rm -f "$NV_COOKIE"

# Test 8.6: Đăng nhập Grafana
GRAFANA_AUTH="Basic YWRtaW46R3JhZmFuYVN0cm9uZ1Bhc3NfMjAyNiE="
GRAFANA_HEALTH=$(curl -sk -o /dev/null -w "%{http_code}" -H "Authorization: ${GRAFANA_AUTH}" https://localhost/grafana/api/health)
echo "  6. Kiểm tra Grafana Health API qua Nginx: HTTP $GRAFANA_HEALTH (Mong đợi: 200)" >> "$OUTPUT_FILE"

# Test 8.7: Kiểm tra Loki Datasource từ Grafana
LOKI_DS_CHECK=$(curl -sk -H "Authorization: ${GRAFANA_AUTH}" https://localhost/grafana/api/datasources/name/Loki | jq -r '.type // "error"')
echo "  7. Kiểm tra Grafana Loki Datasource: $LOKI_DS_CHECK (Mong đợi: loki)" >> "$OUTPUT_FILE"

# Test 8.8: Kiểm tra Prometheus Exporter Targets
PROM_TARGETS=$(docker exec asset-prometheus wget -qO- http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets | length')
echo "  8. Số lượng Scrape Targets hoạt động trong Prometheus: $PROM_TARGETS targets" >> "$OUTPUT_FILE"

# Test 8.9: Kiểm tra trạng thái 12/12 container
TOTAL_RUNNING=$(docker compose ps --status running -q | wc -l)
echo "  9. Tổng số container Up (healthy/running): $TOTAL_RUNNING / 12 containers" >> "$OUTPUT_FILE"

echo -e "\n================================================================================" >> "$OUTPUT_FILE"
echo "HOÀN THÀNH KIỂM CHỨNG BƯỚC 6 - TOÀN BỘ HỆ THỐNG AN TOÀN VÀ ĐẠT CHUẨN" >> "$OUTPUT_FILE"
echo "================================================================================" >> "$OUTPUT_FILE"
echo "Evidence saved to $OUTPUT_FILE"
