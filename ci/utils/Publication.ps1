# Publish only the verified final executable to the configured product share.
function Get-PublicationHost {
    $server = $env:ARTIFACTS_SHARING_HOST
    if ([string]::IsNullOrWhiteSpace($server)) {
        throw 'Required publication variable is missing: ARTIFACTS_SHARING_HOST'
    }
    if ($server -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]*\z') {
        throw 'ARTIFACTS_SHARING_HOST must contain only a server name or IPv4 address, without a UNC path or share.'
    }
    return $server
}

function Get-PublicationShareRoot {
    return ('\\{0}\builds' -f (Get-PublicationHost))
}

function Get-PublicationCredential {
    $server = Get-PublicationHost
    foreach ($name in @('ARTIFACTS_SHARING_USER', 'ARTIFACTS_SHARING_PASSWORD')) {
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
            throw "Required publication variable is missing: $name"
        }
    }
    $user = $env:ARTIFACTS_SHARING_USER
    if ($user -notmatch '[\\@]') { $user = "$server\$user" }
    $password = ConvertTo-SecureString $env:ARTIFACTS_SHARING_PASSWORD -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential($user, $password)
}

function Assert-PublicationAccess {
    $credential = Get-PublicationCredential
    $share = Get-PublicationShareRoot
    $driveName = 'ProVDeskPreflight' + [guid]::NewGuid().ToString('N')
    $mounted = $false
    $temporary = @()
    $operation = 'connect/authenticate'
    try {
        New-PSDrive -Name $driveName -PSProvider FileSystem -Root $share -Credential $credential -ErrorAction Stop | Out-Null
        $mounted = $true
        # Windows PowerShell 5.1 can repeat a UNC root when resolving a temporary PSDrive.
        # Keep the authenticated SMB connection, but use absolute UNC paths for all file operations.
        $directory = "$share\WanPulse\ProVDesk"
        $operation = 'access/create destination directory'
        New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
        # Probe replacement and deletion using only files owned by this invocation.
        $token = [guid]::NewGuid().ToString('N')
        $source = Join-Path $directory ".provdesk-preflight-$token-source.tmp"
        $target = Join-Path $directory ".provdesk-preflight-$token-target.tmp"
        $temporary = @($source, $target)
        $operation = 'write'
        Set-Content -LiteralPath $source -Value $token -NoNewline -Encoding ASCII -ErrorAction Stop
        Set-Content -LiteralPath $target -Value 'previous probe content' -NoNewline -Encoding ASCII -ErrorAction Stop
        $operation = 'read'
        if ((Get-Content -LiteralPath $source -Raw -ErrorAction Stop) -cne $token) { throw 'Probe read-back mismatch.' }
        $operation = 'rename/replace'
        Move-Item -LiteralPath $source -Destination $target -Force -ErrorAction Stop
        if ((Get-Content -LiteralPath $target -Raw -ErrorAction Stop) -cne $token) { throw 'Probe replacement mismatch.' }
        $operation = 'delete'
        Remove-Item -LiteralPath $target -Force -ErrorAction Stop
        Write-Host "Publication access verified: $share\WanPulse\ProVDesk (write, read, replace, delete)."
    } catch {
        throw "Publication preflight failed [$operation] at $share\WanPulse\ProVDesk : $($_.Exception.Message)"
    } finally {
        if ($mounted) {
            foreach ($path in $temporary) {
                try {
                    if (Test-Path -LiteralPath $path -ErrorAction Stop) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
                } catch { Write-Warning "Cannot clean up publication probe: $path" }
            }
            Remove-PSDrive -Name $driveName -Force -ErrorAction Continue
        }
    }
}

function Get-InstallerVersion([string]$FilePath) {
    $version = (Get-Item -LiteralPath $FilePath -ErrorAction Stop).VersionInfo.ProductVersion
    # Use the final executable's version verbatim, but require a safe filename component.
    if ([string]::IsNullOrWhiteSpace($version) -or $version.Length -gt 100 -or
        $version -cnotmatch '\A[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?(?:\+[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?\z') {
        throw 'The final executable must contain a valid product version for publication.'
    }
    return $version
}

function Publish-SignedInstaller([string]$FilePath, [string]$ExpectedSHA256, [pscredential]$Credential, [string]$ExpectedVersion) {
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf) -or
        [IO.Path]::GetFileName($FilePath) -ne 'ProVDesk.exe') {
        throw 'Publication requires the final ProVDesk.exe file.'
    }
    if ($ExpectedSHA256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'Invalid expected executable SHA256.' }
    Assert-Signature $FilePath
    if ((Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash -ne $ExpectedSHA256) {
        throw 'The executable no longer matches its signed build manifest.'
    }
    $version = Get-InstallerVersion $FilePath
    if ($version -cne $ExpectedVersion) { throw 'The executable version does not match its build manifest.' }
    $share = Get-PublicationShareRoot
    $driveName = 'ProVDeskPublish' + [guid]::NewGuid().ToString('N')
    $mounted = $false
    $temporary = $null
    try {
        New-PSDrive -Name $driveName -PSProvider FileSystem -Root $share -Credential $Credential -ErrorAction Stop | Out-Null
        $mounted = $true
        # Windows PowerShell 5.1 can repeat a UNC root when resolving a temporary PSDrive.
        # Keep the authenticated SMB connection, but use absolute UNC paths for all file operations.
        $directory = "$share\WanPulse\ProVDesk"
        $fileName = "ProVDesk-$version.exe"
        New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
        $temporary = Join-Path $directory ('.ProVDesk-' + [guid]::NewGuid().ToString('N') + '.exe')
        Copy-Item -LiteralPath $FilePath -Destination $temporary -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $ExpectedSHA256) {
            throw 'The uploaded executable failed SHA256 verification.'
        }
        # Keep the previous executable until the upload has been fully verified.
        Move-Item -LiteralPath $temporary -Destination (Join-Path $directory $fileName) -Force -ErrorAction Stop
        $temporary = $null
        Write-Host "Published signed executable: $share\WanPulse\ProVDesk\$fileName"
    } finally {
        if ($mounted) {
            if ($temporary -and (Test-Path -LiteralPath $temporary)) {
                Remove-Item -LiteralPath $temporary -Force -ErrorAction Continue
            }
            Remove-PSDrive -Name $driveName -Force -ErrorAction Continue
        }
    }
}
