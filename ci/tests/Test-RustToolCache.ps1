#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../utils/RustToolCache.ps1')
$repository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture = Join-Path $repository ('work/tool-cache-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path "$fixture/ci" | Out-Null
Copy-Item "$repository/ci/rust-tools.json" "$fixture/ci/rust-tools.json"
$script:installs = 0
function Invoke-RustToolInstallation($Tool, $InstallRoot, $Toolchain, $Target) {
    $script:installs++
    New-Item -ItemType Directory -Force -Path "$InstallRoot/bin" | Out-Null
    Set-Content "$InstallRoot/bin/$($Tool.name).exe" $Tool.version -Encoding ASCII
}
function Assert-RustToolVersion($Executable, $Version) {
    if ((Get-Content $Executable -Raw).Trim() -ne $Version) { throw 'Incorrect fixture version.' }
}
Install-CachedRustTools $fixture '14.44.35207' "$fixture/cache"
Install-CachedRustTools $fixture '14.44.35207' "$fixture/cache"
if ($script:installs -ne 2) { throw 'Cache hit unexpectedly rebuilt tools.' }
$exe = Get-ChildItem "$fixture/cache" -Recurse -Filter cargo-expand.exe | Select-Object -First 1
Set-Content $exe.FullName 'corrupt'
Install-CachedRustTools $fixture '14.44.35207' "$fixture/cache"
if ($script:installs -ne 3) { throw 'Corrupted cache did not rebuild.' }
Install-CachedRustTools $fixture '14.43.10000' "$fixture/cache"
if ($script:installs -ne 5) { throw 'Compiler change did not invalidate cache.' }
Write-Host 'Rust cache hit, corruption and compiler invalidation tests passed.'

$lock = Get-Content "$fixture/ci/rust-tools.json" -Raw | ConvertFrom-Json
$lock.tools[0].version = '1.0.96'
$lock | ConvertTo-Json -Depth 5 | Set-Content "$fixture/ci/rust-tools.json" -Encoding UTF8
Install-CachedRustTools $fixture '14.44.35207' "$fixture/cache"
if ($script:installs -ne 7) { throw 'Tool version change did not invalidate cache.' }
Write-Host 'Rust utility lock invalidation test passed.'
