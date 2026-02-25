import uuid
from datetime import datetime

from sqlalchemy import Column, String, Integer, Text, DateTime, ForeignKey, Boolean
from sqlalchemy.orm import relationship
from pydantic import BaseModel
from typing import List, Optional

from .database import Base


# ──────────────────────────────────────
# SQLAlchemy Models
# ──────────────────────────────────────

class UserModel(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True, default=lambda: f"usr_{uuid.uuid4().hex[:10]}")
    kakao_id = Column(String, unique=True, nullable=False, index=True)
    nickname = Column(String, default="")
    profile_image = Column(String, default="")
    device_id = Column(String, index=True, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    sessions = relationship("SessionModel", back_populates="user")


class FolderModel(Base):
    __tablename__ = "folders"

    id = Column(String, primary_key=True, default=lambda: f"fld_{uuid.uuid4().hex[:10]}")
    name = Column(String, nullable=False)
    user_id = Column(String, ForeignKey("users.id"), nullable=True, index=True)
    device_id = Column(String, index=True, default="anonymous")
    color = Column(String, default="#C2E7DA")
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    sessions = relationship("SessionModel", back_populates="folder")


class SessionModel(Base):
    __tablename__ = "sessions"

    id = Column(String, primary_key=True, default=lambda: f"ses_{uuid.uuid4().hex[:10]}")
    filename = Column(String, nullable=False)
    page_count = Column(Integer, default=0)
    template_type = Column(String, default="definition")
    device_id = Column(String, index=True, default="anonymous")
    user_id = Column(String, ForeignKey("users.id"), nullable=True, index=True)
    folder_id = Column(String, ForeignKey("folders.id"), nullable=True, index=True)
    display_name = Column(String, nullable=True)
    source_type = Column(String, default="pdf")  # pdf / manual / csv / xlsx
    status = Column(String, default="processing")  # processing / completed / failed
    created_at = Column(DateTime, default=datetime.utcnow)

    cards = relationship("CardModel", back_populates="session", cascade="all, delete-orphan")
    user = relationship("UserModel", back_populates="sessions")
    folder = relationship("FolderModel", back_populates="sessions")


class CardModel(Base):
    __tablename__ = "cards"

    id = Column(String, primary_key=True, default=lambda: f"card_{uuid.uuid4().hex[:8]}")
    session_id = Column(String, ForeignKey("sessions.id"), nullable=False)
    front = Column(Text, nullable=False)
    back = Column(Text, nullable=False)
    evidence = Column(Text, default="")
    evidence_page = Column(Integer, default=0)
    tags = Column(String, default="")
    template_type = Column(String, default="definition")
    status = Column(String, default="pending")  # pending / accepted / rejected
    created_at = Column(DateTime, default=datetime.utcnow)

    session = relationship("SessionModel", back_populates="cards")


class GradeModel(Base):
    __tablename__ = "grades"

    id = Column(String, primary_key=True, default=lambda: f"grade_{uuid.uuid4().hex[:8]}")
    card_id = Column(String, ForeignKey("cards.id"), nullable=False)
    user_answer = Column(Text, nullable=False)
    has_drawing = Column(Boolean, default=False)
    score = Column(String, nullable=False)  # correct / partial / incorrect
    feedback = Column(Text, default="")
    created_at = Column(DateTime, default=datetime.utcnow)


# ──────────────────────────────────────
# Pydantic Schemas (Request / Response)
# ──────────────────────────────────────

class CardResponse(BaseModel):
    id: str
    front: str
    back: str
    evidence: str
    evidence_page: int
    tags: str
    template_type: str
    status: str


class CardUpdate(BaseModel):
    status: Optional[str] = None
    front: Optional[str] = None
    back: Optional[str] = None


class SessionResponse(BaseModel):
    id: str
    filename: str
    page_count: int
    template_type: str
    status: str
    created_at: str
    cards: List[CardResponse]
    stats: dict


class GradeRequest(BaseModel):
    user_answer: str


class GradeResponse(BaseModel):
    id: str
    card_id: str
    user_answer: str
    score: str
    feedback: str
    model_answer: str


class UserResponse(BaseModel):
    id: str
    kakao_id: str
    nickname: str
    profile_image: str


# ── Folder Schemas ──

class FolderCreate(BaseModel):
    name: str
    color: Optional[str] = None


class FolderUpdate(BaseModel):
    name: Optional[str] = None
    color: Optional[str] = None


class FolderResponse(BaseModel):
    id: str
    name: str
    color: str
    session_count: int
    card_count: int
    created_at: str
    updated_at: str


class SaveToLibraryRequest(BaseModel):
    folder_id: Optional[str] = None
    new_folder_name: Optional[str] = None
    new_folder_color: Optional[str] = None
    display_name: Optional[str] = None


# ── Manual Card Schemas ──

class ManualCardInput(BaseModel):
    front: str
    back: str
    evidence: Optional[str] = None


class ManualSessionCreate(BaseModel):
    display_name: Optional[str] = None
    cards: List[ManualCardInput]
