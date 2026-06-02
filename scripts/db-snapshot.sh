#!/bin/bash
# 프로덕션 SQLite DB 스냅샷 다운로드 + DB Browser 자동 실행
# 사용: bash scripts/db-snapshot.sh
#
# - sqlite3 .backup으로 lock 없이 일관된 스냅샷 생성 (서비스 영향 없음)
# - 로컬은 read-only (chmod 444)로 받아서 실수 방지
# - db_snapshots/latest.db는 항상 가장 최신을 가리키는 symlink

set -e

LOCAL_DIR="$HOME/Desktop/cml/product/decard/back/db_snapshots"
mkdir -p "$LOCAL_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOCAL_FILE="$LOCAL_DIR/decard_$TIMESTAMP.db"
REMOTE_TMP="/tmp/decard_snapshot_$TIMESTAMP.db"

echo "[1/4] VPS에서 일관된 스냅샷 생성 중..."
ssh eupori-server "sqlite3 ~/apps/decard/data/decard.db \".backup $REMOTE_TMP\""

echo "[2/4] 로컬로 다운로드 중..."
scp -q "eupori-server:$REMOTE_TMP" "$LOCAL_FILE"

echo "[3/4] VPS의 임시 파일 정리..."
ssh eupori-server "rm -f $REMOTE_TMP"

echo "[4/4] read-only로 권한 변경 + symlink 업데이트..."
chmod 444 "$LOCAL_FILE"
ln -sf "$LOCAL_FILE" "$LOCAL_DIR/latest.db"

SIZE=$(du -h "$LOCAL_FILE" | cut -f1)
echo ""
echo "✅ 다운로드 완료: $LOCAL_FILE ($SIZE)"
echo "   → latest.db symlink 갱신됨"

# 7일 이상 된 스냅샷 자동 정리 (선택)
find "$LOCAL_DIR" -name "decard_*.db" -mtime +7 -delete 2>/dev/null

echo ""
echo "DB Browser for SQLite 실행 중..."
open -a "DB Browser for SQLite" "$LOCAL_FILE"
