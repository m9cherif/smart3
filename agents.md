# agents.md — Smart Student AI: full session handoff

> **Who this is for:** an AI agent working in OpenCode on a **Linux server**
> (opencode web/serve). You own the repo and the CI. Your job is to build
> **Windows, Linux and Android** artifacts through **GitHub Actions**, keep the
> app under its size budget, and finish the queued tests.
>
> **Read this whole file before changing anything.** It records what was built,
> what was verified, what is deliberately the way it is, and which mistakes were
> already made and fixed.

- Repo: `https://github.com/m9cherif/smart3` (branch `master`)
- Remote head when this was written: `ce2582b` (merge) / `124686c` (CI workflow)
- Working tree at handoff: **clean**
- App version: `1.0.0+1`, application id `com.example.smart_student_ai`
- Flutter used to build everything so far: **3.44.2 stable, Dart 3.12.2**
- Last APK: `build/app/outputs/flutter-apk/app-release.apk`,
  **24,851,525 bytes (23.7 MB)** — budget is **< 40 MB**

---

## 1. What the product is

A study app for primary-school children (Arabic-first, also English/French):

| Feature | What it does |
|---|---|
| Auth | Email + password **plus a 6-digit emailed OTP on every sign-in** |
| Learning Hub | Paste/type text, upload a file, scan an image (OCR), or dictate text |
| Summary | AI summary of the hub text |
| Quiz | AI generates a 5-question multiple-choice quiz, scores it, awards XP |
| Dictation | AI picks the best passage from the text, student reads it aloud, app transcribes and scores accuracy |
| Revision Coach | 7-question primary revision bank, per-subject filter, session score |
| Study Planner | Tasks with priority/deadline, pending count on Home |
| Profile & Stats | Server-synced XP, level, streaks, accuracy, rank |
| Leaderboard | Live ranking from the server |
| Theme | Ocean/Sunrise/Forest/Custom presets, brightness slider, language (en/fr/ar, RTL) |
| Extras | Tray icon + notifications (desktop), landscape lock (mobile) |

The **server (smart.chrif.net) is the source of truth** for accounts and XP.
Local SQLite is an offline cache/fallback only.

---

## 2. Repo map

```
lib/
  main.dart                     app boot, init, LaunchGate, landscape lock
  app_controller.dart           ChangeNotifier + AppScope (theme, locale, prefs)
  app_strings.dart              ALL user-facing strings, en/fr/ar
  app_customization_panel.dart  theme presets, brightness, language, reset
  auth_screen.dart              sign-in/up/verify/loginOtp/forgot/reset
  auth_service.dart             HTTP client for the auth API, session, XP push
  auth_wrapper.dart             signed-in/out routing
  home_screen.dart              dashboard, Learning Hub, hub actions, pickers
  dictation_screen.dart         OCR/import, AI passage preview, record, score
  interactive_quiz_dialog.dart  quiz dialog (scrollable question pane)
  revision_screen.dart          Revision Coach
  ai_service.dart               AI router client, summary, quiz, passage chooser
  ocr_router_service.dart       POST /ocr client
  google_ocr_service.dart       name is historical; now calls the router
  database_service.dart         sqflite (mobile) / sqflite_common_ffi (desktop)
  notification_service.dart     local notifications + scheduling
  tray_service.dart             tray + window_manager (desktop)
  <other>: study planner, profile, leaderboard, settings widgets

site_smart/                     PHP backend deployed to smart.chrif.net
  auth.php                      auth + OTP + progress + leaderboard API
  ocr.php                       keyless OCR router
  api.php, config.php, db.php, .htaccess, index.html
tool/
  server_deploy.php             deploy helper executed by the Hostinger cron
  deploy_smart.php              alternative deploy helper
  sign_windows.ps1              Windows code signing
docs/
  SESSION_REPORT.md             what was built + device test results
  BACKEND_API.md                backend API reference
  TODO_TESTING.md               remaining device checks (queued)
  WINDOWS_SIGNING.md            SmartScreen / certificate guide
.github/workflows/
  build.yml                     matrix android/linux/windows (see §8 — has bugs)
  dart.yml                      dart analyze/test (see §8 — should be replaced)
android/ windows/ linux/        platform runners
```

---

## 3. Runtime architecture / data flow

```
Flutter UI
  ├─ AuthService  ──HTTPS──► https://smart.chrif.net/auth?action=…
  ├─ AIService    ──HTTPS──► https://smart.chrif.net/v1/chat/completions
  │                 (body model:"auto"; fallback api.groq.com direct)
  ├─ OCR router   ──HTTPS──► https://smart.chrif.net/ocr  (POST image_base64)
  └─ DatabaseService ──► local SQLite (offline cache, sessions, streaks)
```

### 3.1 Auth (two-step, mandatory)

| Step | Endpoint | Request | Response |
|---|---|---|---|
| 1 | `POST /auth?action=login` | `{email,password}` | `{ok:true, requires_otp:true, email, mail_sent, message}` |
| 2 | `POST /auth?action=login_verify` | `{email, code}` | `{ok:true, token, user:{…}, progress:{…}, achievements:[…]}` |

- Wrong password → `401 bad_credentials`.
- Unverified account → `403 unverified` + `requires_verification:true`.
- Rate limit: **6 codes per email per hour** (`max_per_hour`), OTP TTL **600 s**.
- OTP codes are single-use; `a_consume_otp` deletes them.
- `logout` invalidates the bearer token server-side. **Offline logout is blocked**
  in the app on purpose (you cannot invalidate a token without the network).
- Other actions: `register`, `verify`, `resend` (`purpose: verify|login`),
  `forgot`, `reset`, `me`, `progress`, `sync`, `leaderboard`, `achievements`.
- Auth header: `Authorization: Bearer <token>` for everything except
  register/login/login_verify/forgot/reset.
- The server reads `action` from `$_GET['action']` **or** from the rewritten
  path (`^auth/([a-z_-]+)/?$` in `.htaccess`). Both work; the app always uses
  the query form.

DB tables used by `auth.php`: `users`, `sessions`, `otps`, `progress`,
`xp_events`, `achievements` (plus `rejected` for failed attempts).

### 3.2 XP / level

Server-side formula and daily goal live in `auth.php` (`a_progress_row`,
`a_sync_achievements`). The app:
- renders what the server returns (`xp`, `level`, `xp_into_level`,
  `xp_per_level`, `level_progress`, `streak`, `today_xp`, `daily_goal`, `rank`);
- pushes awards fire-and-forget with `AuthService.instance.pushProgress()`
  (`action=progress`, body `{xp_delta, revision_delta, dictation_delta, source}`);
- queues deltas locally when offline and flushes them with `action=sync`.

Never make the client authoritative for XP.

### 3.3 AI

`lib/ai_service.dart`:

- Router: `SMART_ROUTER_URL` (default `https://smart.chrif.net/v1/chat/completions`),
  body `{model:"auto", messages, max_tokens, temperature}`. The server picks the
  best free **keyless** model and fails over internally. Verified model:
  `qwen/qwen3.8-27b` (text + vision), ~1.3 s for a passage pick.
- Fallback: direct Groq `api.groq.com` with `GROQ_API_KEY` dart-define
  (optional; only used if the router is unreachable).
- `CONVERT_API_KEY` is used by `ai_service.dart` for file→text conversion;
  also optional at build time.

**Dictation passage chooser** (`AIService.chooseDictationPassage`):
- `< 900 chars` → returns the cleaned text as-is with
  `note: "The whole detected text is short enough to dictate as-is."`
  (`chosenByAi: false`) — the preview dialog still appears.
- Longer text → prompts for strict JSON
  `{"title":"3-6 words","passage":"verbatim excerpt"}`, target 650 chars
  (423–975), verbatim only, skips headers/footers/copyright/URLs/formulas.
- Result must be ≥ 80 chars and "looks like real text", otherwise a heuristic
  fallback is used (`_heuristicPassage`).
- The UI always shows a preview dialog with **Proceed** and **Edit**
  (`_showPassagePreview` in `dictation_screen.dart`). Edit opens the manual text
  dialog pre-filled; "Load text" uses the edited text.

### 3.4 OCR

`POST https://smart.chrif.net/ocr` with
`{image_base64, mime?, language?}` → `{ok, text, provider, score, ms, …}`.
`GET /ocr?action=ping` and `?action=providers` for health.

`ocr.php` scores four engines and early-exits when two keyless results agree:
`ocrspace-neural` (engine 2), `ocrspace-classic` (engine 1), local Tesseract CLI
(only if `shell_exec` is callable), and `groq-vision` (server key). Limits:
12 MB base64 payload, 55 s total budget, 20 s per provider, 1 MB request cap.

The app shrinks images client-side when > 900 KB (max side 2000 px, hard cap
1 MB) before upload.

### 3.5 Backend deployment (important!)

The site root is
`/home/u170282392/domains/smart.chrif.net/public_html`.

Deployment only works through the **pre-existing hourly Hostinger cron**
`4Inb2bna3q`, which runs:

```
php -r 'copy("https://raw.githubusercontent.com/m9cherif/smart3/master/tool/server_deploy.php","/home/u170282392/sd.php"); include("/home/u170282392/sd.php");'
```

So: **push `master` → wait for the next hour → the server updates itself.**
Newly created crons never execute; the Hostinger API returns 405 for
PUT/PATCH and only accepts DELETE. Do not try to "deploy now" through the API.

`tool/server_deploy.php` copies `site_smart/*` into place, writes config, and
handles the `.htaccess` rewrite rules.

---

## 4. Configuration and secrets

### Local `secrets.json` (git-ignored, **never commit**)

```json
{ "GROQ_API_KEY": "…", "CONVERT_API_KEY": "…" }
```

Used by `flutter build … --dart-define-from-file=secrets.json`.

### Compile-time flags

| Define | Default | Purpose |
|---|---|---|
| `AUTH_BASE_URL` | `https://smart.chrif.net/auth` | account API |
| `SMART_ROUTER_URL` | `https://smart.chrif.net/v1/chat/completions` | AI router |
| `GROQ_API_KEY` | empty | direct Groq fallback only |
| `CONVERT_API_KEY` | empty | file→text conversion |

**A build without these files/flags still works**: the router and OCR endpoints
are keyless, and the app degrades gracefully. Do not block CI on secrets.

For GitHub Actions, if you want the flags, add repo secrets
`GROQ_API_KEY` / `CONVERT_API_KEY` and generate `secrets.json` in a step
(see §8). Never echo them into logs.

### Test account (already public in this repo — rotate if you care)

- `no-reply@quran.chrif.net` / `SmartTest.2026Kq7` (name "Smart Test", user id 4)
- Email inbox for OTPs is a Hostinger mailbox — the previous agent read codes
  with the `hostinger-mail` MCP (`INBOX` folder, mailbox
  `AC98701d00f21668e435156d31da36`). From a plain Linux box you cannot read it;
  ask the user for a code or use the API with a mailbox you control.

---

## 5. Build matrix — exact commands

### 5.1 Android (the size-critical target)

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
# artifact: build/app/outputs/flutter-apk/app-release.apk
```

- **Single arm64 ABI only.** Adding other ABIs or `--split-per-abi`-less builds
  doubles the size and breaks the budget.
- `android/app/build.gradle.kts`: `isMinifyEnabled = true`,
  `isShrinkResources = true`, signed with the **debug** signing config
  (fine for side-loading, NOT for Play Store).
- 11 heavy/unused dependencies were removed on purpose: mlkit, tesseract_ocr,
  syncfusion, printing, pdf, dart_openai, google_generative_ai, speech_to_text,
  url_launcher, provider, cupertino_icons. **Do not add them back.**
- `android/gradle.properties` is deliberately tuned for an 8 GB machine:
  `-Xmx2560m`, metaspace 768m, workers 2, no parallel, Kotlin daemon 1280m,
  `kotlin.incremental=false`. On a GitHub runner this is just slower, not
  broken. Leave it unless you also raise it in CI explicitly.
- Gradle wrapper: 8.14 (`services.gradle.org`). AGP 8.11.1, Kotlin 2.2.20.
  JDK 17 or 21 (CI uses Temurin 17).

Size history: 23.7 MB after pruning (before: ~40 MB with the heavy deps).

**CI must fail if the APK exceeds 40 MB:**

```bash
SIZE=$(stat -c%s build/app/outputs/flutter-apk/app-release.apk)
[ "$SIZE" -lt 41943040 ] || { echo "APK too big: $SIZE bytes"; exit 1; }
```

### 5.2 Windows (built on `windows-latest`)

```powershell
flutter build windows --release --dart-define-from-file=secrets.json   # if the file exists
# artifact: build\windows\x64\runner\Release\
```

- `windows/CMakeLists.txt` bundles the VC++ runtime and UCRT
  (`CMAKE_INSTALL_UCRT_LIBRARIES TRUE` + `InstallRequiredSystemLibraries`), plus
  `logo.ico` / `logo.png`, so the folder is portable.
- The app has a tray icon and `setPreventClose(true)`; **closing the window hides
  it to the tray**. `Stop-Process` is the reliable way to kill it in scripts.
- SmartScreen ("Windows protected your PC") can only be removed with a
  **trusted** code-signing certificate. `tool/sign_windows.ps1` +
  `docs/WINDOWS_SIGNING.md` show how (self-signed only helps on your own PC).
  In CI you can sign if a base64 PFX is provided as a secret.
- Portable zip used previously: `dist/SmartStudentAI-Windows-x64.zip` (16.6 MB).

### 5.3 Linux (built on `ubuntu-latest`)

```bash
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev \
  liblzma-dev libblkid-dev libasound2-dev libsqlite3-dev libjsoncpp-dev \
  libnotify-dev libsecret-1-dev
flutter pub get
flutter build linux --release
# artifact: build/linux/x64/release/bundle
```

- `sqflite_common_ffi` loads system `libsqlite3` at runtime — document
  `libsqlite3-0` as a runtime dependency or bundle the .so.
- `record` on Linux shells out to PulseAudio tools at runtime
  (`parec`/`pactl`, package `pulseaudio-utils` / `pipewire-pulse`). It does not
  affect the build, only recording at runtime.
- The Linux runner has not been device-tested yet. First smoke test should be:
  launch → sign in → OTP → home → hub → dictation preview → theme → logout.

---

## 6. UI behaviour that must not regress

- **Landscape lock** on mobile (`SystemChrome.setPreferredOrientations`).
  Phone test resolution is 1600×720 (physical 720×1600, density 300).
- **All strings go through `AppStrings`** (en/fr/ar). No hard-coded UI text.
  Arabic is the default experience for the test user; RTL layout must keep
  working.
- **Home** order: hero → Study Planner card + TASKS panel → Learning Hub card
  (input + Type Text / Upload File / Scan Image / Speak Text) → three action
  cards (Create Summary / Create Quiz / Practice Dictation) → **Revision Coach**
  → Level & XP → Leaderboard / Profile.
- **Hub → Practice Dictation** asks "use hub text or start new"; hub text goes
  through the AI passage chooser and the **Proceed/Edit preview**; the chosen
  passage must remain visible in the "Expected passage" card (this was a real
  bug: an `_isFromHub` flag hid it).
- **Quiz dialog** must stay scrollable in landscape, otherwise **Check Answer**
  is unreachable (fixed this session).
- **Selecting images/files** must never fail silently: null picks and
  `content://` URIs without a path show a message; file picks use
  `withData: true` and stage bytes into a temp file.

---

## 7. What was verified (do not redo unless you change the code)

### 7.1 On the real phone (SM-A065F, Android 16, landscape 1600×720)

- Two-step login: password → emailed code read from the inbox → 6-box OTP →
  home; code reuse rejected; offline logout blocked.
- Redesigned home (streak/XP/level chips, Study Planner, TASKS, Level & XP).
- Learning Hub: Type Text, Upload File (`.txt` pushed to `/sdcard/Download`),
  Scan Image / OCR from gallery, Speak Text (30 s recording → transcription).
- OCR router live: Groq vision won, `score 312.12`, 2195 ms, 195 chars.
- Dictation gallery: AI picked a 560-char passage, Proceed loaded it, Edit
  reused the pre-filled text.
- Generate Summary; Generate Quiz 5 questions with scoring (0/5 → 1/5 →
  Question 2 of 5) and XP synced to the server (`20/50 XP today`).
- Study Planner task created, "1 PENDING" persisted on Home.
- Profile & Stats with Refresh; Leaderboard (3 live users); theme presets.
- Revision Coach card opens a 10-question session; Restart works.
- Guards: Record without a passage, empty hub text, empty speech transcription.

### 7.2 On Windows (same Dart code, rebuilt from HEAD `badc188`)

The phone dropped off Wi-Fi mid-session, so the last UI checks were done on the
Windows release build via mouse/keyboard automation:

- Hub text (1250 chars) → Practice Dictation → "use hub text" →
  **AI preview appeared** with a 506-char "The Water Cycle Description",
  **Proceed** put exactly that excerpt in the Expected-passage card;
- repeating the flow and choosing **Edit** opened the dialog pre-filled; typing
  extra words and pressing **Load text** updated the expected passage;
- theme panel: Sunrise preset repaints instantly, brightness slider moves,
  language chips (العربية / الفرنسية / الإنجليزية) present;
- app was signed in as a second account ("mahmoud cherif", 60 XP) — proves
  sessions and server progress work across installs.

### 7.3 Server-side (curl/PowerShell)

- `GET /ocr?action=ping` → 3 providers healthy.
- AI router returns strict JSON for the passage prompt (qwen/qwen3.8-27b,
  1.3 s, verbatim excerpt, footer/copyright skipped, 719 chars).
- `auth.php` underscore-action bug fixed (commit `2eca0b5`).

`flutter analyze` (whole project): **No issues found**.

### 7.4 Commit trail of this session

```
ce2582b Merge branch 'master'                        (includes the CI commit)
124686c ci: build android linux windows releases      (someone added build.yml)
fbe0ee8 docs: record remaining on-device checks
badc188 fix(app): reach Revision Coach, scroll quiz dialog, harden file picks,
        AI passage for hub text
c5d70ee Report: record the verified live OTP run and packed artifacts
2eca0b5 auth: accept underscored actions when the URL is not rewritten
e65079d Document the session: OTP login, passage preview, OCR router, releases
61ecd8d Bound Gradle/Kotlin heap for 8 GB machines; disable Kotlin incremental
a0b1e67 server-authoritative XP/level + offline delta queue + logout guard
8249f5f Portable Windows build (VC++ runtime, icons, tray)
```

---

## 8. GitHub Actions — current state and what to fix

`.github/workflows/build.yml` already exists and is a good skeleton, but it has
**four real defects**:

1. `flutter-version: '3.50.1'` — **check that this tag actually exists** in
   `storage.googleapis.com/flutter_infra_release/releases`. Everything built so
   far used **3.44.2** (Dart 3.12.2, `pubspec` requires `sdk: ^3.11.1`), and a
   pin to a non-existent version fails the setup step. Either pin `3.44.2` or
   drop `flutter-version` and let `channel: stable` resolve.
2. Android builds with plain `flutter build apk --release` (all ABIs) →
   big APK, likely **over the 40 MB budget**. Use
   `--target-platform android-arm64`.
3. No **size gate** step, so a regression will silently publish a 60 MB APK.
4. No `secrets.json` / `--dart-define` handling (acceptable — the app works
   keyless — but be explicit about it).

Also: `.github/workflows/dart.yml` runs `dart analyze` and `dart test` on a
**Flutter** package. `dart test` is the wrong runner (it fails on a Flutter
package; use `flutter test`) and there is only `test/widget_test.dart`, which
pumps the whole app and will likely need plugin mocks. Replace that workflow
with a single `flutter analyze` job (add `flutter test` only after the widget
test is made hermetic), or delete it.

### 8.1 Recommended workflow (replace `build.yml`)

```yaml
name: Flutter builds

on:
  push:
    branches: [master]
  pull_request:
    branches: [master]
  workflow_dispatch:
  release:
    types: [published]

permissions:
  contents: read

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: '3.44.2'
          cache: true
      - run: flutter pub get
      - run: flutter analyze

  build:
    needs: analyze
    name: ${{ matrix.target }} (${{ matrix.os }})
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        include:
          - os: ubuntu-latest
            target: android
            build_command: >-
              flutter build apk --release --target-platform android-arm64
            artifact_path: build/app/outputs/flutter-apk/app-release.apk
            artifact_name: smart3-android-arm64
          - os: ubuntu-latest
            target: linux
            build_command: flutter build linux --release
            artifact_path: build/linux/x64/release/bundle
            artifact_name: smart3-linux-x64
          - os: windows-latest
            target: windows
            build_command: flutter build windows --release
            artifact_path: build/windows/x64/runner/Release
            artifact_name: smart3-windows-x64
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Set up Java 17
        if: matrix.target == 'android'
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Install Linux desktop dependencies
        if: matrix.target == 'linux'
        run: |
          sudo apt-get update
          sudo apt-get install -y clang cmake ninja-build pkg-config \
            libgtk-3-dev liblzma-dev libblkid-dev libasound2-dev \
            libsqlite3-dev libjsoncpp-dev libnotify-dev libsecret-1-dev

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: '3.44.2'
          cache: true

      - name: Install dependencies
        run: flutter pub get

      - name: Build
        run: ${{ matrix.build_command }}

      - name: Enforce Android size budget (< 40 MB)
        if: matrix.target == 'android'
        shell: bash
        run: |
          SIZE=$(stat -c%s build/app/outputs/flutter-apk/app-release.apk)
          echo "APK size: $SIZE bytes"
          test "$SIZE" -lt 41943040

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: ${{ matrix.artifact_name }}
          path: ${{ matrix.artifact_path }}
          if-no-files-found: error
```

Notes:
- If you later want the dart-defines in CI, add a step **before Build**:
  `echo "{\"GROQ_API_KEY\":\"${{ secrets.GROQ_API_KEY }}\"}" > secrets.json`
  and append `--dart-define-from-file=secrets.json` to the build command.
  Keep `secrets.json` out of artifacts.
- `release: published` gives you zipped binaries on tags if you add a
  `softprops/action-gh-release` step — optional, not required.
- The Windows runner produces a folder, not an installer. Zip it if you want a
  single download (`Compress-Archive`), like `dist/SmartStudentAI-Windows-x64.zip`.
- Linux artifact is a **bundle directory**; `tar -czf` it before upload if the
  artifact viewer matters to you.

---

## 9. Remaining work (priority order)

1. **Fix the CI workflow** as in §8 (the current file cannot succeed).
2. **Push a green run**: analyze + 3 builds + APK size gate. Download the APK and
   confirm `< 40 MB`.
3. **Linux smoke test** (new target): sign-in OTP, hub, dictation preview,
   theme, planner. File bugs with screenshots.
4. **Finish the two phone checks** when a device is available again
   (`docs/TODO_TESTING.md` has the exact taps):
   - hub → Practice Dictation → AI preview → Proceed/Edit **on the phone**
     (already proven on Windows);
   - Logout → two-step OTP sign-in **on the phone**.
5. **Consider** a release keystore for Android (currently debug-signed) and a
   trusted Windows certificate (SmartScreen).
6. Optional code hygiene: `_isFromHub` in `dictation_screen.dart` is now always
   `false` (8 references). It is harmless; remove it only together with a
   rebuild + reinstall so source and shipped binary stay in sync.
7. Optional: auto-retry once when the Android photo picker returns
   permission-denied.

---

## 10. Known issues and workarounds

| Issue | Reality / workaround |
|---|---|
| Phone dropped off wireless ADB | `adb mdns services` empty, LAN sweep found only the router. Reconnect from the phone's Developer options → Wireless debugging. |
| `adb shell input text` does not type into Flutter fields | IME composition + AnyDesk accessibility focus steal input. Use real taps, or load text from a file/gallery. |
| Google photo picker sometimes returns permission-denied Uri | OS race; the app reports it now. Retry the pick. |
| SmartScreen warning | Needs a trusted OV/EV certificate. Self-signed helps only locally. |
| Server deploys only hourly | Existing cron `4Inb2bna3q`; new crons never run; PUT/PATCH 405. |
| Windows app "won't close" | Tray + `setPreventClose(true)`; it hides. Kill the process or use the tray menu. |
| Flutter/pub mirror | `pubspec.lock` resolves through `https://pub.flutter-io.cn` (China mirror) and the tool prints a warning. It works, but if CI is slow, re-resolve with `PUB_HOSTED_URL=https://pub.dev flutter pub get` and commit the new lock. |
| CI Flutter 3.50.1 | Does not exist. See §8. |
| OTP emails | Sent from `no-reply@smart.chrif.net` via Hostinger SMTP, DKIM-signed by `auth.php`. |

---

## 11. Conventions and guardrails

- **Do not** add heavy packages (mlkit, pdf, printing, syncfusion, tesseract,
  speech_to_text, …) — the 40 MB APK budget is the hard constraint.
- **Do not** re-enable incremental Kotlin or raise the Gradle heap without
  measuring; the original crash was a native OOM on an 8 GB machine.
- **Do not** make login one-step again, and do not cache the session in a way
  that bypasses `login_verify`.
- **Do not** commit `secrets.json`, keystores, `.env`, or the Groq key.
- **Do** keep every user-visible string in `app_strings.dart` in all three
  languages; the UI is RTL in Arabic and is tested that way.
- **Do** keep `flutter analyze` clean (the last full run: no issues).
- **Do** keep the visual language: rounded 20–24 px cards, colour-scheme-driven
  widgets, the custom theme panel, the gradient hero.
- Match surrounding style: `snake_case.dart` files, `PascalCase` widgets,
  `const` constructors, no new state-management package (AppScope/ChangeNotifier
  is deliberate).

---

## 12. Cheat sheet

```bash
# analyze / format
flutter analyze
dart format lib

# android
flutter build apk --release --target-platform android-arm64 \
  --dart-define-from-file=secrets.json
adb install -r build/app/outputs/flutter-apk/app-release.apk

# windows
flutter build windows --release --dart-define-from-file=secrets.json

# linux
flutter build linux --release

# backend smoke tests
curl -s https://smart.chrif.net/ocr?action=ping
curl -s -X POST "https://smart.chrif.net/auth?action=login" \
  -H "Content-Type: application/json" \
  -d '{"email":"no-reply@quran.chrif.net","password":"SmartTest.2026Kq7"}'
```

Phone UI coordinates (1600×720 landscape): Logout `(1383,180)`, theme
`(1278,180)`, photo picker OK `(1289,578)`, gallery row `(776,477)`.
Windows UI (1366×768): theme/customise button `(110,84)`, hub
Practice Dictation `(253,400)` when scrolled, dialog "use hub text"
`(536,414)`, preview Proceed `(452,568)`, Edit `(558,568)`.

---

## 13. One-paragraph summary

Smart Student AI is a Flutter study app (Arabic-first, landscape, Material 3
redesign) whose accounts, XP, AI, and OCR all live behind `smart.chrif.net`.
Sign-in is always password **+ emailed OTP**. The Learning Hub feeds Summary,
Quiz, and Dictation; the AI chooses a verbatim dictation passage and the user
confirms it with Proceed/Edit. OCR is routed server-side across three keyless
engines. The Android release is a single 23.7 MB arm64 APK (from 40 MB after
pruning 11 dependencies and enabling R8), Windows is a portable self-contained
folder, Linux is untested but wired. Everything except two phone-only flows was
verified on-device and on the Windows build; the repo is clean at `ce2582b`, and
the immediate job is to repair `.github/workflows/build.yml` so the three
platforms build green through GitHub Actions.
