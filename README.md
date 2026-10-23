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
