#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../utils/Common.ps1')
$script:payload = Join-Path $root ('work/drivers-' + [guid]::NewGuid().ToString('N'))
$members = @('usbmmidd_v2/usbmmIdd.inf', 'usbmmidd_v2/x64/usbmmIdd.dll',
    'drivers/RustDeskPrinterDriver/RustDeskPrinterDriver.inf',
    'drivers/RustDeskPrinterDriver/RustDeskPrinterDriver.gpd',
    'drivers/RustDeskPrinterDriver/RustDeskPrinterDriver-manifest.ini',
    'drivers/RustDeskPrinterDriver/RustDeskPrinterDriverRenderFilter-PipelineConfig.xml',
    'drivers/RustDeskPrinterDriver/RustDeskPrinterDriverRenderFilter.dll')
foreach ($relative in $members) {
    $path = Join-Path $payload $relative
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    Set-Content -LiteralPath $path -Value 'fixture'
}
function Assert-Signature { param($FilePath, [switch]$ThirdParty) }
$script:verifyCode = 0
function Mock-Catalog { $global:LASTEXITCODE = $script:verifyCode }
$env:SIGNTOOL_VERIFY_PATH = 'Mock-Catalog'
Assert-DriverCatalogs
if ((Get-SigningAction 'usbmmidd_v2/x64/usbmmIdd.dll' 'NotSigned' '') -ne 'DriverCatalog') { throw 'Verified member rejected.' }
$unexpected = Join-Path $payload 'usbmmidd_v2/x64/unverified.exe'
Set-Content $unexpected 'fixture'
$failed = $false
try { Assert-DriverCatalogs } catch { $failed = $true }
if (-not $failed -or $script:verifiedCatalogMembers.Count) { throw 'Unexpected file accepted or stale catalog state retained.' }
$failed = $false
try { Get-SigningAction 'usbmmidd_v2/x64/unverified.exe' 'NotSigned' '' } catch { $failed = $true }
if (-not $failed) { throw 'Unknown driver exempted.' }
Remove-Item -LiteralPath $unexpected
$script:verifyCode = 1
$failed = $false
try { Assert-DriverCatalogs } catch { $failed = $true }
if (-not $failed -or $script:verifiedCatalogMembers.Count) { throw 'Invalid catalog membership accepted.' }
Write-Host 'Driver catalog allowlist tests passed (mocked signature verification).'
