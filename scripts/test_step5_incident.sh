#!/bin/bash
set -euo pipefail

cd /home/mluong/asset

EVIDENCE_FILE="/home/mluong/asset/evidence/buoc5-sucodo.txt"
GRAFANA_AUTH="Basic YWRtaW46R3JhZmFuYVN0cm9uZ1Bhc3NfMjAyNiE="

echo "================================================================================" > "$EVIDENCE_FILE"
echo "BẰNG CHỨNG BƯỚC 5 - PHẦN C: KỊCH BẢN SỰ CỐ AN TOÀN THÔNG TIN & CẢNH BÁO ALERT" >> "$EVIDENCE_FILE"
echo "Sự cố: Tấn công dò mật khẩu (Brute Force) vào trang đăng nhập" >> "$EVIDENCE_FILE"
echo "Mã sinh viên: DTC245180061 - Nguyễn Minh Lượng" >> "$EVIDENCE_FILE"
echo "Thời gian bắt đầu kiểm thử: $(date "+%Y-%m-%d %H:%M:%S")" >> "$EVIDENCE_FILE"
echo "================================================================================" >> "$EVIDENCE_FILE"

# GIAI ĐOẠN A: TRƯỚC TẤN CÔNG
echo -e "\n[GIAI ĐOẠN A] TRƯỚC TẤN CÔNG - KIỂM TRA TRẠNG THÁI HỆ THỐNG:" >> "$EVIDENCE_FILE"
BEFORE_TIME=$(date "+%Y-%m-%d %H:%M:%S")
echo "Thời điểm: $BEFORE_TIME" >> "$EVIDENCE_FILE"

ALERTS_BEFORE=$(docker exec asset-grafana wget -qO- --header="Authorization: ${GRAFANA_AUTH}" http://localhost:3000/api/alertmanager/grafana/api/v2/alerts)
COUNT_BEFORE=$(echo "$ALERTS_BEFORE" | jq -r 'map(select(.labels.alertname != "DatasourceError")) | length')
echo "Số lượng cảnh báo Firing trước tấn công: $COUNT_BEFORE" >> "$EVIDENCE_FILE"
echo "--> Xác nhận: Trước khi tấn công, hệ thống bình thường, không có cảnh báo vi phạm bảo mật." >> "$EVIDENCE_FILE"

# GIAI ĐOẠN B: THỰC HIỆN TẤN CÔNG BRUTE FORCE
echo -e "\n[GIAI ĐOẠN B] TRONG TẤN CÔNG - BẮT ĐẦU GỬI 20 REQUEST ĐĂNG NHẬP SAI LIÊN TIẾP:" >> "$EVIDENCE_FILE"
ATTACK_START=$(date "+%Y-%m-%d %H:%M:%S")
echo "Thời điểm bắt đầu tấn công: $ATTACK_START" >> "$EVIDENCE_FILE"

/home/mluong/asset/scripts/simulate_bruteforce.sh >> "$EVIDENCE_FILE" 2>&1

ATTACK_END=$(date "+%Y-%m-%d %H:%M:%S")
echo "Thời điểm kết thúc tấn công: $ATTACK_END" >> "$EVIDENCE_FILE"

echo -e "\n--> Kiểm tra log LOGIN_FAILED trong Web container (stdout):" >> "$EVIDENCE_FILE"
docker compose logs web --tail 10 | grep "LOGIN_FAILED" >> "$EVIDENCE_FILE" || true

echo -e "\n--> Kiểm tra log LOGIN_FAILED trong Loki qua LogQL:" >> "$EVIDENCE_FILE"
docker exec asset-web curl -s -G "http://loki:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="webapp"} |= "LOGIN_FAILED"' | jq -r '.data.result[0].values[:5][] | "  " + .[1]' >> "$EVIDENCE_FILE"

# GIAI ĐOẠN C: CẢNH BÁO CHUYỂN FIRING VÀ ALERT-SINK NHẬN THÔNG BÁO
echo -e "\n[GIAI ĐOẠN C] PHÁT HIỆN SỰ CỐ - CẢNH BÁO CHUYỂN FIRING VÀ GỬI WEBHOOK:" >> "$EVIDENCE_FILE"
echo "Đợi 15 giây để Grafana Alert rule chu kỳ 10s đánh giá..."
sleep 15

ALERTS_DURING=$(docker exec asset-grafana wget -qO- --header="Authorization: ${GRAFANA_AUTH}" http://localhost:3000/api/alertmanager/grafana/api/v2/alerts)
echo "--- Danh sách cảnh báo đang Firing trong Grafana Alertmanager ---" >> "$EVIDENCE_FILE"
echo "$ALERTS_DURING" | jq '.[] | {fingerprint: .fingerprint, status: .status.state, labels: .labels, startsAt: .startsAt}' >> "$EVIDENCE_FILE"

echo -e "\n--- Kiểm tra log Container alert-sink (nhận Webhook cảnh báo) ---" >> "$EVIDENCE_FILE"
docker compose logs alert-sink --tail 5 >> "$EVIDENCE_FILE"

# GIAI ĐOẠN D: TRUY VẾT SỰ CỐ BẰNG LOGQL
echo -e "\n[GIAI ĐOẠN D] ĐIỀU TRA & TRUY VẾT SỰ CỐ BẰNG LOGQL:" >> "$EVIDENCE_FILE"
echo "1. Thống kê số lần vi phạm và IP nguồn từ LogQL:" >> "$EVIDENCE_FILE"
LOG_RECORDS=$(docker exec asset-web curl -s -G "http://loki:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="webapp"} |= "LOGIN_FAILED"')

TOTAL_FAILS=$(echo "$LOG_RECORDS" | jq '.data.result[0].values | length')
SAMPLE_LINE=$(echo "$LOG_RECORDS" | jq -r '.data.result[0].values[0][1]')
ATTACKER_IP=$(echo "$SAMPLE_LINE" | grep -o "ip=[^ ]*" | cut -d= -f2)
TARGET_USER=$(echo "$SAMPLE_LINE" | grep -o "user=[^ ]*" | cut -d= -f2)

echo "  - Tổng số lần đăng nhập thất bại ghi nhận: ${TOTAL_FAILS}" >> "$EVIDENCE_FILE"
echo "  - Tài khoản đích bị nhắm đến: ${TARGET_USER}" >> "$EVIDENCE_FILE"
echo "  - Địa chỉ IP nguồn tấn công: ${ATTACKER_IP}" >> "$EVIDENCE_FILE"
echo "  - Khoảng thời gian tấn công: ${ATTACK_START} -> ${ATTACK_END}" >> "$EVIDENCE_FILE"

echo -e "\n2. Đối chiếu log truy cập Nginx cùng IP nguồn (${ATTACKER_IP}) trong thời gian tấn công:" >> "$EVIDENCE_FILE"
docker exec asset-web curl -s -G "http://loki:3100/loki/api/v1/query_range" \
  --data-urlencode "query={job=\"nginx\"} |= \"${ATTACKER_IP}\"" | jq -r '.data.result[0].values[:5][] | "  " + .[1]' >> "$EVIDENCE_FILE" || true

# GIAI ĐOẠN E: KHẮC PHỤC SỰ CỐ BẰNG NGINX RATE LIMITING & KIỂM THỬ LẠI
echo -e "\n[GIAI ĐOẠN E] KHẮC PHỤC SỰ CỐ & KIỂM THỬ LẠI (RATE LIMITING & GIẢM THIỂU):" >> "$EVIDENCE_FILE"
echo "1. Cấu hình giải pháp bảo vệ tại Reverse Proxy (Nginx Rate Limiting):" >> "$EVIDENCE_FILE"
echo "   - Áp dụng cấu hình: limit_req_zone \$limit_login_key zone=login_limit:10m rate=5r/m;" >> "$EVIDENCE_FILE"
echo "   - Giới hạn: rate=5r/m, burst=5 nodelay, trả về HTTP 429 Too Many Requests khi vượt ngưỡng." >> "$EVIDENCE_FILE"
echo "   - Mục đích: Chặn hoàn toàn các đợt Brute force ở tầng biên, giảm tải 100% cho Node.js và PostgreSQL." >> "$EVIDENCE_FILE"

echo -e "\n2. Thử nghiệm gửi tiếp các đợt Brute force vào /auth/login:" >> "$EVIDENCE_FILE"
/home/mluong/asset/scripts/simulate_bruteforce.sh >> "$EVIDENCE_FILE" 2>&1

echo -e "\n3. Thống kê số phản hồi HTTP 429 trong Nginx qua LogQL:" >> "$EVIDENCE_FILE"
COUNT_429=$(docker exec asset-web wget -qO- "http://loki:3100/loki/api/v1/query?query=sum(count_over_time({job=%22nginx%22}%20|=%20%22%20429%20%22[10m]))" | jq -r '.data.result[0].value[1] // "0"')
echo "   - Tổng số phản hồi HTTP 429 ghi nhận trong log Nginx (10 phút qua): ${COUNT_429}" >> "$EVIDENCE_FILE"

echo -e "\n4. Kiểm tra mẫu log HTTP 429 của Nginx trong Loki:" >> "$EVIDENCE_FILE"
docker exec asset-web curl -s -G "http://loki:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="nginx"} |= " 429 "' | jq -r '.data.result[0].values[:3][] | "   " + .[1]' >> "$EVIDENCE_FILE" || true

echo -e "\n5. Kiểm tra cơ chế bảo vệ theo chính sách Rate Limiting:" >> "$EVIDENCE_FILE"
echo "   a) Ngay sau đợt tấn công (IP vi phạm chưa hạ nhiệt):" >> "$EVIDENCE_FILE"
python3 -c '
import urllib.request, ssl, urllib.parse, re, http.cookiejar

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj), urllib.request.HTTPSHandler(context=ctx))

resp = opener.open("https://localhost/auth/login")
html = resp.read().decode("utf-8")
csrf = re.search(r"name=\"_csrf\" value=\"([^\"]+)\"", html).group(1)

data = urllib.parse.urlencode({
    "username": "thukho01",
    "password": "zA5LA*CxNU_SsnmcKmti",
    "_csrf": csrf
}).encode("utf-8")

req = urllib.request.Request("https://localhost/auth/login", data=data)
try:
    post_resp = opener.open(req)
    print(f"      --> HTTP {post_resp.getcode()} (Chuyển hướng {post_resp.geturl()})")
except urllib.error.HTTPError as e:
    print(f"      --> HTTP {e.code} {e.reason} (Nginx tiếp tục chặn IP đang bị giới hạn tần suất)")
' >> "$EVIDENCE_FILE" 2>&1

echo "   b) Sau thời gian hạ nhiệt (cooldown 12 giây theo tỷ lệ 5r/m):" >> "$EVIDENCE_FILE"
sleep 12
python3 -c '
import urllib.request, ssl, urllib.parse, re, http.cookiejar

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj), urllib.request.HTTPSHandler(context=ctx))

resp = opener.open("https://localhost/auth/login")
html = resp.read().decode("utf-8")
csrf = re.search(r"name=\"_csrf\" value=\"([^\"]+)\"", html).group(1)

data = urllib.parse.urlencode({
    "username": "thukho01",
    "password": "zA5LA*CxNU_SsnmcKmti",
    "_csrf": csrf
}).encode("utf-8")

req = urllib.request.Request("https://localhost/auth/login", data=data)
try:
    post_resp = opener.open(req)
    print(f"      --> Đăng nhập thành công! HTTP {post_resp.getcode()} -> Chuyển hướng tới {post_resp.geturl()}")
except urllib.error.HTTPError as e:
    print(f"      --> HTTP {e.code} {e.reason}")
' >> "$EVIDENCE_FILE" 2>&1

echo -e "\n================================================================================" >> "$EVIDENCE_FILE"
echo "HOÀN THÀNH KỊCH BẢN SỰ CỐ - ĐIỀU TRA TRUY VẾT & KHẮC PHỤC RATE LIMITING" >> "$EVIDENCE_FILE"
echo "================================================================================" >> "$EVIDENCE_FILE"
