import logging
import httpx
from .config import settings

logger = logging.getLogger(__name__)

COLORS = {"error": "#EF4444", "warn": "#F59E0B", "info": "#22C55E"}


async def send_slack_alert(title: str, message: str, level: str = "error") -> None:
    url = settings.SLACK_WEBHOOK_URL
    if not url:
        return
    payload = {
        "attachments": [
            {
                "color": COLORS.get(level, COLORS["info"]),
                "title": f"[데카드] {title}",
                "text": message,
                "footer": f"decard-api | {settings.APP_ENV}",
            }
        ]
    }
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            await client.post(url, json=payload)
    except Exception:
        logger.warning("Slack 알림 전송 실패", exc_info=True)
