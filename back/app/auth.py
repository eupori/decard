import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

import httpx
import jwt as pyjwt
from fastapi import Request
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
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


# ──────────────────────────────────────
# Google Token Verification
# ──────────────────────────────────────

def verify_google_token(id_token_str: str) -> dict:
    """Verify Google ID token and return user info."""
    try:
        # 모든 Client ID 허용 (Web/iOS/Android)
        valid_client_ids = [
            settings.GOOGLE_CLIENT_ID_WEB,
            settings.GOOGLE_CLIENT_ID_IOS,
            settings.GOOGLE_CLIENT_ID_ANDROID,
        ]
        valid_client_ids = [cid for cid in valid_client_ids if cid]

        idinfo = google_id_token.verify_oauth2_token(
            id_token_str,
            google_requests.Request(),
        )

        # audience 검증
        if idinfo.get("aud") not in valid_client_ids:
            raise ValueError("Invalid audience")

        return {
            "sub": idinfo["sub"],
            "email": idinfo.get("email", ""),
            "name": idinfo.get("name", ""),
            "picture": idinfo.get("picture", ""),
        }
    except Exception as e:
        logger.error("Google token verification failed: %s", e)
        raise ValueError(f"Invalid Google token: {e}")


# ──────────────────────────────────────
# Apple Token Verification
# ──────────────────────────────────────

async def verify_apple_token(id_token_str: str, nonce: Optional[str] = None) -> dict:
    """Verify Apple ID token and return user info."""
    try:
        # Apple 공개키 가져오기
        async with httpx.AsyncClient() as client:
            resp = await client.get("https://appleid.apple.com/auth/keys")
            resp.raise_for_status()
            apple_keys = resp.json()

        # JWT 헤더에서 kid 추출
        header = pyjwt.get_unverified_header(id_token_str)
        kid = header.get("kid")

        # 매칭 키 찾기
        key_data = None
        for key in apple_keys.get("keys", []):
            if key.get("kid") == kid:
                key_data = key
                break

        if not key_data:
            raise ValueError("Apple public key not found")

        # 공개키로 JWT 디코딩
        from jwt.algorithms import RSAAlgorithm
        public_key = RSAAlgorithm.from_jwk(key_data)

        payload = pyjwt.decode(
            id_token_str,
            public_key,
            algorithms=["RS256"],
            audience=settings.APPLE_BUNDLE_ID,
            issuer="https://appleid.apple.com",
        )

        return {
            "sub": payload["sub"],
            "email": payload.get("email", ""),
        }
    except Exception as e:
        logger.error("Apple token verification failed: %s", e)
        raise ValueError(f"Invalid Apple token: {e}")


# ──────────────────────────────────────
# Provider-based user creation
# ──────────────────────────────────────

def find_or_create_user_by_provider(
    db: Session,
    provider: str,
    provider_id: str,
    email: str = "",
    nickname: str = "",
    profile_image: str = "",
) -> UserModel:
    """Find or create user by provider (google/apple)."""
    # provider별 ID 컬럼으로 검색
    if provider == "google":
        user = db.query(UserModel).filter(UserModel.google_id == provider_id).first()
    elif provider == "apple":
        user = db.query(UserModel).filter(UserModel.apple_id == provider_id).first()
    else:
        raise ValueError(f"Unknown provider: {provider}")

    if user:
        # 기존 유저 업데이트
        if nickname:
            user.nickname = nickname
        if profile_image:
            user.profile_image = profile_image
        if email:
            user.email = email
        db.commit()
        db.refresh(user)
        return user

    # 이메일로 기존 유저 검색 (다른 provider로 이미 가입한 경우 연동)
    if email:
        existing = db.query(UserModel).filter(UserModel.email == email).first()
        if existing:
            if provider == "google":
                existing.google_id = provider_id
            elif provider == "apple":
                existing.apple_id = provider_id
            if nickname and not existing.nickname:
                existing.nickname = nickname
            if profile_image and not existing.profile_image:
                existing.profile_image = profile_image
            db.commit()
            db.refresh(existing)
            return existing

    # 새 유저 생성
    new_user_kwargs = {
        "nickname": nickname,
        "profile_image": profile_image,
        "email": email,
        "auth_provider": provider,
    }
    if provider == "google":
        new_user_kwargs["google_id"] = provider_id
    elif provider == "apple":
        new_user_kwargs["apple_id"] = provider_id

    user = UserModel(**new_user_kwargs)
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


# ──────────────────────────────────────
# Delete user data
# ──────────────────────────────────────

def delete_user_data(db: Session, user_id: str):
    """Delete all user data (sessions, cards, folders, reviews, grades)."""
    from .models import CardModel, GradeModel, CardReviewModel

    # 유저의 세션 ID 목록
    sessions = db.query(SessionModel).filter(SessionModel.user_id == user_id).all()
    session_ids = [s.id for s in sessions]

    # 카드 ID 목록 (세션에 속한 카드들)
    if session_ids:
        cards = db.query(CardModel).filter(CardModel.session_id.in_(session_ids)).all()
        card_ids = [c.id for c in cards]

        # Grades 삭제
        if card_ids:
            db.query(GradeModel).filter(GradeModel.card_id.in_(card_ids)).delete(synchronize_session=False)

        # CardReviews 삭제
        if card_ids:
            db.query(CardReviewModel).filter(CardReviewModel.card_id.in_(card_ids)).delete(synchronize_session=False)

        # Cards 삭제
        if card_ids:
            db.query(CardModel).filter(CardModel.session_id.in_(session_ids)).delete(synchronize_session=False)

        # Sessions 삭제
        db.query(SessionModel).filter(SessionModel.user_id == user_id).delete(synchronize_session=False)

    # CardReviews (유저 직접 연결) 삭제
    db.query(CardReviewModel).filter(CardReviewModel.user_id == user_id).delete(synchronize_session=False)

    # Folders 삭제
    db.query(FolderModel).filter(FolderModel.user_id == user_id).delete(synchronize_session=False)

    # User 삭제
    db.query(UserModel).filter(UserModel.id == user_id).delete(synchronize_session=False)

    db.commit()
    logger.info("Deleted all data for user %s", user_id)


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
