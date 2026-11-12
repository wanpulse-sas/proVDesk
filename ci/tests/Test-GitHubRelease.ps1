#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../utils/GitHubRelease.ps1')
$saved = @{}
foreach ($name in @('BITBUCKET_BRANCH', 'BITBUCKET_COMMIT', 'BITBUCKET_BUILD_NUMBER', 'GH_TOKEN', 'GITHUB_RELEASE_REPOSITORY')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name)
}
try {
    $env:BITBUCKET_BRANCH = 'master'
    $env:BITBUCKET_COMMIT = 'a' * 40
    $env:BITBUCKET_BUILD_NUMBER = '19'
    $env:GH_TOKEN = 'fixture-token'
    $env:GITHUB_RELEASE_REPOSITORY = 'fixture/product'
    $root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $fixture = Join-Path $root ('work/github-release-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixture | Out-Null
    Set-Content "$fixture/ProVDesk.exe" 'signed fixture'
    $hash = (Get-FileHash "$fixture/ProVDesk.exe").Hash
    Set-Content "$fixture/ProVDesk.exe.sha256" "$hash  ProVDesk.exe"
    @{ Version = '1.5.0'; SourceCommit = $env:BITBUCKET_COMMIT; PipelineCommit = $env:BITBUCKET_COMMIT;
        BuildNumber = '19'; FinalSHA256 = $hash } | ConvertTo-Json | Set-Content "$fixture/build.json"
    function Assert-Signature([string]$FilePath) {
        if ($script:mode -eq 'invalid-signature') { throw 'Invalid fixture signature.' }
        $script:signatureChecked = $true
    }
    function Get-InstallerVersion([string]$FilePath) { return '1.5.0' }
    function Invoke-GitHubCli([string[]]$Arguments) {
        $command = $Arguments[0] + ' ' + $Arguments[1]
        if ($command -eq 'api repos/fixture/product/git/ref/heads/master') {
            return (@{ object = @{ type = 'commit'; sha = $env:BITBUCKET_COMMIT } } | ConvertTo-Json)
        }
        if ($command -eq 'api repos/fixture/product/git/refs') {
            if (-not $script:signatureChecked) { throw 'Unsigned upload attempted.' }
            $script:tagCommit = ($Arguments | Where-Object { $_ -like 'sha=*' }).Substring(4)
            if ('ref=refs/tags/provdesk-1.5.0-build.19' -notin $Arguments) { throw 'Incorrect release tag.' }
            return '{}'
        }
        if ($command -eq 'release create') {
            $script:draft = $true
            $script:assets = @($Arguments | Where-Object { $_ -like "$fixture*" -and $_ -notlike '*release-notes.md' } | ForEach-Object {
                @{ name = [IO.Path]::GetFileName($_); state = 'uploaded'; digest = 'sha256:' + (Get-FileHash $_).Hash.ToLowerInvariant() }
            })
            if ($script:mode -eq 'asset-mismatch') { $script:assets[0].digest = 'sha256:' + ('0' * 64) }
            return ''
        }
        if ($command -eq 'release view') { return '{"databaseId": 123}' }
        if ($command -eq 'api repos/fixture/product/releases/123') {
            return (@{ draft = $script:draft; assets = $script:assets } | ConvertTo-Json -Depth 5)
        }
        if ($command -eq 'release edit') { $script:draft = $false; $script:published = $true; return '' }
        throw "Unexpected fixture request: $command"
    }
    foreach ($script:mode in @('success', 'invalid-signature', 'asset-mismatch')) {
        $script:signatureChecked = $false
        $script:published = $false
        $script:draft = $false
        $script:tagCommit = ''
        $script:assets = @()
        $failed = $false
        try { Publish-SignedGitHubRelease $fixture } catch { $failed = $true }
        if ($script:mode -eq 'success') {
            if ($failed -or -not $script:published -or $script:draft -or $script:tagCommit -ne $env:BITBUCKET_COMMIT) {
                throw 'Signed release was not published for the built commit.'
            }
            if (($script:assets.name | Sort-Object) -join ',' -cne 'build.json,ProVDesk-1.5.0-windows-x86_64.exe,ProVDesk-1.5.0-windows-x86_64.exe.sha256') {
                throw 'Unexpected release assets.'
            }
        } elseif (-not $failed -or $script:published) { throw 'Invalid release was published.' }
        if ($script:mode -eq 'invalid-signature' -and $script:tagCommit) { throw 'Invalid signature changed the remote.' }
        if ($script:mode -eq 'asset-mismatch' -and -not $script:draft) { throw 'Failed upload did not remain a draft.' }
    }
    Write-Host 'Signed GitHub release, signature refusal and failed asset verification passed (local fixtures).'
} finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
}
