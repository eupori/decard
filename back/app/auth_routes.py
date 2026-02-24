import logging
from urllib.parse import urlencode

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import RedirectResponse
from sqlalchemy.orm import Session

from .auth import (
    create_access_token,
    decode_token,
    exchange_kakao_code,
    get_kakao_user,
    find_or_create_user,
    link_device_sessions,
    get_device_id,
)
from .config import settings
from .database import get_db
from .models import UserModel, UserResponse

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v1/auth")


# ──────────────────────────────────────
# GET /auth/kakao/login — 카카오 로그인 페이지로 리다이렉트
# ──────────────────────────────────────

@router.get("/kakao/login")
def kakao_login(platform: str = "web"):
    params = {
        "client_id": settings.KAKAO_CLIENT_ID,
        "redirect_uri": settings.KAKAO_REDIRECT_URI,
        "response_type": "code",
    }
    if platform == "mobile":
        params["state"] = "mobile"
    return RedirectResponse(f"https://kauth.kakao.com/oauth/authorize?{urlencode(params)}")


# ──────────────────────────────────────
# GET /auth/kakao/callback — 카카오 콜백 → JWT 발급 → 프론트 리다이렉트
# ──────────────────────────────────────

@router.get("/kakao/callback")
async def kakao_callback(code: str, state: str = "", db: Session = Depends(get_db)):
    try:
        # 1. 코드 → 토큰 교환
        token_data = await exchange_kakao_code(code)
        kakao_access_token = token_data["access_token"]

        # 2. 카카오 유저 정보 조회
        kakao_user = await get_kakao_user(kakao_access_token)
        kakao_id = str(kakao_user["id"])
        properties = kakao_user.get("properties", {})
        nickname = properties.get("nickname", "")
        profile_image = properties.get("profile_image", "")

        # 3. 유저 생성/조회
        user = find_or_create_user(db, kakao_id, nickname, profile_image)

        # 4. JWT 발급
        jwt_token = create_access_token(user.id)

        # 5. 리다이렉트 (모바일: 커스텀 스킴, 웹: fragment)
        if state == "mobile":
            redirect_url = f"decard://auth?token={jwt_token}"
        else:
            frontend_url = settings.FRONTEND_URL.rstrip("/")
            redirect_url = f"{frontend_url}/#token={jwt_token}"
        return RedirectResponse(redirect_url)

    except Exception as e:
        logger.exception("카카오 로그인 실패")
        if state == "mobile":
            return RedirectResponse("decard://auth?error=login_failed")
        frontend_url = settings.FRONTEND_URL.rstrip("/")
        return RedirectResponse(f"{frontend_url}/#auth_error=login_failed")


# ──────────────────────────────────────
# GET /auth/me — 현재 유저 정보
# ──────────────────────────────────────

@router.get("/me")
def get_me(request: Request, db: Session = Depends(get_db)):
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(401, "인증이 필요합니다.")

    user_id = decode_token(auth_header[7:])
    if not user_id:
        raise HTTPException(401, "유효하지 않은 토큰입니다.")

    user = db.query(UserModel).filter(UserModel.id == user_id).first()
    if not user:
        raise HTTPException(404, "사용자를 찾을 수 없습니다.")

    return UserResponse(
        id=user.id,
        kakao_id=user.kakao_id,
        nickname=user.nickname,
        profile_image=user.profile_image,
    ).model_dump()


# ──────────────────────────────────────
# POST /auth/link-device — 디바이스 세션 마이그레이션
# ──────────────────────────────────────

@router.post("/link-device")
def link_device(request: Request, db: Session = Depends(get_db)):
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(401, "인증이 필요합니다.")

    user_id = decode_token(auth_header[7:])
    if not user_id:
        raise HTTPException(401, "유효하지 않은 토큰입니다.")

    user = db.query(UserModel).filter(UserModel.id == user_id).first()
    if not user:
        raise HTTPException(404, "사용자를 찾을 수 없습니다.")

    device_id = get_device_id(request)
    link_device_sessions(db, user, device_id)

    return {"linked": True, "device_id": device_id}
