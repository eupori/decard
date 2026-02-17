import uuid
from datetime import datetime

from sqlalchemy import Column, String, Integer, Text, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from pydantic import BaseModel
from typing import List, Optional

from .database import Base


# ──────────────────────────────────────
# SQLAlchemy Models
# ──────────────────────────────────────

class SessionModel(Base):
    __tablename__ = "sessions"

    id = Column(String, primary_key=True, default=lambda: f"ses_{uuid.uuid4().hex[:10]}")
    filename = Column(String, nullable=False)
    page_count = Column(Integer, default=0)
    template_type = Column(String, default="definition")
    status = Column(String, default="processing")  # processing / completed / failed
    created_at = Column(DateTime, default=datetime.utcnow)

    cards = relationship("CardModel", back_populates="session", cascade="all, delete-orphan")


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
