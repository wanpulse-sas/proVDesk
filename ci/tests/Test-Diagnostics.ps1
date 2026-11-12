#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../utils/Diagnostics.ps1')
$repository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture = Join-Path $repository ('work/diagnostics-' + [guid]::NewGuid().ToString('N'))
$logDir = "$fixture/build-tools/vcpkg/buildtrees/test"
New-Item -ItemType Directory -Force -Path $logDir, "$fixture/signing-work" | Out-Null
New-Item -ItemType Directory -Force -Path "$fixture/flutter/build/windows" | Out-Null
Set-Content "$fixture/flutter/build/windows/CMakeConfigureLog.yaml" 'flutter configure log'
$env:TEST_DIAGNOSTIC_SECRET = 'test-secret-value'
$env:TEST_DIAGNOSTIC_PRIVATE_KEY_BASE64 = 'fixture-private-key-value'
Set-Content "$logDir/stdout.log" 'error test-secret-value fixture-private-key-value https://user:credential@example.invalid/file'
Set-Content "$fixture/signing-work/private.log" 'must not be exported'
$large = [IO.File]::Create("$logDir/large.log")
$large.SetLength(6MB)
$large.Dispose()
Export-BuildDiagnostics $fixture
if ((Get-Content "$fixture/diagnostics/flutter/build/windows/CMakeConfigureLog.yaml" -Raw).Trim() -ne 'flutter configure log') { throw 'Flutter checkout diagnostics missing.' }
$text = Get-Content "$fixture/diagnostics/build-tools/vcpkg/buildtrees/test/stdout.log" -Raw
if ($text -match 'test-secret-value|fixture-private-key-value|credential' -or $text -notmatch 'REDACTED') { throw 'Secret redaction failed.' }
if (Test-Path "$fixture/diagnostics/signing-work/private.log") { throw 'Non-allowlisted output exported.' }
if (Test-Path "$fixture/diagnostics/build-tools/vcpkg/buildtrees/test/large.log") { throw 'Oversized log exported.' }
Write-Host 'Diagnostic allowlist, size and secret-redaction tests passed.'
