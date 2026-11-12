# Select the VS 2026 instance associated with MSBUILD_PATH, never a global default.
function Get-MsvcToolset([string]$InstallationPath, [string]$Toolset) {
    $versions = @(Get-ChildItem -LiteralPath (Join-Path $InstallationPath 'VC/Tools/MSVC') -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^14\.\d+\.\d+$' } |
        Where-Object {
            $minor = ([version]$_.Name).Minor
            ($Toolset -eq 'v143' -and $minor -ge 30 -and $minor -lt 50) -or
            ($Toolset -eq 'v142' -and $minor -ge 20 -and $minor -lt 30)
        } | Sort-Object { [version]$_.Name } -Descending)
    foreach ($version in $versions) {
        $required = @('bin/Hostx64/x64/cl.exe', 'bin/Hostx64/x64/link.exe', 'include/vector', 'lib/x64/libcmt.lib')
        $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $version.FullName $_) -PathType Leaf) })
        if ($missing.Count -eq 0) { return $version }
    }
    throw "Incomplete $Toolset x64 toolset in $InstallationPath. Install its compiler, headers and libraries."
}

function Get-MsvcTargetsPath([string]$InstallationPath, [ValidateSet('v143', 'v142')][string]$Toolset) {
    # Compiler binaries and MSBuild platform integration can live in different version trees.
    # Search only the selected VS2026 installation; never copy files into Program Files.
    $diagnostics = @()
    foreach ($schema in @('v180', 'v170', 'v160')) {
        $candidate = Join-Path $InstallationPath "MSBuild/Microsoft/VC/$schema"
        $required = @('Microsoft.Cpp.Default.props', 'Microsoft.Cpp.props',
            'Microsoft.Cpp.targets', 'Microsoft.CppBuild.targets',
            "Platforms/x64/PlatformToolsets/$Toolset/Toolset.props",
            "Platforms/x64/PlatformToolsets/$Toolset/Toolset.targets")
        $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $candidate $_) -PathType Leaf) })
        $diagnostics += "${schema}: missing [$($missing -join ', ')]"
        if ($missing.Count -eq 0) {
            # A trailing forward slash is safe in both CMake -T and native MSBuild arguments.
            return [IO.Path]::GetFullPath($candidate).Replace('\', '/').TrimEnd('/') + '/'
        }
    }
    $vcRoot = Join-Path $InstallationPath 'MSBuild/Microsoft/VC'
    $installed = @(Get-ChildItem -LiteralPath $vcRoot -Recurse -File -Filter Toolset.props -ErrorAction SilentlyContinue |
        ForEach-Object { $_.FullName.Substring($vcRoot.Length).TrimStart('\', '/') })
    throw "No complete $Toolset x64 MSBuild integration in $InstallationPath. $($diagnostics -join '; '). Installed toolset definitions: [$($installed -join ', ')]."
}

function Get-MsvcCmakeToolset($Configuration, [ValidateSet('v143', 'v142')][string]$Toolset) {
    $version = if ($Toolset -eq 'v143') { $Configuration.V143Version } else { $Configuration.V142Version }
    $targets = if ($Toolset -eq 'v143') { $Configuration.V143TargetsPath } else { $Configuration.V142TargetsPath }
    if (-not $targets -or $targets -match '[,\r\n]') { throw 'Invalid MSBuild targets path for CMake -T.' }
    return "$Toolset,host=x64,version=$version,VCTargetsPath=$targets"
}

function Test-Vs2026CmakeCapabilities($Capabilities) {
    $version = [version]('{0}.{1}.{2}' -f $Capabilities.version.major, $Capabilities.version.minor, $Capabilities.version.patch)
    return ($version -ge [version]'4.2' -and
        @($Capabilities.generators | Where-Object name -eq 'Visual Studio 18 2026').Count -gt 0)
}

function Get-Vs2026Configuration([switch]$PrepareIntegration) {
    if (-not $env:MSBUILD_PATH -or -not (Test-Path -LiteralPath $env:MSBUILD_PATH -PathType Leaf)) {
        throw 'MSBUILD_PATH must point to the MSBuild executable of Build Tools 2026.'
    }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio Installer vswhere.exe was not found.' }
    $previousEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
        $json = & $vswhere -products '*' -version '[18.0,19.0)' -format json -utf8
        Assert-NativeSuccess 'Discover Visual Studio 2026'
    } finally { [Console]::OutputEncoding = $previousEncoding }
    $installations = @(($json | ConvertFrom-Json))
    $msbuild = (Resolve-Path -LiteralPath $env:MSBUILD_PATH).Path
    $matching = @($installations | Where-Object {
        $_.isComplete -and $_.isLaunchable -and
        $msbuild.StartsWith($_.installationPath.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
    })
    if ($matching.Count -ne 1) { throw 'MSBUILD_PATH must belong to one complete VS 2026 (18.x) installation.' }
    $installation = $matching[0].installationPath.TrimEnd('\')
    $v143 = Get-MsvcToolset $installation 'v143'
    $v142 = Get-MsvcToolset $installation 'v142'
    $devCommand = Join-Path $installation 'Common7/Tools/VsDevCmd.bat'
    if (-not (Test-Path -LiteralPath $devCommand)) { throw 'VsDevCmd.bat is missing.' }
    $candidates = @(Join-Path $installation 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe')
    $pathCmake = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if ($pathCmake) { $candidates += $pathCmake.Source }
    $selectedCmake = $null
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $capabilitiesJson = & $candidate -E capabilities
        Assert-NativeSuccess 'Read CMake capabilities'
        $capabilities = $capabilitiesJson | ConvertFrom-Json
        if (Test-Vs2026CmakeCapabilities $capabilities) {
            $selectedCmake = $candidate
            break
        }
    }
    if (-not $selectedCmake) { throw 'CMake 4.2+ with the Visual Studio 18 2026 generator is required (VS component or PATH).' }
    try { $targets143 = Get-MsvcTargetsPath $installation 'v143' } catch {
        Write-Host 'Installed v143 compiler has no complete MSBuild integration; use the pinned private integration.'
        . (Join-Path $PSScriptRoot 'MsvcIntegration.ps1')
        $workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $private = Get-PrivateMsvcIntegration $workspace (Join-Path $workspace 'ci/msbuild-tools.json') -Prepare:$PrepareIntegration
        $targets143 = Get-MsvcTargetsPath $private 'v143'
    }
    [pscustomobject]@{
        InstallationPath = $installation
        V143Version = $v143.Name
        V142Version = $v142.Name
        V143TargetsPath = $targets143
        V142TargetsPath = Get-MsvcTargetsPath $installation 'v142'
        Compiler = Join-Path $v143.FullName 'bin/Hostx64/x64/cl.exe'
        Linker = Join-Path $v143.FullName 'bin/Hostx64/x64/link.exe'
        CMake = $selectedCmake
        DevCommand = $devCommand
    }
}

function Enable-Vs2026Environment {
    $configuration = Get-Vs2026Configuration
    # Capture the child environment without printing it: it may contain CI secrets.
    $command = '"{0}" -no_logo -arch=amd64 -host_arch=amd64 -vcvars_ver={1} >nul && set' -f $configuration.DevCommand, $configuration.V143Version
    $environmentLines = & $env:ComSpec /d /s /c $command
    Assert-NativeSuccess 'Initialize VS 2026 with the v143 x64 toolset'
    foreach ($line in $environmentLines) {
        if ($line -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process') }
    }
    if (-not $env:VCToolsVersion -or $env:VCToolsVersion.TrimEnd('\', '/') -ne $configuration.V143Version) {
        throw 'VsDevCmd did not select the expected v143 compiler version.'
    }
    $env:PROVDESK_VS_ROOT = $configuration.InstallationPath
    $env:PROVDESK_MSVC_VERSION = $configuration.V143Version
    $env:PROVDESK_CMAKE_TOOLSET = Get-MsvcCmakeToolset $configuration 'v143'
    $vsRoot = $configuration.InstallationPath.Replace('\', '/').TrimEnd('/') + '/'
    $env:PROVDESK_VS_GLOBALS = "VSInstallDir=$vsRoot;VsInstallRoot=$vsRoot"
    $env:PROVDESK_CMAKE_PATH = $configuration.CMake
    $env:VCPKG_VISUAL_STUDIO_PATH = $configuration.InstallationPath
    $env:CC_x86_64_pc_windows_msvc = $configuration.Compiler
    $env:CXX_x86_64_pc_windows_msvc = $configuration.Compiler
    $env:CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER = $configuration.Linker
    $env:PATH = (Split-Path $configuration.CMake -Parent) + ';' + $env:PATH
    return $configuration
}
