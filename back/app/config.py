from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    APP_ENV: str = "dev"

    # Claude Code CLI
    LLM_MODEL: str = "claude-sonnet-4-5-20250929"
    CLAUDE_TIMEOUT_SECONDS: int = 180

    # Database
    DATABASE_URL: str = "sqlite:///./decard.db"

    # CORS
    CORS_ORIGINS: str = "http://localhost:3000,http://localhost:8080"

    # Limits
    MAX_PDF_SIZE_MB: int = 10
    MAX_PAGES: int = 100

    # Kakao OAuth
    KAKAO_CLIENT_ID: str = ""
    KAKAO_CLIENT_SECRET: str = ""
    KAKAO_REDIRECT_URI: str = "https://decard-api.eupori.dev/api/v1/auth/kakao/callback"

    # JWT
    JWT_SECRET_KEY: str = "change-me-in-production"
    JWT_EXPIRE_HOURS: int = 168  # 7 days

    # Slack
    SLACK_WEBHOOK_URL: str = ""

    # Frontend
    FRONTEND_URL: str = "http://localhost:8080"

    # Concurrency
    MAX_CONCURRENT_CLI: int = 3
    MAX_CLI_PER_SESSION: int = 2
    MAX_CONCURRENT_SESSIONS: int = 5
    SESSION_TIMEOUT_MINUTES: int = 15

    model_config = {"env_file": ".env"}


settings = Settings()
