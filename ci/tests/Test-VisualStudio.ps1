#Requires -Version 5.1
# Exercise toolset selection without running a compiler or modifying installed tools.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../utils/Common.ps1')
$fixture = Join-Path $root ('work/vs-selection-' + [Guid]::NewGuid().ToString('N'))
foreach ($version in @('14.29.30133', '14.38.33130', '14.44.35207', '14.50.35717')) {
    foreach ($relative in @('bin/Hostx64/x64/cl.exe', 'bin/Hostx64/x64/link.exe', 'include/vector', 'lib/x64/libcmt.lib')) {
        $path = Join-Path $fixture "VC/Tools/MSVC/$version/$relative"
        New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
        [IO.File]::WriteAllBytes($path, [byte[]]@())
    }
}
New-Item -ItemType Directory -Path "$fixture/VC/Tools/MSVC/14.49.99999" | Out-Null
if ((Get-MsvcToolset $fixture 'v143').Name -ne '14.44.35207') { throw 'v143 selected an incomplete or v145 compiler.' }
if ((Get-MsvcToolset $fixture 'v142').Name -ne '14.29.30133') { throw 'Incorrect v142 selection.' }
Remove-Item -LiteralPath "$fixture/VC/Tools/MSVC/14.29.30133/bin/Hostx64/x64/cl.exe"
$rejected = $false
try { $null = Get-MsvcToolset $fixture 'v142' } catch { $rejected = $true }
if (-not $rejected) { throw 'Incomplete v142 was accepted.' }

# Reproduce VS2026 layouts where v180 has only v145, despite older compilers being installed.
function Add-TargetsFixture([string]$Schema, [string]$Toolset) {
    foreach ($relative in @('Microsoft.Cpp.Default.props', 'Microsoft.Cpp.props',
            'Microsoft.Cpp.targets', 'Microsoft.CppBuild.targets',
            "Platforms/x64/PlatformToolsets/$Toolset/Toolset.props",
            "Platforms/x64/PlatformToolsets/$Toolset/Toolset.targets")) {
        $path = Join-Path $fixture "MSBuild/Microsoft/VC/$Schema/$relative"
        New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
        [IO.File]::WriteAllText($path, '<Project />')
    }
}
Add-TargetsFixture 'v180' 'v145'
$rejected = $false
try { $null = Get-MsvcTargetsPath $fixture 'v143' } catch {
    $rejected = $true
    if ($_.Exception.Message -notmatch 'v180: missing' -or $_.Exception.Message -notmatch 'v145') {
        throw 'Missing integration error must identify missing files and installed toolsets.'
    }
}
if (-not $rejected) { throw 'Compiler files without v143 MSBuild integration were accepted.' }
Add-TargetsFixture 'v170' 'v143'
Add-TargetsFixture 'v160' 'v142'
$targets143 = Get-MsvcTargetsPath $fixture 'v143'
$targets142 = Get-MsvcTargetsPath $fixture 'v142'
if (-not $targets143.EndsWith('/v170/') -or -not $targets142.EndsWith('/v160/')) {
    throw 'MSBuild targets selection did not follow installed toolset integration.'
}
# Prefer complete modern integration, but never a partially installed toolset.
Add-TargetsFixture 'v180' 'v143'
if (-not (Get-MsvcTargetsPath $fixture 'v143').EndsWith('/v180/')) { throw 'Complete v180 integration was ignored.' }
Remove-Item -LiteralPath "$fixture/MSBuild/Microsoft/VC/v180/Platforms/x64/PlatformToolsets/v143/Toolset.targets"
if ((Get-MsvcTargetsPath $fixture 'v143') -ne $targets143) { throw 'Incomplete v180 integration was selected.' }
Remove-Item -LiteralPath "$fixture/MSBuild/Microsoft/VC/v160/Microsoft.Cpp.Default.props"
$rejected = $false
try { $null = Get-MsvcTargetsPath $fixture 'v142' } catch { $rejected = $true }
if (-not $rejected) { throw 'Missing MSBuild common imports were accepted.' }

foreach ($case in @(
    @{ Minor = 1; Generator = 'Visual Studio 18 2026'; Expected = $false },
    @{ Minor = 2; Generator = 'Visual Studio 17 2022'; Expected = $false },
    @{ Minor = 2; Generator = 'Visual Studio 18 2026'; Expected = $true }
)) {
    $capabilities = [pscustomobject]@{
        version = [pscustomobject]@{ major = 4; minor = $case.Minor; patch = 0 }
        generators = @([pscustomobject]@{ name = $case.Generator })
    }
    if ((Test-Vs2026CmakeCapabilities $capabilities) -ne $case.Expected) { throw 'Incorrect CMake capability validation.' }
}

# Verify cmd.exe quoting and environment import with a harmless batch fixture.
$batch = Join-Path $fixture 'Fake VS DevCmd.bat'
Set-Content -LiteralPath $batch -Encoding ASCII -Value "@echo off`r`nset VCToolsVersion=14.44.35207`r`n"
function Get-Vs2026Configuration {
    [pscustomobject]@{
        InstallationPath = $fixture
        V143Version = '14.44.35207'
        V142Version = '14.29.30133'
        V143TargetsPath = $targets143
        V142TargetsPath = $targets142
        Compiler = "$fixture/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/cl.exe"
        Linker = "$fixture/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/link.exe"
        CMake = "$fixture/cmake.exe"
        DevCommand = $batch
    }
}
$null = Enable-Vs2026Environment
if ($env:PROVDESK_MSVC_VERSION -ne '14.44.35207' -or $env:PROVDESK_VS_ROOT -ne $fixture) {
    throw 'Incorrect environment initialization.'
}
if ($env:PROVDESK_CMAKE_TOOLSET -ne "v143,host=x64,version=14.44.35207,VCTargetsPath=$targets143") {
    throw 'Flutter did not receive the complete CMake toolset selection.'
}
if ((Get-MsvcCmakeToolset (Get-Vs2026Configuration) 'v142') -ne "v142,host=x64,version=14.29.30133,VCTargetsPath=$targets142") {
    throw 'The v142 probe uses the wrong compiler or MSBuild targets.'
}
Write-Host 'VS2026 compiler/targets selection, CMake validation and simulated environment tests passed.'
