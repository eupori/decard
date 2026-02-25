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
