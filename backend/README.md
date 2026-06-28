# Text Summarizer Python Backend

FastAPI backend for the Flutter Text Summarizer app. The mobile app sends extracted text here, and this server calls OpenAI so the API key never ships inside Android or iOS builds.

## Structure

```text
backend/
  app/
    main.py                 FastAPI app and routes
    schemas.py              API request/response models
    config.py               .env settings
    services/document_reader.py  TXT/PDF/DOCX/image extraction and OCR
    services/summarizer.py  OpenAI summarization logic
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
OPENAI_API_KEY=...
OPENAI_MODEL=gpt-5.1-mini
PORT=8787
WEB_CONCURRENCY=2
MAX_FILE_BYTES=26214400
OPENAI_MAX_CONCURRENCY=8
```

Use another OpenAI model if your account or product cost target needs it.

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
  "targetRatio": 0.1,
  "language": "auto"
}
```

`language` can be `auto`, `english`, or `vietnamese`.

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
targetRatio: 0.1
language: auto | english | vietnamese
enableOcr: true | false
fallbackText: optional plain text fallback
```

The backend extracts and cleans the document text, then calls OpenAI.

## Flutter integration

Run Flutter with the backend URL:

```powershell
flutter run --dart-define=SUMMARY_API_URL=http://10.0.2.2:8787
```

`10.0.2.2` is the Android emulator address for your computer. For a real phone, replace it with your computer LAN IP while testing, then use your production backend URL after deployment.

If `SUMMARY_API_URL` is not provided, the Flutter app keeps using the local summarizer fallback.

## Production notes

- Keep `OPENAI_API_KEY` only on the backend.
- Add authentication before public launch.
- Add per-user quota/rate limits before paid plans.
- Store files only if the product needs history; otherwise delete source text after summarization.
- Use PostgreSQL for users, subscriptions, and summary history.
- Use Redis/Celery later for very large files or background jobs.
- OCR requires Tesseract. The Dockerfile installs English and Vietnamese OCR data.

## Scaling notes

- Run multiple workers in production with `WEB_CONCURRENCY`.
- Keep `MAX_FILE_BYTES` strict so one upload cannot exhaust memory.
- `OPENAI_MAX_CONCURRENCY` caps simultaneous OpenAI calls per worker to reduce rate-limit spikes.
- PDF/DOCX/OCR extraction runs in a worker thread so the FastAPI event loop can keep serving other users.
- For serious paid traffic, put the API behind a load balancer and use Redis-backed rate limits plus a queue for slow OCR jobs.

## Docker

```powershell
docker build -t text-summarizer-backend .
docker run --env-file .env -p 8787:8787 text-summarizer-backend
```
