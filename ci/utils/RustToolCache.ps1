$script:rustToolCacheCodePath = $PSCommandPath
# Cache only pinned build utilities, never application payloads or signed output.
function Invoke-RustToolInstallation($Tool, [string]$InstallRoot, [string]$Toolchain, [string]$Target) {
    $arguments = @("+$Toolchain", 'install', $Tool.name, '--version', $Tool.version,
        '--locked', '--force', '--target', $Target, '--root', $InstallRoot)
    if ($Tool.features.Count) { $arguments += @('--features', ($Tool.features -join ',')) }
    & cargo @arguments
    if ($LASTEXITCODE -ne 0) { throw "Installing cached Rust tool failed: $($Tool.name)" }
}

function Assert-RustToolVersion([string]$Executable, [string]$Version) {
    $output = & $Executable --version
    if ($LASTEXITCODE -ne 0 -or ($output -join ' ') -notmatch ('(?<![\d.])' + [regex]::Escape($Version) + '(?![\d.])')) {
        throw "Unexpected Rust utility version: $Executable"
    }
}

function Install-CachedRustTools([string]$Workspace, [string]$MsvcVersion, [string]$CacheRoot = '') {
    if (-not $CacheRoot) { $CacheRoot = Join-Path $env:LOCALAPPDATA 'WanPulse/ProVDesk/ci-tools' }
    $lockPath = Join-Path $Workspace 'ci/rust-tools.json'
    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($lock.schema -ne 1 -or $MsvcVersion -notmatch '^14\.[34][0-9]\.\d+$') { throw 'Invalid Rust tool cache configuration.' }
    $identity = (Get-FileHash $lockPath -Algorithm SHA256).Hash + ':' + $MsvcVersion + ':' +
        (Get-FileHash $script:rustToolCacheCodePath -Algorithm SHA256).Hash
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $key = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    $entry = Join-Path $CacheRoot $key
    New-Item -ItemType Directory -Force -Path $entry | Out-Null
    # FileShare.None prevents two builds from updating the same entry concurrently.
    $guard = [IO.File]::Open((Join-Path $entry '.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    try {
        $localBin = Join-Path $Workspace 'build-tools/rust/bin'
        New-Item -ItemType Directory -Force -Path $localBin | Out-Null
        foreach ($tool in $lock.tools) {
            if ($tool.name -notmatch '^[a-z0-9_-]+$') { throw 'Invalid Rust tool name.' }
            $exe = Join-Path $entry "bin/$($tool.name).exe"
            $receiptPath = Join-Path $entry "$($tool.name).json"
            $valid = $false
            if ((Test-Path -LiteralPath $exe) -and (Test-Path -LiteralPath $receiptPath)) {
                try {
                    $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    $valid = $receipt.Key -eq $key -and $receipt.SHA256 -eq (Get-FileHash $exe -Algorithm SHA256).Hash
                } catch { $valid = $false }
            }
            if ($valid) {
                Write-Host "Rust tool cache hit: $($tool.name) $($tool.version)"
            } else {
                Write-Host "Rust tool cache miss: $($tool.name) $($tool.version)"
                # Remove only the receipt; a failed install can never create a valid hit.
                if (Test-Path -LiteralPath $receiptPath) { Remove-Item -LiteralPath $receiptPath }
                Invoke-RustToolInstallation $tool $entry $lock.toolchain $lock.target
            }
            Assert-RustToolVersion $exe $tool.version
            $hash = (Get-FileHash $exe -Algorithm SHA256).Hash
            [pscustomobject]@{ Key = $key; SHA256 = $hash } | ConvertTo-Json |
                Set-Content -LiteralPath $receiptPath -Encoding UTF8
            $destination = Join-Path $localBin "$($tool.name).exe"
            Copy-Item -LiteralPath $exe -Destination $destination -Force
            if ((Get-FileHash $destination -Algorithm SHA256).Hash -ne $hash) { throw 'Cached tool copy failed integrity check.' }
        }
    } finally { $guard.Dispose() }
}
