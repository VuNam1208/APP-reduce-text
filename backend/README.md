# Text Summarizer Python Backend

FastAPI backend for the Flutter Text Summarizer app. The mobile app sends extracted text here, and this server calls the configured AI provider so API keys never ship inside Android or iOS builds.

## Structure

```text
backend/
  app/
    main.py                 FastAPI app and routes
    schemas.py              API request/response models
    config.py               .env settings
    services/document_reader.py  TXT/PDF/DOCX/image extraction and OCR
    services/summarizer.py  OpenAI/Gemini summarization logic
  requirements.txt
  Dockerfile
  .env.example
```

## Setup

1. Create a virtual environment:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

2. Install dependencies:

```powershell
pip install -r requirements.txt
```

3. Copy the environment file:

```powershell
copy .env.example .env
```

4. Edit `.env` and set:

```env
AI_PROVIDER=openai
AI_MAX_CONCURRENCY=8
OPENAI_API_KEY=...
OPENAI_MODEL=gpt-5.1-mini
GEMINI_API_KEY=...
GEMINI_MODEL=gemini-3.1-flash-lite
PORT=8787
WEB_CONCURRENCY=2
MAX_FILE_BYTES=26214400
```

Use `AI_PROVIDER=openai` or `AI_PROVIDER=gemini`. Only the selected provider's API key is required.

5. Run the server:

```powershell
uvicorn app.main:app --reload --host 0.0.0.0 --port 8787
```

## API

### Health check

```http
GET /health
```

### Summarize text

```http
POST /api/summarize
Content-Type: application/json
```

```json
{
  "text": "Long document text here...",
  "targetRatio": 0.2,
  "language": "auto"
}
```

`targetRatio` can be `0.0` to `1.0`, where `0.2` means about 20% of the original length. `language` can be `auto`, `english`, or `vietnamese`.

Response:

```json
{
  "summary": "...",
  "chunks": 1,
  "model": "...",
  "originalWordCount": 1200,
  "summaryWordCount": 140
}
```

### Summarize a file

```http
POST /api/summarize-file
Content-Type: multipart/form-data
```

Fields:

```text
file: TXT/PDF/DOCX/JPG/PNG file
targetRatio: 0.2
language: auto | english | vietnamese
enableOcr: true | false
fallbackText: optional plain text fallback
```

The backend extracts and cleans the document text, then calls the configured AI provider.

## Flutter integration

Create a Flutter build env file at the project root:

```powershell
copy flutter.env.example flutter.env
```

Edit `flutter.env`:

```env
SUMMARY_API_URL=http://10.11.55.255:8787
```

Then run or build the app:

```powershell
flutter run --dart-define-from-file=flutter.env
flutter build apk --debug --dart-define-from-file=flutter.env
```

For the Android emulator, use `http://10.0.2.2:8787`. For a real phone, use your computer LAN IP while testing. For production, use your HTTPS backend URL.

If `SUMMARY_API_URL` is not provided, the Flutter app will show a backend configuration error.

## Production notes

- Keep AI provider keys only on the backend.
- Add authentication before public launch.
- Add per-user quota/rate limits before paid plans.
- Store files only if the product needs history; otherwise delete source text after summarization.
- Use PostgreSQL for users, subscriptions, and summary history.
- Use Redis/Celery later for very large files or background jobs.
- OCR requires Tesseract. The Dockerfile installs English and Vietnamese OCR data.

## Scaling notes

- Run multiple workers in production with `WEB_CONCURRENCY`.
- Keep `MAX_FILE_BYTES` strict so one upload cannot exhaust memory.
- `AI_MAX_CONCURRENCY` caps simultaneous AI calls per worker to reduce rate-limit spikes.
- PDF/DOCX/OCR extraction runs in a worker thread so the FastAPI event loop can keep serving other users.
- For serious paid traffic, put the API behind a load balancer and use Redis-backed rate limits plus a queue for slow OCR jobs.

## Docker

```powershell
docker build -t text-summarizer-backend .
docker run --env-file .env -p 8787:8787 text-summarizer-backend
```
