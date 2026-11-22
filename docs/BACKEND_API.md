# Smart Student AI — backend endpoints used by the app

Base URL: `https://smart.chrif.net`
All requests and responses are JSON (`Content-Type: application/json`).

## Accounts — `/auth`

| Action | Method | Body | Result |
| --- | --- | --- | --- |
| `register` | POST `/auth/register` | `name`, `email`, `password` | `{ ok, requires_verification, email, mail_sent }` — emails a 6-digit code |
| `verify` | POST `/auth/verify` | `email`, `code` | `{ ok, token, user, progress, achievements }` |
| `login` | POST `/auth/login` | `email`, `password` | `{ ok, requires_otp: true, email, mail_sent }` — **never** returns a token |
| `login_verify` | POST `/auth/login_verify` | `email`, `code` | `{ ok, token, user, progress, achievements }` |
| `resend` | POST `/auth/resend` | `email`, `purpose` = `verify` \| `login` \| `reset` | `{ ok, message }` |
| `forgot` | POST `/auth/forgot` | `email` | `{ ok, message }` — emails a reset code |
| `reset` | POST `/auth/reset` | `email`, `code`, `password` | `{ ok, message }` |
| `me` | GET `/auth/me` + `Authorization: Bearer <token>` | — | `{ ok, user, progress, achievements }` |
| `ping` | GET `/auth/ping` | — | service + database health |

### Two-factor sign-in

1. `login` checks the password. On success it invalidates older login codes,
   stores a fresh one (SHA-256 hash, 10-minute TTL, max 8 attempts, single use)
   and emails it. No session is created at this point.
2. `login_verify` consumes the newest unconsumed code for that email and only
   then creates the session token.

Rate limit: at most 6 codes per email per hour (`config.php → mail.max_per_hour`).

## OCR — `/ocr`

Keyless OCR router. The app sends an image and receives the best text found by
several free engines; the app never holds an OCR key.

`POST /ocr`

```json
{ "image_base64": "…", "mime": "image/jpeg", "language": "auto" }
```

`language` accepts `auto`, `ar`, `fr`, `en`. `url` may be sent instead of
`image_base64`.

Response:

```json
{
  "ok": true,
  "text": "…",
  "provider": "ocrspace-neural",
  "provider_label": "OCR.space · Neural (engine 2)",
  "score": 742.5,
  "language": "auto",
  "elapsed_ms": 2100,
  "candidates": [{ "provider": "…", "score": 0, "chars": 0, "ms": 0 }],
  "errors": {}
}
```

Providers, in order:

| Provider | Tier | Notes |
| --- | --- | --- |
| OCR.space neural (engine 2) | keyless | Best on modern photos |
| OCR.space classic (engine 1) | keyless | Sometimes better on clean scans |
| Tesseract CLI | keyless | Only when the host has the binary and `shell_exec` |
| Groq vision | server key | Safety net, key stays on the server |

Every candidate is scored (letters, words, letter ratio, language-specific
bonus, penalties for replacement glyphs and symbol soup). The highest score
wins; the router stops early once a keyless result passes the "good enough"
threshold. Per-IP quota: 40 requests/hour.

`GET /ocr?action=ping` lists the active providers.

## AI router — `/v1/chat/completions`

OpenAI-compatible failover proxy used by the app (`AI_BASE_URL`). Keys live in
`keys.php` on the server only.