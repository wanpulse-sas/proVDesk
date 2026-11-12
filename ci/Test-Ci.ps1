#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'utils/Common.ps1')
$configuration = Get-Vs2026Configuration
foreach ($test in @('Test-SigningPolicy', 'Test-SigningInvocation', 'Test-DriverCatalogs', 'Test-SigningPipeline',
        'Test-Publication', 'Test-BuildResources', 'Test-FlutterPatch', 'Test-VisualStudio', 'Test-MsvcIntegration', 'Test-RustToolCache', 'Test-Diagnostics', 'Test-VcpkgEnvironmentProbe')) {
    & "$PSHOME/powershell.exe" -NoProfile -File (Join-Path $PSScriptRoot "tests/$test.ps1")
    Assert-NativeSuccess $test
}
& "$PSHOME/powershell.exe" -NoProfile -File (Join-Path $PSScriptRoot 'tests/Test-Vcpkg.ps1') -CMakePath $configuration.CMake
Assert-NativeSuccess 'Test-Vcpkg'
& "$PSHOME/powershell.exe" -NoProfile -File (Join-Path $PSScriptRoot 'tests/Test-MsvcPort.ps1') -CMakePath $configuration.CMake
Assert-NativeSuccess 'Test-MsvcPort'
