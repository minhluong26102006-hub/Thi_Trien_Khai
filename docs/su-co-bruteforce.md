# BÁO CÁO SỰ CỐ AN TOÀN THÔNG TIN & TRUY VẾT LOG TẬP TRUNG
**Học phần:** Triển khai và Quản trị Hệ thống Phần mềm  
**Học viên thực hiện:** Nguyễn Minh Lượng  
**Mã số sinh viên (MSSV):** DTC245180061  
**Ngày thực hiện:** 23/10/2026  
**Mức độ nghiêm trọng của sự cố:** High / Critical (Cố gắng xâm nhập trái phép)

---

## 1. Tóm tắt sự cố (Incident Overview)

| Thuộc tính | Chi tiết |
| :--- | :--- |
| **Loại sự cố** | Tấn công dò quét mật khẩu (Brute Force Authentication Attack) |
| **Hệ thống bị nhắm đến** | Cổng xác thực ứng dụng Quản lý Tài sản Thiết bị (`https://localhost/auth/login`) |
| **Tài khoản mục tiêu** | `admin` (Quản trị viên hệ thống) |
| **Địa chỉ IP nguồn** | `172.18.0.1` (Cổng kết nối nội bộ / Host Gateway) |
| **Thời điểm phát hiện** | 2026-10-23 23:46:33 (Đợt 1) và 23:59:05 (Đợt 2) |
| **Số lần vi phạm ghi nhận** | 41+ lần gửi yêu cầu đăng nhập sai liên tiếp trong thời gian ngắn (< 15 giây) |
| **Tác động hệ thống** | Làm gia tăng tải xử lý truy vấn xác thực bcrypt và PostgreSQL; nguy cơ lộ lọt mật khẩu tài khoản quản trị nếu mật khẩu yếu. |

---

## 2. Cơ chế giám sát & Phát hiện tự động (Detection)

Hệ thống sử dụng hạ tầng giám sát log tập trung gồm **Promtail -> Loki -> Grafana Alerting -> Alert Sink Webhook**:

```
+----------------+      +----------+      +------+      +------------------+      +-------------------+
| Container Logs | ---> | Promtail | ---> | Loki | ---> | Grafana Alerting | ---> | Alert-Sink (9099) |
| (web / nginx)  |      |  3.0.0   |      | 3.0  |      | (Rule Evaluator) |      | (Webhook Receiver)|
+----------------+      +----------+      +------+      +------------------+      +-------------------+
```

### Cấu hình Alert Rule trong Grafana (`grafana/provisioning/alerting/alerting.yaml`):
* **Tên luật cảnh báo:** `Asset - Brute force login`
* **Thư mục lưu trữ:** `Asset Monitoring`
* **Mức độ (Severity):** `critical`
* **Chu kỳ đánh giá (Evaluation interval):** `10s` (Đánh giá mỗi 10 giây, phản ứng tức thì sau 0 giây `for: 0s`).
* **Truy vấn LogQL cơ sở (Query A):**
  ```logql
  sum(count_over_time({job="webapp"} |= "LOGIN_FAILED" [1m]))
  ```
* **Bộ xử lý giảm chiều (Reduce Expression B):** `reducer: last` (Lấy giá trị gần nhất của chuỗi thời gian).
* **Ngưỡng kích hoạt (Threshold Expression C):** `is above 5` (Kích hoạt khi số lần đăng nhập thất bại > 5 lần/phút).
* **Contact Point (Kênh nhận cảnh báo):** Webhook `http://alert-sink:9099/webhook`.

### Kết quả kích hoạt cảnh báo:
Khi kẻ tấn công gửi từ 6 yêu cầu thất bại trở lên, Grafana Alert rule lập tức chuyển trạng thái sang **FIRING**. Alertmanager gửi HTTP POST Webhook chứa chi tiết sự cố sang `alert-sink`:
```json
{
  "status": "firing",
  "labels": {
    "alertname": "Asset - Brute force login",
    "grafana_folder": "Asset Monitoring",
    "severity": "critical"
  },
  "annotations": {
    "summary": "Phat hien tan cong do mat khau (Brute Force) vao trang dang nhap!",
    "description": "So lan dang nhap that bai (LOGIN_FAILED) vuot qua 5 lan trong 1 phut. Kiem tra ngay log truy vet qua LogQL va IP nguon!"
  },
  "values": { "B": 12, "C": 1 }
}
```

---

## 3. Điều tra & Truy vết sự cố bằng LogQL (Investigation & Forensics)

Đội ngũ quản trị an toàn thông tin sử dụng công cụ **Grafana Explore** kết hợp nguồn dữ liệu **Loki** để thực hiện truy vết chi tiết hành vi kẻ tấn công qua các câu truy vấn LogQL:

### Câu lệnh 1: Truy vết nhật ký các lần đăng nhập thất bại
```logql
{job="webapp"} |= "LOGIN_FAILED"
```
* **Kết quả phân tích:**
  ```text
  LOGIN_FAILED ip=172.18.0.1 user=admin reason=wrong_password
  LOGIN_FAILED ip=172.18.0.1 user=admin reason=wrong_password
  ...
  ```
* **Nhận định:** Kẻ tấn công liên tục thử mật khẩu sai đối với tài khoản `admin` từ địa chỉ IP `172.18.0.1`.

### Câu lệnh 2: Thống kê số lần đăng nhập thất bại theo thời gian (1 phút)
```logql
sum(count_over_time({job="webapp"} |= "LOGIN_FAILED" [1m]))
```
* **Kết quả:** Đạt đỉnh **12 - 20 lần/phút**, vượt xa ngưỡng bình thường của người dùng cuối.

### Câu lệnh 3: Đối chiếu với nhật ký truy cập Nginx Reverse Proxy
```logql
{job="nginx"} |= "172.18.0.1" |= "/auth/login"
```
* **Kết quả:**
  ```text
  172.18.0.1 - - [23/Oct/2026:16:46:45 +0000] "POST /auth/login HTTP/2.0" 401 3068 "-" "curl/7.81.0" "-" rt=0.081
  172.18.0.1 - - [23/Oct/2026:16:46:44 +0000] "POST /auth/login HTTP/2.0" 401 3068 "-" "curl/7.81.0" "-" rt=0.075
  ```
* **Nhận định:** Kẻ tấn công sử dụng công cụ tự động hóa (`User-Agent: curl/7.81.0`) gửi liên tiếp các yêu cầu POST tới endpoint `/auth/login` với tần suất trung bình ~0.5 giây/lần.

---

## 4. Biện pháp Khắc phục & Giảm thiểu (Mitigation & Hardening)

Để bảo vệ hệ thống khỏi cạn kiệt tài nguyên (CPU do mã hóa bcrypt và pool kết nối CSDL), giải pháp tối ưu nhất là ngăn chặn kẻ tấn công ngay tại tầng **Reverse Proxy (Nginx)** trước khi yêu cầu đi vào Node.js.

### Cấu hình Rate Limiting trên Nginx (`nginx/nginx.conf`):
1. **Chỉ giới hạn tần suất cho phương thức POST (tránh ảnh hưởng người dùng xem giao diện GET):**
   ```nginx
   # Phân loại phương thức yêu cầu: chỉ lấy binary IP khi là POST
   map $request_method $limit_login_key {
       POST $binary_remote_addr;
       default "";
   }

   # Vùng nhớ lưu trữ trạng thái rate limit: dung lượng 10MB, tốc độ tối đa 5 yêu cầu/phút
   limit_req_zone $limit_login_key zone=login_limit:10m rate=5r/m;
   limit_req_status 429;
   ```

2. **Áp dụng chính sách cho endpoint xác thực `/auth/login`:**
   ```nginx
   location = /auth/login {
       limit_req zone=login_limit burst=5 nodelay;
       limit_req_status 429;

       proxy_pass http://web:3000;
       proxy_set_header Host $host;
       proxy_set_header X-Real-IP $remote_addr;
       proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
       proxy_set_header X-Forwarded-Proto $scheme;
       proxy_http_version 1.1;
   }
   ```

### Kiểm thử và Đánh giá hiệu quả sau khắc phục:
* **Khi kẻ tấn công tiếp tục gửi 20 yêu cầu sai liên tiếp:**
  - 5 yêu cầu đầu tiên nằm trong giới hạn burst được xử lý và trả về `HTTP 401`.
  - Từ yêu cầu thứ 6 trở đi, Nginx lập tức từ chối với mã phản hồi **`HTTP 429 Too Many Requests`**.
  - **Node.js và CSDL PostgreSQL hoàn toàn không phải tiếp nhận các yêu cầu vi phạm này.**
* **Kiểm tra nhật ký Nginx qua LogQL:**
  ```logql
  sum(count_over_time({job="nginx"} |= " 429 " [10m]))
  ```
  Số lượng mã phản hồi `HTTP 429` tăng vọt lên **110+**, chứng minh cơ chế bảo vệ biên đang phát huy hiệu quả triệt để.
* **Kiểm tra tính khả dụng đối với người dùng hợp lệ:**
  - Người dùng truy cập xem form đăng nhập (GET `/auth/login`) luôn nhận mã `HTTP 200` bình thường.
  - Sau thời gian hồi phục của thuật toán Leaky Bucket (~12 giây), người dùng chính danh (`thukho01`) thực hiện đăng nhập thành công với mã `HTTP 200` và chuyển hướng tới `/assets`.

---

## 5. Bài học kinh nghiệm & Khuyến nghị mở rộng (Lessons Learned)

1. **Ngăn chặn nhiều lớp (Defense in Depth):**
   - Tầng biên (Nginx Reverse Proxy): Sử dụng Rate Limiting để ngăn chặn DoS/Brute force ở mức mạng/HTTP.
   - Tầng ứng dụng (Node.js Express): Cần bổ sung cơ chế khóa tài khoản tạm thời (ví dụ khóa 15 phút nếu nhập sai quá 5 lần) kết hợp mã CAPTCHA (như Cloudflare Turnstile hoặc Google reCAPTCHA) khi phát hiện đăng nhập sai 3 lần liên tiếp.
2. **Triển khai Fail2ban hoặc CrowdSec:**
   - Đọc trực tiếp log HTTP 429 từ Nginx để tự động tạo quy tắc tường lửa (`iptables`/`nftables`), chặn IP vi phạm trong thời gian dài (ví dụ: 1 giờ hoặc 24 giờ).
3. **Chính sách mật khẩu & Xác thực đa yếu tố (MFA):**
   - Bắt buộc chính sách mật khẩu mạnh (tối thiểu 12 ký tự gồm chữ hoa, chữ thường, số, ký tự đặc biệt).
   - Áp dụng xác thực 2 bước (2FA/TOTP) đối với các nhóm tài khoản quản trị viên (`admin`, `thukho01`, `kythuat01`).
4. **Giám sát thời gian thực:**
   - Hệ thống log tập trung Promtail + Loki chứng minh khả năng phản ứng và điều tra sự cố trong vòng dưới 30 giây kể từ khi xảy ra hành vi bất thường.

---
*Tài liệu thuộc hồ sơ kỹ thuật đồ án môn học - DTC245180061.*
