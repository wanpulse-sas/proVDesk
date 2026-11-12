#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:BITBUCKET_BRANCH -cne 'master') { throw 'SMB publication is restricted to master.' }
. (Join-Path $PSScriptRoot 'utils/Common.ps1')
. (Join-Path $PSScriptRoot 'utils/Publication.ps1')
Initialize-Signing
$credential = Get-PublicationCredential
$manifest = Get-Content -LiteralPath "$root/out/build.json" -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($env:BITBUCKET_BUILD_NUMBER) -or
    [string]::IsNullOrWhiteSpace($env:BITBUCKET_COMMIT) -or
    $manifest.BuildNumber -ne $env:BITBUCKET_BUILD_NUMBER -or
    $manifest.PipelineCommit -ne $env:BITBUCKET_COMMIT) {
    throw 'Publication requires the signed output of the current Bitbucket build.'
}
Publish-SignedInstaller -FilePath "$root/out/ProVDesk.exe" -ExpectedSHA256 $manifest.FinalSHA256 -Credential $credential -ExpectedVersion $manifest.Version
