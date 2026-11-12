#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'utils/Common.ps1')
Assert-FreeDiskSpace 'Prepare-Source'

# Validate configuration, then fetch the pinned GitHub commit and submodules.
Initialize-Signing
$lock = Get-Content -Encoding UTF8 "$root/ci/dependencies.json" -Raw | ConvertFrom-Json
# Push builds use the approved source lock when no manual revision was supplied.
if ([string]::IsNullOrWhiteSpace($env:GITHUB_REVISION)) { $env:GITHUB_REVISION = $lock.sourceCommit }
if ($env:GITHUB_REVISION -notmatch '^[a-fA-F0-9]{40}$') {
    throw 'GITHUB_REVISION doit etre un SHA GitHub complet approuve.'
}
if ($env:GITHUB_REVISION -ne $lock.sourceCommit) { throw 'Ce pipeline complet est valide pour le commit epingle ; revoir les adaptations avant de changer le commit.' }
# Reject stale build directories instead of reusing old binaries.
foreach ($directory in @('source', 'out', 'signing-work', 'build-tools')) {
    if (Test-Path -LiteralPath $directory) { throw "Repertoire deja present : $directory. Utiliser un checkout propre." }
}
$work = (New-Item -ItemType Directory -Path signing-work).FullName
git init source
Assert-NativeSuccess 'git init'
git -C source remote add origin https://github.com/wanpulse-sas/proVDesk.git
Assert-NativeSuccess 'git remote'
git -C source fetch --depth 1 origin $env:GITHUB_REVISION
Assert-NativeSuccess 'git fetch'
git -C source checkout --detach FETCH_HEAD
Assert-NativeSuccess 'git checkout'
git -C source submodule update --init --recursive
Assert-NativeSuccess 'git submodule'
$sourceCommit = git -C source rev-parse HEAD
Assert-NativeSuccess 'git rev-parse'
if ($sourceCommit -ne $env:GITHUB_REVISION) { throw 'Commit source inattendu.' }
Set-Content "$work/source-commit.txt" $sourceCommit -Encoding ASCII
$submodules = git -C source submodule status --recursive
Assert-NativeSuccess 'git submodule status'
Set-Content "$work/submodules-before-build.txt" $submodules -Encoding UTF8
