from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from openai import AsyncOpenAI, APIError, APITimeoutError, RateLimitError

from app.config import Settings
from app.schemas import SummarizeRequest, SummarizeResponse, SummaryLanguage, SummaryQuality

MIN_FINAL_TARGET_COVERAGE = 0.98
MAX_LENGTH_ADJUSTMENT_ATTEMPTS = 3
MAX_FINAL_TARGET_OVERAGE = 1.1
OUTPUT_TOKEN_TO_WORD_RATIO = 2.2
logger = logging.getLogger("text_summarizer.summarizer")


@dataclass(frozen=True)
class SummarizerError(Exception):
    message: str
    status_code: int = 500


class AISummarizer:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._client: AsyncOpenAI | None = None
        self._ai_semaphore = asyncio.Semaphore(max(1, settings.ai_max_concurrency))
        self._provider_rate_limit_lock = asyncio.Lock()
        self._last_provider_request_at: dict[str, float] = {}

    async def summarize(self, request: SummarizeRequest) -> SummarizeResponse:
        provider = self._settings.normalized_ai_provider
        if provider not in {"openai", "gemini"}:
            raise SummarizerError(
                "Unsupported AI_PROVIDER. Use 'openai' or 'gemini'.",
                500,
            )

        text = request.text.strip()
        original_word_count = count_words(text)
        final_target_words = target_word_count(
            original_word_count,
            request.targetRatio,
        )
        chunks = split_into_chunks(text, self._settings.chunk_chars)
        is_chunked = len(chunks) > 1
        use_sectioned_output = should_use_sectioned_output(
            is_chunked=is_chunked,
            target_words=final_target_words,
            max_output_tokens=self._settings.ai_max_output_tokens,
        )
        chunk_target_ratio = chunk_note_ratio(request.targetRatio)

        logger.info(
            "Summarizing document: original_words=%s target_ratio=%.2f target_words=%s chunks=%s sectioned=%s quality=%s",
            original_word_count,
            request.targetRatio,
            final_target_words,
            len(chunks),
            use_sectioned_output,
            request.quality.value,
        )

        async def summarize_chunk(chunk: str) -> str:
            chunk_word_count = count_words(chunk)
            if use_sectioned_output:
                call_ratio = request.targetRatio
                call_target_words = target_word_count(
                    chunk_word_count,
                    request.targetRatio,
                )
                call_mode = "section"
            elif is_chunked:
                call_ratio = chunk_target_ratio
                call_target_words = target_word_count(
                    chunk_word_count,
                    chunk_target_ratio,
                )
                call_mode = "chunk"
            else:
                call_ratio = request.targetRatio
                call_target_words = final_target_words
                call_mode = "final"

            call_original_word_count = chunk_word_count if is_chunked else original_word_count
            section_summary = await self._call_provider(
                provider=provider,
                text=chunk,
                target_ratio=call_ratio,
                target_words=call_target_words,
                original_word_count=call_original_word_count,
                language=request.language,
                quality=request.quality,
                mode=call_mode,
            )
            if use_sectioned_output:
                section_summary = await self._expand_summary_if_too_short(
                    provider=provider,
                    summary=section_summary,
                    source_material=chunk,
                    target_ratio=call_ratio,
                    target_words=call_target_words,
                    original_word_count=call_original_word_count,
                    language=request.language,
                    quality=request.quality,
                )
            return section_summary

        partial_summaries = await asyncio.gather(
            *(summarize_chunk(chunk) for chunk in chunks)
        )

        if use_sectioned_output:
            summary = join_section_summaries(partial_summaries)
        elif len(partial_summaries) == 1:
            summary = partial_summaries[0]
        else:
            summary = await self._call_provider(
                provider=provider,
                text="\n\n".join(partial_summaries),
                target_ratio=request.targetRatio,
                target_words=final_target_words,
                original_word_count=original_word_count,
                language=request.language,
                quality=request.quality,
                mode="final",
            )

        if not use_sectioned_output:
            summary = await self._expand_summary_if_too_short(
                provider=provider,
                summary=summary,
                source_material="\n\n".join(partial_summaries) if is_chunked else text,
                target_ratio=request.targetRatio,
                target_words=final_target_words,
                original_word_count=original_word_count,
                language=request.language,
                quality=request.quality,
            )

        summary_word_count = count_words(summary)
        logger.info(
            "Summary complete: original_words=%s summary_words=%s target_words=%s chunks=%s",
            original_word_count,
            summary_word_count,
            final_target_words,
            len(chunks),
        )

        return SummarizeResponse(
            summary=summary,
            chunks=len(chunks),
            model=self._active_model_name(provider, request.quality),
            originalWordCount=original_word_count,
            summaryWordCount=summary_word_count,
        )

    async def _call_provider(
        self,
        *,
        provider: str,
        text: str,
        target_ratio: float,
        target_words: int,
        original_word_count: int,
        language: SummaryLanguage,
        quality: SummaryQuality,
        mode: str,
    ) -> str:
        if provider == "openai":
            return await self._call_openai(
                text=text,
                target_ratio=target_ratio,
                target_words=target_words,
                original_word_count=original_word_count,
                language=language,
                mode=mode,
            )

        return await self._call_gemini(
            text=text,
            target_ratio=target_ratio,
            target_words=target_words,
            original_word_count=original_word_count,
            language=language,
            quality=quality,
            mode=mode,
        )

    async def _call_openai(
        self,
        *,
        text: str,
        target_ratio: float,
        target_words: int,
        original_word_count: int,
        language: SummaryLanguage,
        mode: str,
    ) -> str:
        if not self._settings.openai_api_key:
            raise SummarizerError("Missing OPENAI_API_KEY in backend/.env.", 500)

        try:
            async with self._ai_semaphore:
                await self._wait_for_provider_rate_limit("openai")
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
                                target_words=target_words,
                                original_word_count=original_word_count,
                                mode=mode,
                            ),
                        },
                    ],
                    max_output_tokens=output_token_budget(
                        target_words,
                        self._settings.ai_max_output_tokens,
                    ),
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
        target_words: int,
        original_word_count: int,
        language: SummaryLanguage,
        quality: SummaryQuality,
        mode: str,
    ) -> str:
        if not self._settings.gemini_api_key:
            raise SummarizerError("Missing GEMINI_API_KEY in backend/.env.", 500)

        try:
            async with self._ai_semaphore:
                await self._wait_for_provider_rate_limit("gemini")
                summary = await asyncio.to_thread(
                    self._call_gemini_sync,
                    text=text,
                    target_ratio=target_ratio,
                    target_words=target_words,
                    original_word_count=original_word_count,
                    language=language,
                    quality=quality,
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
        target_words: int,
        original_word_count: int,
        language: SummaryLanguage,
        quality: SummaryQuality,
        mode: str,
    ) -> str:
        try:
            from google import genai
            from google.genai import types
        except ImportError as error:
            raise SummarizerError(
                "Missing google-genai. Run `pip install -r requirements.txt`.",
                500,
            ) from error

        model = self._resolve_gemini_model(quality)
        client = genai.Client(api_key=self._settings.gemini_api_key)
        try:
            response = client.models.generate_content(
                model=model,
                contents=build_user_prompt(
                    text=text,
                    target_ratio=target_ratio,
                    target_words=target_words,
                    original_word_count=original_word_count,
                    mode=mode,
                ),
                config=types.GenerateContentConfig(
                    system_instruction=build_system_prompt(language),
                    max_output_tokens=output_token_budget(
                        target_words,
                        self._settings.ai_max_output_tokens,
                    ),
                ),
            )
            return (getattr(response, "text", "") or "").strip()
        finally:
            client.close()

    @property
    def _openai_client(self) -> AsyncOpenAI:
        if self._client is None:
            self._client = AsyncOpenAI(
                api_key=self._settings.openai_api_key,
                timeout=self._settings.request_timeout_seconds,
            )
        return self._client

    async def _wait_for_provider_rate_limit(self, provider: str) -> None:
        interval = self._provider_min_request_interval(provider)
        if interval <= 0:
            return

        async with self._provider_rate_limit_lock:
            loop = asyncio.get_running_loop()
            now = loop.time()
            last_request_at = self._last_provider_request_at.get(provider, 0)
            wait_seconds = last_request_at + interval - now

            if wait_seconds > 0:
                await asyncio.sleep(wait_seconds)

            self._last_provider_request_at[provider] = loop.time()

    def _provider_min_request_interval(self, provider: str) -> float:
        if provider == "gemini":
            return max(0, self._settings.gemini_min_request_interval_seconds)

        if provider == "openai":
            return max(0, self._settings.openai_min_request_interval_seconds)

        return 0

    def _resolve_gemini_model(self, quality: SummaryQuality) -> str:
        if quality == SummaryQuality.high:
            return self._settings.gemini_model_high

        return self._settings.gemini_model

    def _active_model_name(self, provider: str, quality: SummaryQuality) -> str:
        if provider == "openai":
            return f"openai:{self._settings.openai_model}"

        return f"gemini:{self._resolve_gemini_model(quality)}"

    async def _expand_summary_if_too_short(
        self,
        *,
        provider: str,
        summary: str,
        source_material: str,
        target_ratio: float,
        target_words: int,
        original_word_count: int,
        language: SummaryLanguage,
        quality: SummaryQuality,
    ) -> str:
        if not should_expand_summary(summary, target_words):
            return summary

        best_summary = summary
        best_word_count = count_words(summary)

        for _ in range(MAX_LENGTH_ADJUSTMENT_ATTEMPTS):
            candidate = await self._call_provider(
                provider=provider,
                text=build_expansion_source(
                    current_summary=best_summary,
                    source_material=source_material,
                ),
                target_ratio=target_ratio,
                target_words=target_words,
                original_word_count=original_word_count,
                language=language,
                quality=quality,
                mode="expand",
            )
            candidate_word_count = count_words(candidate)

            if candidate_word_count <= best_word_count:
                break

            best_summary = candidate
            best_word_count = candidate_word_count

            if not should_expand_summary(best_summary, target_words):
                break

        return best_summary


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


def build_user_prompt(
    *,
    text: str,
    target_ratio: float,
    target_words: int,
    original_word_count: int,
    mode: str,
) -> str:
    if mode == "chunk":
        task = (
            "Extract detailed notes from this document section. "
            "These notes will be merged later; do not compress aggressively yet."
        )
    elif mode == "section":
        task = (
            "Create this section's part of the final summary. "
            "This output will be concatenated with other section summaries, so cover this section in detail and do not compress aggressively."
        )
    elif mode == "expand":
        task = (
            "The current summary is too short. Revise and expand it using the source material. "
            "Keep the same meaning, add back important details, and do not stop early."
        )
    else:
        task = "Create the final polished summary for this document."

    if target_ratio <= 0:
        length_instruction = (
            "The user selected 0%. Return the shortest useful summary possible, "
            "keeping only the single most essential idea."
        )
    elif mode == "chunk":
        length_instruction = (
            f"For this intermediate section, keep detailed notes around {target_words} words. "
            "The final summary length will be controlled after all sections are merged."
        )
    else:
        minimum_words = minimum_target_words(target_words)
        maximum_words = maximum_target_words(target_words)
        length_instruction = (
            f"The user selected {round(target_ratio * 100)}% of the original document. "
            f"The original document has about {original_word_count} words, so the final summary should be about {target_words} words. "
            f"This is a hard length requirement: write between {minimum_words} and {maximum_words} words. "
            "This percentage is based on the original document length, not on the current prompt or intermediate notes. "
            "Prefer being slightly longer over being too short, and never return a very short overview when a detailed summary is requested."
        )

    return "\n".join(
        [
            task,
            length_instruction,
            "Do not be overly concise. Include enough concrete details, names, numbers, decisions, arguments, evidence, and supporting points to reach the requested length.",
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


def should_expand_summary(summary: str, target_words: int) -> bool:
    if target_words < 25:
        return False

    return count_words(summary) < minimum_target_words(target_words)


def minimum_target_words(target_words: int) -> int:
    return max(1, round(target_words * MIN_FINAL_TARGET_COVERAGE))


def maximum_target_words(target_words: int) -> int:
    return max(1, round(target_words * MAX_FINAL_TARGET_OVERAGE))


def build_expansion_source(*, current_summary: str, source_material: str) -> str:
    return "\n\n".join(
        [
            "<current_summary>",
            current_summary,
            "</current_summary>",
            "<source_material>",
            source_material,
            "</source_material>",
        ]
    )


def target_word_count(original_word_count: int, target_ratio: float) -> int:
    if original_word_count <= 0 or target_ratio <= 0:
        return 0

    return max(1, min(original_word_count, round(original_word_count * target_ratio)))


def chunk_note_ratio(target_ratio: float) -> float:
    if target_ratio <= 0:
        return 0.6

    return min(1.0, max(0.6, target_ratio * 2))


def output_token_budget(target_words: int, max_output_tokens: int) -> int:
    if target_words <= 0:
        return min(max_output_tokens, 512)

    requested_tokens = max(1024, round(target_words * OUTPUT_TOKEN_TO_WORD_RATIO))
    return max(512, min(max_output_tokens, requested_tokens))


def should_use_sectioned_output(
    *,
    is_chunked: bool,
    target_words: int,
    max_output_tokens: int,
) -> bool:
    if not is_chunked or target_words <= 0:
        return False

    return target_words > single_call_word_capacity(max_output_tokens)


def single_call_word_capacity(max_output_tokens: int) -> int:
    return max(1200, round((max_output_tokens / OUTPUT_TOKEN_TO_WORD_RATIO) * 0.85))


def join_section_summaries(sections: list[str]) -> str:
    return "\n\n".join(section.strip() for section in sections if section.strip())


def count_words(text: str) -> int:
    words = [word for word in text.strip().split() if word]
    return len(words)
