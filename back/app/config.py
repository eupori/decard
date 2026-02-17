from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    APP_ENV: str = "dev"

    # Claude API
    ANTHROPIC_API_KEY: str = ""
    LLM_MODEL: str = "claude-sonnet-4-5-20250929"
    LLM_MAX_TOKENS: int = 8000

    # Database
    DATABASE_URL: str = "sqlite:///./decard.db"

    # CORS
    CORS_ORIGINS: str = "http://localhost:3000,http://localhost:8080"

    # Limits
    MAX_PDF_SIZE_MB: int = 10
    MAX_PAGES: int = 100

    model_config = {"env_file": ".env"}


settings = Settings()
