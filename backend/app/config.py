from functools import lru_cache
from pathlib import Path
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    ai_provider: str = Field(default="openai", alias="AI_PROVIDER")
    ai_max_concurrency: int = Field(default=8, alias="AI_MAX_CONCURRENCY")
    ai_max_output_tokens: int = Field(default=8192, alias="AI_MAX_OUTPUT_TOKENS")
    openai_min_request_interval_seconds: float = Field(
        default=0,
        alias="OPENAI_MIN_REQUEST_INTERVAL_SECONDS",
    )
    openai_api_key: str = Field(default="", alias="OPENAI_API_KEY")
    openai_model: str = Field(default="gpt-5.1-mini", alias="OPENAI_MODEL")
    openai_model_high: str = Field(default="gpt-4o", alias="OPENAI_MODEL_HIGH")
    gemini_min_request_interval_seconds: float = Field(
        default=4.5,
        alias="GEMINI_MIN_REQUEST_INTERVAL_SECONDS",
    )
    gemini_api_key: str = Field(default="", alias="GEMINI_API_KEY")
    gemini_model: str = Field(
        default="gemini-2.5-flash-lite",
        alias="GEMINI_MODEL",
    )
    gemini_model_high: str = Field(
        default="gemini-2.5-pro",
        alias="GEMINI_MODEL_HIGH",
    )
    app_env: str = Field(default="development", alias="APP_ENV")
    allowed_origins: str = Field(default="*", alias="ALLOWED_ORIGINS")
    trust_proxy_headers: bool = Field(default=False, alias="TRUST_PROXY_HEADERS")
    web_concurrency: int = Field(default=2, alias="WEB_CONCURRENCY")
    max_file_bytes: int = Field(default=25 * 1024 * 1024, alias="MAX_FILE_BYTES")
    max_text_chars: int = Field(default=220_000, alias="MAX_TEXT_CHARS")
    chunk_chars: int = Field(default=12_000, alias="CHUNK_CHARS")
    ocr_languages: str = Field(default="eng+vie", alias="OCR_LANGUAGES")
    document_processing_timeout_seconds: float = Field(
        default=120,
        alias="DOCUMENT_PROCESSING_TIMEOUT_SECONDS",
    )
    request_timeout_seconds: float = Field(
        default=90,
        alias="REQUEST_TIMEOUT_SECONDS",
    )

    model_config = SettingsConfigDict(
        env_file=Path(__file__).resolve().parents[1] / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
        populate_by_name=True,
    )

    @property
    def cors_origins(self) -> list[str]:
        origins = [item.strip() for item in self.allowed_origins.split(",")]
        return [origin for origin in origins if origin]

    @property
    def normalized_ai_provider(self) -> str:
        return self.ai_provider.strip().lower()


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
