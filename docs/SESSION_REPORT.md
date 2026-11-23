# Session report — 2026-11-22

What changed in this session, what is verified, and what is still open.

## 1. Login now always needs an emailed code (OTP)

Password alone no longer signs you in.

- `POST /auth` with `action=login` verifies the email + password, then emails a
  6-digit code and answers `{"ok":true,"requires_otp":true,...}`. It does **not**
  return a session token.
- `POST /auth` with `action=login_verify` (email + code) issues the session token.
- Codes are single-use: replaying a used code answers `{"ok":false,...,"no_otp":true}`.
- `action=resend` also supports the `login` purpose.
- Offline logout is blocked while a session is live, so a cached session cannot
  be silently dropped without the server.

Files: `site_smart/auth.php`, `lib/auth_service.dart` (`AuthResult.requiresOtp`,
`loginVerify`, `signIn` no longer persists on the first step),
`lib/auth_screen.dart` (new two-step UI).

Verified live with curl against `https://smart.chrif.net/auth`:
register → verify → login (`requires_otp`) → emailed code → `login_verify` → token;
reused code rejected. Re-checked after the 17:00 deploy: `/auth/login` answered
`requires_otp` + `mail_sent`, the code from the mailbox produced a token for
user 4, and replaying it answered `no_otp`.

## 2. Redesigned UI

- `lib/auth_screen.dart` rebuilt: brand panel, glass card, six-box OTP input,
  live password-strength meter, clear error states.
- App theme and launch screen refreshed (`lib/main.dart`, `lib/app_strings.dart`).
- Android launcher label is now “Smart Student AI”
  (`android/app/src/main/AndroidManifest.xml`).

## 3. AI picks the dictation passage

- `AIService.chooseDictationPassage` returns a `DictationPassage` chosen from the
  detected text, with a `_heuristicPassage` fallback when the model is unavailable.
- `lib/dictation_screen.dart` shows a preview dialog with **Proceed** / **Edit**
  before the passage is used.

## 4. OCR goes through the keyless router

- New backend `site_smart/ocr.php` at `POST /ocr` (`GET /ocr?action=ping` lists
  providers): scores OCR.space neural (engine 2), OCR.space classic (engine 1),
  local Tesseract CLI (only when `shell_exec` is callable) and Groq vision
  (server key, `qwen/qwen3.8-27b`), and returns the best text.
- Early exit: once two keyless engines agree on a plausible text, extra
  providers are skipped, so a normal page returns in ~1 s.
- App side `lib/ocr_router_service.dart` shrinks images over 900 KB (max side
  2000 px, hard cap 1 MB) before upload; `lib/google_ocr_service.dart` now talks
  to the router; the old `lib/ocr_service.dart` was deleted.

Verified live: `POST /ocr` with `test_ocr.png` returned the correct text in
~1 s via `ocrspace-neural` (score 332.15), with `ocrspace-classic` agreeing.

## 5. Smaller Android release

- Removed 11 unused heavy dependencies (mlkit, tesseract_ocr, syncfusion,
  printing, pdf, dart_openai, google_generative_ai, speech_to_text,
  url_launcher, provider, cupertino_icons).
- Enabled R8 minify + resource shrinking (`android/app/build.gradle.kts`).
- Release is a single arm64 APK (`--target-platform android-arm64`).

## 6. Windows build

- Portable Release build with bundled VC++ runtime/UCRT, icons and a tray icon.
- `tool/sign_windows.ps1` + `docs/WINDOWS_SIGNING.md` explain how to remove the
  SmartScreen “protected your PC” prompt.

## 7. Builds produced

- **Android release:** `build/app/outputs/flutter-apk/app-release.apk`,
  **24,851,525 bytes (23.7 MB)** — comfortably under the 40 MB budget.
  Single arm64 ABI, R8 minify + resource shrinking. Rebuilt after every fix in
  this pass and installed with `adb install -r` on the SM-A065F (Android 16).
- **Windows release:** `build/windows/x64/runner/Release/`, portable, bundled
  VC++ runtime + UCRT; packaged as `dist/SmartStudentAI-Windows-x64.zip`
  (**16.6 MB**, down from 19.0 MB thanks to the pruned plugins).
- Phone artifact: `dist/SmartStudentAI-1.0.0-arm64.apk` (23.7 MB).

Two build-environment bugs had to be fixed to get there (committed):
`android/gradle.properties` asked for `-Xmx8G -XX:MaxMetaspaceSize=4G` on an
8 GB machine, which made the Gradle daemon die with a native out-of-memory;
and the Kotlin incremental caches under `build/` failed to close on Windows
(`Could not close incremental caches`). The heap is now 2.5 GB (Kotlin daemon
1.3 GB) and Kotlin incremental compilation is off for release.

## Known limitation

The SmartScreen prompt can only be removed for real with a **trusted
code-signing certificate** (OV/EV). A self-signed certificate makes the prompt
disappear on your own machine only. See `docs/WINDOWS_SIGNING.md`.

## 8. Full on-device test (this pass)

Ran against the installed arm64 release on the SM-A065F (Android 16), landscape
1600×720, signed in as `no-reply@quran.chrif.net` (user 4).

Verified working:

- **Login + OTP:** password step → emailed code (read from Hostinger INBOX) →
  six-box OTP screen → home. Rejects reuse.
- **Home dashboard:** hero greeting, streak/XP/level chips, Study Planner card,
  TASKS panel, Level & XP card, Profile & Stats, Leaderboard, Logout.
- **Learning Hub:** Type Text / Upload File / Scan Image / Speak Text.
- **OCR from the gallery image:** Groq vision won (`score 312.12`, 2195 ms,
  195 chars) and the text landed in the hub input.
- **Dictation → gallery:** 1429-char OCR text → AI picked a **560-char**
  "The Water Cycle Process" passage (footer/copyright skipped) → preview with
  **Proceed** and **Edit**. Proceed loads it; Edit opens the passage pre-filled
  and "Load text" reuses it.
- **Speak Text in the hub:** mic permission prompt → 30 s AI recording →
  Groq transcription ("I'm going to put the microphone on top.") inserted into
  the field.
- **Generate Summary:** AI summary dialog from that text.
- **Generate Quiz:** 5 AI questions, answer selection, scoring loop.
- **Study Planner:** priority dropdown, task creation, "Task added", task
  persisted on the Home TASKS panel ("1 PENDING").
- **Profile & Stats:** live server data (name, email, Verified, Level 1,
  XP bar, streaks, Today's XP), Refresh works.
- **Leaderboard:** live rankings and podium (mohamed cherif 60 XP #1,
  mahmoud cherif 60 XP #2, Smart Test 0 XP #3).
- **Theme panel:** Ocean / Sunrise / Forest / Custom; switching Sunrise
  repaints the app instantly and persists.
- **Guards:** Record without a passage shows "Load a passage before
  recording."; empty hub text shows the summary/quiz hint.

Bugs found and fixed:

- **Revision Coach was unreachable** — `features[1]` (`RevisionScreen`) was
  built but never rendered. Added a Revision Coach card under the Learning Hub
  (`lib/home_screen.dart`).
- **Quiz dialog overflowed in landscape** — the question pane was a fixed
  `Column`, pushing **Check Answer** off-screen with no scroll. Wrapped it in a
  `SingleChildScrollView` (`lib/interactive_quiz_dialog.dart`).
- **Silent picker failures** — a null image/file pick did nothing. Both now
  show a message. File picks also request `withData: true` and fall back to
  staging bytes in a temp file when Android returns a `content://` Uri with no
  path (`lib/home_screen.dart`, `lib/dictation_screen.dart`).
- **Hub text skipped the AI passage step** — opening Dictation with text from
  the Learning Hub loaded the whole text without a preview. It now runs the
  same `chooseDictationPassage` + Proceed/Edit preview, and the chosen passage
  stays visible on the screen instead of being hidden by the hub flag.
- **Empty speech result was silent** — when the AI transcription came back
  empty the field just stayed blank. It now shows "No speech detected. Please
  try again." (`lib/app_strings.dart`, `lib/home_screen.dart`).

## 9. Verification of the rebuilt APK

The fixes above were rebuilt into a fresh 23.7 MB APK and re-tested on the same
device:

- **Revision Coach card** is rendered under the Learning Hub and opens a
  10-question session; Restart resets it and the question advances.
- **Quiz scroll fix:** **Check Answer** is reachable after scrolling in
  landscape, the answer scores (0/5 → 1/5) and **Next Question** advances to
  Question 2 of 5.
- **Upload File:** the pushed `/sdcard/Download/passage_test.txt` loads with
  "Text detected successfully" — the previously dead picker path now works and
  `content://` Uris are handled.
- **XP sync:** the correct quiz answer moved the home dashboard to
  `20/50 XP today` after a relaunch, i.e. the award reached the server, not just
  the local database.
- **Home/Study Planner:** the persisted task still shows `1 PENDING`.

## Known limitations

- SmartScreen prompt can only be removed for real with a **trusted
  code-signing certificate** (OV/EV). A self-signed certificate makes the prompt
  disappear on your own machine only. See `docs/WINDOWS_SIGNING.md`.
- The Android **photo picker intermittently returns a permission-denied Uri**
  (platform race); the app now reports it instead of failing silently. Retrying
  the pick works.
- Google Photos keeps stale thumbnails for deleted files; this is OS behaviour,
  not the app.

## Open items / TODO

- [x] Reinstall the rebuilt APK and smoke-test the Revision card + quiz scrolling.
- [x] Confirm XP earned on-device reaches the server (`20/50 XP today`).
- [x] Confirm **Upload File** loads a pushed `.txt` file.
- [ ] Re-run the hub → Practice Dictation flow on the rebuilt APK (AI passage
      preview + Proceed/Edit for hub text).
- [ ] Re-test Logout → two-step OTP login on the rebuilt APK.
- [ ] Optional: buy/install a trusted code-signing certificate for Windows.
