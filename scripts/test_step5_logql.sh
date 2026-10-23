#!/bin/bash
set -euo pipefail

cd /home/mluong/asset

EVIDENCE_FILE="/home/mluong/asset/evidence/buoc5-logql.txt"

echo "================================================================================" > "$EVIDENCE_FILE"
echo "BANG CHUNG BUOC 5 - PHAN B: KET QUA TRUY VAN LOGQL QUA LOKI API" >> "$EVIDENCE_FILE"
echo "Ma sinh vien: DTC245180061 - Nguyen Minh Luong" >> "$EVIDENCE_FILE"
echo "Thoi gian kiem tra: $(date "+%Y-%m-%d %H:%M:%S")" >> "$EVIDENCE_FILE"
echo "================================================================================" >> "$EVIDENCE_FILE"

execute_logql() {
  local title="$1"
  local query="$2"
  echo -e "\n--------------------------------------------------------------------------------" >> "$EVIDENCE_FILE"
  echo "$title" >> "$EVIDENCE_FILE"
  echo "Truy van LogQL: $query" >> "$EVIDENCE_FILE"
  echo "--------------------------------------------------------------------------------" >> "$EVIDENCE_FILE"
  
  RESP=$(docker exec asset-web curl -s -G "http://loki:3100/loki/api/v1/query_range" --data-urlencode "query=${query}")
  STATUS=$(echo "$RESP" | jq -r .status)
  RESULT_TYPE=$(echo "$RESP" | jq -r .data.resultType)
  COUNT=$(echo "$RESP" | jq '.data.result | length')
  
  echo "Status: $STATUS | ResultType: $RESULT_TYPE | Matches: $COUNT" >> "$EVIDENCE_FILE"
  echo "Chi tiet ket qua:" >> "$EVIDENCE_FILE"
  echo "$RESP" | jq '.data.result[:3]' >> "$EVIDENCE_FILE"
}

execute_logql "Q1: Cac dong log loi phia server (HTTP 5xx) cua Nginx"   '{job="nginx"} |~ "\" 5[0-9]{2} "'

execute_logql "Q2: Cac dong log chua tu khoa loi hoac that bai cua Web Application"   '{job="webapp"} |~ "(?i)(error|exception|failed)"'

execute_logql "Q3: Cac dong log su kien dang nhap that bai (LOGIN_FAILED)"   '{job="webapp"} |= "LOGIN_FAILED"'

execute_logql "Q4: Tong so lan dang nhap that bai trong khoang thoi gian 1 phut (Metric Query)"   'sum(count_over_time({job="webapp"} |= "LOGIN_FAILED" [1m]))'

execute_logql "Q5: Cac dong log su kien thay doi trang thai tai san (ASSET_STATUS_CHANGE)"   '{job="webapp"} |= "ASSET_STATUS_CHANGE"'

echo -e "\n================================================================================" >> "$EVIDENCE_FILE"
echo "HOAN THANH TRUY VAN 5 CAU LOGQL - KET QUA GHI THANH CONG" >> "$EVIDENCE_FILE"
echo "================================================================================" >> "$EVIDENCE_FILE"
