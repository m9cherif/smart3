# TODO — remaining device checks

Everything below was blocked because the test phone (SM-A065F) dropped off
Wi-Fi / wireless debugging mid-session. The PC could only reach the router
(`192.168.1.1`) on the LAN and the phone did not appear in `adb mdns services`,
so it is not currently reachable.

Reconnect procedure on the phone: **Developer options → Wireless debugging →
on**, then on the PC:

```powershell
$adb = 'G:\android_SDK\platform-tools\adb.exe'
& $adb mdns services
& $adb connect <ip>:<port>   # only needed if mdns does not pick it up
& $adb devices
```

## 1. Learning Hub → Practice Dictation (hub text path)

This exercises `DictationScreen.initialText` → `_refineInitialPassage()` →
`_showPassagePreview()`.

1. Load text into the hub: **Upload File** → `Download/passage_test.txt`
   (291 chars, so the chooser returns it whole with the
   "short enough to dictate as-is" note — the preview still must appear).
   For a real AI pick, push a longer text (> 900 chars), e.g. the water-cycle
   sample, and load that instead.
2. Scroll to **Practice Dictation** → choose **Use hub text**.
3. Expect: status "Choosing the best passage…", then the preview dialog with
   the AI passage, **Proceed** and **Edit**.
4. **Proceed** → the passage stays in the Expected-passage panel (previously it
   was hidden by the `_isFromHub` flag).
5. Repeat with **Edit** → dialog pre-filled → **Load text** keeps the edits.
6. While the chooser runs, Type Text / Upload File / Scan Image / Speak Text and
   **Record** must be disabled.

## 2. Logout → two-step OTP login

1. From Home, tap **Logout** (`(1383,180)` in 1600×720 landscape).
2. Sign in with `no-reply@quran.chrif.net` / `SmartTest.2026Kq7`.
3. Expect the OTP screen ("We emailed a 6-digit sign-in code to …"), not Home.
4. Read the code from the Hostinger INBOX (`AC98701d00f21668e435156d31da36`,
   folder `INBOX`) and enter it.
5. Confirm the code cannot be reused (sign out, enter the same code → rejected
   with an expired/invalid message).
6. Confirm offline logout is blocked (airplane mode → Logout shows the guard).

## 3. Theme panel extras (new build)

1. Open the theme button at `(1278,180)`.
2. Drag the **brightness** slider to both ends; the app must repaint and keep
   the choice after relaunch.
3. Switch **language** chips (English / Français / العربية) and check that the
   home hero, feature cards and buttons all switch.

## 4. Study Planner (new build)

Previously verified on the older build; re-check on the new one:

1. Open **Study Planner**, add a task with priority High.
2. Home TASKS panel shows the task and the pending count.
3. Complete/delete it and confirm the count drops.

## 5. Rounds that already passed on this build

- Login + OTP (earlier build, same code path)
- Revision Coach card → 10-question session, Restart
- Quiz dialog scroll → Check Answer → score 1/5 → Next Question
- Upload File (`.txt` from Download) → "Text detected successfully"
- XP sync → `20/50 XP today` after relaunch
- OCR from gallery (Groq vision, 195 chars) and dictation gallery passage
- Speak Text (30 s recording → Groq transcription)
- Generate Summary, Generate Quiz (5 questions, scoring)
- Profile & Stats, Leaderboard, theme presets
- Server-side: `/ocr?action=ping` (3 providers), AI router passage JSON
  (qwen/qwen3.8-27b, 1.3 s, verbatim excerpt, footer skipped)

## 6. Build artefacts

- `build/app/outputs/flutter-apk/app-release.apk` — 24,851,525 bytes (23.7 MB),
  arm64, R8-shrunk, debug-signed.
- Rebuild: `flutter build apk --release --target-platform android-arm64
  --dart-define-from-file=secrets.json`
- Install: `adb install -r build/app/outputs/flutter-apk/app-release.apk`

## 7. Known limitations (not bugs in the app)

- `adb shell input text` does not reach Flutter text fields on this phone
  (IME composition + AnyDesk accessibility focus). Use real taps or load text
  from a file when testing.
- Android photo picker occasionally returns a permission-denied Uri; the app
  reports it, retrying works.
- Windows SmartScreen prompt persists without a trusted code-signing
  certificate (`docs/WINDOWS_SIGNING.md`).
