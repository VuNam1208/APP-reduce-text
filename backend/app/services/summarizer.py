from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import Any

from openai import AsyncOpenAI, APIError, APITimeoutError, RateLimitError

from app.config import Settings
from app.schemas import SummarizeRequest, SummarizeResponse, SummaryLanguage


@dataclass(frozen=True)
class SummarizerError(Exception):
    message: str
    status_code: int = 500


class AISummarizer:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._client: AsyncOpenAI | None = None
        self._gemini_client_instance: Any | None = None
        self._ai_semaphore = asyncio.Semaphore(max(1, settings.ai_max_concurrency))

    async def summarize(self, request: SummarizeRequest) -> SummarizeResponse:
        provider = self._settings.normalized_ai_provider
        if provider not in {"openai", "gemini"}:
            raise SummarizerError(
                "Unsupported AI_PROVIDER. Use 'openai' or 'gemini'.",
                500,
            )

        text = request.text.strip()
        chunks = split_into_chunks(text, self._settings.chunk_chars)
        partial_summaries: list[str] = []

        for chunk in chunks:
            partial_summaries.append(
                await self._call_provider(
                    provider=provider,
                    text=chunk,
                    target_ratio=request.targetRatio,
                    language=request.language,
                    mode="chunk" if len(chunks) > 1 else "final",
                )
            )

        if len(partial_summaries) == 1:
            summary = partial_summaries[0]
        else:
            summary = await self._call_provider(
                provider=provider,
                text="\n\n".join(partial_summaries),
                target_ratio=request.targetRatio,
                language=request.language,
                mode="final",
            )

        return SummarizeResponse(
            summary=summary,
            chunks=len(chunks),
            model=self._active_model_name(provider),
            originalWordCount=count_words(text),
            summaryWordCount=count_words(summary),
        )

    async def _call_provider(
        self,
        *,
        provider: str,
        text: str,
        target_ratio: float,
        language: SummaryLanguage,
        mode: str,
    ) -> str:
        if provider == "openai":
            return await self._call_openai(
                text=text,
                target_ratio=target_ratio,
                language=language,
                mode=mode,
            )

        return await self._call_gemini(
            text=text,
            target_ratio=target_ratio,
            language=language,
            mode=mode,
        )

    async def _call_openai(
        self,
        *,
        text: str,
        target_ratio: float,
        language: SummaryLanguage,
        mode: str,
    ) -> str:
        if not self._settings.openai_api_key:
            raise SummarizerError("Missing OPENAI_API_KEY in backend/.env.", 500)

        try:
            async with self._ai_semaphore:
                response = await self._openai_client.responses.create(
                    model=self._settings.openai_model,
                    input=[
                        {
                            "role": "system",
                            "content": build_system_prompt(language),
                        },
                        {
                            "role": "user",
                            "content": build_user_prompt(
                                text=text,
                                target_ratio=target_ratio,
                                mode=mode,
                            ),
                        },
                    ],
                )
        except RateLimitError as error:
            raise SummarizerError("OpenAI rate limit reached.", 429) from error
        except APITimeoutError as error:
            raise SummarizerError("OpenAI request timed out.", 504) from error
        except APIError as error:
            message = getattr(error, "message", None) or "OpenAI request failed."
            raise SummarizerError(message, 502) from error

        summary = response.output_text.strip()
        if not summary:
            raise SummarizerError("OpenAI returned an empty summary.", 502)

        return summary

    async def _call_gemini(
        self,
        *,
        text: str,
        target_ratio: float,
        language: SummaryLanguage,
        mode: str,
    ) -> str:
        if not self._settings.gemini_api_key:
            raise SummarizerError("Missing GEMINI_API_KEY in backend/.env.", 500)

        try:
            async with self._ai_semaphore:
                summary = await asyncio.to_thread(
                    self._call_gemini_sync,
                    text=text,
                    target_ratio=target_ratio,
                    language=language,
                    mode=mode,
                )
        except SummarizerError:
            raise
        except Exception as error:
            status_code = getattr(error, "status_code", None) or getattr(
                error,
                "code",
                None,
            )
            if isinstance(status_code, int):
                message = getattr(error, "message", None) or str(error)
                raise SummarizerError(message, status_code) from error

            raise SummarizerError(f"Gemini request failed: {error}", 502) from error

        if not summary:
            raise SummarizerError("Gemini returned an empty summary.", 502)

        return summary

    def _call_gemini_sync(
        self,
        *,
        text: str,
        target_ratio: float,
        language: SummaryLanguage,
        mode: str,
    ) -> str:
        try:
            from google.genai import types
        except ImportError as error:
            raise SummarizerError(
                "Missing google-genai. Run `pip install -r requirements.txt`.",
                500,
            ) from error

        response = self._gemini_client.models.generate_content(
            model=self._settings.gemini_model,
            contents=build_user_prompt(
                text=text,
                target_ratio=target_ratio,
                mode=mode,
            ),
            config=types.GenerateContentConfig(
                system_instruction=build_system_prompt(language),
            ),
        )
        return (getattr(response, "text", "") or "").strip()

    @property
    def _openai_client(self) -> AsyncOpenAI:
        if self._client is None:
            self._client = AsyncOpenAI(
                api_key=self._settings.openai_api_key,
                timeout=self._settings.request_timeout_seconds,
            )
        return self._client

    @property
    def _gemini_client(self) -> Any:
        if self._gemini_client_instance is None:
            try:
                from google import genai
            except ImportError as error:
                raise SummarizerError(
                    "Missing google-genai. Run `pip install -r requirements.txt`.",
                    500,
                ) from error

            self._gemini_client_instance = genai.Client(
                api_key=self._settings.gemini_api_key,
            )
        return self._gemini_client_instance

    def _active_model_name(self, provider: str) -> str:
        if provider == "openai":
            return f"openai:{self._settings.openai_model}"

        return f"gemini:{self._settings.gemini_model}"


def build_system_prompt(language: SummaryLanguage) -> str:
    language_instruction = {
        SummaryLanguage.auto: (
            "Keep the summary in the same language as the source text. "
            "If the source mixes English and Vietnamese, preserve the natural meaning."
        ),
        SummaryLanguage.english: "Write the summary in English.",
        SummaryLanguage.vietnamese: "Write the summary in Vietnamese.",
    }[language]

    return " ".join(
        [
            "You summarize documents for a commercial mobile app.",
            "Keep core ideas, decisions, numbers, names, and conclusions.",
            "Do not add facts that are not in the source.",
            "Use clear paragraphs or concise bullet points when helpful.",
            language_instruction,
        ]
    )


def build_user_prompt(*, text: str, target_ratio: float, mode: str) -> str:
    task = (
        "Summarize this document section. It will later be merged with other summaries."
        if mode == "chunk"
        else "Create the final polished summary for this document."
    )
    length_instruction = (
        "Target length: as short as possible because the user selected 0%. "
        "Keep only the single most essential idea."
        if target_ratio <= 0
        else f"Target length: about {round(target_ratio * 100)}% of the original."
    )

    return "\n".join(
        [
            task,
            length_instruction,
            "Return only the summary text. Do not ask for more input.",
            "",
            "<source_text>",
            text,
            "</source_text>",
        ]
    )


def split_into_chunks(text: str, max_chars: int) -> list[str]:
    paragraphs = [paragraph.strip() for paragraph in text.split("\n\n")]
    paragraphs = [paragraph for paragraph in paragraphs if paragraph]

    if not paragraphs:
        return [text]

    chunks: list[str] = []
    current = ""

    for paragraph in paragraphs:
        candidate = f"{current}\n\n{paragraph}" if current else paragraph
        if len(candidate) <= max_chars:
            current = candidate
            continue

        if current:
            chunks.append(current)
            current = ""

        if len(paragraph) <= max_chars:
            current = paragraph
        else:
            chunks.extend(split_long_paragraph(paragraph, max_chars))

    if current:
        chunks.append(current)

    return chunks


def split_long_paragraph(paragraph: str, max_chars: int) -> list[str]:
    return [
        paragraph[index : index + max_chars]
        for index in range(0, len(paragraph), max_chars)
    ]


def count_words(text: str) -> int:
    words = [word for word in text.strip().split() if word]
    return len(words)
