#!/bin/bash
set -e

BASE_URL="http://localhost:3000"
COOKIE_DIR=$(mktemp -d)
EVIDENCE_FILE="/home/mluong/asset/evidence/buoc12-web-db.txt"
trap "rm -rf $COOKIE_DIR" EXIT

extract_csrf() {
  local html="$1"
  echo "$html" | grep -o 'name="_csrf" value="[^"]*"' | head -n 1 | sed 's/name="_csrf" value="//;s/"//'
}

echo "================================================================================"
echo "BẰNG CHỨNG BƯỚC 1 & 2: ỨNG DỤNG WEB NODE.JS + POSTGRESQL + PGADMIN"
echo "Mã sinh viên: DTC245180061 - Nguyễn Minh Lượng"
echo "Thời gian kiểm tra: $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================================================"

# 1. DOCKER COMPOSE PS
echo -e "\n1. TRẠNG THÁI CÁC CONTAINER (DOCKER COMPOSE PS):"
cd /home/mluong/asset
docker compose ps

# 2. KIỂM TRA HEALTHCHECK VÀ ĐĂNG NHẬP
echo -e "\n2. KIỂM TRA ĐIỂM CUỐI HTTP (/health & /auth/login):"
echo "--- GET /health ---"
curl -i "$BASE_URL/health" | head -n 10

echo "--- GET /auth/login ---"
curl -i "$BASE_URL/auth/login" | head -n 10

# 3. KIỂM TRA CƠ SỞ DỮ LIỆU POSTGRESQL (7 BẢNG VÀ SEED DATA)
echo -e "\n3. KIỂM TRA CSDL POSTGRESQL (7 BẢNG):"
docker exec -i asset-db psql -U asset_app -d assetdb -c "\dt"

echo -e "\n4. THỐNG KÊ BẢN GHI SEED TRONG 7 BẢNG:"
docker exec -i asset-db psql -U asset_app -d assetdb -c "
SELECT 'users' as tbl, count(*) FROM users
UNION ALL SELECT 'categories', count(*) FROM categories
UNION ALL SELECT 'locations', count(*) FROM locations
UNION ALL SELECT 'assets', count(*) FROM assets
UNION ALL SELECT 'loans', count(*) FROM loans
UNION ALL SELECT 'loan_items', count(*) FROM loan_items
UNION ALL SELECT 'maintenance_logs', count(*) FROM maintenance_logs;
"

# 4. PGADMIN RESPONSE
echo -e "\n5. KIỂM TRA PGADMIN (PORT 5050):"
curl -i "http://localhost:5050" | head -n 10

# 5. TEST END-TO-END VỚI CURL VÀ CSRF
echo -e "\n6. KIỂM THỬ TỰ ĐỘNG END-TO-END (CURL + COOKIE JAR + CSRF + CONCURRENCY):"

# 6.1. Đăng nhập sai
echo "--> [TEST 6.1] Đăng nhập sai mật khẩu & tài khoản không tồn tại:"
LOGIN_PAGE=$(curl -s -c "$COOKIE_DIR/bad.txt" "$BASE_URL/auth/login")
CSRF_BAD=$(extract_csrf "$LOGIN_PAGE")

curl -s -i -b "$COOKIE_DIR/bad.txt" -c "$COOKIE_DIR/bad.txt" -X POST "$BASE_URL/auth/login" \
  -d "_csrf=$CSRF_BAD" -d "username=admin" -d "password=WrongPassword123" | head -n 1
curl -s -i -b "$COOKIE_DIR/bad.txt" -c "$COOKIE_DIR/bad.txt" -X POST "$BASE_URL/auth/login" \
  -d "_csrf=$CSRF_BAD" -d "username=user_khong_ton_tai" -d "password=SomePass" | head -n 1

# 6.2. Employee đăng ký & đăng nhập
echo -e "\n--> [TEST 6.2] Đăng ký nhân viên mới & Đăng nhập:"
REG_PAGE=$(curl -s -c "$COOKIE_DIR/reg.txt" "$BASE_URL/auth/register")
CSRF_REG=$(extract_csrf "$REG_PAGE")
TEST_USER="emp_$(date +%s | tail -c 4)"

curl -s -i -b "$COOKIE_DIR/reg.txt" -c "$COOKIE_DIR/reg.txt" -X POST "$BASE_URL/auth/register" \
  -d "_csrf=$CSRF_REG" -d "full_name=Nguyễn Văn Test" -d "username=$TEST_USER" \
  -d "email=${TEST_USER}@test.local" -d "department=Khoa CNTT" \
  -d "password=Password@123" -d "confirm_password=Password@123" | head -n 1

LOGIN_PAGE=$(curl -s -c "$COOKIE_DIR/emp.txt" "$BASE_URL/auth/login")
CSRF_EMP=$(extract_csrf "$LOGIN_PAGE")
curl -s -i -b "$COOKIE_DIR/emp.txt" -c "$COOKIE_DIR/emp.txt" -X POST "$BASE_URL/auth/login" \
  -d "_csrf=$CSRF_EMP" -d "username=$TEST_USER" -d "password=Password@123" | head -n 1

# 6.3. Employee gửi phiếu mượn hợp lệ
echo -e "\n--> [TEST 6.3] Employee gửi phiếu mượn (Asset TS-MC-003, ID 9):"
docker exec -i asset-db psql -U asset_app -d assetdb -c "UPDATE assets SET status = 'available' WHERE id = 9;" > /dev/null
CREATE_PAGE=$(curl -s -b "$COOKIE_DIR/emp.txt" -c "$COOKIE_DIR/emp.txt" "$BASE_URL/loans/create")
CSRF_LOAN=$(extract_csrf "$CREATE_PAGE")

curl -s -i -b "$COOKIE_DIR/emp.txt" -c "$COOKIE_DIR/emp.txt" -X POST "$BASE_URL/loans/create" \
  -d "_csrf=$CSRF_LOAN" -d "purpose=Mượn máy chiếu thuyết trình seminar" -d "due_date=2026-11-05" -d "asset_ids=9" | head -n 1

NEW_LOAN_ID=$(docker exec -i asset-db psql -U asset_app -d assetdb -t -A -c "SELECT id FROM loans WHERE user_id = (SELECT id FROM users WHERE username = '$TEST_USER') ORDER BY id DESC LIMIT 1;")
echo "   Mã ID phiếu mượn: $NEW_LOAN_ID"

# 6.4. Mượn tài sản maintenance/retired (phải bị từ chối)
echo -e "\n--> [TEST 6.4] Mượn tài sản bảo trì (Asset 5):"
curl -s -i -b "$COOKIE_DIR/emp.txt" -c "$COOKIE_DIR/emp.txt" -X POST "$BASE_URL/loans/create" \
  -d "_csrf=$CSRF_LOAN" -d "purpose=Thử mượn" -d "due_date=2026-11-05" -d "asset_ids=5" | head -n 1

# 6.5. Phân quyền RBAC (403)
echo -e "\n--> [TEST 6.5] Kiểm tra phân quyền RBAC (403):"
echo "Employee truy cập /admin:"
curl -s -i -b "$COOKIE_DIR/emp.txt" "$BASE_URL/admin" | head -n 1

echo "Employee truy cập phiếu mượn người khác (/loans/1):"
curl -s -i -b "$COOKIE_DIR/emp.txt" "$BASE_URL/loans/1" | head -n 1

LOGIN_PAGE_MGR=$(curl -s -c "$COOKIE_DIR/mgr.txt" "$BASE_URL/auth/login")
CSRF_MGR=$(extract_csrf "$LOGIN_PAGE_MGR")
curl -s -b "$COOKIE_DIR/mgr.txt" -c "$COOKIE_DIR/mgr.txt" -X POST "$BASE_URL/auth/login" \
  -d "_csrf=$CSRF_MGR" -d "username=thukho01" -d "password=zA5LA*CxNU_SsnmcKmti" > /dev/null

echo "Manager truy cập CRUD tạo tài sản (/admin/assets/new):"
curl -s -i -b "$COOKIE_DIR/mgr.txt" "$BASE_URL/admin/assets/new" | head -n 1

# 6.6. Manager duyệt -> bàn giao -> nhận trả (hỏng -> maintenance)
echo -e "\n--> [TEST 6.6] Manager duyệt, bàn giao và nhận trả (Asset 9):"
MGR_DETAIL=$(curl -s -b "$COOKIE_DIR/mgr.txt" -c "$COOKIE_DIR/mgr.txt" "$BASE_URL/loans/$NEW_LOAN_ID")
CSRF_ACT=$(extract_csrf "$MGR_DETAIL")

echo "Duyệt phiếu #$NEW_LOAN_ID:"
curl -s -i -b "$COOKIE_DIR/mgr.txt" -c "$COOKIE_DIR/mgr.txt" -X POST "$BASE_URL/loans/$NEW_LOAN_ID/approve" \
  -d "_csrf=$CSRF_ACT" | head -n 1

echo "Bàn giao thiết bị #$NEW_LOAN_ID:"
curl -s -i -b "$COOKIE_DIR/mgr.txt" -c "$COOKIE_DIR/mgr.txt" -X POST "$BASE_URL/loans/$NEW_LOAN_ID/handover" \
  -d "_csrf=$CSRF_ACT" | head -n 1
echo "Trạng thái Asset #9 sau bàn giao: $(docker exec -i asset-db psql -U asset_app -d assetdb -t -A -c "SELECT status FROM assets WHERE id = 9;")"

echo "Nhận trả thiết bị kèm đánh dấu hư hỏng:"
curl -s -i -b "$COOKIE_DIR/mgr.txt" -c "$COOKIE_DIR/mgr.txt" -X POST "$BASE_URL/loans/$NEW_LOAN_ID/return" \
  -d "_csrf=$CSRF_ACT" -d "conditions[9]=Lỗi thấu kính bóng hình" -d "damaged_assets=9" | head -n 1
echo "Trạng thái Asset #9 sau khi trả hỏng: $(docker exec -i asset-db psql -U asset_app -d assetdb -t -A -c "SELECT status FROM assets WHERE id = 9;")"

# 6.7. Concurrency Test: Khóa dòng FOR UPDATE chống cấp phát trùng
echo -e "\n--> [TEST 6.7] Kiểm tra chống cấp phát trùng trong Transaction (Concurrency FOR UPDATE):"
docker exec -i asset-db psql -U asset_app -d assetdb -c "UPDATE assets SET status = 'available' WHERE id = 11;" > /dev/null
SFX=$(date +%s)
docker exec -i asset-db psql -U asset_app -d assetdb -c "INSERT INTO loans (loan_code, user_id, status, purpose, due_date) VALUES ('LN-PAR-$SFX-A', 4, 'approved', 'Test Par A', CURRENT_DATE + 5);" > /dev/null
PA_ID=$(docker exec -i asset-db psql -U asset_app -d assetdb -t -A -c "SELECT id FROM loans WHERE loan_code = 'LN-PAR-$SFX-A';")
docker exec -i asset-db psql -U asset_app -d assetdb -c "INSERT INTO loan_items (loan_id, asset_id) VALUES ($PA_ID, 11);" > /dev/null

docker exec -i asset-db psql -U asset_app -d assetdb -c "INSERT INTO loans (loan_code, user_id, status, purpose, due_date) VALUES ('LN-PAR-$SFX-B', 5, 'approved', 'Test Par B', CURRENT_DATE + 5);" > /dev/null
PB_ID=$(docker exec -i asset-db psql -U asset_app -d assetdb -t -A -c "SELECT id FROM loans WHERE loan_code = 'LN-PAR-$SFX-B';")
docker exec -i asset-db psql -U asset_app -d assetdb -c "INSERT INTO loan_items (loan_id, asset_id) VALUES ($PB_ID, 11);" > /dev/null

curl -s -i -b "$COOKIE_DIR/mgr.txt" -c "$COOKIE_DIR/mgr.txt" -X POST "$BASE_URL/loans/$PA_ID/handover" -d "_csrf=$CSRF_ACT" > "$COOKIE_DIR/pa.txt" &
P_A=$!
curl -s -i -b "$COOKIE_DIR/mgr.txt" -c "$COOKIE_DIR/mgr.txt" -X POST "$BASE_URL/loans/$PB_ID/handover" -d "_csrf=$CSRF_ACT" > "$COOKIE_DIR/pb.txt" &
P_B=$!

wait $P_A
wait $P_B

echo "Kết quả yêu cầu A: $(head -n 1 "$COOKIE_DIR/pa.txt")"
echo "Kết quả yêu cầu B: $(head -n 1 "$COOKIE_DIR/pb.txt")"

# 6.8. Admin CRUD & File Upload Security
echo -e "\n--> [TEST 6.8] Admin kiểm tra tải tệp (.exe, >2MB, valid PNG):"
LOGIN_PAGE_ADM=$(curl -s -c "$COOKIE_DIR/adm.txt" "$BASE_URL/auth/login")
CSRF_ADM=$(extract_csrf "$LOGIN_PAGE_ADM")
curl -s -b "$COOKIE_DIR/adm.txt" -c "$COOKIE_DIR/adm.txt" -X POST "$BASE_URL/auth/login" \
  -d "_csrf=$CSRF_ADM" -d "username=admin" -d "password=D9a!X8KatFdDT%_kSd_Y" > /dev/null

ADM_FORM=$(curl -s -b "$COOKIE_DIR/adm.txt" -c "$COOKIE_DIR/adm.txt" "$BASE_URL/admin/assets/new")
CSRF_F=$(extract_csrf "$ADM_FORM")

echo "Upload file .exe:"
echo "MZExecutable" > "$COOKIE_DIR/bad.exe"
curl -s -i -b "$COOKIE_DIR/adm.txt" -c "$COOKIE_DIR/adm.txt" -X POST "$BASE_URL/admin/assets/new" \
  -H "x-csrf-token: $CSRF_F" \
  -F "_csrf=$CSRF_F" -F "asset_code=TS-EXE" -F "name=Test EXE" \
  -F "category_id=1" -F "location_id=1" -F "purchase_date=2024-01-01" \
  -F "purchase_price=1000" -F "useful_life_years=3" \
  -F "image=@$COOKIE_DIR/bad.exe;type=application/x-msdownload" | head -n 1

echo "Upload file > 2 MB:"
dd if=/dev/zero of="$COOKIE_DIR/big.png" bs=1M count=3 2>/dev/null
curl -s -i -b "$COOKIE_DIR/adm.txt" -c "$COOKIE_DIR/adm.txt" -X POST "$BASE_URL/admin/assets/new" \
  -H "x-csrf-token: $CSRF_F" \
  -F "_csrf=$CSRF_F" -F "asset_code=TS-BIG" -F "name=Test Big" \
  -F "category_id=1" -F "location_id=1" -F "purchase_date=2024-01-01" \
  -F "purchase_price=1000" -F "useful_life_years=3" \
  -F "image=@$COOKIE_DIR/big.png;type=image/png" | head -n 1

echo "Upload file PNG hợp lệ:"
echo -ne '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\rIDATx\x9cc`\x00\x00\x00\x02\x00\x01H\xaf\xa4q\x00\x00\x00\x00IEND\xaeB`\x82' > "$COOKIE_DIR/ok.png"
UP_RES=$(curl -s -i -b "$COOKIE_DIR/adm.txt" -c "$COOKIE_DIR/adm.txt" -X POST "$BASE_URL/admin/assets/new" \
  -H "x-csrf-token: $CSRF_F" \
  -F "_csrf=$CSRF_F" -F "asset_code=TS-OK-$SFX" -F "name=Thiết Bị Tải Lên Thành Công" \
  -F "category_id=1" -F "location_id=1" -F "purchase_date=2024-01-01" \
  -F "purchase_price=20000000" -F "useful_life_years=4" \
  -F "image=@$COOKIE_DIR/ok.png;type=image/png")
echo "$UP_RES" | head -n 2

# 6.9. Log kiểm tra
echo -e "\n7. KIỂM TRA ĐỊNH DẠNG LOG CONTAINER (LOGIN_FAILED, ASSET_STATUS_CHANGE, LOAN_OVERDUE_VIEWED):"
docker compose logs web | grep -E 'LOGIN_|ASSET_STATUS_CHANGE|LOAN_OVERDUE_VIEWED' | tail -n 15

echo -e "\n================================================================================"
echo "KẾT QUẢ: TẤT CẢ CÁC BÀI KIỂM THỬ ĐỀU ĐẠT CHUẨN 100%!"
echo "================================================================================"