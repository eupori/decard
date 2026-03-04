from datetime import datetime, timezone

from sqlalchemy import func
from sqlalchemy.orm import Session

from .config import settings
from .models import SessionModel


def _month_start() -> datetime:
    """이번 달 1일 00:00 UTC."""
    now = datetime.now(timezone.utc)
    return datetime(now.year, now.month, 1, tzinfo=timezone.utc)


def _next_month_start() -> datetime:
    """다음 달 1일 00:00 UTC."""
    now = datetime.now(timezone.utc)
    year, month = (now.year, now.month + 1) if now.month < 12 else (now.year + 1, 1)
    return datetime(year, month, 1, tzinfo=timezone.utc)


def _count_used(user_id: str | None, device_id: str, db: Session) -> int:
    """이번 달 PDF 생성 횟수 (실패 제외)."""
    start = _month_start()
    q = db.query(func.count(SessionModel.id)).filter(
        SessionModel.source_type == "pdf",
        SessionModel.status != "failed",
        SessionModel.created_at >= start,
    )
    if user_id:
        q = q.filter(SessionModel.user_id == user_id)
    else:
        q = q.filter(SessionModel.device_id == device_id)
    return q.scalar() or 0


def get_billing_status(user_id: str | None, device_id: str, db: Session) -> dict:
    used = _count_used(user_id, device_id, db)
    limit = settings.FREE_MONTHLY_LIMIT
    return {
        "used": used,
        "limit": limit,
        "remaining": max(0, limit - used),
        "resets_at": _next_month_start().isoformat().replace("+00:00", "Z"),
    }


def can_generate(user_id: str | None, device_id: str, db: Session) -> dict:
    status = get_billing_status(user_id, device_id, db)
    if status["remaining"] > 0:
        return {"allowed": True, "remaining": status["remaining"]}
    return {
        "allowed": False,
        "remaining": 0,
        "message": f"이번 달 무료 {status['limit']}회를 모두 사용했습니다. {status['resets_at'][:10]}에 리셋됩니다.",
    }
