#Requires -Version 5.1
# Real runner integration probes, before Flutter downloads and Rust utility compilation.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'utils/Common.ps1')
Use-BuildTools
Initialize-Signing
Assert-FreeDiskSpace 'Toolchain integration preflight'
$lock = Get-Content -LiteralPath "$root/ci/dependencies.json" -Raw -Encoding UTF8 | ConvertFrom-Json
New-Item -ItemType Directory -Path "$root/build-tools" | Out-Null
python "$root/ci/probes/Test-Symlinks.py"
Assert-NativeSuccess 'Flutter directory symlink privileges'
$script:visualStudio | ConvertTo-Json | Set-Content -Encoding UTF8 "$work/visual-studio.json"
Copy-Item -LiteralPath "$root/ci/msbuild-tools.json" -Destination "$work/msbuild-tools.json"
# Validate all source patches before any expensive compilation.
git -C source apply --check "$root/ci/patches/windows-full-features.patch"
Assert-NativeSuccess 'Source feature patch preflight'
git -C source apply --check "$root/ci/patches/wrapper-manifest.patch"
Assert-NativeSuccess 'Wrapper patch preflight'
git -C source/libs/hbb_common apply --check "$root/source/scripts/windows/provdesk-hbb-common.patch"
Assert-NativeSuccess 'Submodule patch preflight'
foreach ($name in @('libvpx-msbuild.patch', 'opus-static-runtime.patch')) {
    $portPatch = Join-Path $root "ci/patches/$name"
    git -C source apply --check $portPatch
    Assert-NativeSuccess "Native port patch preflight: $name"
    git -C source apply $portPatch
    Assert-NativeSuccess "Apply native port patch: $name"
    Copy-Item -LiteralPath $portPatch -Destination "$work/$name"
}
. (Join-Path $PSScriptRoot 'utils/MsvcPort.ps1')
Write-MsvcPortSelection "$root/build-tools/msbuild-selection.cmake" $script:visualStudio
Copy-Item -LiteralPath "$root/build-tools/msbuild-selection.cmake" -Destination "$work/msbuild-selection.cmake"
# Loading the DLL catches dependency/architecture problems that Test-Path cannot.
python -c "import ctypes, os; dll=ctypes.WinDLL(os.path.join(os.environ['LIBCLANG_PATH'], 'libclang.dll')); assert dll.clang_createIndex"
Assert-NativeSuccess 'Load x64 libclang and locate clang_createIndex'

$cmakeParallelArguments = @(Get-NativeParallelArguments -CMake)
$msbuildParallelArguments = @(Get-NativeParallelArguments)
# Exercise MSBuild integration before downloading vcpkg or its helper tools.
foreach ($toolset in @('v143', 'v142')) {
    $build = Join-Path $root "build-tools/probes/$toolset"
    $cmakeToolset = Get-MsvcCmakeToolset $script:visualStudio $toolset
    # Derive _MSC_VER from the selected toolset minor, including older v143 versions.
    $version = if ($toolset -eq 'v143') { $script:visualStudio.V143Version } else { $script:visualStudio.V142Version }
    $expectedCompiler = 1900 + ([version]$version).Minor
    & $script:visualStudio.CMake -S "$root/ci/probes" -B $build -G 'Visual Studio 18 2026' -A x64 -T $cmakeToolset "-DCMAKE_GENERATOR_INSTANCE=$($script:visualStudio.InstallationPath)" "-DCMAKE_VS_GLOBALS=$env:PROVDESK_VS_GLOBALS" "-DPROVDESK_EXPECTED_MSC_VER=$expectedCompiler" | Tee-Object -FilePath "$work/toolchain-probe.log" -Append
    Assert-NativeSuccess "Configure native probe $toolset"
    & $script:visualStudio.CMake --build $build --config Release @cmakeParallelArguments | Tee-Object -FilePath "$work/toolchain-probe.log" -Append
    Assert-NativeSuccess "Compile/link/resource probe $toolset"
    & "$build/Release/provdesk-probe.exe"
    Assert-NativeSuccess "Execute native probe $toolset"
}

$expectedCompiler = 1900 + ([version]$script:visualStudio.V143Version).Minor
& $script:visualStudio.CMake "-DPROVDESK_MSBUILD=$env:MSBUILD_PATH" "-DPROVDESK_EXPECTED_MSC_VER=$expectedCompiler" "-DPROVDESK_MSBUILD_PARALLEL_ARGS=$($msbuildParallelArguments -join ';')" -P "$root/ci/probes/Test-MsvcPort.cmake" | Tee-Object -FilePath "$work/toolchain-probe.log" -Append
Assert-NativeSuccess 'Direct MSBuild invocation used by libvpx'

Assert-FreeDiskSpace 'vcpkg checkout'
git init build-tools/vcpkg
Assert-NativeSuccess 'Init vcpkg'
git -C build-tools/vcpkg remote add origin https://github.com/microsoft/vcpkg.git
Assert-NativeSuccess 'Remote vcpkg'
# Registry version resolution requires vcpkg history.
git -C build-tools/vcpkg fetch origin $lock.vcpkgCommit
Assert-NativeSuccess 'Fetch vcpkg'
git -C build-tools/vcpkg checkout --detach FETCH_HEAD
Assert-NativeSuccess 'Checkout vcpkg'
$vcpkgCommit = git -C build-tools/vcpkg rev-parse HEAD
Assert-NativeSuccess 'Commit vcpkg'
if ($vcpkgCommit -ne $lock.vcpkgCommit) { throw 'Commit vcpkg inattendu.' }
& "$env:VCPKG_ROOT/bootstrap-vcpkg.bat" -disableMetrics
Assert-NativeSuccess 'Bootstrap vcpkg'
# Persist compiler selection outside the sanitized vcpkg environment.
. (Join-Path $PSScriptRoot 'utils/Vcpkg.ps1')
$selectionPath = Join-Path $root 'build-tools/vcpkg-selection.cmake'
Write-VcpkgSelection $selectionPath $script:visualStudio.InstallationPath $script:visualStudio.V143Version
& $script:visualStudio.CMake -P "$root/ci/triplets/x64-windows-static.cmake"
Assert-NativeSuccess 'Validate vcpkg triplet includes'
Copy-Item -LiteralPath $selectionPath -Destination "$work/vcpkg-selection.cmake"
Set-Location "$root/source"
$manifest = Get-Content -Encoding UTF8 vcpkg.json -Raw | ConvertFrom-Json
if ($manifest.'vcpkg-configuration'.'default-registry'.baseline -ne $lock.vcpkgCommit) { throw 'Baseline vcpkg inattendu.' }

# Unlike cmake -P, vcpkg env resolves the actual instance and initializes vcvars.
$probe = Join-Path $root 'ci/probes/Test-VcpkgEnvironment.ps1'
$selection = Join-Path $work 'visual-studio.json'
$command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}" -SelectionFile "{1}"' -f $probe, $selection
& "$env:VCPKG_ROOT/vcpkg.exe" env $command --triplet x64-windows-static "--overlay-triplets=$root/ci/triplets" "--x-install-root=$env:VCPKG_ROOT/installed"
Assert-NativeSuccess 'Real vcpkg Visual Studio selection'

# Sign only the fresh probe; never distribute it as a product artifact.
$probeExe = "$root/build-tools/probes/v143/Release/provdesk-probe.exe"
Invoke-WanPulseSign $probeExe
Assert-Signature $probeExe
Remove-Item -LiteralPath "$root/build-tools/probes/v143/Release/provdesk-probe.exe", "$root/build-tools/probes/v142/Release/provdesk-probe.exe", "$root/build-tools/probes/direct-msbuild/bin/provdesk-msbuild-probe.exe"
[pscustomobject]@{
    VcpkgCommit = $lock.vcpkgCommit
    V143 = $script:visualStudio.V143Version
    V142 = $script:visualStudio.V142Version
    SigningVerified = $true
} | ConvertTo-Json | Set-Content -Encoding UTF8 "$work/toolchain-preflight.json"
