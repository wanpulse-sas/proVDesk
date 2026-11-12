#Requires -Version 5.1
# Run the actual signing stage on disposable files with fake native signing tools.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture = Join-Path $repository ('work/signing-flow-' + [guid]::NewGuid().ToString('N'))
$payload = "$fixture/artifacts/ci-payload"
New-Item -ItemType Directory -Force -Path "$fixture/ci/utils", "$fixture/signing-work", $payload | Out-Null
foreach ($name in @('Common', 'VisualStudio', 'BuildResources')) {
    Copy-Item "$repository/ci/utils/$name.ps1" "$fixture/ci/utils/$name.ps1"
}
Copy-Item "$repository/ci/Sign-Payload.ps1" "$fixture/ci/Sign-Payload.ps1"
Set-Content "$payload/ProVDesk.exe" 'OWN'
Set-Content "$payload/vendor.dll" 'VENDOR'
$driverFiles = @('usbmmidd_v2/usbmmidd.cat', 'usbmmidd_v2/usbmmIdd.inf', 'usbmmidd_v2/x64/usbmmIdd.dll',
    'drivers/RustDeskPrinterDriver/rustdeskprinterdriver.cat', 'drivers/RustDeskPrinterDriver/RustDeskPrinterDriver.inf',
    'drivers/RustDeskPrinterDriver/RustDeskPrinterDriver.gpd', 'drivers/RustDeskPrinterDriver/RustDeskPrinterDriver-manifest.ini',
    'drivers/RustDeskPrinterDriver/RustDeskPrinterDriverRenderFilter-PipelineConfig.xml',
    'drivers/RustDeskPrinterDriver/RustDeskPrinterDriverRenderFilter.dll')
foreach ($relative in $driverFiles) {
    $path = Join-Path $payload $relative
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    Set-Content $path 'DRIVER'
}
$signer = @'
@echo off
set "target=%~4"
echo SIGNED>>"%target:~10%"
exit /b 0
'@
Set-Content "$fixture/sign.cmd" $signer -Encoding ASCII
Set-Content "$fixture/verify.cmd" "@echo off`r`nexit /b 0" -Encoding ASCII
$child = @'
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/ci/utils/Common.ps1"
$env:WP_SIGNTOOL_PATH = "$PSScriptRoot/sign.cmd"
$env:SIGNTOOL_VERIFY_PATH = "$PSScriptRoot/verify.cmd"
$env:SIGNING_CONTAINER = 'test'
$env:SIGNING_PASSWORD = 'test'
$env:SIGNING_THUMBPRINT = 'A' * 40
$env:MIN_FREE_DISK_GB = '1'
function Get-AuthenticodeSignature {
    param($LiteralPath)
    $text = Get-Content -LiteralPath $LiteralPath -Raw
    $own = $text.Contains('SIGNED')
    $vendor = $text.Contains('VENDOR') -or $LiteralPath.EndsWith('.cat')
    [pscustomobject]@{
        Status = if ($own -or $vendor) { 'Valid' } else { 'NotSigned' }
        SignerCertificate = if ($own) { [pscustomobject]@{ Thumbprint = ('A' * 40); Subject = 'Test signer' } }
            elseif ($vendor) { [pscustomobject]@{ Thumbprint = ('B' * 40); Subject = 'Test vendor' } } else { $null }
        TimeStamperCertificate = if ($own) { [pscustomobject]@{ Subject = 'Test timestamp' } } else { $null }
    }
}
$original = @(Get-PayloadManifest)
ConvertTo-Json -InputObject $original | Set-Content "$work/payload-unsigned.json" -Encoding UTF8
. "$PSScriptRoot/ci/Sign-Payload.ps1"
Assert-SignedPayload
$after = @(Get-PayloadManifest)
foreach ($entry in $original) {
    $actual = $after | Where-Object Path -eq $entry.Path
    if ($entry.Path -eq 'ProVDesk.exe') {
        if ($actual.SHA256 -eq $entry.SHA256) { throw 'Own binary was not signed.' }
    } elseif ($actual.SHA256 -ne $entry.SHA256) { throw 'Vendor/driver bytes changed.' }
}
$report = Get-Content "$work/signatures.json" -Raw | ConvertFrom-Json
if (@($report | Where-Object Action -eq 'WanPulse').Count -ne 1) { throw 'Unexpected signing count.' }
'@
Set-Content "$fixture/run.ps1" $child -Encoding UTF8
& "$PSHOME/powershell.exe" -NoProfile -File "$fixture/run.ps1"
if ($LASTEXITCODE -ne 0) { throw 'Signing stage integration test failed.' }
Write-Host 'Actual signing-stage manifests, report and byte preservation passed (mocked cryptography).'
