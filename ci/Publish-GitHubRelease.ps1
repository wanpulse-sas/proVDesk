#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'utils/Common.ps1')
. (Join-Path $PSScriptRoot 'utils/Publication.ps1')
. (Join-Path $PSScriptRoot 'utils/GitHubRelease.ps1')
Initialize-Signing
Invoke-GitHubAppSession { Publish-SignedGitHubRelease -OutputDirectory "$root/out" }
