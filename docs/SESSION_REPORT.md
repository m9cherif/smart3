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
reused code rejected.

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

- **Android release:** `build/app/outputs/flutter-apk/app-release.apk`, **23.7 MB**,
  single arm64 ABI, R8-shrunk. Installed with `adb install -r` on the
  SM-A065F (Android 16) and started successfully — the redesigned sign-in
  screen renders.
- **Windows release:** `build/windows/x64/runner/Release/`, portable, bundled
  VC++ runtime + UCRT.

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

## Open items / TODO

- [ ] **On-device smoke test is blocked:** after the phone reboot, Android
      turned wireless debugging off, so `adb` cannot reach it. Re-enable
      *Developer options → Wireless debugging* on the phone (or plug in USB)
      and the APK is already installed — only the walkthrough is left:
      sign-in (email → password → emailed code), dictation passage preview
      (Proceed / Edit), OCR from a gallery image.
- [ ] Confirm the shrinker did not strip anything needed at runtime (R8).
      Startup and the sign-in screen were verified; the rest of the flows
      still need the device test above.
- [ ] Confirm the 17:00 server cron redeployed `/ocr` with the early-exit +
      Qwen model change.
- [ ] Zip the rebuilt Windows release into `dist/`.
- [ ] Optional: buy/install a trusted code-signing certificate for Windows.
