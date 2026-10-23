# Hệ thống Quản lý Tài sản / Thiết bị (Asset & Equipment Management System)

- **Môn học**: Triển khai và Quản trị Hệ thống Phần mềm
- **Sinh viên thực hiện**: Nguyễn Minh Lượng
- **Mã số sinh viên (MSSV)**: DTC245180061
- **Repository**: DTC245180061-asset-devops
- **Kiến trúc hệ thống**: Docker Compose triển khai trên Ubuntu WSL2 với Nginx Reverse Proxy (HTTPS tự ký, TLS 1.2/1.3, Security Headers), Node.js Express App, PostgreSQL 16 và pgAdmin 4.

---

## 1. Yêu cầu môi trường
- Hệ điều hành: Windows 11 với WSL2 (Ubuntu 22.04 LTS).
- Docker Desktop tích hợp WSL2 engine.
- OpenSSL (sẵn có trong WSL2) để sinh chứng chỉ SSL tự ký.

---

## 2. Cấu hình biến môi trường
Sao chép tệp mẫu `.env.example` thành `.env` và thiết lập các giá trị bí mật:
```bash
cp .env.example .env
```
*(Lưu ý: Tệp `.env` đã được đưa vào `.gitignore` để tránh rò rỉ mã bí mật).*

---

## 3. Sinh chứng chỉ SSL tự ký cho Nginx Reverse Proxy
Chạy script sinh chứng chỉ SSL tự ký được lưu trong thư mục `nginx/`:
```bash
# Cú pháp cơ bản (SAN gồm DNS:localhost và IP:127.0.0.1)
./nginx/gen-cert.sh

# Hoặc bổ sung thêm IP LAN của máy Windows nếu muốn truy cập từ mạng nội bộ:
./nginx/gen-cert.sh 192.168.1.50
```
- Script sẽ tự động tạo cặp tệp:
  - `nginx/certs/server.crt`: Chứng chỉ X.509 RSA 2048-bit, thời hạn 365 ngày.
  - `nginx/certs/server.key`: Khóa riêng tư bảo mật (chỉ đọc nội bộ).
- Các tệp `.key` và `.crt` đều được loại trừ khỏi Git qua `.gitignore`.

---

## 4. Khởi chạy hệ thống bằng Docker Compose
Khởi động toàn bộ các dịch vụ ngầm định:
```bash
docker compose up -d --build
```

Kiểm tra trạng thái các container:
```bash
docker compose ps
```
Tất cả các dịch vụ `asset-db`, `asset-web`, `asset-pgadmin`, `asset-nginx` đều phải ở trạng thái running / healthy.

Kiểm tra cú pháp cấu hình Nginx:
```bash
docker compose exec nginx nginx -t
```

---

## 5. Điểm truy cập dịch vụ (Endpoints)
- **Ứng dụng Web Quản lý Tài sản**:
  - `https://localhost` (Cổng 443 - HTTPS với đầy đủ Security Headers: HSTS, CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy).
  - Truy cập `http://localhost` sẽ tự động chuyển hướng 301 sang `https://localhost`.
- **Trình quản trị CSDL pgAdmin 4**:
  - `https://localhost/pgadmin/` (chạy dưới subpath thông qua Reverse Proxy, cổng 5050 gốc đã bị đóng bảo mật).
- **Điểm kiểm tra sức khỏe**:
  - `https://localhost/health` (trả về `OK`).

> **Lưu ý về Cảnh báo Chứng chỉ SSL trên Trình duyệt:**
> Khi truy cập qua trình duyệt Windows, do chứng chỉ là tự ký (Self-signed Certificate), trình duyệt sẽ hiện cảnh báo bảo mật. Bạn chỉ cần nhấn **Advanced (Nâng cao)** -> **Proceed to localhost (Tiếp tục truy cập localhost (không an toàn))**. Tuyệt đối không cài chứng chỉ vào kho tin cậy (Root CA Store) của Windows khi chưa có sự cho phép.

---

## 6. Hướng dẫn đăng ký Server Database trong pgAdmin 4
1. Đăng nhập vào `https://localhost/pgadmin/` với tài khoản quản trị pgAdmin.
2. Tại cây điều hướng bên trái, nhấp chuột phải vào **Servers** -> **Register** -> **Server...**.
3. Tab **General**:
   - `Name`: `Asset-PostgreSQL`
4. Tab **Connection**:
   - `Host name/address`: `db` (tên service trong Docker network `asset_net`)
   - `Port`: `5432`
   - `Maintenance database`: `assetdb`
   - `Username`: `asset_app`
   - `Password`: Nhập mật khẩu trong `.env` (`POSTGRES_PASSWORD`)
5. Nhấn **Save**. Kiểm tra nhánh `Schemas` -> `public` -> `Tables` sẽ thấy đủ 7 bảng: `users`, `categories`, `locations`, `assets`, `loans`, `loan_items`, `maintenance_logs`.

---

## 7. Hệ thống Giám sát Prometheus và Grafana
Hệ thống tích hợp giám sát tập trung qua Prometheus và trực quan hóa với Grafana:
- **Grafana Web Dashboard**:
  - URL: `https://localhost/grafana/` (chạy qua Nginx Reverse Proxy với hỗ trợ WebSocket).
  - Provisioned tự động thư mục dashboard **Asset Monitoring** gồm 3 bảng điều khiển chuyên sâu:
    1. `Asset - Containers`: Tỷ lệ CPU %, bộ nhớ RAM, lưu lượng mạng Network I/O theo từng container (thu thập từ cAdvisor).
    2. `Asset - Nginx`: Kết nối đang hoạt động (Active Connections), tần suất yêu cầu (Requests/sec), kết nối Handled vs Accepted (thu thập từ Nginx Prometheus Exporter).
    3. `Asset - PostgreSQL`: Số lượng kết nối Client, giao dịch/giây (Commits vs Rollbacks), Tuples Returned/Fetched, tỷ lệ Cache Hit Ratio (%), kích thước Database `assetdb` (thu thập từ PostgreSQL Exporter).

---

## 8. Lệnh tạo người dùng `exporter` an toàn trong CSDL PostgreSQL
Đối với trường hợp volume CSDL đã tồn tại từ trước (khi `init.sql` không chạy lại), chạy lệnh sau trong WSL để tạo user `exporter` có role giám sát `pg_monitor`:
```bash
docker exec -i asset-db psql -U asset_app -d assetdb -c "
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'exporter') THEN
    CREATE ROLE exporter WITH LOGIN PASSWORD 'Exp_SecPass_2026_dbmon!';
  ELSE
    ALTER ROLE exporter WITH PASSWORD 'Exp_SecPass_2026_dbmon!';
  END IF;
  GRANT pg_monitor TO exporter;
  GRANT CONNECT ON DATABASE assetdb TO exporter;
END \$\$;
"
```

---

## 9. Hướng dẫn xem trang Prometheus Targets an toàn
Theo kiến trúc bảo mật, Prometheus (cổng 9090) không được publish công khai ra bên ngoài mà chỉ chạy nội bộ trong mạng `asset_net`. Để kiểm tra hoặc chụp ảnh trang Targets:
1. Tạo tệp đè cấu hình tạm thời `docker-compose.override.yml` (tệp này đã nằm trong `.gitignore`, không commit):
```yaml
services:
  prometheus:
    ports:
      - "127.0.0.1:9090:9090"
```
2. Cập nhật dịch vụ Prometheus:
```bash
docker compose up -d prometheus
```
3. Mở trình duyệt truy cập: `http://localhost:9090/targets` (xác nhận tất cả các job `cadvisor`, `nginx`, `postgres`, `prometheus` đều có trạng thái `UP`).
4. Chụp ảnh xong, xóa tệp override và áp dụng lại cấu hình để đóng cổng 9090:
```bash
rm -f docker-compose.override.yml
docker compose up -d prometheus
```

---

## 10. Hệ thống Log tập trung Loki + Promtail & Kịch bản sự cố An toàn thông tin
Hệ thống sử dụng **Grafana Loki** kết hợp **Promtail** để thu thập, lập chỉ mục và phân tích log thời gian thực từ 12 container Docker:
- **Truy vấn LogQL trên Grafana Explore** (`https://localhost/grafana/explore`):
  - Log lỗi Nginx 4xx/5xx: `{job="docker", container=~".*nginx.*"} |~ "(4[0-9]{2}|5[0-9]{2})"`
  - Log đăng nhập thất bại: `{job="docker", container=~".*web.*"} |= "Đăng nhập thất bại"`
  - Log PostgreSQL truy vấn chậm: `{job="docker", container=~".*db.*"} |~ "(duration:|error|warning)"`
- **Dashboard trực quan hóa log**:
  - Tự động nạp dashboard **Logs - Asset & Security** tại thư mục **Asset Monitoring** trên Grafana.
- **Kịch bản sự cố An toàn thông tin (Tấn công Brute Force)**:
  - Script mô phỏng tấn công: `bash scripts/simulate_bruteforce.sh 20`
  - Cơ chế phòng thủ 1 (Nginx): Cấu hình `limit_req_zone` giới hạn 5 yêu cầu/phút, trả HTTP 429 khi bị quét.
  - Cơ chế phát hiện 2 (Loki + Grafana Alerting): Quy tắc cảnh báo `HighFailedLoginRate` tự động kích hoạt khi có trên 10 lần đăng nhập thất bại/phút.
  - Webhook tiếp nhận cảnh báo: Dịch vụ `alert-sink` (Python/Flask) ghi nhận alert JSON và log chi tiết.
  - Báo cáo sự cố chi tiết và bằng chứng truy vết log: `docs/su-co-bruteforce.md`.

---

## 11. Các biện pháp Hardening bảo mật & Quét lỗ hổng Trivy
Toàn bộ hệ thống được áp dụng các biện pháp gia cố bảo mật chuyên sâu (Bước 6):
1. **Chạy container với người dùng không đặc quyền (Non-root)**:
   - `web`: chạy dưới tài khoản `node` (UID:GID `1000:1000`).
   - `prometheus`, `nginx-exporter`, `postgres-exporter`: chạy dưới tài khoản `nobody` (UID:GID `65534:65534`).
   - `grafana`: chạy dưới tài khoản `grafana` (UID:GID `472:472`).
   - `loki`, `alert-sink`: chạy dưới tài khoản unprivileged `10001:10001`.
   - *Ngoại lệ kỹ thuật có ghi chú*: `cadvisor` (đọc cgroups/sysfs của host), `promtail` (đọc docker.sock), `nginx` (tiến trình master bind cổng 80/443, worker chạy dưới UID 101).
2. **Cô lập mạng 3 phân vùng (3-Tier Network Isolation)**:
   - `asset_frontend` (bridge): Chỉ gồm `nginx`, `web`, `pgadmin`, `grafana`.
   - `asset_backend` (bridge, `internal: true`): Chứa `asset-db`, `web`, `pgadmin`, `postgres-exporter`. Hoàn toàn không có gateway ra ngoài mạng Internet.
   - `asset_monitoring` (bridge): Phân vùng giám sát riêng biệt cho Prometheus, Grafana, Loki, Promtail và các Exporter.
   - CSDL `asset-db` chỉ kết nối duy nhất vào `asset_backend`, không công bố bất kỳ cổng nào ra máy host Windows.
3. **Phân quyền tối thiểu CSDL PostgreSQL (Least Privilege)**:
   - Chuyển quyền sở hữu bảng và sequence sang user quản trị hệ thống `db_admin`.
   - User ứng dụng `asset_app` bị thu hồi toàn bộ quyền `CREATE` trên schema `public`, chỉ được cấp quyền `SELECT, INSERT, UPDATE, DELETE` trên bảng dữ liệu. Khi kẻ tấn công chèn lệnh `DROP TABLE` hoặc `CREATE TABLE`, PostgreSQL lập tức từ chối `permission denied`.
4. **Hạn chế đặc quyền Linux & Giới hạn tài nguyên (Capabilities & Resource Limits)**:
   - Áp dụng `security_opt: [no-new-privileges:true]` và `cap_drop: [ALL]` trên các dịch vụ.
   - Giới hạn cứng RAM (`mem_limit`) và CPU (`cpus`) cho từng container để phòng chống tấn công DoS/kiệt quệ tài nguyên máy chủ.
5. **Bảo mật Nginx & Ứng dụng Web**:
   - Ẩn thông tin phiên bản qua `server_tokens off;` (Nginx) và `app.disable("x-powered-by")` (Express).
   - Session cookie cấu hình an toàn tuyệt đối: `HttpOnly; Secure; SameSite=Strict`.
   - Thiết lập đầy đủ các HTTP Security Headers: HSTS (1 năm), CSP, X-Frame-Options (SAMEORIGIN), X-Content-Type-Options (nosniff), Referrer-Policy, Permissions-Policy.
   - Chặn tuyệt đối endpoint nhạy cảm `/nginx_status` trên cổng 443 HTTPS.
6. **Bảo vệ cổng qua Tường lửa Windows Defender Firewall**:
   - Trên môi trường Docker Desktop / WSL2, port forwarding được ánh xạ qua tiến trình Windows (`com.docker.backend.exe`, `wslrelay.exe`). Do đó UFW bên trong WSL2 không có tác dụng bảo vệ cổng máy host.
   - Quy tắc tường lửa Windows host để chỉ cho phép máy trạm quản trị kết nối vào cổng 80/443:
     ```powershell
     # Chạy trên Windows PowerShell với quyền Administrator:
     New-NetFirewallRule -DisplayName "AssetApp_Allow_Admin_HTTPS" -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow -RemoteAddress "192.168.1.10"
     New-NetFirewallRule -DisplayName "AssetApp_Block_Others_HTTPS" -Direction Inbound -LocalPort 443 -Protocol TCP -Action Block
     ```
7. **Quét lỗ hổng an ninh bằng Trivy**:
   - Tự động quét mã nguồn và toàn bộ 8 Docker images thông qua script: `bash scripts/run_trivy_scan.sh`
   - Báo cáo kết quả quét chi tiết lưu tại: `evidence/buoc6-trivy.txt`.