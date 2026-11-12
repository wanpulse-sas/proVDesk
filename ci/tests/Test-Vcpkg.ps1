#Requires -Version 5.1
param([Parameter(Mandatory = $true)][string]$CMakePath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../utils/Vcpkg.ps1')
$repository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture = Join-Path $repository ('work/vcpkg-selection-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path "$fixture/ci/triplets", "$fixture/build-tools/vcpkg/triplets" | Out-Null
Copy-Item "$repository/ci/triplets/x64-windows-static.cmake" "$fixture/ci/triplets/"
# Minimal vendor fixture checks that upstream settings survive the overlay.
Set-Content "$fixture/build-tools/vcpkg/triplets/x64-windows-static.cmake" 'set(VCPKG_CRT_LINKAGE static)' -Encoding ASCII
Write-VcpkgSelection "$fixture/build-tools/vcpkg-selection.cmake" 'C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools' '14.44.35207'
$check = @'
include("${CMAKE_CURRENT_LIST_DIR}/ci/triplets/x64-windows-static.cmake")
if(NOT VCPKG_CRT_LINKAGE STREQUAL "static" OR NOT VCPKG_PLATFORM_TOOLSET STREQUAL "v143")
  message(FATAL_ERROR "Vendor defaults or toolset were lost")
endif()
if(NOT VCPKG_PLATFORM_TOOLSET_VERSION STREQUAL "14.44.35207")
  message(FATAL_ERROR "Exact v143 version was lost")
endif()
if(NOT VCPKG_VISUAL_STUDIO_PATH STREQUAL [==[C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools]==])
  message(FATAL_ERROR "VS2026 path changed: vcpkg requires the exact native instance path")
endif()
file(WRITE "${CMAKE_CURRENT_LIST_DIR}/selected-vs.txt" "${VCPKG_VISUAL_STUDIO_PATH}")
'@
Set-Content "$fixture/check.cmake" $check -Encoding ASCII
$names = @('VCPKG_ROOT', 'PROVDESK_MSVC_VERSION', 'PROVDESK_VS_ROOT')
$saved = @{}
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
try {
    foreach ($value in @('', 'invalid-inherited-value')) {
        foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $value) }
        & $CMakePath -P "$fixture/check.cmake"
        if ($LASTEXITCODE -ne 0) { throw 'Triplet depends on inherited environment.' }
        $selected = [IO.File]::ReadAllText("$fixture/selected-vs.txt")
        if ($selected -cne 'C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools') {
            throw 'CMake output does not exactly match the vswhere installation path.'
        }
    }
    $rejected = $false
    try { Write-VcpkgSelection "$fixture/invalid.cmake" 'C:\VS' '14.51.36231' } catch { $rejected = $true }
    if (-not $rejected) { throw 'v145 was accepted as v143.' }
    Write-Host 'vcpkg triplet tests passed with missing and conflicting environment variables.'
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
}

$packages = @('aom', 'libjpeg-turbo', 'opus', 'libvpx', 'libyuv', 'mfx-dispatch', 'ffmpeg') | ForEach-Object { "${_}:x64-windows-static 1.0" }
Assert-VcpkgInventory $packages
foreach ($invalid in @(@(), @('aom:x64-windows-static 1.0'))) {
    $rejected = $false
    try { Assert-VcpkgInventory $invalid } catch { $rejected = $true }
    if (-not $rejected) { throw 'Incomplete vcpkg inventory accepted.' }
}
