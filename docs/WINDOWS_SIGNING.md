# Windows "Windows protected your PC" — what it is and how to remove it

When someone downloads `SmartStudentAI-Windows-x64.zip` from the internet,
Windows attaches a **Mark-of-the-Web** to the file. Because the app is not
signed with a certificate from a trusted authority, SmartScreen shows:

> Windows protected your PC → More info → Run anyway

That screen comes from the operating system, not from the app. There is no code
change, registry tweak or build flag that removes it. **Only a code-signing
certificate from a trusted CA removes it**, because Windows needs to know who
published the file.

## Options, best to worst

| Option | SmartScreen | Cost | Notes |
| --- | --- | --- | --- |
| **EV code-signing certificate** (hardware token or cloud HSM) | Removed immediately | ~$300–600 / year | The only option that removes the warning on day one. |
| **OV code-signing certificate** (file-based .pfx) | Fades after enough downloads | ~$150–300 / year | Warning appears at first; Microsoft builds reputation per publisher over time. |
| **Self-signed certificate** | Still warns | Free | Marks the file signed, but no CA vouches for it. Testing only. |
| **Microsoft Store / MSIX distribution** | Handled by the Store | Store account | The Store signs packages it publishes. |

## Signing the build

`tool/sign_windows.ps1` signs both the build output and the packaged copy:

```powershell
# With a real certificate
.\tool\sign_windows.ps1 -PfxPath C:\certs\smart.pfx
# Then re-create the ZIP so it contains the signed exe
Compress-Archive -Path dist\SmartStudentAI-Windows-x64 `
                 -DestinationPath dist\SmartStudentAI-Windows-x64.zip -Force

# Testing the pipeline without buying a certificate
.\tool\sign_windows.ps1 -SelfSigned
```

The script uses `signtool.exe` from the Windows 10/11 SDK and timestamps the
signature (DigiCert RFC 3161) so it stays valid after the certificate expires.

## What we do in the meantime

The app is self-contained (Visual C++ runtime and UCRT are bundled), so the
only friction on a fresh PC is that first SmartScreen prompt. Until a
certificate is purchased:

1. `README.txt` in the package tells the user to choose **More info → Run anyway**.
2. Your own machines and the school's PCs can whitelist the folder
   (`Add-MpPreference -ExclusionPath`) or the file, so no prompt appears.
3. Every future build is a one-line sign command once a certificate exists.
