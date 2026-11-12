# Write literal CMake values; vcpkg removes custom environment variables on Windows.
function Write-VcpkgSelection([string]$Destination, [string]$InstallationPath, [string]$ToolsetVersion) {
    if ($ToolsetVersion -notmatch '^14\.[34][0-9]\.\d+$') { throw 'A validated v143 version is required.' }
    if ($InstallationPath -notmatch '^[A-Za-z]:[\\/]' -or $InstallationPath.Contains(']==]') -or
        $InstallationPath.Contains("`n") -or $InstallationPath.Contains("`r")) {
        throw 'Invalid Visual Studio installation path.'
    }
    # Preserve the native vswhere spelling: vcpkg compares the instance path literally.
    # CMake bracket arguments preserve backslashes without escape processing.
    $cmakePath = $InstallationPath
    $content = @(
        '# Generated from the validated VS 2026 configuration; no environment lookup.'
        "set(VCPKG_PLATFORM_TOOLSET_VERSION [==[$ToolsetVersion]==])"
        "set(VCPKG_VISUAL_STUDIO_PATH [==[$cmakePath]==])"
    ) -join "`n"
    [IO.File]::WriteAllText($Destination, $content + "`n", (New-Object Text.UTF8Encoding($false)))
}

function Assert-VcpkgInventory([string[]]$Packages) {
    foreach ($name in @('aom', 'libjpeg-turbo', 'opus', 'libvpx', 'libyuv', 'mfx-dispatch', 'ffmpeg')) {
        $pattern = '^' + [regex]::Escape($name) + ':x64-windows-static\s+'
        if (-not @($Packages | Where-Object { $_ -match $pattern }).Count) {
            throw "Missing expected vcpkg package in installation inventory: $name"
        }
    }
}
# Inspect the actual archive: a successful vcpkg exit can still hide CRT warnings.
function Assert-OpusStaticRuntime([string]$InstallRoot) {
    $dumpbin = (Get-Command dumpbin.exe -ErrorAction Stop).Source
    foreach ($variant in @(
        @{ Relative = 'lib/opus.lib'; Expected = 'LIBCMT' },
        @{ Relative = 'debug/lib/opus.lib'; Expected = 'LIBCMTD' }
    )) {
        $library = Join-Path $InstallRoot ("x64-windows-static/" + $variant.Relative)
        if (-not (Test-Path -LiteralPath $library -PathType Leaf)) { throw "Opus library is missing: $library" }
        $output = & $dumpbin /nologo /directives $library
        if ($LASTEXITCODE -ne 0) { throw "Cannot inspect Opus runtime: $library" }
        $runtimes = @([regex]::Matches(($output -join "`n"), '(?i)/DEFAULTLIB:(?:"([^"]+)"|(\S+))') |
            ForEach-Object {
                $name = if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
                $name.ToUpperInvariant() -replace '\.LIB$', ''
            } | Where-Object { $_ -in @('LIBCMT', 'LIBCMTD', 'MSVCRT', 'MSVCRTD') } | Sort-Object -Unique)
        if ($runtimes.Count -ne 1 -or $runtimes[0] -ne $variant.Expected) {
            throw "Opus CRT mismatch in $library : expected $($variant.Expected), found $($runtimes -join ', ')."
        }
        Write-Host "Opus CRT verified: $($variant.Relative) -> $($variant.Expected)"
    }
}
