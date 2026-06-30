from enum import Enum

from pydantic import BaseModel, Field


class SummaryLanguage(str, Enum):
    auto = "auto"
    english = "english"
    vietnamese = "vietnamese"


class SummaryQuality(str, Enum):
    fast = "fast"
    high = "high"


class SummarizeRequest(BaseModel):
    text: str = Field(min_length=1)
    targetRatio: float = Field(default=0.1, ge=0.0, le=1.0)
    language: SummaryLanguage = SummaryLanguage.auto
    quality: SummaryQuality = SummaryQuality.fast


class SummarizeResponse(BaseModel):
    summary: str
    chunks: int
    model: str
    originalWordCount: int
    summaryWordCount: int
    fileName: str | None = None
    extractedText: str | None = None


class HealthResponse(BaseModel):
    ok: bool
    environment: str
