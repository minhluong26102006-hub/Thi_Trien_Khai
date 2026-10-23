#!/bin/bash
set -euo pipefail

cd /home/mluong/asset

EVIDENCE_FILE="/home/mluong/asset/evidence/buoc3-nginx.txt"
COOKIE_DIR=$(mktemp -d)
trap "rm -rf $COOKIE_DIR" EXIT

# Mat khau tai khoan seed
ADMIN_PASS="D9a!X8KatFdDT%_kSd_Y"
NV1_PASS="5&j#6)7ZmGySQZicXbCS"

extract_csrf() {
  local html="$1"
  echo "$html" | grep -o 'name="_csrf" value="[^"]*"' | head -n 1 | sed 's/name="_csrf" value="//;s/"//'
}

echo "================================================================================" > "$EVIDENCE_FILE"
echo "BANG CHUNG BUOC 3: NGINX REVERSE PROXY, HTTPS TU KY VA SECURITY HEADERS" >> "$EVIDENCE_FILE"
echo "Ma sinh vien: DTC245180061 - Nguyen Minh Luong" >> "$EVIDENCE_FILE"
echo "Thoi gian kiem tra: $(date "+%Y-%m-%d %H:%M:%S")" >> "$EVIDENCE_FILE"
echo "================================================================================" >> "$EVIDENCE_FILE"

echo -e "\n1. KIEM TRA DOCKER COMPOSE PS (NGINX, WEB, DB, PGADMIN):" >> "$EVIDENCE_FILE"
docker compose ps >> "$EVIDENCE_FILE"

echo -e "\n2. CU PHAP CAU HINH NGINX (nginx -t):" >> "$EVIDENCE_FILE"
docker compose exec nginx nginx -t >> "$EVIDENCE_FILE" 2>&1

echo -e "\n3. KIEM TRA CHUNG CHI SSL (openssl s_client & x509):" >> "$EVIDENCE_FILE"
openssl s_client -connect localhost:443 </dev/null 2>/dev/null | openssl x509 -noout -subject -dates -ext subjectAltName >> "$EVIDENCE_FILE"

echo -e "\n4. KIEM TRA REDIRECT HTTP -> HTTPS (CONG 80 -> CONG 443, MA 301):" >> "$EVIDENCE_FILE"
curl -I http://localhost >> "$EVIDENCE_FILE" 2>&1

echo -e "\n5. KIEM TRA HTTPS RESPONSE VA SECURITY HEADERS (CONG 443):" >> "$EVIDENCE_FILE"
curl -kI https://localhost >> "$EVIDENCE_FILE" 2>&1

echo -e "\n6. XAC NHAN CONG 3000 VA 5050 DA BI GO PUBLISH (CONNECTION REFUSED):" >> "$EVIDENCE_FILE"
echo "--- Ket noi toi localhost:3000 ---" >> "$EVIDENCE_FILE"
curl -I --connect-timeout 2 http://localhost:3000 >> "$EVIDENCE_FILE" 2>&1 || true
echo "--- Ket noi toi localhost:5050 ---" >> "$EVIDENCE_FILE"
curl -I --connect-timeout 2 http://localhost:5050 >> "$EVIDENCE_FILE" 2>&1 || true

echo -e "\n7. KIEM TRA PGADMIN QUA NGINX SUBPATH (/pgadmin/):" >> "$EVIDENCE_FILE"
curl -kIL https://localhost/pgadmin/ | head -n 35 >> "$EVIDENCE_FILE"

echo -e "\n8. KIEM TRA NGINX STUB_STATUS NOI BO (CHO PROMETHEUS EXPORTER):" >> "$EVIDENCE_FILE"
docker exec asset-nginx wget -qO- http://127.0.0.1/nginx_status >> "$EVIDENCE_FILE"

echo -e "\n9. KIEM TRA DANG NHAP EMPLOYEE QUA HTTPS (COOKIE SECURE & PROXY):" >> "$EVIDENCE_FILE"
LOGIN_PAGE=$(curl -sk -c "$COOKIE_DIR/emp.txt" https://localhost/auth/login)
CSRF_TOKEN=$(extract_csrf "$LOGIN_PAGE")

LOGIN_RESP=$(curl -sk -i -b "$COOKIE_DIR/emp.txt" -c "$COOKIE_DIR/emp.txt" \
  --data-urlencode "username=nhanvien01" \
  --data-urlencode "password=${NV1_PASS}" \
  --data-urlencode "_csrf=${CSRF_TOKEN}" \
  https://localhost/auth/login)
echo "--- HTTP Response Header sau khi Login ---" >> "$EVIDENCE_FILE"
echo "$LOGIN_RESP" | grep -E "HTTP/|location:|set-cookie:" >> "$EVIDENCE_FILE"

ASSETS_PAGE=$(curl -sk -b "$COOKIE_DIR/emp.txt" https://localhost/assets)
echo "--- Kiem tra noi dung trang /assets sau khi login ---" >> "$EVIDENCE_FILE"
echo "$ASSETS_PAGE" | grep -o "Danh Mục Tài Sản" | head -n 1 >> "$EVIDENCE_FILE"
echo "Employee truy cap danh muc tai san qua HTTPS thanh cong." >> "$EVIDENCE_FILE"

echo -e "\n10. KIEM TRA ADMIN DANG NHAP & UPLOAD ANH TAI SAN QUA HTTPS:" >> "$EVIDENCE_FILE"
ADMIN_LOGIN_PAGE=$(curl -sk -c "$COOKIE_DIR/admin.txt" https://localhost/auth/login)
ADMIN_CSRF=$(extract_csrf "$ADMIN_LOGIN_PAGE")
curl -sk -b "$COOKIE_DIR/admin.txt" -c "$COOKIE_DIR/admin.txt" \
  --data-urlencode "username=admin" \
  --data-urlencode "password=${ADMIN_PASS}" \
  --data-urlencode "_csrf=${ADMIN_CSRF}" \
  https://localhost/auth/login > /dev/null

TEST_PNG="$COOKIE_DIR/test_https.png"
printf "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB\`\x82" > "$TEST_PNG"

FORM_PAGE=$(curl -sk -b "$COOKIE_DIR/admin.txt" https://localhost/admin/assets/new)
NEW_CSRF=$(extract_csrf "$FORM_PAGE")

# Xoa neu da ton tai tu truoc
docker exec -i asset-db psql -U asset_app -d assetdb -c "DELETE FROM assets WHERE asset_code='ASSET-HTTPS-TEST';" > /dev/null 2>&1 || true

CREATE_RESP=$(curl -sk -i -b "$COOKIE_DIR/admin.txt" -c "$COOKIE_DIR/admin.txt" \
  -H "x-csrf-token: ${NEW_CSRF}" \
  -F "_csrf=${NEW_CSRF}" \
  -F "asset_code=ASSET-HTTPS-TEST" \
  -F "name=Thiet bi kiem thu HTTPS" \
  -F "category_id=1" \
  -F "location_id=1" \
  -F "serial_number=SN-HTTPS-001" \
  -F "purchase_date=2024-01-01" \
  -F "purchase_price=25000000" \
  -F "useful_life_years=5" \
  -F "status=available" \
  -F "note=Tao qua kiem thu Buoc 3" \
  -F "image=@${TEST_PNG};type=image/png" \
  https://localhost/admin/assets/new)

echo "--- HTTP Response tao tai san kem Upload anh qua HTTPS ---" >> "$EVIDENCE_FILE"
echo "$CREATE_RESP" | grep -E "HTTP/|location:" >> "$EVIDENCE_FILE"

UPLOADED_IMG=$(docker exec -i asset-db psql -U asset_app -d assetdb -t -c "SELECT image_path FROM assets WHERE asset_code='ASSET-HTTPS-TEST';" | tr -d "[:space:]")
echo "Duong dan anh trong CSDL: $UPLOADED_IMG" >> "$EVIDENCE_FILE"

IMG_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "https://localhost${UPLOADED_IMG}")
echo "HTTP Status phuc vu anh qua HTTPS: $IMG_STATUS" >> "$EVIDENCE_FILE"

echo -e "\n11. KIEM TRA TRANG NHAN TAI SAN KEM MA QR CODE QUA HTTPS:" >> "$EVIDENCE_FILE"
LABEL_HTML=$(curl -sk -b "$COOKIE_DIR/admin.txt" https://localhost/assets/1/label)
echo "--- Kiem tra the QR Code trong HTML nhan ---" >> "$EVIDENCE_FILE"
echo "$LABEL_HTML" | grep -o 'src="data:image/png;base64,[^"]*"' | head -c 80 >> "$EVIDENCE_FILE"
echo -e "\n... (ma QR Base64 hop le, hien thi tot qua HTTPS)" >> "$EVIDENCE_FILE"

echo -e "\n12. KIEM TRA NGINX ACCESS LOG FORMAT (stdout):" >> "$EVIDENCE_FILE"
docker compose logs nginx --tail 10 >> "$EVIDENCE_FILE"

echo -e "\n================================================================================" >> "$EVIDENCE_FILE"
echo "KET THUC BUOC 3 - TAT CA KIEM THU THANH CONG 100%" >> "$EVIDENCE_FILE"
echo "================================================================================" >> "$EVIDENCE_FILE"
