#!/bin/bash
set -eo pipefail

TARGET_URL="https://localhost/auth/login"
ATTEMPTS=20
TARGET_USER="admin"

echo "================================================================================"
echo "MÔ PHỎNG TẤN CÔNG BRUTE FORCE VÀO TRANG ĐĂNG NHẬP (MỤC ĐÍCH HỌC TẬP)"
echo "Target: ${TARGET_URL}"
echo "Target User: ${TARGET_USER}"
echo "Số lần thử: ${ATTEMPTS}"
echo "Khoảng cách giữa các lần: ~0.5 giây"
echo "Thời gian bắt đầu: $(date "+%Y-%m-%d %H:%M:%S")"
echo "================================================================================"

COOKIE_DIR=$(mktemp -d)
trap "rm -rf $COOKIE_DIR" EXIT

extract_csrf() {
  local html="$1"
  echo "$html" | grep -o 'name="_csrf" value="[^"]*"' | head -n 1 | sed 's/name="_csrf" value="//;s/"//'
}

for i in $(seq 1 $ATTEMPTS); do
  TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
  WRONG_PASS="IncorrectPass_${i}_$(date +%s%N | tail -c 6)"
  
  # Lay CSRF token
  GET_RESP=$(curl -sk -i -c "$COOKIE_DIR/jar_${i}.txt" "$TARGET_URL")
  GET_CODE=$(echo "$GET_RESP" | grep -o "HTTP/[12\.]* [0-9]*" | head -n 1 | awk '{print $2}')
  
  if [ "$GET_CODE" = "429" ]; then
    echo "[${TIMESTAMP}] [#${i}/${ATTEMPTS}] GET /auth/login -> HTTP 429 (Bị Nginx Rate Limit chặn ngay lập tức)"
    sleep 0.5
    continue
  fi
  
  CSRF_TOKEN=$(extract_csrf "$GET_RESP")
  
  # Gui yeu cau dang nhap sai
  POST_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE_DIR/jar_${i}.txt" -c "$COOKIE_DIR/jar_${i}.txt" \
    --data-urlencode "username=${TARGET_USER}" \
    --data-urlencode "password=${WRONG_PASS}" \
    --data-urlencode "_csrf=${CSRF_TOKEN}" \
    "$TARGET_URL")
    
  if [ "$POST_CODE" = "429" ]; then
    echo "[${TIMESTAMP}] [#${i}/${ATTEMPTS}] POST /auth/login -> HTTP 429 (Bị Nginx Rate Limit chặn)"
  else
    echo "[${TIMESTAMP}] [#${i}/${ATTEMPTS}] POST /auth/login -> HTTP ${POST_CODE} (Lỗi mật khẩu)"
  fi
  rm -f "$COOKIE_DIR/jar_${i}.txt"
  
  sleep 0.5
done

echo "================================================================================"
echo "HOÀN THÀNH MÔ PHỎNG TẤN CÔNG: ${ATTEMPTS} YÊU CẦU ĐÃ ĐƯỢC XỬ LÝ."
echo "Thời gian kết thúc: $(date "+%Y-%m-%d %H:%M:%S")"
echo "================================================================================"
