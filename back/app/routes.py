import asyncio
import csv
import io
import logging
from typing import Optional

from fastapi import APIRouter, UploadFile, File, Form, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from .auth import get_device_id, get_owner_filter, get_owner_filter_for_folder, get_owner_id
from .config import settings
from .database import get_db, SessionLocal
from .models import (
    SessionModel, CardModel, GradeModel, FolderModel,
    CardResponse, CardUpdate, SessionResponse, GradeResponse,
    FolderCreate, FolderUpdate, FolderResponse, SaveToLibraryRequest,
)
from .pdf_service import extract_text_from_pdf, validate_pdf
from .card_service import generate_cards
from .grade_service import grade_answer

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v1")


# ──────────────────────────────────────
# POST /api/v1/generate — PDF 업로드 + 카드 생성
# ──────────────────────────────────────

@router.post("/generate")
async def generate(
    request: Request,
    file: UploadFile = File(...),
    template_type: str = Form("definition"),
    db: Session = Depends(get_db),
    device_id: str = Depends(get_device_id),
):
    # "subjective" — TODO: MVP 이후 추가
    if template_type not in ("definition", "cloze", "comparison"):
        raise HTTPException(400, "지원하지 않는 템플릿입니다. (definition / cloze / comparison)")

    # File size pre-check (Content-Length header)
    if file.size and file.size > settings.MAX_PDF_SIZE_MB * 1024 * 1024:
        raise HTTPException(400, f"파일 크기가 {settings.MAX_PDF_SIZE_MB}MB를 초과합니다.")

    content = await file.read()

    # PDF 검증 (첫 페이지만 빠르게)
    valid, error = validate_pdf(content, settings.MAX_PDF_SIZE_MB)
    if not valid:
        raise HTTPException(400, error)

    # 세션 생성 (즉시 반환 — 텍스트 추출은 백그라운드에서)
    owner = get_owner_id(request)
    session = SessionModel(
        filename=file.filename or "unknown.pdf",
        page_count=0,
        template_type=template_type,
        device_id=device_id,
        user_id=owner["user_id"],
        status="processing",
    )
    db.add(session)
    db.commit()
    db.refresh(session)

    # 백그라운드에서 텍스트 추출 + 카드 생성
    asyncio.create_task(
        _generate_in_background(session.id, content, template_type)
    )

    return _build_session_response(session)


# ──────────────────────────────────────
# GET /api/v1/sessions — 세션 목록
# ──────────────────────────────────────

@router.get("/sessions")
def list_sessions(request: Request, db: Session = Depends(get_db)):
    owner_filter = get_owner_filter(request)
    query = db.query(SessionModel).filter(
        SessionModel.status.in_(["completed", "processing", "failed"])
    )
    sessions = (
        owner_filter(query)
        .order_by(SessionModel.created_at.desc())
        .limit(50)
        .all()
    )
    return [
        {
            "id": s.id,
            "filename": s.filename,
            "page_count": s.page_count,
            "template_type": s.template_type,
            "status": s.status,
            "card_count": len(s.cards),
            "folder_id": s.folder_id,
            "display_name": s.display_name,
            "created_at": s.created_at.isoformat() + "Z",
        }
        for s in sessions
    ]


# ──────────────────────────────────────
# DELETE /api/v1/sessions/{id} — 세션 삭제
# ──────────────────────────────────────

@router.delete("/sessions/{session_id}")
def delete_session(session_id: str, request: Request, db: Session = Depends(get_db)):
    owner_filter = get_owner_filter(request)
    session = owner_filter(db.query(SessionModel).filter(SessionModel.id == session_id)).first()
    if not session:
        raise HTTPException(404, "세션을 찾을 수 없습니다.")
    db.delete(session)
    db.commit()
    return {"deleted": session_id}


# ──────────────────────────────────────
# GET /api/v1/sessions/{id} — 세션 조회
# ──────────────────────────────────────

@router.get("/sessions/{session_id}")
def get_session(session_id: str, request: Request, db: Session = Depends(get_db)):
    owner_filter = get_owner_filter(request)
    session = owner_filter(db.query(SessionModel).filter(SessionModel.id == session_id)).first()
    if not session:
        raise HTTPException(404, "세션을 찾을 수 없습니다.")
    return _build_session_response(session)


# ──────────────────────────────────────
# PATCH /api/v1/cards/{id} — 카드 상태/내용 수정
# ──────────────────────────────────────

@router.patch("/cards/{card_id}")
def update_card(card_id: str, update: CardUpdate, db: Session = Depends(get_db)):
    card = db.query(CardModel).filter(CardModel.id == card_id).first()
    if not card:
        raise HTTPException(404, "카드를 찾을 수 없습니다.")

    if update.status and update.status in ("accepted", "rejected", "pending"):
        card.status = update.status
    if update.front is not None:
        card.front = update.front
    if update.back is not None:
        card.back = update.back

    db.commit()
    db.refresh(card)

    return _card_to_response(card)


# ──────────────────────────────────────
# POST /api/v1/sessions/{id}/accept-all — 전체 채택
# ──────────────────────────────────────

@router.post("/sessions/{session_id}/accept-all")
def accept_all(session_id: str, db: Session = Depends(get_db)):
    cards = db.query(CardModel).filter(
        CardModel.session_id == session_id,
        CardModel.status == "pending",
    ).all()
    for card in cards:
        card.status = "accepted"
    db.commit()
    return {"accepted": len(cards)}


# ──────────────────────────────────────
# POST /api/v1/cards/{id}/grade — AI 채점
# ──────────────────────────────────────

@router.post("/cards/{card_id}/grade")
async def grade_card(
    card_id: str,
    user_answer: str = Form(""),
    drawing: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db),
):
    card = db.query(CardModel).filter(CardModel.id == card_id).first()
    if not card:
        raise HTTPException(404, "카드를 찾을 수 없습니다.")

    # 손글씨 이미지 읽기
    drawing_image = None
    has_drawing = False
    if drawing and drawing.filename:
        drawing_image = await drawing.read()
        has_drawing = True

    if not user_answer.strip() and not drawing_image:
        raise HTTPException(400, "답안을 입력해주세요. (텍스트 또는 손글씨)")

    try:
        result = await grade_answer(
            question=card.front,
            model_answer=card.back,
            user_answer=user_answer,
            drawing_image=drawing_image,
        )

        grade = GradeModel(
            card_id=card_id,
            user_answer=user_answer,
            has_drawing=has_drawing,
            score=result["score"],
            feedback=result["feedback"],
        )
        db.add(grade)
        db.commit()
        db.refresh(grade)

        return GradeResponse(
            id=grade.id,
            card_id=card_id,
            user_answer=user_answer,
            score=result["score"],
            feedback=result["feedback"],
            model_answer=card.back,
        ).model_dump()

    except Exception as e:
        logger.exception("채점 실패: card=%s", card_id)
        raise HTTPException(500, _safe_error("채점에 실패했습니다", e))


# ──────────────────────────────────────
# GET /api/v1/sessions/{id}/download — CSV 다운로드
# ──────────────────────────────────────

@router.get("/sessions/{session_id}/download")
def download_csv(session_id: str, request: Request, db: Session = Depends(get_db)):
    owner_filter = get_owner_filter(request)
    session = owner_filter(db.query(SessionModel).filter(SessionModel.id == session_id)).first()
    if not session:
        raise HTTPException(404, "세션을 찾을 수 없습니다.")

    # 채택 카드 우선, 없으면 pending 포함
    cards = db.query(CardModel).filter(
        CardModel.session_id == session_id,
        CardModel.status.in_(["accepted", "pending"]),
    ).all()

    if not cards:
        raise HTTPException(404, "다운로드할 카드가 없습니다.")

    # Anki 임포트 포맷 (TSV: 앞면 \t 뒷면 \t 태그)
    output = io.StringIO()
    writer = csv.writer(output, delimiter="\t")

    for card in cards:
        back_with_evidence = (
            f"{card.back}\n\n"
            f"📖 근거 (p.{card.evidence_page}): {card.evidence}"
        )
        writer.writerow([card.front, back_with_evidence, card.tags])

    output.seek(0)
    safe_name = session.filename.replace(".pdf", "").replace(" ", "_")
    filename = f"decard_{safe_name}_{session.template_type}.txt"

    # RFC 5987: 한국어 파일명을 UTF-8로 인코딩
    from urllib.parse import quote
    encoded_filename = quote(filename)

    return StreamingResponse(
        io.BytesIO(output.getvalue().encode("utf-8-sig")),
        media_type="text/tab-separated-values",
        headers={
            "Content-Disposition": f"attachment; filename*=UTF-8''{encoded_filename}",
        },
    )


# ──────────────────────────────────────
# Folder CRUD
# ──────────────────────────────────────

PRESET_COLORS = {"#C2E7DA", "#6290C3", "#9B72CF", "#F59E0B", "#EF4444", "#94A3B8"}


@router.get("/folders")
def list_folders(request: Request, db: Session = Depends(get_db)):
    folder_filter = get_owner_filter_for_folder(request)
    folders = (
        folder_filter(db.query(FolderModel))
        .order_by(FolderModel.created_at.desc())
        .all()
    )
    result = []
    for f in folders:
        session_count = len(f.sessions)
        card_count = sum(len(s.cards) for s in f.sessions)
        result.append({
            "id": f.id,
            "name": f.name,
            "color": f.color,
            "session_count": session_count,
            "card_count": card_count,
            "created_at": f.created_at.isoformat() + "Z",
            "updated_at": f.updated_at.isoformat() + "Z",
        })
    return result


@router.post("/folders")
def create_folder(
    body: FolderCreate,
    request: Request,
    db: Session = Depends(get_db),
    device_id: str = Depends(get_device_id),
):
    owner = get_owner_id(request)
    color = body.color if body.color and body.color in PRESET_COLORS else "#C2E7DA"
    folder = FolderModel(
        name=body.name,
        color=color,
        user_id=owner["user_id"],
        device_id=device_id,
    )
    db.add(folder)
    db.commit()
    db.refresh(folder)
    return {
        "id": folder.id,
        "name": folder.name,
        "color": folder.color,
        "session_count": 0,
        "card_count": 0,
        "created_at": folder.created_at.isoformat() + "Z",
        "updated_at": folder.updated_at.isoformat() + "Z",
    }


@router.patch("/folders/{folder_id}")
def update_folder(
    folder_id: str,
    body: FolderUpdate,
    request: Request,
    db: Session = Depends(get_db),
):
    folder_filter = get_owner_filter_for_folder(request)
    folder = folder_filter(db.query(FolderModel).filter(FolderModel.id == folder_id)).first()
    if not folder:
        raise HTTPException(404, "폴더를 찾을 수 없습니다.")

    if body.name is not None:
        folder.name = body.name
    if body.color is not None and body.color in PRESET_COLORS:
        folder.color = body.color
    from datetime import datetime as dt
    folder.updated_at = dt.utcnow()

    db.commit()
    db.refresh(folder)

    session_count = len(folder.sessions)
    card_count = sum(len(s.cards) for s in folder.sessions)
    return {
        "id": folder.id,
        "name": folder.name,
        "color": folder.color,
        "session_count": session_count,
        "card_count": card_count,
        "created_at": folder.created_at.isoformat() + "Z",
        "updated_at": folder.updated_at.isoformat() + "Z",
    }


@router.delete("/folders/{folder_id}")
def delete_folder(
    folder_id: str,
    request: Request,
    db: Session = Depends(get_db),
):
    folder_filter = get_owner_filter_for_folder(request)
    folder = folder_filter(db.query(FolderModel).filter(FolderModel.id == folder_id)).first()
    if not folder:
        raise HTTPException(404, "폴더를 찾을 수 없습니다.")

    # 세션의 folder_id를 null로 (세션 자체는 보존)
    for s in folder.sessions:
        s.folder_id = None
    db.delete(folder)
    db.commit()
    return {"deleted": folder_id}


@router.get("/folders/{folder_id}/sessions")
def list_folder_sessions(
    folder_id: str,
    request: Request,
    db: Session = Depends(get_db),
):
    folder_filter = get_owner_filter_for_folder(request)
    folder = folder_filter(db.query(FolderModel).filter(FolderModel.id == folder_id)).first()
    if not folder:
        raise HTTPException(404, "폴더를 찾을 수 없습니다.")

    sessions = (
        db.query(SessionModel)
        .filter(SessionModel.folder_id == folder_id)
        .order_by(SessionModel.created_at.desc())
        .all()
    )
    return [
        {
            "id": s.id,
            "filename": s.filename,
            "page_count": s.page_count,
            "template_type": s.template_type,
            "status": s.status,
            "card_count": len(s.cards),
            "folder_id": s.folder_id,
            "display_name": s.display_name,
            "created_at": s.created_at.isoformat() + "Z",
        }
        for s in sessions
    ]


# ──────────────────────────────────────
# Save to / Remove from Library
# ──────────────────────────────────────

@router.post("/sessions/{session_id}/save-to-library")
def save_to_library(
    session_id: str,
    body: SaveToLibraryRequest,
    request: Request,
    db: Session = Depends(get_db),
    device_id: str = Depends(get_device_id),
):
    owner_filter = get_owner_filter(request)
    session = owner_filter(db.query(SessionModel).filter(SessionModel.id == session_id)).first()
    if not session:
        raise HTTPException(404, "세션을 찾을 수 없습니다.")

    # 폴더 결정: 기존 폴더 or 새 폴더 생성
    if body.folder_id:
        folder_filter = get_owner_filter_for_folder(request)
        folder = folder_filter(db.query(FolderModel).filter(FolderModel.id == body.folder_id)).first()
        if not folder:
            raise HTTPException(404, "폴더를 찾을 수 없습니다.")
    elif body.new_folder_name:
        owner = get_owner_id(request)
        color = body.new_folder_color if body.new_folder_color and body.new_folder_color in PRESET_COLORS else "#C2E7DA"
        folder = FolderModel(
            name=body.new_folder_name,
            color=color,
            user_id=owner["user_id"],
            device_id=device_id,
        )
        db.add(folder)
        db.flush()
    else:
        raise HTTPException(400, "folder_id 또는 new_folder_name을 지정해주세요.")

    session.folder_id = folder.id
    if body.display_name is not None:
        session.display_name = body.display_name

    db.commit()
    return {
        "session_id": session.id,
        "folder_id": folder.id,
        "folder_name": folder.name,
        "display_name": session.display_name,
    }


@router.delete("/sessions/{session_id}/remove-from-library")
def remove_from_library(
    session_id: str,
    request: Request,
    db: Session = Depends(get_db),
):
    owner_filter = get_owner_filter(request)
    session = owner_filter(db.query(SessionModel).filter(SessionModel.id == session_id)).first()
    if not session:
        raise HTTPException(404, "세션을 찾을 수 없습니다.")

    session.folder_id = None
    session.display_name = None
    db.commit()
    return {"removed": session_id}


# ──────────────────────────────────────
# Helpers
# ──────────────────────────────────────

async def _generate_in_background(
    session_id: str,
    pdf_content: bytes,
    template_type: str,
) -> None:
    """Request 스코프 밖에서 별도 DB 세션으로 텍스트 추출 + 카드 생성."""
    db = SessionLocal()
    try:
        # 텍스트 추출 (백그라운드에서 실행)
        pages = extract_text_from_pdf(pdf_content)
        if not pages:
            raise ValueError("텍스트를 추출할 수 없는 PDF입니다.")
        if len(pages) > settings.MAX_PAGES:
            raise ValueError(f"페이지 수 초과: {len(pages)}/{settings.MAX_PAGES}")

        session = db.query(SessionModel).filter(SessionModel.id == session_id).first()
        if not session:
            logger.error("백그라운드 생성: 세션 없음 session=%s", session_id)
            return

        session.page_count = len(pages)
        db.commit()

        cards_data = await generate_cards(pages, template_type)

        for card_data in cards_data:
            status = card_data.pop("status", "pending")
            card_data.pop("recommend", None)
            db.add(CardModel(session_id=session.id, status=status, **card_data))

        session.status = "completed"
        db.commit()
        logger.info("백그라운드 생성 완료: session=%s, cards=%d", session_id, len(cards_data))
    except Exception as e:
        logger.exception("백그라운드 카드 생성 실패: session=%s", session_id)
        session = db.query(SessionModel).filter(SessionModel.id == session_id).first()
        if session:
            session.status = "failed"
            db.commit()
        from .slack import send_slack_alert
        await send_slack_alert(
            "카드 생성 실패",
            f"session: `{session_id}`\nerror: {type(e).__name__}: {e}",
        )
    finally:
        db.close()


def _safe_error(detail: str, exc: Exception) -> str:
    """Hide internal error details in production."""
    if settings.APP_ENV == "dev":
        return f"{detail}: {exc}"
    return detail


def _card_to_response(card: CardModel) -> dict:
    return CardResponse(
        id=card.id,
        front=card.front,
        back=card.back,
        evidence=card.evidence,
        evidence_page=card.evidence_page,
        tags=card.tags,
        template_type=card.template_type,
        status=card.status,
    ).model_dump()


def _build_session_response(session: SessionModel) -> dict:
    cards = [_card_to_response(c) for c in session.cards]
    stats = {
        "total": len(cards),
        "accepted": sum(1 for c in cards if c["status"] == "accepted"),
        "rejected": sum(1 for c in cards if c["status"] == "rejected"),
        "pending": sum(1 for c in cards if c["status"] == "pending"),
    }
    return {
        "id": session.id,
        "filename": session.filename,
        "page_count": session.page_count,
        "template_type": session.template_type,
        "status": session.status,
        "folder_id": session.folder_id,
        "display_name": session.display_name,
        "created_at": session.created_at.isoformat() + "Z",
        "cards": cards,
        "stats": stats,
    }
