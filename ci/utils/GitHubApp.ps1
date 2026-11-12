function ConvertTo-GitHubBase64Url([byte[]]$Bytes) {
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-GitHubAppJwt {
    if ([string]::IsNullOrWhiteSpace($env:GITHUB_APP_CLIENT_ID) -or
        [string]::IsNullOrWhiteSpace($env:GITHUB_APP_PRIVATE_KEY_BASE64)) {
        throw 'GitHub publication requires GITHUB_APP_CLIENT_ID and secured GITHUB_APP_PRIVATE_KEY_BASE64.'
    }
    $git = Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $gitRoot = Split-Path (Split-Path $git.Source -Parent) -Parent
    $openssl = Join-Path $gitRoot 'usr/bin/openssl.exe'
    if (-not (Test-Path -LiteralPath $openssl -PathType Leaf)) { throw 'OpenSSL from Git for Windows is required for GitHub App authentication.' }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $header = ConvertTo-GitHubBase64Url ([Text.Encoding]::UTF8.GetBytes('{"alg":"RS256","typ":"JWT"}'))
    $claims = @{ iat = $now - 60; exp = $now + 540; iss = $env:GITHUB_APP_CLIENT_ID } | ConvertTo-Json -Compress
    $payload = $header + '.' + (ConvertTo-GitHubBase64Url ([Text.Encoding]::UTF8.GetBytes($claims)))
    $directory = Join-Path ([IO.Path]::GetTempPath()) ('provdesk-github-app-' + [guid]::NewGuid().ToString('N'))
    $keyPath = Join-Path $directory 'key.pem'
    $payloadPath = Join-Path $directory 'payload.txt'
    $signaturePath = Join-Path $directory 'signature.bin'
    # PowerShell 5.1 cannot import PEM keys. Restrict the temporary directory before writing the key.
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner($identity)
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
        $identity, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
    $null = [IO.Directory]::CreateDirectory($directory, $acl)
    try {
        [IO.File]::WriteAllBytes($keyPath, [Convert]::FromBase64String($env:GITHUB_APP_PRIVATE_KEY_BASE64))
        [IO.File]::WriteAllText($payloadPath, $payload, [Text.Encoding]::ASCII)
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $null = & $openssl dgst -sha256 -sign $keyPath -out $signaturePath $payloadPath 2>&1
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $previousPreference }
        if ($code -ne 0) { throw 'OpenSSL signing failed.' }
        return $payload + '.' + (ConvertTo-GitHubBase64Url ([IO.File]::ReadAllBytes($signaturePath)))
    } catch {
        throw 'Cannot sign the GitHub App JWT. Check the base64-encoded PEM private key and Git for Windows.'
    } finally {
        foreach ($path in @($keyPath, $payloadPath, $signaturePath)) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
        }
        [IO.Directory]::Delete($directory)
    }
}

function Invoke-GitHubAppSession([scriptblock]$Action) {
    if ($env:BITBUCKET_BRANCH -cne 'master') { throw 'GitHub App authentication is restricted to master.' }
    $null = Get-Command gh -CommandType Application -ErrorAction Stop
    $repository = Get-GitHubReleaseRepository
    $jwt = New-GitHubAppJwt
    $headers = @{
        Authorization = "Bearer $jwt"
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent' = 'ProVDesk-Bitbucket-CI'
    }
    try {
        $installation = Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/$repository/installation" -Headers $headers -ErrorAction Stop
        $body = @{ repositories = @($repository.Split('/')[1]); permissions = @{ contents = 'write' } } | ConvertTo-Json -Depth 3 -Compress
        $response = Invoke-RestMethod -Method Post -Uri "https://api.github.com/app/installations/$($installation.id)/access_tokens" -Headers $headers -ContentType 'application/json' -Body $body -ErrorAction Stop
    } catch {
        throw 'GitHub App authentication failed. Check the app installation, repository access, Contents: write permission and runner clock/network.'
    }
    if ([string]::IsNullOrWhiteSpace($response.token)) { throw 'GitHub did not return an installation token.' }
    $previousToken = $env:GH_TOKEN
    try {
        $env:GH_TOKEN = $response.token
        & $Action
    } finally {
        try {
            $headers.Authorization = 'Bearer ' + $response.token
            $null = Invoke-RestMethod -Method Delete -Uri 'https://api.github.com/installation/token' -Headers $headers -ErrorAction Stop
        } catch {
            Write-Warning 'GitHub installation token revocation failed; the token will expire automatically.'
        } finally { $env:GH_TOKEN = $previousToken }
    }
}
