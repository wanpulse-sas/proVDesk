# Native tool defaults are preserved; only explicit user limits are forwarded.
function Get-NativeParallelArguments([switch]$CMake) {
    $level = [Environment]::GetEnvironmentVariable('CMAKE_BUILD_PARALLEL_LEVEL')
    if (-not [string]::IsNullOrEmpty($level)) {
        $count = 0
        if ($level -notmatch '^[0-9]+$' -or -not [int]::TryParse($level, [ref]$count) -or $count -lt 1) {
            throw 'CMAKE_BUILD_PARALLEL_LEVEL must be empty or a positive integer.'
        }
    }
    if ($CMake) {
        $arguments = @('--parallel')
        if (-not [string]::IsNullOrEmpty($level)) { $arguments += $level }
        $arguments += '--'
    } else {
        $arguments = @(if ([string]::IsNullOrEmpty($level)) { '/m' } else { "/m:$level" })
    }
    # Share the native C++ scheduler across projects instead of multiplying /m by /MP.
    # Without a numeric override MSVC chooses its own processor-based concurrency.
    $arguments += @('/p:UseMultiToolTask=true', '/p:EnforceProcessCountAcrossBuilds=true')
    if (-not [string]::IsNullOrEmpty($level)) { $arguments += "/p:MultiProcMaxCount=$level" }
    return $arguments
}

function Get-AvailableDiskBytes([string]$VolumeRoot) {
    $drive = New-Object System.IO.DriveInfo($VolumeRoot)
    if (-not $drive.IsReady) { throw "Disk is not ready: $VolumeRoot" }
    return $drive.AvailableFreeSpace
}

function Assert-FreeDiskSpace([string]$Operation) {
    $minimumGiB = 10
    if (-not [string]::IsNullOrWhiteSpace($env:MIN_FREE_DISK_GB)) {
        if (-not [int]::TryParse($env:MIN_FREE_DISK_GB, [ref]$minimumGiB) -or $minimumGiB -lt 1) {
            throw 'MIN_FREE_DISK_GB must be a positive integer (GiB).'
        }
    }
    $paths = @($root, $env:TEMP)
    foreach ($name in @('CARGO_HOME', 'RUSTUP_HOME', 'LOCALAPPDATA')) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if (-not [string]::IsNullOrWhiteSpace($value)) { $paths += $value }
    }
    # Default Rust caches live in the service account profile.
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { $paths += $env:USERPROFILE }
    $volumes = @($paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
        if ($_ -notmatch '^[A-Za-z]:[\\/]') { throw "Expected a local absolute path for disk checks: $_" }
        [IO.Path]::GetPathRoot($_)
    } | Sort-Object -Unique)
    foreach ($volume in $volumes) {
        $available = Get-AvailableDiskBytes $volume
        Write-Host ('Disk check [{0}]: {1} {2:N1} GiB free; minimum {3} GiB' -f $Operation, $volume, ($available / 1GB), $minimumGiB)
        if ($available -lt ([long]$minimumGiB * 1GB)) {
            throw "Insufficient free disk space before $Operation on $volume. Free space manually and restart the pipeline."
        }
    }
}
