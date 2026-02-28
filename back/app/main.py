import asyncio
import logging
from datetime import datetime, timedelta

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .database import create_tables, SessionLocal
from .models import SessionModel
from .routes import router
from .auth_routes import router as auth_router
from .slack import send_slack_alert

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

app = FastAPI(
    title="Decard API",
    description="PDF → 근거 포함 암기카드 생성 API",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in settings.CORS_ORIGINS.split(",")],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization", "X-Device-ID"],
)

app.include_router(router)
app.include_router(auth_router)


async def _cleanup_stuck_sessions():
    """SESSION_TIMEOUT_MINUTES 이상 processing 상태인 세션을 failed로 전환."""
    timeout_minutes = settings.SESSION_TIMEOUT_MINUTES
    while True:
        db = SessionLocal()
        try:
            cutoff = datetime.utcnow() - timedelta(minutes=timeout_minutes)
            stuck = db.query(SessionModel).filter(
                SessionModel.status == "processing",
                SessionModel.created_at < cutoff,
            ).all()
            for s in stuck:
                s.status = "failed"
                s.error_message = f"처리 시간 초과 ({timeout_minutes}분). 다시 시도해주세요."
                logger.warning("stuck 세션 정리: %s (%s)", s.id, s.filename)
            if stuck:
                db.commit()
        except Exception:
            logger.exception("stuck 세션 정리 중 오류")
        finally:
            db.close()
        await asyncio.sleep(300)  # 5분 주기


@app.on_event("startup")
def startup():
    create_tables()
    loop = asyncio.get_event_loop()
    loop.create_task(
        send_slack_alert("서버 시작", "decard-api 서버가 시작되었습니다.", "info")
    )
    loop.create_task(_cleanup_stuck_sessions())


@app.get("/health")
def health():
    from .claude_cli import _check_memory, _cli_semaphore, MAX_CONCURRENT_CLI
    mem = _check_memory()

    db = SessionLocal()
    try:
        processing = db.query(SessionModel).filter(
            SessionModel.status == "processing"
        ).count()
    finally:
        db.close()

    return {
        "status": "ok",
        "service": "decard",
        "memory": mem,
        "cli_semaphore": {
            "max": MAX_CONCURRENT_CLI,
            "available": _cli_semaphore._value,
        },
        "processing_sessions": processing,
        "max_concurrent_sessions": settings.MAX_CONCURRENT_SESSIONS,
    }
