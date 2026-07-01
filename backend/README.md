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
  nginx/
    nginx.conf              Main Nginx config
    conf.d/app.conf         Reverse proxy to FastAPI (HTTP)
    conf.d/ssl.conf.example HTTPS template for production
  requirements.txt
  Dockerfile
  docker-compose.yml        Production: app + Nginx
  docker-compose.dev.yml    Local Docker without Nginx
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
AI_MAX_OUTPUT_TOKENS=8192
OPENAI_MIN_REQUEST_INTERVAL_SECONDS=0
OPENAI_API_KEY=...
OPENAI_MODEL=gpt-5.1-mini
OPENAI_MODEL_HIGH=gpt-4o
GEMINI_MIN_REQUEST_INTERVAL_SECONDS=4.5
GEMINI_API_KEY=...
GEMINI_MODEL=gemini-2.5-flash-lite
GEMINI_MODEL_HIGH=gemini-2.5-pro
PORT=8787
WEB_CONCURRENCY=2
TRUST_PROXY_HEADERS=false
MAX_FILE_BYTES=26214400
```

Use `AI_PROVIDER=openai` or `AI_PROVIDER=gemini`. Only the selected provider's API key is required.

For production behind Nginx, set:

```env
APP_ENV=production
ALLOWED_ORIGINS=https://yourdomain.com
TRUST_PROXY_HEADERS=true
```

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
  "language": "auto",
  "quality": "fast"
}
```

`targetRatio` can be `0.0` to `1.0`, where `0.2` means about 20% of the original length. `language` can be `auto`, `english`, or `vietnamese`. `quality` can be `fast` (economical model) or `high` (premium model). With `AI_PROVIDER=gemini`, fast uses `GEMINI_MODEL` and high uses `GEMINI_MODEL_HIGH`. With `AI_PROVIDER=openai`, fast uses `OPENAI_MODEL` and high uses `OPENAI_MODEL_HIGH`.

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
quality: fast | high
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

For the Android emulator, use `http://10.0.2.2:8787`. For a real phone, use your computer LAN IP while testing. For production, point `SUMMARY_API_URL` at your HTTPS Nginx URL, for example `https://api.yourdomain.com`.

## Docker + Nginx (production)

The recommended commercial layout is:

```text
Client (Flutter) -> Nginx (80/443, SSL) -> FastAPI container (:8787, internal)
```

1. Copy and edit environment:

```powershell
cd backend
copy .env.example .env
```

Set `AI_PROVIDER`, API keys, and for production:

```env
APP_ENV=production
ALLOWED_ORIGINS=https://yourdomain.com
TRUST_PROXY_HEADERS=true
WEB_CONCURRENCY=2
```

2. Start the stack:

```powershell
docker compose up --build -d
```

3. Check health through Nginx:

```powershell
curl http://localhost/health
```

The FastAPI container is not exposed publicly; only Nginx ports `80` and `443` are published.

### HTTPS

1. Copy `nginx/conf.d/ssl.conf.example` to `nginx/conf.d/ssl.conf`.
2. Replace `api.example.com` with your domain and certificate paths.
3. Obtain certificates with Certbot on the server and mount them via the `certbot_conf` volume in `docker-compose.yml`.
4. Restart Nginx: `docker compose restart nginx`.

### Docker without Nginx (quick API test)

```powershell
docker compose -f docker-compose.dev.yml up --build
```

This exposes port `8787` directly for local testing.

### Single-container Docker (legacy)

```powershell
docker build -t text-summarizer-backend .
docker run --env-file .env -p 8787:8787 text-summarizer-backend
```

If `SUMMARY_API_URL` is not provided, the Flutter app will show a backend configuration error.

## Production notes

- Keep AI provider keys only on the backend (`.env` on the server, never in Flutter builds).
- Put the API behind Nginx with HTTPS before public launch.
- Add authentication before paid plans.
- Add per-user quota/rate limits before scaling traffic.
- Store files only if the product needs history; otherwise delete source text after summarization.
- Use PostgreSQL for users, subscriptions, and summary history.
- Use Redis/Celery later for very large files or background jobs.
- OCR requires Tesseract. The Dockerfile installs English and Vietnamese OCR data.

## Scaling notes

- Run multiple workers in production with `WEB_CONCURRENCY`.
- Keep `MAX_FILE_BYTES` strict so one upload cannot exhaust memory.
- `AI_MAX_CONCURRENCY` caps simultaneous AI calls per worker to reduce rate-limit spikes.
- PDF/DOCX/OCR extraction runs in a worker thread so the FastAPI event loop can keep serving other users.
- Nginx `proxy_read_timeout` is set to 900s for slow OCR/summarization jobs.
- For serious paid traffic, put Nginx behind a load balancer and use Redis-backed rate limits plus a queue for slow OCR jobs.
