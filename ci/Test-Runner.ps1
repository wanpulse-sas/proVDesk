#Requires -Version 5.1
# Check the runner and prepare missing private MSBuild integration; no build or private-key operations.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'utils/Common.ps1')
. (Join-Path $PSScriptRoot 'utils/Publication.ps1')
if ($env:BITBUCKET_BRANCH -ceq 'master') {
    . (Join-Path $PSScriptRoot 'utils/GitHubRelease.ps1')
    Assert-GitHubReleaseAccess
    Assert-PublicationAccess
}
Assert-FreeDiskSpace 'Test-Runner'
if (($env:OS -ne 'Windows_NT') -or -not [Environment]::Is64BitProcess) { throw 'Windows x64 / PowerShell 5.1 x64 requis.' }
foreach ($command in @('git', 'rustup', 'cargo', 'python')) {
    $tool = Get-Command $command -ErrorAction Stop
    Write-Host "$command : $($tool.Source)"
    if ($command -eq 'cargo') { continue } # The pipeline installs the pinned Rust toolchain later.
    & $tool.Source --version | Out-Host
    Assert-NativeSuccess "Version $command"
}
python -c "import sys, venv, ssl; assert sys.maxsize > 2**32, 'Python x64 requis'; assert sys.version_info[:2] == (3, 15), 'Python 3.15.x requis'"
Assert-NativeSuccess 'Python x64 et modules standard'
Initialize-Signing
Use-BuildTools -SkipVisualStudio
$configuration = Get-Vs2026Configuration -PrepareIntegration
Write-Host "VS 2026: $($configuration.InstallationPath)"
Write-Host "v143: $($configuration.V143Version); v142: $($configuration.V142Version)"
Write-Host "v143 MSBuild targets: $($configuration.V143TargetsPath)"
Write-Host "v142 MSBuild targets: $($configuration.V142TargetsPath)"
Write-Host "CMake: $($configuration.CMake)"
Write-Host 'Base configuration found. Key access, SDK components and network access still require runner validation.'
