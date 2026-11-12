#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../utils/Common.ps1')
$fixture = Join-Path $root ('work/sign-call-' + [guid]::NewGuid().ToString('N') + '.cmd')
New-Item -ItemType Directory -Force -Path (Split-Path $fixture -Parent) | Out-Null
$env:WP_SIGNTOOL_PATH = $fixture
$env:SIGNING_CONTAINER = 'test'
$env:SIGNING_PASSWORD = 'dummy-secret'
$script:expectedThumbprint = 'A' * 40
$script:timestampUrl = 'http://example.invalid'
$script:checked = 0
function Assert-Signature { param($FilePath) $script:checked++ }
foreach ($code in @(0, 7)) {
    [IO.File]::WriteAllText($fixture, "@echo off`r`necho dummy-secret 1>&2`r`necho dummy-secret`r`nexit /b $code`r`n")
    $failed = $false
    try {
        $output = @(Invoke-WanPulseSign 'fixture.exe')
        if ($output.Count) { throw 'Framework output leaked into pipeline output.' }
    } catch {
        $failed = $true
        if ($_.Exception.Message -match 'dummy-secret') { throw 'Framework secret leaked.' }
    }
    if ($failed -ne ($code -ne 0)) { throw "Incorrect signing outcome for exit $code" }
    if ($ErrorActionPreference -ne 'Stop') { throw 'Error preference was not restored.' }
}
if ($script:checked -ne 1) { throw 'Signature must be checked only after exit zero.' }
Write-Host 'Native signing stderr/exit-code tests passed.'
