import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

import httpx
from fastapi import Request
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from .config import settings
from .models import UserModel, SessionModel, FolderModel, CardReviewModel

logger = logging.getLogger(__name__)

# ──────────────────────────────────────
# JWT
# ──────────────────────────────────────

def create_access_token(user_id: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(hours=settings.JWT_EXPIRE_HOURS)
    return jwt.encode(
        {"sub": user_id, "exp": expire},
        settings.JWT_SECRET_KEY,
        algorithm="HS256",
    )


def decode_token(token: str) -> Optional[str]:
    """Returns user_id or None."""
    try:
        payload = jwt.decode(token, settings.JWT_SECRET_KEY, algorithms=["HS256"])
        return payload.get("sub")
    except JWTError:
        return None


# ──────────────────────────────────────
# Kakao OAuth
# ──────────────────────────────────────

async def exchange_kakao_code(code: str) -> dict:
    """Exchange authorization code for access token."""
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            "https://kauth.kakao.com/oauth/token",
            data={
                "grant_type": "authorization_code",
                "client_id": settings.KAKAO_CLIENT_ID,
                "client_secret": settings.KAKAO_CLIENT_SECRET,
                "redirect_uri": settings.KAKAO_REDIRECT_URI,
                "code": code,
            },
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        resp.raise_for_status()
        return resp.json()


async def get_kakao_user(access_token: str) -> dict:
    """Fetch user profile from Kakao."""
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            "https://kapi.kakao.com/v2/user/me",
            headers={"Authorization": f"Bearer {access_token}"},
        )
        resp.raise_for_status()
        return resp.json()


def find_or_create_user(db: Session, kakao_id: str, nickname: str, profile_image: str) -> UserModel:
    """Find existing user by kakao_id or create new one."""
    user = db.query(UserModel).filter(UserModel.kakao_id == str(kakao_id)).first()
    if user:
        user.nickname = nickname
        user.profile_image = profile_image
        db.commit()
        db.refresh(user)
        return user

    user = UserModel(
        kakao_id=str(kakao_id),
        nickname=nickname,
        profile_image=profile_image,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def link_device_sessions(db: Session, user: UserModel, device_id: str):
    """Migrate device_id sessions to user."""
    if not device_id or device_id == "anonymous":
        return

    # 디바이스 ID를 유저에 저장
    user.device_id = device_id
    db.commit()

    # 해당 디바이스의 세션들을 유저에 연결 + device_id 제거 (로그아웃 후 안 보이게)
    sessions = db.query(SessionModel).filter(
        SessionModel.device_id == device_id,
        SessionModel.user_id.is_(None),
    ).all()
    for s in sessions:
        s.user_id = user.id
        s.device_id = f"migrated_{user.id}"
    db.commit()

    # 폴더도 마이그레이션
    folders = db.query(FolderModel).filter(
        FolderModel.device_id == device_id,
        FolderModel.user_id.is_(None),
    ).all()
    for f in folders:
        f.user_id = user.id
        f.device_id = f"migrated_{user.id}"
    db.commit()

    # CardReview도 마이그레이션
    reviews = db.query(CardReviewModel).filter(
        CardReviewModel.device_id == device_id,
        CardReviewModel.user_id.is_(None),
    ).all()
    for r in reviews:
        r.user_id = user.id
        r.device_id = f"migrated_{user.id}"
    db.commit()

    logger.info("Linked %d sessions, %d folders, %d reviews from device %s to user %s",
                len(sessions), len(folders), len(reviews), device_id, user.id)


# ──────────────────────────────────────
# Request helpers (dual auth)
# ──────────────────────────────────────

def _get_user_id_from_token(request: Request) -> Optional[str]:
    """Extract user_id from Authorization Bearer token."""
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        token = auth_header[7:]
        return decode_token(token)
    return None


def get_device_id(request: Request) -> str:
    """Extract device ID from X-Device-ID header, default to 'anonymous'."""
    return request.headers.get("X-Device-ID", "anonymous")


def get_owner_filter(request: Request):
    """Return SQLAlchemy filter for session ownership.

    Priority: JWT user_id > X-Device-ID header.
    Returns a callable that takes SessionModel query and applies the filter.
    """
    user_id = _get_user_id_from_token(request)
    device_id = get_device_id(request)

    if user_id:
        # 로그인 유저: user_id로만 조회 (마이그레이션된 세션 포함)
        return lambda q: q.filter(SessionModel.user_id == user_id)
    else:
        # 비로그인: device_id로만 조회
        return lambda q: q.filter(SessionModel.device_id == device_id)


def get_owner_filter_for_folder(request: Request):
    """Return SQLAlchemy filter for folder ownership (dual auth)."""
    user_id = _get_user_id_from_token(request)
    device_id = get_device_id(request)

    if user_id:
        return lambda q: q.filter(FolderModel.user_id == user_id)
    else:
        return lambda q: q.filter(FolderModel.device_id == device_id)


def get_owner_id(request: Request) -> dict:
    """Return dict with user_id and device_id for session creation."""
    user_id = _get_user_id_from_token(request)
    device_id = get_device_id(request)
    return {"user_id": user_id, "device_id": device_id}
