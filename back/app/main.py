import asyncio
import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .database import create_tables
from .routes import router
from .auth_routes import router as auth_router
from .slack import send_slack_alert

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


@app.on_event("startup")
def startup():
    create_tables()
    asyncio.get_event_loop().create_task(
        send_slack_alert("서버 시작", "decard-api 서버가 시작되었습니다.", "info")
    )


@app.get("/health")
def health():
    from .claude_cli import _check_memory
    mem = _check_memory()
    return {
        "status": "ok",
        "service": "decard",
        "memory": mem,
        "cli_semaphore": 3,
    }
