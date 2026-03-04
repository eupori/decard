from sqlalchemy import create_engine, event, text, inspect
from sqlalchemy.orm import sessionmaker, DeclarativeBase

from .config import settings

engine = create_engine(
    settings.DATABASE_URL,
    connect_args={"check_same_thread": False} if "sqlite" in settings.DATABASE_URL else {},
)
SessionLocal = sessionmaker(bind=engine)


@event.listens_for(engine, "connect")
def _set_sqlite_pragma(dbapi_conn, connection_record):
    cursor = dbapi_conn.cursor()
    cursor.execute("PRAGMA journal_mode=WAL")
    cursor.execute("PRAGMA busy_timeout=5000")
    cursor.execute("PRAGMA synchronous=NORMAL")
    cursor.close()


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def create_tables():
    Base.metadata.create_all(bind=engine)
    _migrate_device_id()
    _migrate_users_table()
    _migrate_folders()
    _migrate_source_type()
    _migrate_card_reviews()
    _migrate_public_cardsets()
    _migrate_session_progress()
    _migrate_users_auth_providers()


def _migrate_device_id():
    """Add device_id column to sessions table if missing."""
    insp = inspect(engine)
    columns = [c["name"] for c in insp.get_columns("sessions")]
    if "device_id" not in columns:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE sessions ADD COLUMN device_id VARCHAR DEFAULT 'anonymous'"))
            conn.execute(text("CREATE INDEX IF NOT EXISTS ix_sessions_device_id ON sessions (device_id)"))


def _migrate_users_table():
    """Create users table + add user_id column to sessions if missing."""
    insp = inspect(engine)

    # users 테이블은 create_all에서 이미 생성됨 (Base.metadata)
    # sessions.user_id 컬럼만 마이그레이션
    columns = [c["name"] for c in insp.get_columns("sessions")]
    if "user_id" not in columns:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE sessions ADD COLUMN user_id VARCHAR"))
            conn.execute(text("CREATE INDEX IF NOT EXISTS ix_sessions_user_id ON sessions (user_id)"))


def _migrate_folders():
    """Add folder_id, display_name columns to sessions if missing."""
    insp = inspect(engine)

    # folders 테이블은 create_all에서 이미 생성됨
    columns = [c["name"] for c in insp.get_columns("sessions")]
    if "folder_id" not in columns:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE sessions ADD COLUMN folder_id VARCHAR"))
            conn.execute(text("CREATE INDEX IF NOT EXISTS ix_sessions_folder_id ON sessions (folder_id)"))
    if "display_name" not in columns:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE sessions ADD COLUMN display_name VARCHAR"))


def _migrate_source_type():
    """Add source_type column to sessions table if missing."""
    insp = inspect(engine)
    columns = [c["name"] for c in insp.get_columns("sessions")]
    if "source_type" not in columns:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE sessions ADD COLUMN source_type VARCHAR DEFAULT 'pdf'"))


def _migrate_card_reviews():
    """card_reviews 테이블은 create_all에서 생성됨. 인덱스만 보장."""
    insp = inspect(engine)
    if "card_reviews" not in insp.get_table_names():
        return  # create_all에서 이미 생성
    # 추가 인덱스 (이미 모델에 정의되어 있으므로 보통 불필요하지만, 안전장치)
    with engine.begin() as conn:
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_card_reviews_card_id ON card_reviews (card_id)"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_card_reviews_user_id ON card_reviews (user_id)"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_card_reviews_device_id ON card_reviews (device_id)"))


def _migrate_public_cardsets():
    """public_cardsets, public_cards 테이블은 create_all에서 생성됨. 인덱스만 보장."""
    insp = inspect(engine)
    if "public_cardsets" not in insp.get_table_names():
        return
    with engine.begin() as conn:
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_public_cardsets_category ON public_cardsets (category)"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_public_cardsets_status ON public_cardsets (status)"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_public_cards_cardset_id ON public_cards (cardset_id)"))


def _migrate_session_progress():
    """Add error_message, progress, total_chunks, completed_chunks to sessions."""
    insp = inspect(engine)
    columns = [c["name"] for c in insp.get_columns("sessions")]
    with engine.begin() as conn:
        if "error_message" not in columns:
            conn.execute(text("ALTER TABLE sessions ADD COLUMN error_message VARCHAR"))
        if "progress" not in columns:
            conn.execute(text("ALTER TABLE sessions ADD COLUMN progress INTEGER DEFAULT 0"))
        if "total_chunks" not in columns:
            conn.execute(text("ALTER TABLE sessions ADD COLUMN total_chunks INTEGER DEFAULT 0"))
        if "completed_chunks" not in columns:
            conn.execute(text("ALTER TABLE sessions ADD COLUMN completed_chunks INTEGER DEFAULT 0"))


def _migrate_users_auth_providers():
    """Add google_id, apple_id, email, auth_provider to users. Make kakao_id nullable."""
    insp = inspect(engine)
    if "users" not in insp.get_table_names():
        return
    columns = [c["name"] for c in insp.get_columns("users")]
    with engine.begin() as conn:
        if "google_id" not in columns:
            conn.execute(text("ALTER TABLE users ADD COLUMN google_id VARCHAR"))
            conn.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS ix_users_google_id ON users (google_id)"))
        if "apple_id" not in columns:
            conn.execute(text("ALTER TABLE users ADD COLUMN apple_id VARCHAR"))
            conn.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS ix_users_apple_id ON users (apple_id)"))
        if "email" not in columns:
            conn.execute(text("ALTER TABLE users ADD COLUMN email VARCHAR"))
        if "auth_provider" not in columns:
            conn.execute(text("ALTER TABLE users ADD COLUMN auth_provider VARCHAR DEFAULT 'kakao'"))

    # kakao_id nullable 처리: SQLite는 ALTER COLUMN 미지원이라 테이블 재생성 필요
    # 하지만 기존 데이터 모두 kakao_id가 있으므로, 새 유저만 nullable이면 됨
    # SQLAlchemy 모델에서 nullable=True로 이미 변경했으므로 새 테이블은 문제없음
    # 기존 테이블은 NOT NULL 제약이 남아있지만, INSERT 시 NULL을 넣으면
    # SQLite는 기본적으로 NOT NULL 제약을 무시하지 않음
    # → 테이블 재생성 마이그레이션 필요
    _recreate_users_table_if_needed(conn, columns)


def _recreate_users_table_if_needed(conn, columns):
    """Recreate users table to make kakao_id nullable (SQLite limitation)."""
    if "auth_provider" in columns:
        # 이미 마이그레이션 완료된 상태면 스킵 (auth_provider가 원래부터 있었으면 새 스키마)
        return

    # 기존 데이터 백업 → 새 테이블 생성 → 데이터 복원
    conn.execute(text("ALTER TABLE users RENAME TO users_old"))
    conn.execute(text("""
        CREATE TABLE users (
            id VARCHAR PRIMARY KEY,
            kakao_id VARCHAR,
            google_id VARCHAR,
            apple_id VARCHAR,
            email VARCHAR,
            auth_provider VARCHAR DEFAULT 'kakao',
            nickname VARCHAR DEFAULT '',
            profile_image VARCHAR DEFAULT '',
            device_id VARCHAR,
            created_at DATETIME
        )
    """))
    conn.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS ix_users_kakao_id ON users (kakao_id)"))
    conn.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS ix_users_google_id ON users (google_id)"))
    conn.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS ix_users_apple_id ON users (apple_id)"))
    conn.execute(text("CREATE INDEX IF NOT EXISTS ix_users_device_id ON users (device_id)"))
    conn.execute(text("""
        INSERT INTO users (id, kakao_id, nickname, profile_image, device_id, created_at, auth_provider)
        SELECT id, kakao_id, nickname, profile_image, device_id, created_at, 'kakao'
        FROM users_old
    """))
    conn.execute(text("DROP TABLE users_old"))
