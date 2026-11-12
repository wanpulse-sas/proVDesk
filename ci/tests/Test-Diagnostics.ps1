#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../utils/Diagnostics.ps1')
$repository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture = Join-Path $repository ('work/diagnostics-' + [guid]::NewGuid().ToString('N'))
$logDir = "$fixture/build-tools/vcpkg/buildtrees/test"
New-Item -ItemType Directory -Force -Path $logDir, "$fixture/signing-work" | Out-Null
$env:TEST_DIAGNOSTIC_SECRET = 'test-secret-value'
Set-Content "$logDir/stdout.log" 'error test-secret-value https://user:credential@example.invalid/file'
Set-Content "$fixture/signing-work/private.log" 'must not be exported'
$large = [IO.File]::Create("$logDir/large.log")
$large.SetLength(6MB)
$large.Dispose()
Export-BuildDiagnostics $fixture
$text = Get-Content "$fixture/diagnostics/build-tools/vcpkg/buildtrees/test/stdout.log" -Raw
if ($text -match 'test-secret-value|credential' -or $text -notmatch 'REDACTED') { throw 'Secret redaction failed.' }
if (Test-Path "$fixture/diagnostics/signing-work/private.log") { throw 'Non-allowlisted output exported.' }
if (Test-Path "$fixture/diagnostics/build-tools/vcpkg/buildtrees/test/large.log") { throw 'Oversized log exported.' }
Write-Host 'Diagnostic allowlist, size and secret-redaction tests passed.'
