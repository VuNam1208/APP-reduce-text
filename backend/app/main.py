import asyncio

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.schemas import (
    HealthResponse,
    SummarizeRequest,
    SummarizeResponse,
    SummaryLanguage,
)
from app.services.document_reader import (
    DocumentProcessingError,
    extract_document_text,
)
from app.services.summarizer import OpenAISummarizer, SummarizerError

settings = get_settings()
UPLOAD_READ_CHUNK_BYTES = 1024 * 1024

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


@app.post("/api/summarize-file", response_model=SummarizeResponse)
async def summarize_file(
    targetRatio: float = Form(default=0.1, ge=0.05, le=0.6),
    language: SummaryLanguage = Form(default=SummaryLanguage.auto),
    enableOcr: bool = Form(default=True),
    fallbackText: str = Form(default=""),
    file: UploadFile | None = File(default=None),
) -> SummarizeResponse:
    if file is None and not fallbackText.strip():
        raise HTTPException(status_code=400, detail="File is required.")

    file_name = file.filename if file and file.filename else "document.txt"
    file_bytes = await read_upload_file(file) if file else b""

    try:
        document = await asyncio.wait_for(
            asyncio.to_thread(
                extract_document_text,
                file_name=file_name,
                data=file_bytes,
                fallback_text=fallbackText,
                enable_ocr=enableOcr,
                ocr_languages=settings.ocr_languages,
            ),
            timeout=settings.document_processing_timeout_seconds,
        )
    except DocumentProcessingError as error:
        raise HTTPException(status_code=error.status_code, detail=error.message) from error
    except asyncio.TimeoutError as error:
        raise HTTPException(
            status_code=504,
            detail="Document processing timed out.",
        ) from error

    text = document.text.strip()
    if not text:
        raise HTTPException(
            status_code=400,
            detail="This file does not contain readable text to summarize.",
        )

    if len(text) > settings.max_text_chars:
        raise HTTPException(
            status_code=413,
            detail=f"Text is too large. Limit is {settings.max_text_chars} characters.",
        )

    try:
        response = await summarizer.summarize(
            SummarizeRequest(
                text=text,
                targetRatio=targetRatio,
                language=language,
            )
        )
        response.fileName = document.name
        response.extractedText = document.text
        return response
    except SummarizerError as error:
        raise HTTPException(status_code=error.status_code, detail=error.message) from error


async def read_upload_file(file: UploadFile) -> bytes:
    data = bytearray()

    while True:
        chunk = await file.read(UPLOAD_READ_CHUNK_BYTES)
        if not chunk:
            break

        data.extend(chunk)
        if len(data) > settings.max_file_bytes:
            raise HTTPException(
                status_code=413,
                detail=f"File is too large. Limit is {settings.max_file_bytes} bytes.",
            )

    return bytes(data)
