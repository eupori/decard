#!/bin/bash
# Docker 컨테이너에서 OCR + vocab 흐름 동작 검증
# Usage: ./docker_smoke.sh

set -e

IMAGE="decard-api:phase6"
CONTAINER="decard-smoke"

echo "=== 1. 컨테이너 내부 명령 검증 ==="
docker run --rm "$IMAGE" sh -c '
  set -e
  echo "[python]" && python3 --version
  echo "[tesseract]" && tesseract --version 2>&1 | head -1
  echo "[langs]" && tesseract --list-langs 2>&1 | grep -E "^(jpn|kor|chi_sim|eng)$" | sort | tr "\n" " " && echo
  echo "[pdftoppm]" && pdftoppm -v 2>&1 | head -1
  echo "[pytesseract]" && python3 -c "import pytesseract; print(pytesseract.get_tesseract_version())"
  echo "[pdf2image]" && python3 -c "import pdf2image; print(\"ok\")"
  echo "[claude CLI]" && claude --version 2>&1 | head -1
'

echo ""
echo "=== 2. 컨테이너 띄우고 health 확인 ==="
docker rm -f "$CONTAINER" 2>/dev/null || true
docker run -d --name "$CONTAINER" -p 18001:8001 \
  -e KAKAO_CLIENT_ID=dummy \
  -e KAKAO_CLIENT_SECRET=dummy \
  -e JWT_SECRET_KEY=dummy-test \
  "$IMAGE"

# 서버 준비 대기 (최대 30초)
for i in $(seq 1 30); do
  if curl -fs http://localhost:18001/health > /dev/null 2>&1; then
    echo "✓ 서버 준비됨 (${i}초)"
    break
  fi
  sleep 1
done

curl -s http://localhost:18001/health | python3 -m json.tool

echo ""
echo "=== 3. OCR 폴백 테스트 (일본어 교재 이미지 PDF) ==="
PDF="/Users/cml/Downloads/일본어 교재.pdf"
if [ -f "$PDF" ]; then
  RESP=$(curl -s -X POST http://localhost:18001/api/v1/generate \
    -H "X-Device-ID: docker-smoke" \
    -F "file=@$PDF" \
    -F "template_type=vocab")
  echo "$RESP" | python3 -m json.tool
  SID=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
  echo ""
  echo "세션: $SID"
  echo "5초마다 폴링..."

  for i in $(seq 1 60); do
    sleep 5
    STATUS=$(curl -s -H "X-Device-ID: docker-smoke" \
      "http://localhost:18001/api/v1/sessions/$SID" \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{d[\"status\"]} progress={d[\"progress\"]}% cards={d[\"card_count\"]}')")
    echo "[$((i*5))s] $STATUS"
    if echo "$STATUS" | grep -qE "^(completed|failed)"; then
      break
    fi
  done

  echo ""
  echo "최종 결과:"
  curl -s -H "X-Device-ID: docker-smoke" \
    "http://localhost:18001/api/v1/sessions/$SID" \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'status: {d[\"status\"]}')
print(f'cards: {d[\"card_count\"]}')
if d.get('error_message'): print(f'error: {d[\"error_message\"]}')
for c in d.get('cards', [])[:5]:
    print(f'  - {c[\"front\"]} → {c[\"back\"]}')
print(f'  ... ({len(d.get(\"cards\", []))}장)')
"
else
  echo "PDF 없음, OCR 테스트 건너뜀: $PDF"
fi

echo ""
echo "=== 4. 정리 ==="
docker rm -f "$CONTAINER"
echo "완료"
