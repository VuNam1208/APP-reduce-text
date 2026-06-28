from enum import Enum

from pydantic import BaseModel, Field


class SummaryLanguage(str, Enum):
    auto = "auto"
    english = "english"
    vietnamese = "vietnamese"


class SummarizeRequest(BaseModel):
    text: str = Field(min_length=1)
    targetRatio: float = Field(default=0.1, ge=0.05, le=0.6)
    language: SummaryLanguage = SummaryLanguage.auto


class SummarizeResponse(BaseModel):
    summary: str
    chunks: int
    model: str
    originalWordCount: int
    summaryWordCount: int


class HealthResponse(BaseModel):
    ok: bool
    environment: str
