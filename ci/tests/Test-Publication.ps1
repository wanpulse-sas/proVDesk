#Requires -Version 5.1
# Exercise real file publication with a local drive and mocked signature/SMB authentication.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../utils/Publication.ps1')
$savedEnvironment = @{}
foreach ($name in @('ARTIFACTS_SHARING_HOST', 'ARTIFACTS_SHARING_USER', 'ARTIFACTS_SHARING_PASSWORD')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
}
try {
$env:ARTIFACTS_SHARING_HOST = 'storage-fixture.example'
$env:ARTIFACTS_SHARING_USER = 'publisher'
$env:ARTIFACTS_SHARING_PASSWORD = 'fixture'
$repository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture = Join-Path $repository ('work/publication-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$fixture/share", "$fixture/out" -Force | Out-Null
Set-Content "$fixture/out/ProVDesk.exe" 'signed fixture'
Set-Content "$fixture/out/build.json" 'must not be published'
Set-Content "$fixture/out/vendor.dll" 'must not be published'
$hash = (Get-FileHash "$fixture/out/ProVDesk.exe").Hash
$credential = New-Object System.Management.Automation.PSCredential('test', (ConvertTo-SecureString 'fixture' -AsPlainText -Force))
$script:rejectSignature = $false
$script:signatureChecked = $false
$script:mountCount = 0
$script:copyMode = 'success'
$script:copyCount = 0
$script:requireSignature = $true
$script:failureMode = ''
$script:expectedShare = '\\storage-fixture.example\builds'
$script:productionShareRoot = (Get-Command Get-PublicationShareRoot).ScriptBlock
function Get-PublicationShareRoot {
    if ((& $script:productionShareRoot) -ne $script:expectedShare) { throw 'Incorrect configured UNC share.' }
    return "$fixture/share"
}
$script:fixtureVersion = '1.5.0'
function Get-Item {
    param($LiteralPath, $ErrorAction)
    if ($LiteralPath -eq "$fixture/out/ProVDesk.exe") {
        return [pscustomobject]@{ VersionInfo = [pscustomobject]@{ ProductVersion = $script:fixtureVersion } }
    }
    Microsoft.PowerShell.Management\Get-Item -LiteralPath $LiteralPath -ErrorAction Stop
}
function Assert-Signature([string]$FilePath) {
    if ($script:rejectSignature) { throw 'Rejected fixture signature.' }
    $script:signatureChecked = $true
}
function New-PSDrive {
    param($Name, $PSProvider, $Root, $Credential, $ErrorAction)
    if (($script:requireSignature -and -not $script:signatureChecked) -or $Root -ne "$fixture/share" -or $null -eq $Credential) {
        throw 'Incorrect destination or missing pre-upload signature verification.'
    }
    if ($script:failureMode -eq 'connect/authenticate') { throw 'Simulated SMB connection failure.' }
    $script:mountCount++
    Microsoft.PowerShell.Management\New-PSDrive -Name $Name -PSProvider FileSystem -Root "$fixture/share" -Scope Script
}
function Copy-Item {
    param($LiteralPath, $Destination, $ErrorAction)
    $script:copyCount++
    if ((Split-Path $LiteralPath -Leaf) -ne 'ProVDesk.exe') { throw 'Unexpected published file.' }
    Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -ErrorAction Stop
    if ($script:copyMode -eq 'corrupt') { Add-Content -LiteralPath $Destination 'corruption' }
    if ($script:copyMode -eq 'fail') { throw 'Simulated interrupted upload.' }
}
function Expect-Failure([scriptblock]$Action) {
    $failed = $false
    try { & $Action } catch { $failed = $true }
    if (-not $failed) { throw 'Expected publication failure was accepted.' }
}
$publish = { Publish-SignedInstaller "$fixture/out/ProVDesk.exe" $hash $credential '1.5.0' }
& $publish
$destination = "$fixture/share/WanPulse/ProVDesk/ProVDesk-1.5.0.exe"
if ((Get-FileHash $destination).Hash -ne $hash -or $script:copyCount -ne 1) { throw 'First upload failed.' }
# Verify replacement of an existing executable with Windows PowerShell 5.1 file operations.
Set-Content -LiteralPath $destination 'previous build'
& $publish
if ((Get-FileHash $destination).Hash -ne $hash) { throw 'Replacement failed.' }
foreach ($mode in @('corrupt', 'fail')) {
    $script:copyMode = $mode
    Expect-Failure $publish
    if ((Get-FileHash $destination).Hash -ne $hash) { throw 'A failed upload changed the published executable.' }
    if (@(Get-ChildItem "$fixture/share/WanPulse/ProVDesk" -Force).Count -ne 1) { throw 'Temporary upload was not cleaned.' }
}
$mounts = $script:mountCount
$script:rejectSignature = $true
Expect-Failure $publish
$script:rejectSignature = $false
Expect-Failure { Publish-SignedInstaller "$fixture/out/ProVDesk.exe" ('0' * 64) $credential '1.5.0' }
Expect-Failure { Publish-SignedInstaller "$fixture/out/vendor.dll" $hash $credential '1.5.0' }
foreach ($invalid in @('', '..', '../other', '1.5.0\other', '1.5.0.', '1.5.0:stream', '1.5.0 ', "1.5.0`n")) {
    $script:fixtureVersion = $invalid
    Expect-Failure $publish
}
$script:fixtureVersion = '2.0.0'
Expect-Failure $publish
if ($script:mountCount -ne $mounts) { throw 'Unverified input reached the SMB share.' }
$script:copyMode = 'success'
Publish-SignedInstaller "$fixture/out/ProVDesk.exe" $hash $credential '2.0.0'
if ((Get-FileHash "$fixture/share/WanPulse/ProVDesk/ProVDesk-2.0.0.exe").Hash -ne $hash -or
    (Get-FileHash $destination).Hash -ne $hash) { throw 'Versioned executables were not preserved side by side.' }
foreach ($valid in @('1.5.0+68', '1.5.0.1', '2.0.0-rc.1+42')) {
    $script:fixtureVersion = $valid
    if ((Get-InstallerVersion "$fixture/out/ProVDesk.exe") -cne $valid) { throw 'Product version was rewritten.' }
    Publish-SignedInstaller "$fixture/out/ProVDesk.exe" $hash $credential $valid
    if ((Get-FileHash -LiteralPath "$fixture/share/WanPulse/ProVDesk/ProVDesk-$valid.exe").Hash -ne $hash) {
        throw 'The detected version was not preserved in the published filename.'
    }
}
$entries = @(Get-ChildItem "$fixture/share/WanPulse/ProVDesk" -Force)
if ($entries.Count -ne 5 -or @($entries | Where-Object { $_.PSIsContainer -or $_.Name -notlike 'ProVDesk-*.exe' }).Count) {
    throw 'Publication created a version directory, an unversioned executable or an unexpected artifact.'
}
if ((Get-FileHash "$fixture/out/ProVDesk.exe").Hash -ne $hash) { throw 'Publication modified the source executable.' }
if (@(Get-PSDrive | Where-Object Name -Like 'ProVDeskPublish*').Count) { throw 'Publication drive leaked.' }
$savedUser = $env:ARTIFACTS_SHARING_USER
$savedPassword = $env:ARTIFACTS_SHARING_PASSWORD
try {
    $env:ARTIFACTS_SHARING_USER = 'publisher'
    $env:ARTIFACTS_SHARING_PASSWORD = 'fixture'
    if ((Get-PublicationCredential).UserName -ne 'storage-fixture.example\publisher') { throw 'Incorrect local account qualification.' }
    $env:ARTIFACTS_SHARING_USER = 'DOMAIN\publisher'
    if ((Get-PublicationCredential).UserName -ne 'DOMAIN\publisher') { throw 'Domain account was rewritten.' }
    $env:ARTIFACTS_SHARING_PASSWORD = ''
    Expect-Failure { Get-PublicationCredential }
} finally {
    $env:ARTIFACTS_SHARING_USER = $savedUser
    $env:ARTIFACTS_SHARING_PASSWORD = $savedPassword
}
# Exercise the actual preflight file operations on the local drive.
$script:requireSignature = $false
function Set-Content {
    param($LiteralPath, $Value, [switch]$NoNewline, $Encoding, $ErrorAction)
    if ($script:failureMode -eq 'write') { throw 'Simulated write denial.' }
    Microsoft.PowerShell.Management\Set-Content @PSBoundParameters
}
function Get-Content {
    param($LiteralPath, [switch]$Raw, $ErrorAction)
    if ($script:failureMode -eq 'read') { throw 'Simulated read denial.' }
    Microsoft.PowerShell.Management\Get-Content @PSBoundParameters
}
function Move-Item {
    param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
    if ($script:failureMode -eq 'rename/replace') { throw 'Simulated replacement denial.' }
    Microsoft.PowerShell.Management\Move-Item @PSBoundParameters
}
function Remove-Item {
    param($LiteralPath, [switch]$Force, $ErrorAction)
    if ($script:failureMode -eq 'delete') {
        $script:failureMode = '' # Let finally perform its cleanup after the simulated failure.
        throw 'Simulated delete denial.'
    }
    Microsoft.PowerShell.Management\Remove-Item @PSBoundParameters
}
Assert-PublicationAccess
foreach ($mode in @('connect/authenticate', 'write', 'read', 'rename/replace', 'delete')) {
    $script:failureMode = $mode
    $message = ''
    try { Assert-PublicationAccess } catch { $message = $_.Exception.Message }
    if (-not $message.Contains("[$mode]")) { throw "Preflight did not fail with the expected operation: $mode" }
    if (@(Get-ChildItem "$fixture/share/WanPulse/ProVDesk" -Force).Count -ne 5) { throw 'Preflight leaked temporary files or removed published files.' }
    if (@(Get-PSDrive | Where-Object Name -Like 'ProVDeskPreflight*').Count) { throw 'Preflight drive leaked.' }
    if ((Get-FileHash $destination).Hash -ne $hash) { throw 'Preflight modified a published executable.' }
}
$script:failureMode = ''
$mounts = $script:mountCount
foreach ($invalid in @('', ' ', '\\server\builds', 'server/path', 'server:445', "server`n")) {
    $env:ARTIFACTS_SHARING_HOST = $invalid
    Expect-Failure { Assert-PublicationAccess }
}
if ($script:mountCount -ne $mounts) { throw 'Invalid host reached SMB.' }
# A second host proves that neither publication nor account qualification is hard-coded.
$env:ARTIFACTS_SHARING_HOST = 'another-storage'
$script:expectedShare = '\\another-storage\builds'
if ((Get-PublicationCredential).UserName -ne 'another-storage\publisher') { throw 'Host change did not update account qualification.' }
Assert-PublicationAccess
$script:fixtureVersion = '1.5.0'
$script:requireSignature = $true
& $publish
$env:ARTIFACTS_SHARING_USER = 'publisher@example.test'
if ((Get-PublicationCredential).UserName -ne 'publisher@example.test') { throw 'UPN account was rewritten.' }
# Ensure this gate remains before tool provisioning or compilation.
$runner = [IO.File]::ReadAllText("$repository/ci/Test-Runner.ps1")
if ($runner.IndexOf('Assert-PublicationAccess') -lt 0 -or
    $runner.IndexOf('Assert-PublicationAccess') -gt $runner.IndexOf('Assert-FreeDiskSpace')) {
    throw 'Publication access is not checked at the start of Test-Runner.'
}
Write-Host 'Dynamic host, credentials, publication and SMB preflight operations passed on a local fixture; no server was contacted.'

} finally {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name]) }
}
