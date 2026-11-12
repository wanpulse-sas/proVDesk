#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../utils/GitHubRelease.ps1')
$saved = @{}
foreach ($name in @('BITBUCKET_BRANCH', 'GH_TOKEN', 'GITHUB_APP_CLIENT_ID', 'GITHUB_APP_PRIVATE_KEY_BASE64', 'GITHUB_RELEASE_REPOSITORY')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name)
}
$git = Get-Command git -CommandType Application | Select-Object -First 1
$gitRoot = Split-Path (Split-Path $git.Source -Parent) -Parent
$openssl = Join-Path $gitRoot 'usr/bin/openssl.exe'
$fixture = Join-Path $PSScriptRoot ('../../work/github-app-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
try {
    & $openssl genrsa -out "$fixture/key.pem" 2048
    if ($LASTEXITCODE -ne 0) { throw 'Cannot generate fixture key.' }
    & $openssl pkey -in "$fixture/key.pem" -pubout -out "$fixture/public.pem"
    if ($LASTEXITCODE -ne 0) { throw 'Cannot export fixture public key.' }
    $env:GITHUB_APP_CLIENT_ID = 'Iv1.fixture'
    $env:GITHUB_APP_PRIVATE_KEY_BASE64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("$fixture/key.pem"))
    $jwt = New-GitHubAppJwt
    $parts = $jwt.Split('.')
    [IO.File]::WriteAllText("$fixture/payload", ($parts[0] + '.' + $parts[1]), [Text.Encoding]::ASCII)
    function Decode([string]$Value) {
        $value = $Value.Replace('-', '+').Replace('_', '/')
        return ,([Convert]::FromBase64String($value.PadRight($value.Length + ((4 - $value.Length % 4) % 4), '=')))
    }
    [IO.File]::WriteAllBytes("$fixture/signature", (Decode $parts[2]))
    & $openssl dgst -sha256 -verify "$fixture/public.pem" -signature "$fixture/signature" "$fixture/payload"
    if ($LASTEXITCODE -ne 0) { throw 'JWT RSA signature does not verify.' }
    $claims = [Text.Encoding]::UTF8.GetString((Decode $parts[1])) | ConvertFrom-Json
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($claims.iss -ne 'Iv1.fixture' -or $claims.iat -gt $now - 50 -or $claims.exp -le $now -or $claims.exp -gt $now + 600) {
        throw 'Invalid JWT identity or lifetime.'
    }

    # Network and gh discovery are replaced; signing above uses a disposable real key.
    function Get-Command { return @{ Source = 'fixture-gh' } }
    function New-GitHubAppJwt { return 'fixture-jwt' }
    $script:issued = 0
    $script:revoked = 0
    function Invoke-RestMethod($Method, $Uri, $Headers, $ContentType, $Body, $ErrorAction) {
        if ($Method -eq 'Get' -and $Uri -eq 'https://api.github.com/repos/fixture/product/installation') {
            if ($Headers.Authorization -ne 'Bearer fixture-jwt') { throw 'Missing App JWT.' }
            return @{ id = 123 }
        }
        if ($Method -eq 'Post' -and $Uri -eq 'https://api.github.com/app/installations/123/access_tokens') {
            $request = $Body | ConvertFrom-Json
            if (@($request.repositories).Count -ne 1 -or $request.repositories[0] -ne 'product' -or $request.permissions.contents -ne 'write') {
                throw 'Token is not scoped to the release repository.'
            }
            $script:issued++
            return @{ token = "fixture-installation-$script:issued" }
        }
        if ($Method -eq 'Delete' -and $Uri -eq 'https://api.github.com/installation/token') {
            if ($Headers.Authorization -ne "Bearer fixture-installation-$script:issued") { throw 'Wrong token revoked.' }
            $script:revoked++
            return
        }
        throw 'Unexpected fixture HTTP request.'
    }
    $env:BITBUCKET_BRANCH = 'master'
    $env:GITHUB_RELEASE_REPOSITORY = 'fixture/product'
    $env:GH_TOKEN = 'previous-token'
    foreach ($fail in @($false, $true)) {
        $failed = $false
        try {
            Invoke-GitHubAppSession {
                if ($env:GH_TOKEN -ne "fixture-installation-$script:issued") { throw 'Installation token not available to gh.' }
                if ($fail) { throw 'Fixture publication failure.' }
            }
        } catch {
            if (-not $fail -or $_.Exception.Message -ne 'Fixture publication failure.') { throw }
            $failed = $true
        }
        if ($failed -ne $fail -or $env:GH_TOKEN -ne 'previous-token' -or $script:revoked -ne $script:issued) {
            throw 'Session did not restore the environment and revoke its token.'
        }
    }
    $env:BITBUCKET_BRANCH = 'codex/validation'
    $refused = $false
    try { Invoke-GitHubAppSession { throw 'Must not run.' } } catch {
        if ($_.Exception.Message -ne 'GitHub App authentication is restricted to master.') { throw }
        $refused = $true
    }
    if (-not $refused -or $script:issued -ne 2) { throw 'Unexpected installation token request.' }
    Write-Host 'GitHub App JWT signature, scoped sessions, cleanup and branch restriction passed (offline fixtures).'
} finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    foreach ($name in @('key.pem', 'public.pem', 'payload', 'signature')) {
        $path = Join-Path $fixture $name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    Remove-Item -LiteralPath $fixture
}
