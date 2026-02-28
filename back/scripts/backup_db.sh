#!/usr/bin/env bash
# ============================================================
# Decard SQLite DB 백업 스크립트
# - sqlite3 .backup 으로 hot copy
# - gzip 압축 후 S3 업로드
# - 30일 이상 된 로컬 백업 자동 삭제
# - 실패 시 Slack 웹훅 알림
#
# crontab 설정 예시 (매일 새벽 3시):
#   0 3 * * * /home/ubuntu/apps/decard/back/scripts/backup_db.sh >> /home/ubuntu/apps/decard/logs/backup.log 2>&1
#
# 필수 환경변수:
#   BACKUP_S3_BUCKET  - S3 버킷명 (예: decard-backups)
#   SLACK_WEBHOOK_URL - Slack 알림 웹훅 URL
#
# 선택 환경변수:
#   DB_PATH           - DB 파일 경로 (기본: ~/apps/decard/data/decard.db)
#   BACKUP_DIR        - 백업 저장 경로 (기본: ~/apps/decard/backups)
#   RETENTION_DAYS    - 로컬 백업 보관일 (기본: 30)
# ============================================================

set -euo pipefail

# --- 설정 ---
DB_PATH="${DB_PATH:-$HOME/apps/decard/data/decard.db}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/apps/decard/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="decard_backup_${TIMESTAMP}.db"
BACKUP_GZ="${BACKUP_FILE}.gz"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

notify_slack() {
    local message="$1"
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -sf -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$message\"}" \
            "$SLACK_WEBHOOK_URL" > /dev/null 2>&1 || true
    fi
}

cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        local err_msg="[Decard Backup] FAILED at $(date '+%Y-%m-%d %H:%M:%S') on $(hostname). Exit code: $exit_code"
        log "ERROR: 백업 실패 (exit code: $exit_code)"
        notify_slack "$err_msg"
    fi
    # 임시 파일 정리
    rm -f "${BACKUP_DIR}/${BACKUP_FILE}" 2>/dev/null || true
}

trap cleanup EXIT

# --- 사전 검증 ---
if [[ ! -f "$DB_PATH" ]]; then
    log "ERROR: DB 파일 없음: $DB_PATH"
    exit 1
fi

if [[ -z "${BACKUP_S3_BUCKET:-}" ]]; then
    log "ERROR: BACKUP_S3_BUCKET 환경변수 미설정"
    exit 1
fi

if ! command -v sqlite3 &> /dev/null; then
    log "ERROR: sqlite3 명령어 없음"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    log "ERROR: aws CLI 없음"
    exit 1
fi

# --- 백업 디렉토리 생성 ---
mkdir -p "$BACKUP_DIR"

# --- 1. SQLite 안전 백업 (hot copy) ---
log "백업 시작: $DB_PATH → $BACKUP_FILE"
sqlite3 "$DB_PATH" ".backup '${BACKUP_DIR}/${BACKUP_FILE}'"
log "SQLite 백업 완료"

# --- 2. gzip 압축 ---
gzip "${BACKUP_DIR}/${BACKUP_FILE}"
BACKUP_SIZE=$(du -h "${BACKUP_DIR}/${BACKUP_GZ}" | cut -f1)
log "압축 완료: ${BACKUP_GZ} (${BACKUP_SIZE})"

# --- 3. S3 업로드 ---
log "S3 업로드 시작: s3://${BACKUP_S3_BUCKET}/${BACKUP_GZ}"
aws s3 cp "${BACKUP_DIR}/${BACKUP_GZ}" "s3://${BACKUP_S3_BUCKET}/${BACKUP_GZ}" --quiet
log "S3 업로드 완료"

# --- 4. 오래된 로컬 백업 삭제 (30일) ---
DELETED_COUNT=$(find "$BACKUP_DIR" -name "decard_backup_*.db.gz" -mtime +${RETENTION_DAYS} -print -delete | wc -l | tr -d ' ')
if [[ "$DELETED_COUNT" -gt 0 ]]; then
    log "오래된 백업 ${DELETED_COUNT}개 삭제 (${RETENTION_DAYS}일 초과)"
fi

# --- 5. 성공 알림 ---
log "백업 성공: ${BACKUP_GZ} (${BACKUP_SIZE}) → s3://${BACKUP_S3_BUCKET}"
notify_slack "[Decard Backup] SUCCESS: ${BACKUP_GZ} (${BACKUP_SIZE}) uploaded to S3"
