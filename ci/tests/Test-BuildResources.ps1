#Requires -Version 5.1
# Test resource policy without building or changing runner configuration.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../utils/BuildResources.ps1')
$root = 'C:\checkout'
$names = @('MIN_FREE_DISK_GB', 'TEMP', 'USERPROFILE', 'LOCALAPPDATA', 'CARGO_HOME', 'RUSTUP_HOME', 'CARGO_BUILD_JOBS', 'VCPKG_MAX_CONCURRENCY', 'CMAKE_BUILD_PARALLEL_LEVEL', 'CL_MPCount')
$saved = @{}
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
function Expect-Failure([scriptblock]$Action, [string]$Message) {
    $failed = $false
    try { & $Action } catch { $failed = $true }
    if (-not $failed) { throw $Message }
}
try {
    foreach ($name in @('CARGO_BUILD_JOBS', 'VCPKG_MAX_CONCURRENCY', 'CMAKE_BUILD_PARALLEL_LEVEL', 'CL_MPCount')) {
        [Environment]::SetEnvironmentVariable($name, $null)
    }
    $native = @(Get-NativeParallelArguments)
    $cmake = @(Get-NativeParallelArguments -CMake)
    if (($native -join '|') -ne '/m|/p:UseMultiToolTask=true|/p:EnforceProcessCountAcrossBuilds=true') {
        throw 'MSBuild automatic scheduling was not requested.'
    }
    if (($cmake -join '|') -ne '--parallel|--|/p:UseMultiToolTask=true|/p:EnforceProcessCountAcrossBuilds=true') {
        throw 'CMake automatic scheduling was not requested.'
    }
    foreach ($name in @('CARGO_BUILD_JOBS', 'VCPKG_MAX_CONCURRENCY', 'CMAKE_BUILD_PARALLEL_LEVEL', 'CL_MPCount')) {
        if ([Environment]::GetEnvironmentVariable($name)) { throw "Default environment was changed: $name" }
    }
    $env:CARGO_BUILD_JOBS = '7'
    $env:VCPKG_MAX_CONCURRENCY = '5'
    $env:CMAKE_BUILD_PARALLEL_LEVEL = '3'
    $env:CL_MPCount = '4'
    $native = @(Get-NativeParallelArguments)
    $cmake = @(Get-NativeParallelArguments -CMake)
    if ($native[0] -ne '/m:3' -or $native[-1] -ne '/p:MultiProcMaxCount=3' -or
        $cmake[0] -ne '--parallel' -or $cmake[1] -ne '3' -or $cmake[-1] -ne '/p:MultiProcMaxCount=3') {
        throw 'Explicit native build limit was not forwarded to both schedulers.'
    }
    if ($env:CARGO_BUILD_JOBS -ne '7' -or $env:VCPKG_MAX_CONCURRENCY -ne '5' -or
        $env:CMAKE_BUILD_PARALLEL_LEVEL -ne '3' -or $env:CL_MPCount -ne '4') {
        throw 'A user-provided concurrency limit was overwritten.'
    }
    foreach ($invalid in @('0', '-1', 'default', '1.5', ' 3', '2147483648')) {
        $env:CMAKE_BUILD_PARALLEL_LEVEL = $invalid
        Expect-Failure { Get-NativeParallelArguments } "Invalid native limit accepted: $invalid"
        Expect-Failure { Get-NativeParallelArguments -CMake } "Invalid CMake limit accepted: $invalid"
    }
    foreach ($name in @('TEMP', 'USERPROFILE', 'LOCALAPPDATA', 'CARGO_HOME', 'RUSTUP_HOME')) {
        [Environment]::SetEnvironmentVariable($name, 'C:\cache')
    }
    $env:MIN_FREE_DISK_GB = ''
    $script:calls = 0
    $script:freeBytes = 10GB
    function Get-AvailableDiskBytes([string]$VolumeRoot) {
        $script:calls++
        if ($VolumeRoot -eq 'D:\') { return 9GB }
        return $script:freeBytes
    }
    Assert-FreeDiskSpace 'Exact default boundary'
    if ($script:calls -ne 1) { throw 'Volumes were not deduplicated.' }
    $script:freeBytes = 10GB - 1
    Expect-Failure { Assert-FreeDiskSpace 'Below default' } 'Low disk space was accepted.'
    $env:MIN_FREE_DISK_GB = '5'
    Assert-FreeDiskSpace 'Custom threshold'
    foreach ($invalid in @('0', '-1', 'abc', '1.5', '2147483648')) {
        $env:MIN_FREE_DISK_GB = $invalid
        Expect-Failure { Assert-FreeDiskSpace 'Invalid threshold' } "Invalid threshold accepted: $invalid"
    }
    $env:MIN_FREE_DISK_GB = '10'
    $script:freeBytes = 36GB
    $env:CARGO_HOME = 'D:\cargo'
    Expect-Failure { Assert-FreeDiskSpace 'Separate cache volume' } 'Low cache volume was ignored.'
    $env:CARGO_HOME = '\\server\cache'
    Expect-Failure { Assert-FreeDiskSpace 'UNC cache' } 'Unsupported volume was accepted.'
    $env:CARGO_HOME = 'C:\cache'
    function Get-AvailableDiskBytes([string]$VolumeRoot) { throw 'Disk query failed.' }
    Expect-Failure { Assert-FreeDiskSpace 'Unreadable disk' } 'Disk query failure was ignored.'
    Write-Host 'Build resource policy tests passed.'
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
}
