from functools import lru_cache
from pathlib import Path
from typing import Any

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    openai_api_key: str = Field(default="", alias="OPENAI_API_KEY")
    openai_model: str = Field(default="gpt-5.1-mini", alias="OPENAI_MODEL")
    app_env: str = Field(default="development", alias="APP_ENV")
    allowed_origins: str = Field(default="*", alias="ALLOWED_ORIGINS")
    max_text_chars: int = Field(default=220_000, alias="MAX_TEXT_CHARS")
    chunk_chars: int = Field(default=12_000, alias="CHUNK_CHARS")
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


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
