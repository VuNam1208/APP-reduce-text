from __future__ import annotations

import asyncio
from dataclasses import dataclass

from openai import AsyncOpenAI, APIError, APITimeoutError, RateLimitError

from app.config import Settings
from app.schemas import SummarizeRequest, SummarizeResponse, SummaryLanguage


@dataclass(frozen=True)
class SummarizerError(Exception):
    message: str
    status_code: int = 500


class OpenAISummarizer:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._client: AsyncOpenAI | None = None
        self._openai_semaphore = asyncio.Semaphore(
            max(1, settings.openai_max_concurrency)
        )

    async def summarize(self, request: SummarizeRequest) -> SummarizeResponse:
        if not self._settings.openai_api_key:
            raise SummarizerError("Missing OPENAI_API_KEY in backend/.env.", 500)

        text = request.text.strip()
        chunks = split_into_chunks(text, self._settings.chunk_chars)
        partial_summaries: list[str] = []

        for chunk in chunks:
            partial_summaries.append(
                await self._call_openai(
                    text=chunk,
                    target_ratio=request.targetRatio,
                    language=request.language,
                    mode="chunk" if len(chunks) > 1 else "final",
                )
            )

        if len(partial_summaries) == 1:
            summary = partial_summaries[0]
        else:
            summary = await self._call_openai(
                text="\n\n".join(partial_summaries),
                target_ratio=request.targetRatio,
                language=request.language,
                mode="final",
            )

        return SummarizeResponse(
            summary=summary,
            chunks=len(chunks),
            model=self._settings.openai_model,
            originalWordCount=count_words(text),
            summaryWordCount=count_words(summary),
        )

    async def _call_openai(
        self,
        *,
        text: str,
        target_ratio: float,
        language: SummaryLanguage,
        mode: str,
    ) -> str:
        try:
            async with self._openai_semaphore:
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

    @property
    def _openai_client(self) -> AsyncOpenAI:
        if self._client is None:
            self._client = AsyncOpenAI(
                api_key=self._settings.openai_api_key,
                timeout=self._settings.request_timeout_seconds,
            )
        return self._client


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

    return "\n".join(
        [
            task,
            f"Target length: about {round(target_ratio * 100)}% of the original.",
            "",
            text,
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
