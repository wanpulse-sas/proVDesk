#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'utils/Common.ps1')
Assert-FreeDiskSpace 'Prepare-BuildEnvironment'
Use-BuildTools
$lock = Get-Content -Encoding UTF8 "$root/ci/dependencies.json" -Raw | ConvertFrom-Json
foreach ($command in @('git', 'rustup', 'cargo', 'python', 'cmake')) {
    $null = Get-Command $command -ErrorAction Stop
}
if (-not (Test-Path -LiteralPath "$work/toolchain-preflight.json")) { throw 'Run Test-Toolchain before preparing build dependencies.' }

# Use build-local SDKs; never patch shared Flutter or vcpkg installations.
# Persist long-path support before checkout in the deeply nested runner workspace.
git clone --config core.longpaths=true --branch $lock.flutterVersion --depth 1 https://github.com/flutter/flutter.git build-tools/flutter
Assert-NativeSuccess 'Clone Flutter'
$flutterCommit = git -C build-tools/flutter rev-parse HEAD
Assert-NativeSuccess 'Commit Flutter'
if ($flutterCommit -ne $lock.flutterCommit) { throw 'Commit Flutter inattendu.' }
# Patch before the first Flutter invocation so its tool snapshot includes VS 2026 support.
$vsPatch = Join-Path $root 'ci/patches/flutter-vs2026.patch'
. (Join-Path $PSScriptRoot 'utils/FlutterPatch.ps1')
Set-FlutterVs2026Patch -Sdk "$root/build-tools/flutter" -Patch $vsPatch -Receipt "$work/flutter-vs2026.patch"
$script:visualStudio | ConvertTo-Json | Set-Content -Encoding UTF8 "$work/visual-studio.json"
flutter config --enable-windows-desktop
Assert-NativeSuccess 'Configuration Flutter'
flutter precache --windows
Assert-NativeSuccess 'Precache Flutter'
$flutterPatch = Join-Path $root '.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff'
git -C build-tools/flutter apply --check $flutterPatch
Assert-NativeSuccess 'Verification du patch Flutter'
git -C build-tools/flutter apply $flutterPatch
Assert-NativeSuccess 'Patch Flutter'
$engine = Get-LockedAsset 'engine'
Copy-Item "$engine/*" "$root/build-tools/flutter/bin/cache/artifacts/engine/windows-x64-release/" -Force

Assert-FreeDiskSpace 'Rust toolchain'
rustup toolchain install $env:RUSTUP_TOOLCHAIN --profile minimal --component rustfmt
Assert-NativeSuccess 'Rust 1.91.1'
rustup target add x86_64-pc-windows-msvc --toolchain $env:RUSTUP_TOOLCHAIN
Assert-NativeSuccess 'Cible Rust MSVC x64'
. (Join-Path $PSScriptRoot 'utils/RustToolCache.ps1')
Assert-FreeDiskSpace 'Rust tool cache'
Install-CachedRustTools -Workspace $root -MsvcVersion $script:visualStudio.V143Version
python -m venv "$root/build-tools/python"
Assert-NativeSuccess 'Environnement Python'
& "$root/build-tools/python/Scripts/python.exe" -m pip install --only-binary=:all: brotli==1.2.1
Assert-NativeSuccess 'Brotli'
& "$root/build-tools/python/Scripts/python.exe" -m unittest discover -s "$root/ci/tests" -p test_package.py
Assert-NativeSuccess 'Package regression tests'
& "$root/build-tools/python/Scripts/python.exe" "$root/ci/tests/Test-ForkPackage.py" "$root/libs/portable/generate.py"
Assert-NativeSuccess 'Pinned fork package producer/consumer test'

# The real vcpkg environment was validated by Test-Toolchain before this stage.
. (Join-Path $PSScriptRoot 'utils/Vcpkg.ps1')
Set-Location $root
Assert-FreeDiskSpace 'vcpkg compilation'
& "$env:VCPKG_ROOT/vcpkg.exe" install --triplet x64-windows-static "--overlay-triplets=$root/ci/triplets" "--x-install-root=$env:VCPKG_ROOT/installed"
Assert-NativeSuccess 'Dependances natives vcpkg'
Assert-OpusStaticRuntime "$env:VCPKG_ROOT/installed"
Copy-Item -LiteralPath "$root/ci/triplets/x64-windows-static.cmake" -Destination "$work/x64-windows-static.cmake"
$packages = @(& "$env:VCPKG_ROOT/vcpkg.exe" list "--x-install-root=$env:VCPKG_ROOT/installed")
Assert-NativeSuccess 'Inventaire vcpkg'
Assert-VcpkgInventory $packages
$packages | Set-Content -Encoding UTF8 "$work/vcpkg-packages.txt"

# Enable the upstream Windows features while preserving the fork branding.
$patch = Join-Path $root 'ci/patches/windows-full-features.patch'
git apply --check $patch
Assert-NativeSuccess 'Verification du patch features'
git apply $patch
Assert-NativeSuccess 'Activation hwcodec/vram'
Copy-Item -LiteralPath $patch -Destination "$work/windows-full-features.patch"
Copy-Item -LiteralPath "$root/ci/dependencies.json" -Destination "$work/dependencies.json"
flutter doctor -v | Set-Content -Encoding UTF8 "$work/flutter-doctor.txt"
Assert-NativeSuccess 'Flutter doctor'
rustc --version | Set-Content -Encoding UTF8 "$work/rust-version.txt"
Assert-NativeSuccess 'Version Rust'
& "$root/build-tools/python/Scripts/python.exe" -m pip freeze | Set-Content -Encoding UTF8 "$work/python-packages.txt"
Assert-NativeSuccess 'Inventaire Python'
