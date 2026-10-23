# TÀI LIỆU TỔNG HỢP PHỤC VỤ VIẾT BÁO CÁO HỌC PHẦN
**Học phần**: Triển khai và Quản trị Hệ thống Phần mềm  
**Đề tài**: Triển khai Hệ thống Quản lý Tài sản / Thiết bị bằng Docker Compose  
**Sinh viên thực hiện**: Nguyễn Minh Lượng  
**Mã số sinh viên (MSSV)**: DTC245180061  
**Repository**: [`minhluong26102006-hub/Thi_Trien_Khai`](https://github.com/minhluong26102006-hub/Thi_Trien_Khai)  
**Ngày hoàn thiện**: 24/10/2026  

---

## BẢNG 1: THÀNH PHẦN HỆ THỐNG VÀ PHIÊN BẢN THỰC TẾ

| Thành phần Dịch vụ | Container Name | Image & Tag Cố định | Cổng Nội bộ | Cổng Host | Vai trò kiến trúc |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Reverse Proxy** | `asset-nginx` | `nginx:1.27.0-alpine` | 80, 443 | **80, 443** | Điểm tiếp nhận duy nhất, SSL Termination, Security Headers, Rate Limiting |
| **Ứng dụng Web** | `asset-web` | Tự build (`node:20.18.0-alpine`) | 3000 | Không publish | Web MVC Node.js Express, EJS, QR Code, Uploads ảnh dưới user `node:1000` |
| **Cơ sở dữ liệu** | `asset-db` | `postgres:16.3-alpine` | 5432 | Không publish | CSDL quan hệ PostgreSQL 16, cô lập trong mạng `backend: internal` |
| **Quản trị CSDL** | `asset-pgadmin` | `dpage/pgadmin4:8.7` | 80 | Không publish | Giao diện Web GUI quản trị CSDL qua subpath `/pgadmin/` |
| **Máy chủ Giám sát** | `asset-prometheus` | `prom/prometheus:v2.53.0` | 9090 | Không publish | Thu thập & lưu trữ Time-Series Metrics, retention 7 ngày, user `nobody:65534` |
| **Trực quan hóa** | `asset-grafana` | `grafana/grafana:11.0.0` | 3000 | Không publish | Dashboard giám sát CPU/RAM/DB/Log, Alerting Rules, subpath `/grafana/` |
| **Thu thập Log** | `asset-loki` | `grafana/loki:3.0.0` | 3100 | Không publish | Máy chủ lưu trữ và truy vấn LogQL tập trung, user `10001:10001` |
| **Log Shipper** | `asset-promtail` | `grafana/promtail:3.0.0` | - | Không publish | Đọc log container qua socket `/var/run/docker.sock` và chuyển tiếp về Loki |
| **Container Metrics** | `asset-cadvisor` | `gcr.io/cadvisor/cadvisor:v0.49.1` | 8080 | Không publish | Thu thập thông số phần cứng CPU, RAM, Network I/O của 12 containers |
| **Nginx Exporter** | `asset-nginx-exporter` | `nginx/nginx-prometheus-exporter:1.2.0` | 9113 | Không publish | Cào thông số kết nối Nginx từ stub_status cổng 80 nội bộ |
| **Postgres Exporter**| `asset-postgres-exporter`| `prometheuscommunity/postgres-exporter:v0.15.0` | 9187 | Không publish | Cào thông số hiệu năng PostgreSQL (Transactions, Cache Hit, Connections) |
| **Tiếp nhận Cảnh báo**| `asset-alert-sink` | Tự build (`python:3.12-alpine`) | 9099 | Không publish | Webhook endpoint tiếp nhận cảnh báo an toàn thông tin từ Grafana |

---

## BẢNG 2: THỐNG KÊ SỐ LIỆU THỰC TẾ CỦA DỰ ÁN

| Chỉ số kỹ thuật | Giá trị thực tế | Nguồn kiểm chứng |
| :--- | :--- | :--- |
| **Tổng số commit Git** | Đúng **3 commit** | `git log --oneline` |
| - Commit 1 (`b54d1c4`) | 57 tệp thay đổi, +7214 dòng | Web app, DB, pgAdmin, Nginx HTTPS |
| - Commit 2 (`c1616ee`) | 12 tệp thay đổi, +790 dòng | Prometheus, Grafana, cAdvisor, 2 Exporters |
| - Commit 3 (`5ec3d9f`) | 21 tệp thay đổi, +1370 dòng | Loki, Promtail, Alert-sink, Hardening, Trivy |
| **Tổng số container Docker** | **12 container** (100% Up/Healthy) | `docker compose ps` |
| **Phân vùng mạng cô lập** | **3 mạng Bridge**: `frontend`, `backend` (`internal: true`), `monitoring` | `docker network ls` |
| **Số lượng Volume có tên** | **6 volumes**: `db_data`, `web_uploads`, `pgadmin_data`, `prometheus_data`, `grafana_data`, `loki_data` | `docker volume ls` |
| **Số cổng công bố ra máy Host** | Duy nhất **2 cổng**: `80` (HTTP redirect) và `443` (HTTPS) | `Get-NetTCPConnection` trên Windows |
| **Bảng dữ liệu CSDL** | **7 bảng**: `users`, `categories`, `locations`, `assets`, `loans`, `loan_items`, `maintenance_logs` | Schema `public` trong PostgreSQL |
| **Số Scrape Targets Prometheus**| **4 targets** (`cadvisor`, `nginx`, `postgres`, `prometheus`) - 100% UP | Prometheus API `/api/v1/targets` |
| **Dashboards Grafana Tự động** | **4 dashboards**: `Containers`, `Nginx`, `PostgreSQL`, `Logs - Asset & Security` | Grafana API `/api/search` |
| **File Bằng chứng Kiểm chứng** | **9 tệp text** trong thư mục `evidence/` | `ls evidence/` |

---

## CHƯƠNG 1: TỔNG QUAN VÀ THIẾT KẾ KIẾN TRÚC HỆ THỐNG

### (a) Đoạn văn phong báo cáo
> "Nhằm giải quyết bài toán quản lý tài sản, thiết bị công nghệ thông tin tại các cơ quan, đơn vị đào tạo một cách khoa học, an toàn và tối ưu tài nguyên, hệ thống được thiết kế theo kiến trúc vi dịch vụ (Microservices-ready) triển khai trên nền tảng Docker Compose. Toàn bộ giải pháp được phân chia thành 3 phân vùng mạng độc lập tuân thủ nghiêm ngặt mô hình phòng thủ theo chiều sâu (Defense-in-Depth): Phân vùng Frontend (tiếp nhận lưu lượng người dùng qua Nginx Reverse Proxy), Phân vùng Backend (chứa ứng dụng nghiệp vụ Node.js Express và CSDL PostgreSQL 16 được cấu hình `internal: true` triệt tiêu hoàn toàn nguy cơ truy cập trái phép từ Internet), và Phân vùng Monitoring (chuyên biệt cho hệ sinh thái giám sát Prometheus, Grafana, Loki, Promtail và cAdvisor). Kiến trúc loại bỏ việc công bố trực tiếp cổng của các dịch vụ nội bộ (CSDL 5432, pgAdmin 5050, Web 3000, Prometheus 9090, Loki 3100), toàn bộ truy cập đều được dẫn truyền qua Nginx với mã hóa TLS 1.2/1.3 và cơ chế chuyển hướng HTTP sang HTTPS bắt buộc."

### (b) File cấu hình đáng đưa vào báo cáo
- `docker-compose.yml` (khối định nghĩa 3 phân vùng mạng `networks` và ánh xạ cổng `ports`).
- `nginx/nginx.conf` (khối định nghĩa `upstream` và chuyển hướng SSL).

### (c) Tên file evidence tương ứng
- `evidence/buoc0-moitruong.txt` (Thông tin môi trường Windows 11, WSL2, Docker version).
- `evidence/buoc3-nginx.txt` (Kiểm tra cổng công bố và phân vùng mạng).

### (d) Danh sách ảnh cần chụp & Lệnh thực hiện
1. **Ảnh Kiến trúc Docker Compose**:
   - *Lệnh*: `docker compose ps`
   - *Mô tả*: Ảnh chụp cửa sổ terminal thể hiện danh sách đầy đủ 12 container đang ở trạng thái `running / healthy`.
2. **Ảnh Kiểm tra Cổng Mở trên Host Windows**:
   - *Lệnh*: `Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -in 80, 443, 3000, 5050, 5432, 9090, 3100 }`
   - *Mô tả*: Ảnh PowerShell chứng minh máy chủ Windows chỉ mở duy nhất cổng 80 và 443, các cổng nội bộ hoàn toàn được bảo vệ.

---

## CHƯƠNG 2: TRIỂN KHAI ỨNG DỤNG WEB QUẢN LÝ TÀI SẢN (NODE.JS + POSTGRESQL + PGADMIN)

### (a) Đoạn văn phong báo cáo
> "Ứng dụng nghiệp vụ Quản lý Tài sản Thiết bị được xây dựng trên nền tảng Node.js Express theo mô hình MVC, sử dụng PostgreSQL 16 làm hệ quản trị cơ sở dữ liệu và pgAdmin 4 cho công tác quản trị dữ liệu trực quan. Cơ sở dữ liệu được thiết kế chuẩn hóa gồm 7 bảng quan hệ có ràng buộc toàn vẹn khóa ngoại (Foreign Keys), chỉ mục (Indexes) và ràng buộc kiểm tra (Check Constraints). Hệ thống hỗ trợ đầy đủ các quy trình nghiệp vụ: Quản lý vòng đời tài sản (nhập mới, khấu hao, upload hình ảnh thực tế, xuất nhãn QR Code Base64), Phân quyền 3 vai trò người dùng (Admin, Thủ kho, Nhân viên), Toàn trình mượn trả thiết bị (Tạo phiếu -> Duyệt -> Bàn giao -> Nhận trả kèm biên bản hiện trạng) với cơ chế kiểm soát nghiêm ngặt (mỗi nhân viên tối đa 3 phiếu mở, thời hạn mượn tối đa 30 ngày, tối đa 5 thiết bị/phiếu), và Quản lý bảo trì sửa chữa. Trình quản trị pgAdmin 4 được cấu hình chạy an toàn dưới subpath `/pgadmin/` thông qua Nginx Reverse Proxy."

### (b) File cấu hình đáng đưa vào báo cáo
- `db/init.sql` (Schema 7 bảng, Trigger cập nhật thời gian, Ràng buộc kiểm tra, Dữ liệu mẫu ban đầu).
- `web/Dockerfile` (Multi-stage build tối ưu, `USER node` non-root, xử lý thư mục upload).
- `web/src/controllers/loanController.js` (Hàm kiểm soát nghiệp vụ mượn trả toàn trình và ràng buộc logic).

### (c) Tên file evidence tương ứng
- `evidence/buoc12-web-db.txt` (Kiểm thử đăng nhập 3 vai trò, tạo phiếu mượn, duyệt, bàn giao, nhận trả, upload ảnh, tạo mã QR).

### (d) Danh sách ảnh cần chụp & Lệnh thực hiện
1. **Ảnh Giao diện Danh sách Tài sản & Thống kê**:
   - *URL*: `https://localhost/assets`
   - *Mô tả*: Giao diện web hiển thị danh sách thiết bị kèm hình ảnh đại diện, tình trạng hoạt động và bộ lọc tìm kiếm.
2. **Ảnh Nhãn in Mã QR Code Động**:
   - *URL*: `https://localhost/assets/1/label`
   - *Mô tả*: Trang in tem nhãn tài sản chứa mã QR Base64, mã thiết bị và thông tin kỹ thuật phục vụ kiểm kê.
3. **Ảnh Quản trị pgAdmin qua Nginx Subpath**:
   - *URL*: `https://localhost/pgadmin/`
   - *Mô tả*: Giao diện pgAdmin kết nối thành công tới CSDL `assetdb`, duyệt cấu trúc 7 bảng trong schema `public`.

---

## CHƯƠNG 3: CẤU HÌNH NGINX REVERSE PROXY, HTTPS TỰ KÝ & SECURITY HEADERS

### (a) Đoạn văn phong báo cáo
> "Để đảm bảo an toàn thông tin trên đường truyền và che giấu cấu trúc mạng nội bộ, máy chủ Nginx 1.27 Alpine được cấu hình đóng vai trò Reverse Proxy và SSL Termination. Script tự động hóa `nginx/gen-cert.sh` sử dụng OpenSSL để sinh cặp chứng chỉ RSA 2048-bit có trường SAN (Subject Alternative Name) bao gồm cả `DNS:localhost`, `IP:127.0.0.1` và địa chỉ IP LAN máy trạm, đảm bảo khả năng truy cập an toàn trong mạng nội bộ. Nginx chỉ chấp nhận các giao thức mã hóa hiện đại TLS 1.2 và TLS 1.3 với danh sách Cipher Suite mạnh, tự động chuyển hướng 301 toàn bộ lưu lượng HTTP cổng 80 sang HTTPS cổng 443. Đồng thời, Nginx được thiết lập các HTTP Security Headers nghiêm ngặt gồm: HSTS (thời hạn 1 năm), X-Frame-Options (SAMEORIGIN chống Clickjacking), X-Content-Type-Options (nosniff chống MIME-sniffing), Content-Security-Policy (CSP), Referrer-Policy và Permissions-Policy. Endpoint nội bộ `/nginx_status` bị chặn hoàn toàn từ ngoài qua HTTPS (trả về HTTP 404)."

### (b) File cấu hình đáng đưa vào báo cáo
- `nginx/gen-cert.sh` (Script sinh khóa bí mật và chứng chỉ số SAN X.509).
- `nginx/nginx.conf` (Cấu hình SSL Protocols, Ciphers, Security Headers với chỉ thị `always`, Reverse Proxy locations).

### (c) Tên file evidence tương ứng
- `evidence/buoc3-nginx.txt` (Kết quả kiểm thử SSL Handshake, Redirect 301, Security Headers và chặn stub_status).

### (d) Danh sách ảnh cần chụp & Lệnh thực hiện
1. **Ảnh Kiểm tra SSL Handshake & TLS Version**:
   - *Lệnh*: `openssl s_client -connect localhost:443 -tls1_3`
   - *Mô tả*: Kết quả handshake thành công với TLSv1.3, hiển thị Certificate Subject chứa MSSV `DTC245180061`.
2. **Ảnh HTTP Security Headers trên DevTools Trình duyệt**:
   - *Thao tác*: Bấm `F12` trên Chrome/Edge tại `https://localhost/`, xem tab **Network** -> **Headers**.
   - *Mô tả*: Thể hiện đầy đủ các headers: `Strict-Transport-Security`, `X-Frame-Options`, `X-Content-Type-Options`, `Content-Security-Policy`.

---

## CHƯƠNG 4: HỆ THỐNG GIÁM SÁT HIỆU NĂNG VỚI PROMETHEUS, GRAFANA & EXPORTERS

### (a) Đoạn văn phong báo cáo
> "Hệ thống tích hợp giải pháp giám sát hiệu năng tập trung theo thời gian thực chuẩn công nghiệp dựa trên bộ công cụ Prometheus và Grafana. Nằm trọn vẹn trong phân vùng mạng `monitoring`, máy chủ Prometheus định kỳ thu thập (scrape) dữ liệu số liệu từ 4 mục tiêu: cAdvisor (thu thập thông số tài nguyên CPU, RAM, Network I/O của 12 container Docker), Nginx Prometheus Exporter (thu thập lưu lượng yêu cầu, kết nối active), PostgreSQL Exporter (thu thập tần suất giao dịch commits/rollbacks, tỷ lệ trúng cache, số lượng client kết nối vào CSDL `assetdb` qua tài khoản có role `pg_monitor`), và chính tiến trình Prometheus. Grafana được tích hợp reverse proxy qua subpath `/grafana/` với cơ chế WebSocket Upgrade, tự động cấu hình (Provisioning) sẵn nguồn dữ liệu và 3 Dashboard trực quan hóa chuyên sâu: `Asset - Containers`, `Asset - Nginx` và `Asset - PostgreSQL`, cung cấp cái nhìn toàn diện về sức khỏe hạ tầng."

### (b) File cấu hình đáng đưa vào báo cáo
- `prometheus/prometheus.yml` (Định nghĩa 4 scrape jobs: `cadvisor`, `nginx`, `postgres`, `prometheus`).
- `grafana/provisioning/datasources/prometheus.yaml` (Cấu hình nạp tự động Prometheus datasource).
- `grafana/provisioning/dashboards/dashboards.yaml` (Cấu hình nạp tự động thư mục dashboards).

### (c) Tên file evidence tương ứng
- `evidence/buoc4-giamsat.txt` (Trạng thái UP của 4 Scrape Targets, xác minh dữ liệu biểu đồ CPU, RAM, Cache Hit Ratio).

### (d) Danh sách ảnh cần chụp & Lệnh thực hiện
1. **Ảnh Trang Scrape Targets của Prometheus**:
   - *Lệnh tạm mở cổng*: Tạo `docker-compose.override.yml` publish cổng 9090 tạm thời, mở `http://localhost:9090/targets`.
   - *Mô tả*: Cả 4 scrape pools đều hiển thị trạng thái `UP (1/1 up)` màu xanh lá cây.
2. **Ảnh Dashboard Giám sát Tài nguyên Container (Asset - Containers)**:
   - *URL*: `https://localhost/grafana/d/asset-containers/`
   - *Mô tả*: Biểu đồ trực quan hóa % CPU tiêu thụ và dung lượng bộ nhớ RAM của 12 container theo thời gian.
3. **Ảnh Dashboard Giám sát Hiệu năng CSDL (Asset - PostgreSQL)**:
   - *URL*: `https://localhost/grafana/d/asset-postgres/`
   - *Mô tả*: Biểu đồ Tỷ lệ Cache Hit Ratio (> 99%), số Client Connections, thông lượng Commits/sec.

---

## CHƯƠNG 5: LOG TẬP TRUNG LOKI/PROMTAIL, SỰ CỐ AN TOÀN THÔNG TIN & HARDENING BẢO MẬT

### (a) Đoạn văn phong báo cáo
> "Nhằm đáp ứng yêu cầu kiểm toán và phát hiện bất thường, hệ thống triển khai hạ tầng log tập trung dựa trên Grafana Loki và Promtail. Promtail đọc log các container thông qua Docker socket, trích xuất metadata và đẩy về Loki phục vụ phân tích qua ngôn ngữ LogQL. Trên nền tảng này, một kịch bản tấn công An toàn thông tin mô phỏng (Dò quét mật khẩu Brute Force vào trang đăng nhập) đã được thực nghiệm và thiết lập quy trình ứng phó 3 tầng: Tầng 1 (Nginx Rate Limiting chặn dồn dập với HTTP 429), Tầng 2 (Loki phát hiện đột biến số lần đăng nhập sai và kích hoạt luật cảnh báo `HighFailedLoginRate` trên Grafana Alerting), Tầng 3 (Grafana gửi webhook tới dịch vụ `alert-sink` ghi nhận log cảnh báo an ninh). Song song đó, toàn bộ 10 biện pháp Hardening bảo mật chuyên sâu đã được thực thi thành công: Chạy container dưới người dùng không đặc quyền (Non-root `node:1000`, `nobody:65534`, `appuser:10001`), Áp dụng nguyên tắc đặc quyền tối thiểu (Least Privilege) trên PostgreSQL (user app bị thu hồi quyền `CREATE` trên schema public, không thể `DROP TABLE`), Bật `no-new-privileges:true` và `cap_drop: [ALL]`, Giới hạn trần RAM và CPU cho từng dịch vụ, Ẩn phiên bản phần mềm (`server_tokens off`, bỏ `x-powered-by`), Session Cookie an toàn (`HttpOnly; Secure; SameSite=Strict`), và Hướng dẫn thiết lập tường lửa Windows Defender Firewall."

### (b) File cấu hình đáng đưa vào báo cáo
- `loki/loki-config.yaml` và `promtail/promtail-config.yaml` (Cấu hình thu thập log tập trung).
- `grafana/provisioning/alerting/alerting.yaml` (Định nghĩa luật cảnh báo `HighFailedLoginRate` và Contact Point Webhook).
- `alert-sink/server.py` (Mã nguồn Webhook tiếp nhận cảnh báo an ninh).
- `docs/su-co-bruteforce.md` (Báo cáo chi tiết sự cố an toàn thông tin và truy vết LogQL).

### (c) Tên file evidence tương ứng
- `evidence/buoc5-logql.txt` (Kết quả truy vấn LogQL Nginx lỗi, Đăng nhập sai, CSDL chậm).
- `evidence/buoc5-sucodo.txt` (Bằng chứng mô phỏng Brute Force, Nginx 429, Alerting Firing và Alert-Sink log).
- `evidence/buoc6-hardening.txt` (Bằng chứng UID Non-root, CSDL từ chối DROP TABLE, Security Headers, Tài nguyên).

### (d) Danh sách ảnh cần chụp & Lệnh thực hiện
1. **Ảnh Truy vấn LogQL trên Grafana Explore**:
   - *URL*: `https://localhost/grafana/explore`
   - *Truy vấn*: `{job="docker", container=~".*web.*"} |= "Đăng nhập thất bại"`
   - *Mô tả*: Biểu đồ phân bố log thất bại màu đỏ và các dòng nhật ký truy vết chi tiết.
2. **Ảnh Cảnh báo Firing trên Grafana Alerting**:
   - *URL*: `https://localhost/grafana/alerting/list`
   - *Mô tả*: Quy tắc cảnh báo `HighFailedLoginRate` hiển thị trạng thái `Firing` màu đỏ sau đợt tấn công mô phỏng.
3. **Ảnh Kiểm chứng CSDL Từ chối DROP TABLE**:
   - *Lệnh*: `docker exec -it asset-db psql -U asset_app -d assetdb -c "DROP TABLE assets;"`
   - *Mô tả*: Terminal in lỗi `ERROR: must be owner of table assets`, chứng minh user app không có quyền phá hoại CSDL.

---

## CHƯƠNG 6: KIỂM THỬ HỆ THỐNG TỪ TRẠNG THÁI SẠCH & ĐÁNH GIÁ AN NINH VỚI TRIVY

### (a) Đoạn văn phong báo cáo
> "Nhằm chứng minh tính ổn định, độc lập và khả năng tái lập (Reproducibility) của giải pháp 'triển khai bằng một lệnh', một quy trình kiểm thử toàn diện từ trạng thái sạch (Clean-state Smoke Test) đã được thực hiện trong môi trường độc lập `~/asset-verify`. Quá trình kiểm thử tự động hóa 100% các kịch bản: sinh chứng chỉ mới, khởi chạy 12 dịch vụ, xác thực 3 vai trò người dùng, thêm tài sản kèm upload ảnh thực tế dưới user non-root `node`, chu trình mượn trả toàn trình qua CSDL, tạo phiếu bảo trì, truy cập pgAdmin, kiểm tra sức khỏe Grafana/Loki/Prometheus và kích hoạt kịch bản rate limit brute force. Kết quả đạt 100% tỷ lệ thành công (PASS). Đồng thời, công cụ phân tích tĩnh an ninh mã nguồn và container image Trivy đã được ứng dụng để quét toàn diện mã nguồn và 8 images. Các phát hiện an ninh đều được đánh giá rủi ro, phân loại và giải trình lý do chấp nhận rủi ro đối với các thư viện upstream của hệ điều hành nền tảng."

### (b) File cấu hình đáng đưa vào báo cáo
- `scripts/run_trivy_scan.sh` (Script tự động hóa quét an ninh bằng Trivy).
- `scripts/test_step6_hardening.sh` (Bộ kiểm thử tự động 8 tiêu chí hardening và 9 smoke tests).

### (c) Tên file evidence tương ứng
- `evidence/buoc6-trivy.txt` (Báo cáo quét lỗ hổng Trivy của 8 container images và mã nguồn web).
- `evidence/final-smoke-test.txt` (Biên bản kiểm thử từ trạng thái sạch hoàn chỉnh với kết luận PASS 100%).

### (d) Danh sách ảnh cần chụp & Lệnh thực hiện
1. **Ảnh Lịch sử Git Đạt Chuẩn 3 Commit**:
   - *Lệnh*: `git log --oneline --graph`
   - *Mô tả*: Cửa sổ terminal hiển thị đúng 3 commit duy nhất với thông điệp chuẩn xác của sinh viên `Nguyễn Minh Lượng`.
2. **Ảnh Báo cáo Quét Lỗ hổng An ninh Trivy**:
   - *Lệnh*: `bash scripts/run_trivy_scan.sh`
   - *Mô tả*: Bảng tóm tắt kết quả quét an ninh container images với phân loại CRITICAL, HIGH, MEDIUM, LOW.

---

## KẾT LUẬN & HƯỚNG PHÁT TRIỂN

### 1. Kết quả Đạt được
- Triển khai thành công hệ thống Quản lý Tài sản / Thiết bị hoàn chỉnh bằng Docker Compose trên nền tảng Windows 11 WSL2.
- 100% dịch vụ được container hóa, phân vùng mạng 3 tầng cô lập triệt để và bảo mật đường truyền qua HTTPS tự ký.
- Tích hợp thành công giải pháp giám sát tập trung toàn diện (Prometheus + Grafana) và quản lý log thời gian thực (Loki + Promtail).
- Thực nghiệm thành công kịch bản an toàn thông tin (chống Brute Force) với cơ chế phòng thủ đa tầng và tự động kích hoạt cảnh báo tới Webhook.
- Áp dụng đầy đủ và kiểm chứng hiệu lực của 10 biện pháp Hardening bảo mật và kiểm thử tái lập thành công từ trạng thái sạch.

### 2. Hướng Phát triển Tiếp theo
- Tích hợp giải pháp quản lý bí mật tập trung (HashiCorp Vault) thay thế việc lưu trữ thông tin nhạy cảm trong file `.env`.
- Triển khai cụm Kubernetes (K8s / K3s) để hỗ trợ khả năng tự động co giãn (Horizontal Pod Autoscaling) và cân bằng tải đa máy chủ (High Availability).
- Bổ sung chữ ký số cho chứng chỉ SSL thông qua Let's Encrypt kết hợp DNS Challenge khi triển khai trên tên miền Internet thực tế.