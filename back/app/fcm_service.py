"""Firebase Cloud Messaging (FCM) 푸시 알림 전송.

서비스 계정 키 파일은 .env의 FCM_SERVICE_ACCOUNT_PATH로 지정 (기본: ./firebase-service-account.json).
파일 없거나 초기화 실패 시 모든 send_*() 호출은 no-op (앱 동작에 영향 없음).
"""
import logging
import os
from typing import Iterable, Optional

logger = logging.getLogger(__name__)

_initialized = False
_init_failed = False


def _init():
    """Firebase Admin SDK 지연 초기화. 한 번 실패하면 재시도 안 함."""
    global _initialized, _init_failed
    if _initialized or _init_failed:
        return

    try:
        import firebase_admin
        from firebase_admin import credentials
    except ImportError:
        logger.warning("firebase_admin 미설치 — FCM 알림 비활성화")
        _init_failed = True
        return

    key_path = os.environ.get(
        "FCM_SERVICE_ACCOUNT_PATH",
        os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                     "firebase-service-account.json"),
    )
    if not os.path.exists(key_path):
        logger.warning("FCM 서비스 계정 키 없음 (%s) — 푸시 알림 비활성화", key_path)
        _init_failed = True
        return

    try:
        cred = credentials.Certificate(key_path)
        firebase_admin.initialize_app(cred)
        _initialized = True
        logger.info("FCM 초기화 완료 (key=%s)", key_path)
    except Exception as e:
        logger.error("FCM 초기화 실패: %s: %s — 푸시 알림 비활성화", type(e).__name__, e)
        _init_failed = True


def is_available() -> bool:
    _init()
    return _initialized


def send_to_tokens(
    tokens: Iterable[str],
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> int:
    """여러 디바이스 토큰에 동일 알림 전송. 성공 건수 반환.

    토큰 단위로 개별 전송 (send_each_for_multicast는 토큰 통째 invalid 시 전체 실패할 수 있음).
    실패는 로그만 남기고 무시 (네트워크 오류, 토큰 만료 등).
    """
    _init()
    if not _initialized:
        return 0

    from firebase_admin import messaging

    tokens = [t for t in tokens if t]
    if not tokens:
        return 0

    success = 0
    for token in tokens:
        try:
            message = messaging.Message(
                notification=messaging.Notification(title=title, body=body),
                data={k: str(v) for k, v in (data or {}).items()},
                token=token,
                android=messaging.AndroidConfig(
                    priority="high",
                    notification=messaging.AndroidNotification(
                        channel_id="decard_default",
                        sound="default",
                    ),
                ),
                apns=messaging.APNSConfig(
                    payload=messaging.APNSPayload(
                        aps=messaging.Aps(sound="default", badge=1),
                    ),
                ),
            )
            messaging.send(message)
            success += 1
        except Exception as e:
            logger.warning("FCM 전송 실패 token=%s...: %s: %s",
                           token[:20], type(e).__name__, e)
    logger.info("FCM 전송 결과: %d/%d 성공", success, len(tokens))
    return success
