<#
.SYNOPSIS
    Signs the Smart Student AI Windows executable so Windows can verify who
    published it.

.DESCRIPTION
    Windows SmartScreen ("Windows protected your PC") appears for any file that
    is not signed by a certificate chaining to a trusted CA *and* that has not
    built up download reputation. Running this script with a real certificate
    is the only way to remove that warning.

    Two kinds of certificate work:
      * EV code-signing (hardware token / cloud HSM) — removes the warning
        immediately, even for a brand-new publisher.
      * OV code-signing — the warning fades away after enough downloads.

    A self-signed certificate ("-SelfSigned") only makes the file
    cryptographically signed; SmartScreen will still warn because no CA vouches
    for it. It is useful for testing the signing pipeline only.

.PARAMETER PfxPath
    Path to a .pfx/.p12 file with the code-signing certificate.

.PARAMETER PfxPassword
    Password for the .pfx file. Omit to be prompted securely.

.PARAMETER TimestampUrl
    RFC 3161 timestamp server. Defaults to DigiCert's public one. Timestamping
    keeps signatures valid after the certificate expires.

.PARAMETER SelfSigned
    Create/use a local self-signed certificate instead of a .pfx. For testing.

.EXAMPLE
    .\tool\sign_windows.ps1 -PfxPath C:\certs\smart.pfx

.EXAMPLE
    .\tool\sign_windows.ps1 -PfxPath C:\certs\smart.pfx -PfxPassword 'secret'

.EXAMPLE
    .\tool\sign_windows.ps1 -SelfSigned
#>
[CmdletBinding(DefaultParameterSetName = 'Pfx')]
param(
    [Parameter(ParameterSetName = 'Pfx', Mandatory = $true)]
    [string]$PfxPath,

    [Parameter(ParameterSetName = 'Pfx')]
    [string]$PfxPassword,

    [Parameter(ParameterSetName = 'SelfSigned', Mandatory = $true)]
    [switch]$SelfSigned,

    [string]$TimestampUrl = 'http://timestamp.digicert.com',

    [string]$BuildDir = "$PSScriptRoot\..\build\windows\x64\runner\Release",

    [string]$DistDir = "$PSScriptRoot\..\dist"
)

$ErrorActionPreference = 'Stop'

function Get-SignTool {
    $candidates = @(
        (Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName),
        (Get-ChildItem "${env:ProgramFiles}\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName)
    ) | Where-Object { $_ -and (Test-Path $_) }

    if (-not $candidates) {
        throw 'signtool.exe was not found. Install the Windows 10/11 SDK ("Signing Tools for Desktop Apps").'
    }
    return $candidates[0]
}

function Sign-File {
    param([string]$Path, [string[]]$ExtraArgs)

    if (-not (Test-Path $Path)) {
        Write-Host "  skip (missing): $Path" -ForegroundColor DarkYellow
        return
    }

    Write-Host "  signing: $Path" -ForegroundColor Cyan
    $arguments = @('sign', '/fd', 'sha256', '/tr', $TimestampUrl, '/td', 'sha256') + $ExtraArgs + @($Path)
    & $Script:Signtool @arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "signtool failed for $Path (exit $LASTEXITCODE)"
    }
}

$Script:Signtool = Get-SignTool
Write-Host "signtool: $Script:Signtool" -ForegroundColor DarkGray

$signArgs = @()
if ($PSCmdlet.ParameterSetName -eq 'SelfSigned') {
    $subject = 'CN=Smart Student AI (self-signed, test only)'
    $cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq $subject } | Select-Object -First 1
    if (-not $cert) {
        Write-Host "Creating self-signed certificate '$subject' for 3 years..." -ForegroundColor Yellow
        $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $subject `
            -CertStoreLocation Cert:\CurrentUser\My `
            -NotAfter (Get-Date).AddYears(3) `
            -KeyUsage DigitalSignature
    }
    $signArgs = @('/sha1', $cert.Thumbprint)
} else {
    if (-not (Test-Path $PfxPath)) { throw "Certificate not found: $PfxPath" }
    if (-not $PfxPassword) {
        $secure = Read-Host -Prompt 'Certificate password' -AsSecureString
        $PfxPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    }
    $signArgs = @('/f', (Resolve-Path $PfxPath).Path, '/p', $PfxPassword)
}

$targets = @(
    (Join-Path $BuildDir 'smart_student_ai.exe'),
    (Join-Path $DistDir 'SmartStudentAI-Windows-x64\smart_student_ai.exe')
)

foreach ($target in $targets) { Sign-File -Path $target -ExtraArgs $signArgs }

Write-Host ''
Write-Host 'Signed files:' -ForegroundColor Green
foreach ($target in $targets) {
    if (Test-Path $target) {
        Get-AuthenticodeSignature $target |
            Select-Object Status, @{n = 'File'; e = { Split-Path $_.Path -Leaf } } |
            Format-Table -AutoSize
    }
}

Write-Host ''
Write-Host 'Remember to rebuild the portable ZIP so it contains the signed exe:' -ForegroundColor Yellow
Write-Host '  Compress-Archive -Path dist\SmartStudentAI-Windows-x64 -DestinationPath dist\SmartStudentAI-Windows-x64.zip -Force'
