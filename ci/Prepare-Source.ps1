#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'utils/Common.ps1')
Assert-FreeDiskSpace 'Prepare-Source'

# Prepare the Bitbucket checkout directly and record its source revision.
Initialize-Signing
$revision = git -C $root rev-parse HEAD
Assert-NativeSuccess 'Read pipeline commit'
if ($revision -notmatch '^[a-fA-F0-9]{40}$') { throw 'Commit du checkout invalide.' }
if (-not [string]::IsNullOrWhiteSpace($env:BITBUCKET_COMMIT) -and $env:BITBUCKET_COMMIT -ne $revision) {
    throw 'Le checkout ne correspond pas au commit du pipeline Bitbucket.'
}
if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_REVISION)) {
    throw 'GITHUB_REVISION est obsolete : selectionner la branche ou le commit du pipeline.'
}
$changes = @(git -C $root status --porcelain --untracked-files=normal)
Assert-NativeSuccess 'Check pipeline working tree'
if ($changes.Count -gt 0) { throw 'Le checkout du pipeline contient des modifications non commitees.' }
# Reject stale build directories instead of reusing old binaries.
foreach ($directory in @('out', 'signing-work', 'build-tools', 'artifacts', 'target', 'flutter/build')) {
    if (Test-Path -LiteralPath $directory) { throw "Repertoire deja present : $directory. Utiliser un checkout propre." }
}
$work = (New-Item -ItemType Directory -Path signing-work).FullName
git -C $root submodule update --init --recursive
Assert-NativeSuccess 'git submodule'
Set-Content "$work/source-commit.txt" $revision -Encoding ASCII
$submodules = git -C $root submodule status --recursive
Assert-NativeSuccess 'git submodule status'
Set-Content "$work/submodules-before-build.txt" $submodules -Encoding UTF8
