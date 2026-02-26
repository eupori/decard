import uuid
from datetime import datetime

from sqlalchemy import Column, String, Integer, Float, Text, DateTime, ForeignKey, Boolean
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


class CardReviewModel(Base):
    __tablename__ = "card_reviews"

    id = Column(String, primary_key=True, default=lambda: f"rev_{uuid.uuid4().hex[:8]}")
    card_id = Column(String, ForeignKey("cards.id"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=True, index=True)
    device_id = Column(String, index=True, default="anonymous")
    rating = Column(Integer, nullable=False)  # 1=Again, 2=Hard, 3=Good, 4=Easy
    interval_days = Column(Float, default=0)
    ease_factor = Column(Float, default=2.5)
    due_date = Column(DateTime, nullable=False)
    reviewed_at = Column(DateTime, default=datetime.utcnow)


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
    template_type: str = "definition"  # definition / multiple_choice / cloze


class ManualSessionCreate(BaseModel):
    display_name: Optional[str] = None
    cards: List[ManualCardInput]


# ── SRS Schemas ──

class ReviewRequest(BaseModel):
    rating: int  # 1=Again, 2=Hard, 3=Good, 4=Easy


class ReviewResponse(BaseModel):
    id: str
    card_id: str
    rating: int
    interval_days: float
    ease_factor: float
    due_date: str


class StudyStatsResponse(BaseModel):
    reviews_today: int
    mastered_cards: int
    streak_days: int
    due_cards: int


# ──────────────────────────────────────
# Explore (Public Cardsets)
# ──────────────────────────────────────

class PublicCardsetModel(Base):
    __tablename__ = "public_cardsets"

    id = Column(String, primary_key=True, default=lambda: f"pcs_{uuid.uuid4().hex[:10]}")
    title = Column(String, nullable=False)
    description = Column(Text, default="")
    category = Column(String, nullable=False)
    tags = Column(String, default="")
    card_count = Column(Integer, default=0)
    download_count = Column(Integer, default=0)
    author_id = Column(String, ForeignKey("users.id"), nullable=True)
    author_name = Column(String, default="데카드")
    is_featured = Column(Boolean, default=False)
    status = Column(String, default="published")
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow)

    cards = relationship("PublicCardModel", back_populates="cardset", cascade="all, delete-orphan")


class PublicCardModel(Base):
    __tablename__ = "public_cards"

    id = Column(String, primary_key=True, default=lambda: f"pcrd_{uuid.uuid4().hex[:8]}")
    cardset_id = Column(String, ForeignKey("public_cardsets.id"), nullable=False)
    front = Column(Text, nullable=False)
    back = Column(Text, nullable=False)
    evidence = Column(Text, default="")
    template_type = Column(String, default="definition")
    sort_order = Column(Integer, default=0)

    cardset = relationship("PublicCardsetModel", back_populates="cards")


# ── Explore Pydantic Schemas ──

class PublicCardsetResponse(BaseModel):
    id: str
    title: str
    description: str
    category: str
    tags: str
    card_count: int
    download_count: int
    author_name: str
    is_featured: bool
    created_at: str


class PublicCardResponse(BaseModel):
    id: str
    front: str
    back: str
    evidence: str
    template_type: str
    sort_order: int


class PublishRequest(BaseModel):
    session_id: str
    title: str
    description: str = ""
    category: str = "etc"
