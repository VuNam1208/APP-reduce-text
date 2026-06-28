from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.schemas import HealthResponse, SummarizeRequest, SummarizeResponse
from app.services.summarizer import OpenAISummarizer, SummarizerError

settings = get_settings()

app = FastAPI(
    title="Text Summarizer API",
    version="1.0.0",
    description="Commercial backend API for AI document summarization.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

summarizer = OpenAISummarizer(settings)


@app.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    return HealthResponse(ok=True, environment=settings.app_env)


@app.post("/api/summarize", response_model=SummarizeResponse)
async def summarize(request: SummarizeRequest) -> SummarizeResponse:
    text = request.text.strip()

    if not text:
        raise HTTPException(status_code=400, detail="Text is required.")

    if len(text) > settings.max_text_chars:
        raise HTTPException(
            status_code=413,
            detail=f"Text is too large. Limit is {settings.max_text_chars} characters.",
        )

    try:
        return await summarizer.summarize(request)
    except SummarizerError as error:
        raise HTTPException(status_code=error.status_code, detail=error.message) from error
