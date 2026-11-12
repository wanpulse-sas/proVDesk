#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../utils/Common.ps1')
$script:expectedThumbprint = 'A' * 40
# Membership verification itself is exercised by Test-DriverCatalogs.
$script:verifiedCatalogMembers = @('usbmmidd_v2/x64/usbmmIdd.dll')
$cases = @(
    @('ProVDesk.exe', 'NotSigned', '', 'WanPulse'),
    @('tools/updater.exe', 'NotSigned', '', 'WanPulse'),
    @('tools/uninstall.exe', 'NotSigned', '', 'WanPulse'),
    @('flutter_windows.dll', 'NotSigned', '', 'WanPulse'),
    @('vendor/library.dll', 'Valid', ('B' * 40), 'ThirdParty'),
    @('ProVDesk.exe', 'Valid', ('A' * 40), 'WanPulseExisting'),
    @('usbmmidd_v2/x64/usbmmIdd.dll', 'NotSigned', '', 'DriverCatalog')
)
foreach ($case in $cases) {
    if ((Get-SigningAction $case[0] $case[1] $case[2]) -ne $case[3]) { throw "Politique incorrecte : $($case[0])" }
}
foreach ($case in @(@('ProVDesk.exe', 'Valid'), @('vendor/library.dll', 'HashMismatch'), @('vendor/library.dll', 'UnknownError'))) {
    $rejected = $false
    try { $null = Get-SigningAction $case[0] $case[1] ('B' * 40) } catch { $rejected = $true }
    if (-not $rejected) { throw "Signature inattendue acceptee : $($case[0])" }
}

function Mock-Verify { $global:LASTEXITCODE = $script:verifyCode; Write-Output 'Verification simulated' }
function Get-AuthenticodeSignature { param($LiteralPath) $script:signature }
$env:SIGNTOOL_VERIFY_PATH = 'Mock-Verify'
$script:verifyCode = 0
$script:signature = [pscustomobject]@{
    Status = 'Valid'
    SignerCertificate = [pscustomobject]@{ Thumbprint = ('B' * 40) }
    TimeStamperCertificate = $null
}
$output = @(Assert-Signature 'vendor.dll' -ThirdParty)
if ($output.Count -ne 0) { throw 'Sortie du verificateur melangee au rapport JSON.' }
$rejected = $false
try { Assert-Signature 'ProVDesk.exe' } catch { $rejected = $true }
if (-not $rejected) { throw 'Signature tierce acceptee comme WanPulse.' }
$script:signature.SignerCertificate.Thumbprint = $script:expectedThumbprint
$rejected = $false
try { Assert-Signature 'ProVDesk.exe' } catch { $rejected = $true }
if (-not $rejected) { throw 'Horodatage WanPulse manquant accepte.' }
$script:signature.TimeStamperCertificate = [pscustomobject]@{ Subject = 'Timestamp' }
Assert-Signature 'ProVDesk.exe'
$script:verifyCode = 2
$rejected = $false
try { Assert-Signature 'ProVDesk.exe' } catch { $rejected = $true }
if (-not $rejected) { throw 'Avertissement SignTool accepte.' }
Write-Host 'Signing policy tests passed (mocked tools; no real signing).'

# An inherited workspace flag must not disable this dedicated signing pipeline.
$savedSkip = $env:SKIP_SIGNATURE
$savedContainer = $env:SIGNING_CONTAINER
try {
    $env:SKIP_SIGNATURE = 'true'
    $env:SIGNING_CONTAINER = ''
    $message = ''
    try { Initialize-Signing } catch { $message = $_.Exception.Message }
    if ($env:SKIP_SIGNATURE -ne 'false') { throw 'Inherited skip flag was not overridden.' }
    if ($message -notmatch 'SIGNING_CONTAINER') { throw 'Required signing credentials were not checked.' }
    Write-Host 'Mandatory signing initialization test passed.'
} finally {
    $env:SKIP_SIGNATURE = $savedSkip
    $env:SIGNING_CONTAINER = $savedContainer
}